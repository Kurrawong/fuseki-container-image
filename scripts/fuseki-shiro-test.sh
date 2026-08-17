#!/usr/bin/env bash

set -euo pipefail

IMAGE_NAME="${FUSEKI_TEST_IMAGE:-fuseki-container-image-fuseki}"
TEST_PASSWORD='shiro-lifecycle!test@password#2026'
CONTAINER_NAME="fuseki-shiro-test-$$"
CUSTOM_RUNTIME_CONTAINER="fuseki-shiro-runtime-test-$$"
CUSTOM_SOURCE_CONTAINER="fuseki-shiro-source-test-$$"
DEFAULT_PASSWORD_CONTAINER="fuseki-shiro-default-password-test-$$"
TEST_BASE="$(mktemp -d)"
CUSTOM_RUNTIME_BASE="$(mktemp -d)"
CUSTOM_SOURCE_BASE="$(mktemp -d)"
DEFAULT_PASSWORD_BASE="$(mktemp -d)"
INVALID_PASSWORD_BASE="$(mktemp -d)"
CUSTOM_SOURCE_FILE="$(mktemp)"

cleanup() {
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  docker rm -f "${CUSTOM_RUNTIME_CONTAINER}" >/dev/null 2>&1 || true
  docker rm -f "${CUSTOM_SOURCE_CONTAINER}" >/dev/null 2>&1 || true
  docker rm -f "${DEFAULT_PASSWORD_CONTAINER}" >/dev/null 2>&1 || true
  rm -rf \
    "${TEST_BASE}" \
    "${CUSTOM_RUNTIME_BASE}" \
    "${CUSTOM_SOURCE_BASE}" \
    "${DEFAULT_PASSWORD_BASE}" \
    "${INVALID_PASSWORD_BASE}"
  rm -f "${CUSTOM_SOURCE_FILE}"
}
trap cleanup EXIT

fail() {
  echo "Shiro lifecycle test failed: $*" >&2
  exit 1
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "${actual}" != "${expected}" ]]; then
    fail "${message}: expected '${expected}', got '${actual}'"
  fi
}

wait_for_ping() {
  local container_name="$1"

  for _ in $(seq 1 30); do
    if docker exec "${container_name}" curl -fsS 'http://localhost:3030/$/ping' >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done

  fail "timed out waiting for ${container_name}"
}

