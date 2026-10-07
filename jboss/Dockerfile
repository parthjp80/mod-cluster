# JBoss application server (WildFly, the upstream of JBoss EAP) with the
# mod_cluster subsystem registered in standalone.xml and the demo app deployed.
#
# Build context: repository root
#   docker buildx build --platform linux/amd64 -f jboss/Dockerfile -t modcluster-jboss .
#
# Base image: Eclipse Temurin JRE 21 on Ubuntu 24.04 ("noble"), NOT the official
# quay.io/wildfly/wildfly image. The official image is RHEL 10 based and needs an
# x86-64-v2+ CPU; Proxmox VMs with the default kvm64/qemu64 CPU type are
# x86-64-v1 and the container dies with "CPU does not support x86-64-v2".
# Ubuntu 24.04 + Temurin run on any x86-64 CPU.
ARG WILDFLY_VERSION=41.0.1.Final
ARG WILDFLY_SHA1=362710c3795651a1076b0fa778cb8a53162f8ff1
ARG JDK_IMAGE=eclipse-temurin:21-jdk-noble
ARG JRE_IMAGE=eclipse-temurin:21-jre-noble

# ---------------------------------------------------------------------------
# Stage 1: unpack WildFly and register mod_cluster in standalone.xml
# (offline, embedded CLI). Runs on the BUILD machine's native platform: the JVM
# crashes under QEMU emulation (e.g. building linux/amd64 on an Apple-silicon
# Mac), and everything this stage produces is platform independent.
# ---------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM ${JDK_IMAGE} AS wildfly
ARG WILDFLY_VERSION
ARG WILDFLY_SHA1
ENV JBOSS_HOME=/opt/jboss/wildfly

RUN curl -fsSL -o /tmp/wildfly.tar.gz \
      "https://github.com/wildfly/wildfly/releases/download/${WILDFLY_VERSION}/wildfly-${WILDFLY_VERSION}.tar.gz" \
 && echo "${WILDFLY_SHA1}  /tmp/wildfly.tar.gz" | sha1sum -c - \
 && mkdir -p ${JBOSS_HOME} \
 && tar xzf /tmp/wildfly.tar.gz -C ${JBOSS_HOME} --strip-components=1 \
 && rm /tmp/wildfly.tar.gz

COPY jboss/configure-modcluster.cli /tmp/configure-modcluster.cli
RUN ${JBOSS_HOME}/bin/jboss-cli.sh --file=/tmp/configure-modcluster.cli \
 && grep -q 'urn:jboss:domain:modcluster' ${JBOSS_HOME}/standalone/configuration/standalone.xml \
 && rm -rf ${JBOSS_HOME}/standalone/configuration/standalone_xml_history \
           ${JBOSS_HOME}/standalone/data ${JBOSS_HOME}/standalone/log ${JBOSS_HOME}/standalone/tmp

# 2. Deploy the dummy application (exploded WAR, context root /demo)
COPY app/demo.war ${JBOSS_HOME}/standalone/deployments/demo.war
RUN touch ${JBOSS_HOME}/standalone/deployments/demo.war.dodeploy

# ---------------------------------------------------------------------------
# Stage 2: runtime image for the target platform
# ---------------------------------------------------------------------------
FROM ${JRE_IMAGE}
ENV JBOSS_HOME=/opt/jboss/wildfly \
    LAUNCH_JBOSS_IN_BACKGROUND=true

RUN groupadd -r -g 1001 jboss \
 && useradd -r -u 1001 -g jboss -d /opt/jboss -s /sbin/nologin jboss

# WildFly with mod_cluster in standalone.xml + demo app (built in stage 1)
COPY --from=wildfly --chown=jboss:jboss /opt/jboss /opt/jboss

# Entrypoint: sets node name / bind address / proxies from the pod environment
COPY --chown=jboss:jboss --chmod=0755 jboss/entrypoint.sh /opt/jboss/entrypoint.sh

USER jboss
WORKDIR /opt/jboss
EXPOSE 8080 9990
ENTRYPOINT ["/opt/jboss/entrypoint.sh"]
