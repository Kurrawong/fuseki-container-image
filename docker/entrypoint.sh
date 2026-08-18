#!/bin/sh

set -eu

# Materialize the runtime Shiro configuration from the application source on
# every start so source-managed credential and policy updates take effect.
if grep -Fq '${ADMIN_PASSWORD}' "${FUSEKI_HOME}/shiro.ini"; then
  if [ -z "${ADMIN_PASSWORD:-}" ]; then
    echo "ADMIN_PASSWORD must be set when the Shiro source uses its placeholder" >&2
    exit 1
  fi

  carriage_return="$(printf '\r')"
  line_feed='
'
  case "${ADMIN_PASSWORD}" in
    *","*|*"${carriage_return}"*|*"${line_feed}"*|[[:space:]]*|*[[:space:]])
      echo "ADMIN_PASSWORD must not contain commas, line breaks, or leading/trailing whitespace" >&2
      exit 1
      ;;
  esac
fi

shiro_tmp="$(umask 077 && mktemp "${FUSEKI_BASE}/shiro.ini.tmp.XXXXXX")"
trap 'rm -f "${shiro_tmp}"' 0 1 2 15
if ! envsubst '${ADMIN_PASSWORD}' < "${FUSEKI_HOME}/shiro.ini" > "${shiro_tmp}"; then
  exit 1
fi
chmod 600 "${shiro_tmp}"
mv "${shiro_tmp}" "${FUSEKI_BASE}/shiro.ini"
trap - 0 1 2 15

# Create configuration directory if it doesn't exist
mkdir -p "${FUSEKI_BASE}/configuration"

# Copy any configs from /opt/fuseki/configuration to runtime location
if [ -d "/opt/fuseki/configuration" ]; then
    cp -r /opt/fuseki/configuration/* "${FUSEKI_BASE}/configuration/" 2>/dev/null || true
fi

exec \
  "${JAVA_HOME}/bin/java" \
  ${JAVA_OPTS:-} \
  -Xshare:off \
  -Dlog4j.configurationFile="${FUSEKI_HOME}/log4j2.properties" \
  -cp "${FUSEKI_HOME}/fuseki-server.jar:${FUSEKI_HOME}/lib/*" \
  org.apache.jena.fuseki.main.cmds.FusekiServerCmd
