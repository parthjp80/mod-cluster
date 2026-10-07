# Troubleshooting

All commands assume `NS=modcluster`.

## Quick health picture

```bash
kubectl -n modcluster get pods,svc -o wide
scripts/status.sh                         # node table + load factor, per Apache
kubectl -n modcluster logs httpd-0 | grep -E 'CONFIG|ENABLE-APP|STATUS' | tail
kubectl -n modcluster logs jboss-0 | grep -i modcluster
```

## Symptoms

### `503 Service Unavailable` on `/demo`

No enabled node has registered `/demo` with the Apache that served you.

1. `scripts/status.sh` — are both `jboss-*` nodes listed under that httpd?
2. If a node is missing, check the JBoss log for
   `MODCLUSTER000043: Failed to send ... to httpd-0-mcmp/...:6666`.
   - `<unresolved>` → the `httpd-N-mcmp` Service doesn't exist / DNS issue.
   - `Connection refused` / timeout → httpd pod not running, or the
     NetworkPolicy is blocking (pod labels must be `app=jboss`).
3. If the node is listed but the context is `STOPPED`/`DISABLED`, the
   deployment failed or the server is still starting — check
   `kubectl logs jboss-0` for `WFLYSRV0025` (started) and deployment errors.

### Apache returns `403` on `/mod_cluster_manager`

The `Require ip` lists in `apache/conf/mod_cluster.conf` only allow private
ranges. If your LAN isn't 192.168/16, 10/8 or 172.16/12, add it. From inside the
pod it always works:

```bash
kubectl -n modcluster exec httpd-0 -- curl -s http://127.0.0.1:6666/mod_cluster_manager
```

### Node shows `Load: -1` or `Status: NOTOK`

httpd can't reach the node's registered address (`http://<pod-ip>:8080`). The
JBoss pod binds its HTTP listener to `$POD_IP` and registers that address;
make sure the pod network allows httpd → jboss on 8080. Also check the `ping`
attempts in the httpd log (`proxy_cluster:info`).

### Traffic doesn't shift when a node is loaded

* Wait at least 15–20 s: STATUS every 5 s, 4-sample decayed history.
* Use `info.jsp` (no session). `index.jsp` creates a session and sticks you to
  one node — that is intended.
* `cpu` is the **node's** load average. If both JBoss pods are on the same
  worker, `burn.jsp` raises both loads equally. Check
  `kubectl -n modcluster get pods -o wide`.
* Make sure `busyness` has `capacity` set — without it, any single in-flight
  request reports 100 % busy and both nodes look the same.

### JBoss pod stuck in `Init:0/1`

The init container waits until `httpd-0-mcmp.<namespace>.svc.cluster.local`
and `httpd-1-mcmp...` resolve (`kubectl logs jboss-0 -c wait-for-httpd-services`).
The Services are part of `k8s/httpd.yaml`; apply the whole kustomization
(`kubectl apply -k k8s`). The fully qualified name is deliberate: busybox
`nslookup` exits non-zero for a short name whenever any DNS search domain
returns NXDOMAIN, even though the name itself resolved.

### `Fatal glibc error: CPU does not support x86-64-v2`

The container image needs a newer CPU feature level than the VM exposes.
Proxmox's default CPU type (`kvm64`/`qemu64`) is x86-64-v1 — check with

```bash
kubectl -n modcluster exec httpd-0 -- grep -m1 -o -w 'sse4_2' /proc/cpuinfo || echo "x86-64-v1 only"
```

This project's JBoss image avoids it (Ubuntu 24.04 + Temurin). To run
RHEL 9/10-based images (official WildFly, JBoss EAP, UBI) on these VMs, change
each Proxmox VM's CPU type to **`host`** (or at least `x86-64-v2-AES`):
Proxmox UI → VM → Hardware → Processors → Type, then **shut down and start**
the VM (a reboot from inside the guest is not enough). Drain each node first:
`kubectl drain k8s-worker-1 --ignore-daemonsets --delete-emptydir-data`.
Use `host` only if you don't live-migrate between hosts with different CPUs.

### Helper scripts hang

An occasional `kubectl exec` stream never returns. `status.sh` and
`stress.sh` wrap every exec in a 20 s / 90 s time limit; if you run the
commands by hand, add `curl -m 10` and press Ctrl-C if needed.

### `ImagePullBackOff`

* ghcr.io packages are **private** by default. Either make the two packages
  public (GitHub → Packages → settings) or create a pull secret:

  ```bash
  kubectl -n modcluster create secret docker-registry ghcr \
    --docker-server=ghcr.io --docker-username=<user> --docker-password=<PAT with read:packages>
  kubectl -n modcluster patch serviceaccount default \
    -p '{"imagePullSecrets":[{"name":"ghcr"}]}'
  ```

* Built on an Apple-silicon Mac without `PLATFORM=linux/amd64` → `exec format
  error`. The Makefile defaults to `linux/amd64`.

### JBoss restarts with `OOMKilled`

The container limit is 900 Mi with `-Xmx512m`. `hog.jsp` refuses to grow the
heap past ~85 %, but if you change `JAVA_OPTS`, keep the limit ≈ heap + 350 Mi
(metaspace, threads, native).

## Turning up logging

Apache (temporary, inside the pod):

```bash
kubectl -n modcluster exec httpd-0 -- sh -c \
  "sed -i 's/^LogLevel .*/LogLevel warn manager:debug proxy_cluster:debug/' conf/extra/mod_cluster.conf && httpd -k graceful"
```

JBoss (runtime, via the management CLI in the pod):

```bash
kubectl -n modcluster exec jboss-0 -- /opt/jboss/wildfly/bin/jboss-cli.sh -c \
  '/subsystem=logging/logger=org.jboss.modcluster:add(level=DEBUG)'
```

With DEBUG on, every `STATUS` message and its `Load=` value appears in the
JBoss log.

## Reading live mod_cluster state from JBoss

```bash
kubectl -n modcluster exec jboss-0 -- /opt/jboss/wildfly/bin/jboss-cli.sh -c \
  '/subsystem=modcluster/proxy=default:read-proxies-info'
```

returns the raw `INFO` reply of each Apache (nodes, hosts, contexts) as seen
from this JBoss node.
