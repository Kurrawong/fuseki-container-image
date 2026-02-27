#!/usr/bin/env bash

set -euo pipefail

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command curl
require_command jq

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FUSEKI_BASE_URL="${FUSEKI_BASE_URL:-http://localhost:3030}"
SMOKE_DATASET="${SMOKE_DATASET:-test-geosparql}"
SMOKE_DATA_FILE="${SMOKE_DATA_FILE:-${REPO_ROOT}/testdata/data-geosparql.ttl}"
SMOKE_EXPECTED_COUNT="${SMOKE_EXPECTED_COUNT:-2}"
SMOKE_TIMEOUT_SECONDS="${SMOKE_TIMEOUT_SECONDS:-90}"

if [[ ! -f "${SMOKE_DATA_FILE}" ]]; then
  echo "Smoke test data file does not exist: ${SMOKE_DATA_FILE}" >&2
  exit 1
fi

ping_url="${FUSEKI_BASE_URL}/\$/ping"
datasets_url="${FUSEKI_BASE_URL}/\$/datasets"
data_url="${FUSEKI_BASE_URL}/${SMOKE_DATASET}/data?default"
query_url="${FUSEKI_BASE_URL}/${SMOKE_DATASET}/sparql"

echo "Waiting for Fuseki: ${ping_url}"
deadline=$((SECONDS + SMOKE_TIMEOUT_SECONDS))
until curl -fsS "${ping_url}" >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "Timed out after ${SMOKE_TIMEOUT_SECONDS}s waiting for Fuseki readiness" >&2
    exit 1
  fi
  sleep 1
done

tmp_create="$(mktemp)"
tmp_upload="$(mktemp)"
tmp_query="$(mktemp)"
cleanup() {
  rm -f "${tmp_create}" "${tmp_upload}" "${tmp_query}"
}
trap cleanup EXIT

echo "Creating dataset: ${SMOKE_DATASET}"
create_status="$(
  curl -sS -o "${tmp_create}" -w "%{http_code}" -X POST "${datasets_url}" \
    -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
    --data "dbName=${SMOKE_DATASET}&dbType=tdb2"
)"
if [[ "${create_status}" != "200" ]]; then
  echo "Failed to create dataset (HTTP ${create_status})" >&2
  cat "${tmp_create}" >&2
  exit 1
fi

echo "Uploading data: ${SMOKE_DATA_FILE}"
upload_status="$(
  curl -sS -o "${tmp_upload}" -w "%{http_code}" -X POST "${data_url}" \
    -H "Content-Type: text/turtle" \
    --data-binary "@${SMOKE_DATA_FILE}"
)"
if [[ "${upload_status}" != "200" ]]; then
  echo "Failed to upload smoke test data (HTTP ${upload_status})" >&2
  cat "${tmp_upload}" >&2
  exit 1
fi

SMOKE_QUERY="$(cat <<'EOF'
PREFIX geo: <http://www.opengis.net/ont/geosparql#>
PREFIX geof: <http://www.opengis.net/def/function/geosparql/>

SELECT DISTINCT ?address
WHERE {
  BIND("POLYGON ((152.685242 -27.161808, 152.698975 -27.829361, 153.492737 -27.829361, 153.435059 -27.178912, 152.685242 -27.161808))"^^geo:wktLiteral AS ?polygon)
  ?address geo:hasGeometry / geo:asWKT ?point .
  FILTER(geof:sfWithin(?point, ?polygon))
}
EOF
)"

echo "Running README GeoSPARQL smoke query"
query_status="$(
  curl -sS -o "${tmp_query}" -w "%{http_code}" -G "${query_url}" \
    --data-urlencode "query=${SMOKE_QUERY}" \
    --data-urlencode "format=application/sparql-results+json"
)"
if [[ "${query_status}" != "200" ]]; then
  echo "Smoke query failed (HTTP ${query_status})" >&2
  cat "${tmp_query}" >&2
  exit 1
fi

actual_count="$(jq -r '.results.bindings | length' "${tmp_query}")"
if [[ "${actual_count}" != "${SMOKE_EXPECTED_COUNT}" ]]; then
  echo "Unexpected smoke query result count. Expected ${SMOKE_EXPECTED_COUNT}, got ${actual_count}" >&2
  cat "${tmp_query}" >&2
  exit 1
fi

echo "Smoke test passed: query returned ${actual_count} result(s)"
