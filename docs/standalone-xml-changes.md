# What `configure-modcluster.cli` changes in `standalone.xml`

The JBoss image starts from WildFly's stock `standalone.xml` (the non-HA
profile, which has **no** mod_cluster by default) and runs
[`jboss/configure-modcluster.cli`](../jboss/configure-modcluster.cli) against it
at image build time. These are the only differences — captured with `diff`
from the built image (WildFly 41.0.1.Final):

```bash
docker run --rm --entrypoint cat ghcr.io/parthjp80/modcluster-jboss:1.0.1 \
  /opt/jboss/wildfly/standalone/configuration/standalone.xml
```

## 1. Extension

```xml
<extensions>
    ...
    <extension module="org.jboss.as.modcluster"/>
    ...
</extensions>
```

## 2. IO worker pool (sizes the "busyness" metric)

```xml
<subsystem xmlns="urn:jboss:domain:io:...">
    <worker name="default" task-max-threads="40"/>
    ...
</subsystem>
```

## 3. The mod_cluster subsystem

```xml
<subsystem xmlns="urn:jboss:domain:modcluster:6.0">
    <proxy name="default"
           listener="default"
           proxies="httpd-proxy-1 httpd-proxy-2"
           advertise="false"
           balancer="mycluster"
           excluded-contexts="ROOT,wildfly-services"
           status-interval="5"
           ping="10"
           node-timeout="20"
           stop-context-timeout="10"
           sticky-session="true"
           sticky-session-remove="false"
           sticky-session-force="false">
        <dynamic-load-provider decay="2.0" history="4">
            <load-metric type="heap"     weight="2"/>
            <load-metric type="busyness" weight="2" capacity="40.0"/>
            <load-metric type="cpu"      weight="1"/>
        </dynamic-load-provider>
    </proxy>
</subsystem>
```

| Attribute | Value | Why |
|---|---|---|
| `listener` | `default` | Register the Undertow **HTTP** listener (8080). httpd proxies with `mod_proxy_http`; AJP is not needed. |
| `proxies` | two outbound socket bindings | Static list of httpd MCMP endpoints. Each JBoss registers with **both** Apaches. |
| `advertise` | `false` | Multicast advertise doesn't work across most Kubernetes CNIs (flannel included). |
| `balancer` | `mycluster` | Balancer name created on the httpd side. Matches `ManagerBalancerName`. |
| `excluded-contexts` | `ROOT,wildfly-services` | Don't publish the WildFly welcome page (`/`) or `/wildfly-services`; only `/demo` is routed. |
| `status-interval` | `5` | Seconds between `STATUS` messages, i.e. how fresh the load factor in httpd is (default 10). |
| `ping` / `node-timeout` | `10` / `20` | httpd health-pings the node via its connector; seconds to wait for a node reply. |
| `stop-context-timeout` | `10` | On shutdown, wait up to 10 s for in-flight requests to drain after `STOP-APP`. |
| `sticky-session*` | `true/false/false` | Keep a session on its node; if that node dies, fail over (don't return 503). |
| `dynamic-load-provider` | see below | Computes the load factor from live metrics. |

### Load metrics

| Metric | Weight | What it measures |
|---|---|---|
| `heap` | 2 | used heap / max heap (`-Xmx512m` in the pod) |
| `busyness` | 2 | in-flight HTTP requests / `capacity` (40). **Undertow doesn't report a thread max, so `capacity` is required** — without it one request = 100 % busy. |
| `cpu` | 1 | system load average / CPU count. In a container this is the **whole Kubernetes node's** load average, which is why the JBoss pods use anti-affinity to land on different workers. |

## 4. Outbound socket bindings (where the Apaches are)

```xml
<socket-binding-group name="standard-sockets" ...>
    ...
    <outbound-socket-binding name="httpd-proxy-1">
        <remote-destination host="${modcluster.proxy1.host:httpd-0-mcmp}"
                            port="${modcluster.proxy1.port:6666}"/>
    </outbound-socket-binding>
    <outbound-socket-binding name="httpd-proxy-2">
        <remote-destination host="${modcluster.proxy2.host:httpd-1-mcmp}"
                            port="${modcluster.proxy2.port:6666}"/>
    </outbound-socket-binding>
</socket-binding-group>
```

The expressions are resolved at server start; `jboss/entrypoint.sh` sets them
from the `MODCLUSTER_PROXY1` / `MODCLUSTER_PROXY2` environment variables.

## Prefer a hand-written standalone.xml?

You can bake a full file instead of running the CLI: copy the snippets above
into your own `standalone.xml`, and in the first stage of `jboss/Dockerfile`
replace the `jboss-cli.sh` `RUN` step with

```dockerfile
COPY jboss/standalone.xml ${JBOSS_HOME}/standalone/configuration/standalone.xml
```

The CLI approach is used by default because it survives WildFly upgrades — a
copied file is tied to the exact WildFly version it came from.
