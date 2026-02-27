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
SMOKE_DATA_GRAPH="${SMOKE_DATA_GRAPH:-https://example.org/smoke-graph}"
SMOKE_GEOSPARQL_EXPECTED_COUNT="${SMOKE_GEOSPARQL_EXPECTED_COUNT:-1}"
SMOKE_FTS_EXPECTED_COUNT="${SMOKE_FTS_EXPECTED_COUNT:-2}"
SMOKE_SPATIAL_INDEX_EXPECTED_COUNT="${SMOKE_SPATIAL_INDEX_EXPECTED_COUNT:-4}"
SMOKE_TIMEOUT_SECONDS="${SMOKE_TIMEOUT_SECONDS:-90}"
SMOKE_DELETE_SPATIAL_INDEX_CMD="${SMOKE_DELETE_SPATIAL_INDEX_CMD:-}"
SMOKE_RESTART_CMD="${SMOKE_RESTART_CMD:-}"

if [[ ! -f "${SMOKE_DATA_FILE}" ]]; then
  echo "Smoke test data file does not exist: ${SMOKE_DATA_FILE}" >&2
  exit 1
fi

ping_url="${FUSEKI_BASE_URL}/\$/ping"
datasets_url="${FUSEKI_BASE_URL}/\$/datasets"
query_url="${FUSEKI_BASE_URL}/${SMOKE_DATASET}/sparql"
if [[ -n "${SMOKE_DATA_GRAPH}" ]]; then
  data_url="${FUSEKI_BASE_URL}/${SMOKE_DATASET}/data?graph=${SMOKE_DATA_GRAPH}"
else
  data_url="${FUSEKI_BASE_URL}/${SMOKE_DATASET}/data?default"
fi

wait_for_fuseki() {
  echo "Waiting for Fuseki: ${ping_url}"
  local deadline
  deadline=$((SECONDS + SMOKE_TIMEOUT_SECONDS))

  until curl -fsS "${ping_url}" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "Timed out after ${SMOKE_TIMEOUT_SECONDS}s waiting for Fuseki readiness" >&2
      exit 1
    fi
    sleep 1
  done
}

wait_for_fuseki

tmp_create="$(mktemp)"
tmp_datasets="$(mktemp)"
tmp_upload="$(mktemp)"
tmp_query_geosparql="$(mktemp)"
tmp_query_fts="$(mktemp)"
tmp_query_spatial_index="$(mktemp)"
cleanup() {
  rm -f "${tmp_create}" "${tmp_datasets}" "${tmp_upload}" "${tmp_query_geosparql}" "${tmp_query_fts}" "${tmp_query_spatial_index}"
}
trap cleanup EXIT

datasets_status="$(
  curl -sS -o "${tmp_datasets}" -w "%{http_code}" "${datasets_url}"
)"
if [[ "${datasets_status}" != "200" ]]; then
  echo "Failed to list datasets (HTTP ${datasets_status})" >&2
  cat "${tmp_datasets}" >&2
  exit 1
fi

if jq -e --arg ds "/${SMOKE_DATASET}" '.datasets[]? | select(."ds.name" == $ds)' "${tmp_datasets}" >/dev/null; then
  echo "Dataset configured: ${SMOKE_DATASET}"
else
  echo "Expected dataset '/${SMOKE_DATASET}' is missing. Smoke tests require preconfigured dataset setup." >&2
  cat "${tmp_datasets}" >&2
  exit 1
fi

echo "Uploading data: ${SMOKE_DATA_FILE}"
if [[ -n "${SMOKE_DATA_GRAPH}" ]]; then
  echo "Target graph: ${SMOKE_DATA_GRAPH}"
else
  echo "Target graph: default"
fi
upload_status="$(
  curl -sS -o "${tmp_upload}" -w "%{http_code}" -X POST "${data_url}" \
    -H "Content-Type: text/turtle" \
    --data-binary "@${SMOKE_DATA_FILE}"
)"
if [[ "${upload_status}" != "200" && "${upload_status}" != "201" && "${upload_status}" != "204" ]]; then
  echo "Failed to upload smoke test data (HTTP ${upload_status})" >&2
  cat "${tmp_upload}" >&2
  exit 1