write_anonymous_shiro_fixture() {
  local path="$1"
  local marker="$2"

  cat > "${path}" <<EOF
[main]

[urls]
/\$/ping = anon
/** = anon

# ${marker}
EOF
  chmod 644 "${path}"
}

assert_password_rejected() {
  local label="$1"
  local password="$2"
  local output

  if output="$(
    timeout 10s docker run --rm \
      --env "ADMIN_PASSWORD=${password}" \
      --volume "${INVALID_PASSWORD_BASE}:/fuseki" \
      "${IMAGE_NAME}" 2>&1
  )"; then
    fail "${label} ADMIN_PASSWORD was accepted"
  fi
  if [[ "${output}" != *"ADMIN_PASSWORD must not contain"* ]]; then
    fail "${label} ADMIN_PASSWORD did not produce the expected validation error"
  fi
  if [[ "${output}" == *"${password}"* ]]; then
    fail "${label} ADMIN_PASSWORD leaked into validation output"
  fi
}

# The test runner's UID is not necessarily the image's UID 1000 (notably in
# GitHub Actions), so let the disposable container user initialize these bases.
chmod 777 \
  "${TEST_BASE}" \
  "${CUSTOM_RUNTIME_BASE}" \
  "${CUSTOM_SOURCE_BASE}" \
  "${DEFAULT_PASSWORD_BASE}" \
  "${INVALID_PASSWORD_BASE}"

assert_password_rejected "comma-containing" 'unsafe,password'
assert_password_rejected "newline-containing" $'unsafe\npassword'
assert_password_rejected "whitespace-padded" ' unsafe-password '

docker run --detach \
  --name "${CONTAINER_NAME}" \
  --env "ADMIN_PASSWORD=${TEST_PASSWORD}" \
  --env "JAVA_OPTIONS=-Xms96m -Xmx96m" \
  --volume "${TEST_BASE}:/fuseki" \
  "${IMAGE_NAME}" >/dev/null

for _ in $(seq 1 30); do
  if docker exec "${CONTAINER_NAME}" test -f /fuseki/shiro.ini; then
    break
  fi
  sleep 1
done

docker exec "${CONTAINER_NAME}" test -f /opt/fuseki/shiro.ini || fail "image Shiro source is missing"
docker exec "${CONTAINER_NAME}" test -f /fuseki/shiro.ini || fail "runtime Shiro configuration is missing"

docker exec "${CONTAINER_NAME}" grep -Fq "${TEST_PASSWORD}" /fuseki/shiro.ini || fail "ADMIN_PASSWORD was not substituted"
if docker exec "${CONTAINER_NAME}" grep -Fq '${ADMIN_PASSWORD}' /fuseki/shiro.ini; then
  fail "runtime Shiro configuration still contains the ADMIN_PASSWORD placeholder"
fi

assert_equals \
  "1000:1000 600" \
  "$(docker exec "${CONTAINER_NAME}" stat -c '%u:%g %a' /fuseki/shiro.ini)" \
  "runtime Shiro configuration ownership or mode"

wait_for_ping "${CONTAINER_NAME}"

ping_status="$(docker exec "${CONTAINER_NAME}" curl -sS -o /dev/null -w '%{http_code}' 'http://localhost:3030/$/ping')"
datasets_status="$(docker exec "${CONTAINER_NAME}" curl -sS -o /dev/null -w '%{http_code}' 'http://localhost:3030/$/datasets')"
authenticated_datasets_status="$(
  docker exec \
    --env "TEST_ADMIN_PASSWORD=${TEST_PASSWORD}" \
    "${CONTAINER_NAME}" \
    sh -c 'curl -sS -o /dev/null -w "%{http_code}" --user "admin:${TEST_ADMIN_PASSWORD}" "http://localhost:3030/$/datasets"'
)"
anonymous_write_status="$(
  docker exec \
    "${CONTAINER_NAME}" \
    curl -sS -o /dev/null -w '%{http_code}' \
    --request POST \
    --header 'Content-Type: text/turtle' \
    --data '<https://example.org/s> <https://example.org/p> <https://example.org/o> .' \
    'http://localhost:3030/test/data'
)"

assert_equals "200" "${ping_status}" "anonymous ping status"
assert_equals "401" "${datasets_status}" "anonymous administration status"
assert_equals "200" "${authenticated_datasets_status}" "authenticated administration status"
assert_equals "401" "${anonymous_write_status}" "anonymous write status"

java_command="$(docker exec "${CONTAINER_NAME}" sh -c "tr '\000' ' ' < /proc/1/cmdline")"
if [[ " ${java_command} " != *" -Xms96m "* || " ${java_command} " != *" -Xmx96m "* ]]; then
  fail "JAVA_OPTIONS did not reach the Java process"
fi

container_logs="$(docker logs "${CONTAINER_NAME}" 2>&1)"
if grep -Fq "${TEST_PASSWORD}" <<< "${container_logs}"; then
  fail "ADMIN_PASSWORD leaked into container logs"
fi

docker run --detach \
  --name "${DEFAULT_PASSWORD_CONTAINER}" \
  --volume "${DEFAULT_PASSWORD_BASE}:/fuseki" \
  "${IMAGE_NAME}" >/dev/null

wait_for_ping "${DEFAULT_PASSWORD_CONTAINER}"
docker exec "${DEFAULT_PASSWORD_CONTAINER}" grep -Fq 'admin = admin,admin' /fuseki/shiro.ini || fail "default ADMIN_PASSWORD was not rendered"
default_password_status="$(
  docker exec \
    "${DEFAULT_PASSWORD_CONTAINER}" \
    curl -sS -o /dev/null -w '%{http_code}' \
    --user 'admin:admin' \
    'http://localhost:3030/$/datasets'
)"
assert_equals "200" "${default_password_status}" "default admin credentials status"

write_anonymous_shiro_fixture \
  "${CUSTOM_RUNTIME_BASE}/shiro.ini" \
  "custom-runtime-marker"
runtime_checksum="$(sha256sum "${CUSTOM_RUNTIME_BASE}/shiro.ini")"

docker run --detach \
  --name "${CUSTOM_RUNTIME_CONTAINER}" \
  --volume "${CUSTOM_RUNTIME_BASE}:/fuseki" \
  "${IMAGE_NAME}" >/dev/null

wait_for_ping "${CUSTOM_RUNTIME_CONTAINER}"

docker restart "${CUSTOM_RUNTIME_CONTAINER}" >/dev/null
wait_for_ping "${CUSTOM_RUNTIME_CONTAINER}"

assert_equals \
  "${runtime_checksum}" \
  "$(sha256sum "${CUSTOM_RUNTIME_BASE}/shiro.ini")" \
  "explicit runtime Shiro configuration changed across restart"
docker exec "${CUSTOM_RUNTIME_CONTAINER}" test -f /opt/fuseki/shiro.ini || fail "source disappeared behind non-empty FUSEKI_BASE mount"

write_anonymous_shiro_fixture \
  "${CUSTOM_SOURCE_FILE}" \
  "custom-source-marker"

docker run --detach \
  --name "${CUSTOM_SOURCE_CONTAINER}" \
  --volume "${CUSTOM_SOURCE_BASE}:/fuseki" \
  --volume "${CUSTOM_SOURCE_FILE}:/opt/fuseki/shiro.ini:ro" \
  "${IMAGE_NAME}" >/dev/null

wait_for_ping "${CUSTOM_SOURCE_CONTAINER}"

docker exec "${CUSTOM_SOURCE_CONTAINER}" grep -Fq 'custom-source-marker' /fuseki/shiro.ini || fail "mounted Shiro source did not take precedence"
custom_source_checksum="$(sha256sum "${CUSTOM_SOURCE_BASE}/shiro.ini")"

docker restart "${CUSTOM_SOURCE_CONTAINER}" >/dev/null
wait_for_ping "${CUSTOM_SOURCE_CONTAINER}"
assert_equals \
  "${custom_source_checksum}" \
  "$(sha256sum "${CUSTOM_SOURCE_BASE}/shiro.ini")" \
  "runtime configuration rendered from a custom source changed across restart"
docker exec "${CUSTOM_SOURCE_CONTAINER}" grep -Fq 'custom-source-marker' /fuseki/shiro.ini || fail "custom source configuration did not survive restart"

echo "Shiro lifecycle test passed: defaults, rendering, precedence, access control, and JVM options behave as configured"
