#!/bin/sh

# Create configuration directory if it doesn't exist
mkdir -p "${FUSEKI_BASE}/configuration"

# Copy any configs from /opt/fuseki/configuration to runtime location
if [ -d "/opt/fuseki/configuration" ]; then
    cp -r /opt/fuseki/configuration/* "${FUSEKI_BASE}/configuration/" 2>/dev/null || true
fi

exec \
  "${JAVA_HOME}/bin/java" \
  ${JAVA_OPTS} \
  -Xshare:off \
  -Dlog4j.configurationFile="${FUSEKI_HOME}/log4j2.properties" \
  -cp "${FUSEKI_HOME}/fuseki-server.jar:${FUSEKI_HOME}/lib/*" \
  org.apache.jena.fuseki.main.cmds.FusekiServerCmd