fi

if [[ -n "${SMOKE_DELETE_SPATIAL_INDEX_CMD}" ]]; then
  echo "Deleting spatial index file before restart"
  bash -lc "${SMOKE_DELETE_SPATIAL_INDEX_CMD}"
fi

if [[ -n "${SMOKE_RESTART_CMD}" ]]; then
  echo "Restarting Fuseki to trigger spatial index creation"
  bash -lc "${SMOKE_RESTART_CMD}"
  wait_for_fuseki
fi

run_query_and_assert() {
  local label="$1"
  local query="$2"
  local expected_count="$3"
  local output_file="$4"

  local status
  status="$(
    curl -sS -o "${output_file}" -w "%{http_code}" -G "${query_url}" \
      --data-urlencode "query=${query}" \
      --data-urlencode "format=application/sparql-results+json"
  )"

  if [[ "${status}" != "200" ]]; then
    echo "${label} failed (HTTP ${status})" >&2
    cat "${output_file}" >&2
    exit 1
  fi

  echo "${label} response:"
  jq . "${output_file}"

  local actual_count
  actual_count="$(jq -r '.results.bindings | length' "${output_file}")"
  if [[ "${actual_count}" != "${expected_count}" ]]; then
    echo "${label} returned unexpected result count. Expected ${expected_count}, got ${actual_count}" >&2
    cat "${output_file}" >&2
    exit 1
  fi
}

SMOKE_GEOSPARQL_QUERY="$(cat <<'EOF'
PREFIX geo: <http://www.opengis.net/ont/geosparql#>
PREFIX geof: <http://www.opengis.net/def/function/geosparql/>

SELECT (COUNT(*) AS ?count)
WHERE {
  BIND("POINT (153.13401606 -27.62096167)"^^geo:wktLiteral AS ?point)
  BIND("POLYGON ((152.685242 -27.161808, 152.698975 -27.829361, 153.492737 -27.829361, 153.435059 -27.178912, 152.685242 -27.161808))"^^geo:wktLiteral AS ?polygon)
  FILTER(geof:sfWithin(?point, ?polygon))
}
EOF
)"

SMOKE_FTS_QUERY="$(cat <<'EOF'
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX text: <http://jena.apache.org/text#>

SELECT DISTINCT ?address ?literal
WHERE {
  (?address ?score ?literal) text:query ( rdfs:label "Drive" ) .
}
EOF
)"

SMOKE_SPATIAL_INDEX_QUERY="$(cat <<'EOF'
PREFIX addr: <https://linked.data.gov.au/def/addr/>
PREFIX geo: <http://www.opengis.net/ont/geosparql#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

SELECT ?addr ?label
WHERE {
  ?addr a addr:Address ;
        rdfs:label ?label .
  ?addr geo:sfWithin <https://example.org/australia> .
}
ORDER BY ?label
EOF
)"

echo "Running README GeoSPARQL smoke query"
run_query_and_assert "GeoSPARQL smoke query" "${SMOKE_GEOSPARQL_QUERY}" "${SMOKE_GEOSPARQL_EXPECTED_COUNT}" "${tmp_query_geosparql}"

echo "Running README Lucene FTS smoke query"
run_query_and_assert "Lucene FTS smoke query" "${SMOKE_FTS_QUERY}" "${SMOKE_FTS_EXPECTED_COUNT}" "${tmp_query_fts}"

echo "Running spatial index smoke query"
run_query_and_assert "Spatial index smoke query" "${SMOKE_SPATIAL_INDEX_QUERY}" "${SMOKE_SPATIAL_INDEX_EXPECTED_COUNT}" "${tmp_query_spatial_index}"

echo "Smoke test passed: GeoSPARQL, Lucene FTS, and spatial index queries returned expected results"
