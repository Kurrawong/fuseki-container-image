ARG JENA_VERSION=5.5.0
ARG JENA_HOME="/opt/jena"
ARG FUSEKI_HOME="/opt/fuseki"
ARG FUSEKI_BASE="/fuseki"
ARG JAVA_OPTIONS="-Xmx2048m -Xms2048m"

#
# Builder
#
FROM maven:3-eclipse-temurin-17 AS builder
ARG JENA_VERSION
ARG JENA_HOME
ARG FUSEKI_HOME
ENV JENA_BUILD_DIR="/tmp/jena-build"
ENV NODE_OPTIONS="--max-old-space-size=4096"

WORKDIR ${JENA_BUILD_DIR}

RUN apt-get update && \
    apt-get install -y \
        bash \
        curl \
        wget \
        patch \
        unzip

# Install Node.js and build dependencies
RUN curl -fsSL https://deb.nodesource.com/setup_23.x -o nodesource_setup.sh && \
    bash nodesource_setup.sh && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install yarn
RUN corepack enable && \
    corepack prepare yarn@stable --activate

# Download Jena source code
RUN wget "https://github.com/apache/jena/archive/refs/tags/jena-${JENA_VERSION}.zip" -O jena.zip \
  && unzip jena.zip && mv "jena-jena-${JENA_VERSION}" jena

# Apply a dependency patch for GeoSPARQL support
WORKDIR ${JENA_BUILD_DIR}/jena
COPY patches/enable-geosparql.diff .
RUN patch -p1 < enable-geosparql.diff

WORKDIR ${JENA_BUILD_DIR}/jena/jena-fuseki2
RUN mvn package -Dmaven.javadoc.skip=true -DskipTests

RUN unzip "${JENA_BUILD_DIR}/jena/jena-fuseki2/apache-jena-fuseki/target/apache-jena-fuseki-${JENA_VERSION}.zip" \
  && mkdir -p "${FUSEKI_HOME}" \
  && cd "apache-jena-fuseki-${JENA_VERSION}" \
  && find ./ -maxdepth 1 -mindepth 1 -exec mv -t "${FUSEKI_HOME}" {} + \
  && cd .. \
  && rm -rf "apache-jena-fuseki-${JENA_VERSION}"

WORKDIR ${JENA_BUILD_DIR}/jena/apache-jena
RUN mvn package -Dmaven.javadoc.skip=true -DskipTests

RUN unzip "${JENA_BUILD_DIR}/jena/apache-jena/target/apache-jena-${JENA_VERSION}.zip" \
  && mkdir -p "${JENA_HOME}" \
  && cd "apache-jena-${JENA_VERSION}" \
  && find ./ -maxdepth 1 -mindepth 1 -exec mv -t "${JENA_HOME}" {} + \
  && cd .. \
  && rm -rf "apache-jena-${JENA_VERSION}"

#
# Final
#
FROM amazoncorretto:17-alpine3.19 AS final
ARG JENA_VERSION
ENV JENA_VERSION=${JENA_VERSION}
ARG JENA_HOME
ENV JENA_HOME=${JENA_HOME}
ARG FUSEKI_HOME
ENV FUSEKI_HOME=${FUSEKI_HOME}
ARG FUSEKI_BASE
ENV FUSEKI_BASE=${FUSEKI_BASE}
ARG JAVA_OPTIONS
ENV JAVA_OPTIONS=${JAVA_OPTIONS}

RUN apk add --no-cache \
        bash \
        # curl used for container health check
        curl \
        # jq required for tdb2.xloader
        jq \
        # coreutils required for tdb2.xloader with an updated version of sort with parallel support
        coreutils

COPY --from=builder ${JENA_HOME} ${JENA_HOME}
COPY --from=builder ${FUSEKI_HOME} ${FUSEKI_HOME}

ENV PATH="${JENA_HOME}/bin:${FUSEKI_HOME}:${PATH}"

COPY shiro.ini ${FUSEKI_BASE}/shiro.ini
COPY config.ttl ${FUSEKI_BASE}/config.ttl
COPY entrypoint.sh ${FUSEKI_HOME}/entrypoint.sh

CMD ["/opt/fuseki/entrypoint.sh"]
