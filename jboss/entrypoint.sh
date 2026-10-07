#!/bin/sh
# Starts WildFly with standalone.xml (which has mod_cluster registered).
#
# Environment (all optional):
#   NODE_NAME        mod_cluster node id / JVMRoute   (default: hostname, e.g. jboss-0)
#   POD_IP           address registered with httpd    (default: first IP of hostname)
#   MODCLUSTER_PROXY1  host:port of httpd #1 MCMP     (default: httpd-0-mcmp:6666)
#   MODCLUSTER_PROXY2  host:port of httpd #2 MCMP     (default: httpd-1-mcmp:6666)
#   JAVA_OPTS        JVM options (heap size etc.)
set -e

# (the WildFly base image has no `hostname` binary; $HOSTNAME is set by the runtime)
NODE_NAME="${NODE_NAME:-${HOSTNAME}}"
POD_IP="${POD_IP:-$(getent hosts "${HOSTNAME}" | awk '{print $1; exit}')}"
PROXY1="${MODCLUSTER_PROXY1:-httpd-0-mcmp:6666}"
PROXY2="${MODCLUSTER_PROXY2:-httpd-1-mcmp:6666}"

echo "Starting JBoss node '${NODE_NAME}' on ${POD_IP}; mod_cluster proxies: ${PROXY1}, ${PROXY2}"

# mod_cluster registers the address the HTTP listener is bound to, so bind to
# the pod IP (not 0.0.0.0) - that is the address httpd will proxy to.
exec "${JBOSS_HOME}/bin/standalone.sh" \
    -c standalone.xml \
    -b "${POD_IP}" \
    -bmanagement 0.0.0.0 \
    -Djboss.node.name="${NODE_NAME}" \
    -Djboss.tx.node.id="${NODE_NAME}" \
    -Dmodcluster.proxy1.host="${PROXY1%:*}" -Dmodcluster.proxy1.port="${PROXY1##*:}" \
    -Dmodcluster.proxy2.host="${PROXY2%:*}" -Dmodcluster.proxy2.port="${PROXY2##*:}" \
    "$@"
