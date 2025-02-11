ARG JENA_VERSION=5.2.0
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

RUN apt-get update && \
    apt-get install -y \
        bash \
        curl \ 
        wget

# Install Node.js and build dependencies
RUN curl -fsSL https://deb.nodesource.com/setup_23.x -o nodesource_setup.sh && \
    bash nodesource_setup.sh && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install yarn
RUN corepack enable && \
    corepack prepare yarn@stable --activate

# # Download Jena
RUN wget --quiet https://github.com/apache/jena/archive/refs/tags/jena-${JENA_VERSION}.tar.gz -O /tmp/jena.tar.gz && \
    mkdir -p ${JENA_BUILD_DIR} && \
    tar -xzf /tmp/jena.tar.gz --strip-components=1 -C ${JENA_BUILD_DIR} && \
    rm -f /tmp/jena.tar.gz

# # Build Fuseki
WORKDIR ${JENA_BUILD_DIR}
RUN mvn package -Dmaven.javadoc.skip=true -DskipTests

# Extract Fuseki and Jena Cmds
RUN mkdir -p ${FUSEKI_HOME} && \
    tar -xzf ${JENA_BUILD_DIR}/jena-fuseki2/apache-jena-fuseki/target/apache-jena-fuseki-${JENA_VERSION}.tar.gz --strip-components=1 -C ${FUSEKI_HOME}

RUN mkdir -p ${JENA_HOME} && \
    tar -xzf ${JENA_BUILD_DIR}/apache-jena/target/apache-jena-${JENA_VERSION}.tar.gz --strip-components=1 -C ${JENA_HOME}

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