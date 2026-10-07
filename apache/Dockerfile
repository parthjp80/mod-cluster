# Apache httpd 2.4 + mod_cluster (mod_manager + mod_proxy_cluster) built from source.
#
# Build context: repository root
#   docker build -f apache/Dockerfile -t modcluster-httpd .
ARG HTTPD_IMAGE=httpd:2.4

# ---------------------------------------------------------------------------
# Stage 1: compile the mod_cluster native modules against this exact httpd
# ---------------------------------------------------------------------------
FROM ${HTTPD_IMAGE} AS build

# mod_proxy_cluster has no release tags; pin a known-good commit of main.
ARG MPC_REF=d36ef47e67f6d3e611a447c8410a0b740c2393e4

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc make autoconf libtool perl curl ca-certificates libapr1-dev libaprutil1-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN curl -fsSL "https://github.com/modcluster/mod_proxy_cluster/archive/${MPC_REF}.tar.gz" \
      | tar xz --strip-components=1

# Same loop the upstream project uses in test/httpd/Containerfile.
# "make clean" matters: both modules link ../common/common.slo and the second
# build would otherwise skip compiling it and fail with "common.lo is not valid".
# mod_manager     : receives MCMP messages (CONFIG/STATUS/ENABLE-APP...) from JBoss
# mod_proxy_cluster: builds workers dynamically and picks a node by load factor
WORKDIR /src/native
RUN for m in mod_manager mod_proxy_cluster; do \
      echo "=== building $m"; \
      ( cd "$m" \
        && ./buildconf \
        && ./configure --with-apxs=/usr/local/apache2/bin/apxs \
        && make clean \
        && make \
        && cp *.so /usr/local/apache2/modules/ ) || exit 1; \
    done \
 && ls -l /usr/local/apache2/modules/mod_manager.so /usr/local/apache2/modules/mod_proxy_cluster.so

# ---------------------------------------------------------------------------
# Stage 2: runtime image
# ---------------------------------------------------------------------------
FROM ${HTTPD_IMAGE}

# curl is only here for debugging / the helper scripts (kubectl exec ... curl)
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/apache2/modules/mod_manager.so       /usr/local/apache2/modules/
COPY --from=build /usr/local/apache2/modules/mod_proxy_cluster.so /usr/local/apache2/modules/
COPY apache/conf/mod_cluster.conf /usr/local/apache2/conf/extra/mod_cluster.conf

RUN echo 'Include conf/extra/mod_cluster.conf' >> /usr/local/apache2/conf/httpd.conf \
 && HOSTNAME=build httpd -t

# 80 = user traffic, 6666 = MCMP (JBoss -> httpd management channel)
EXPOSE 80 6666
