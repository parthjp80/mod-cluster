# How the load-based balancing works

mod_cluster differs from plain `mod_proxy_balancer` in one important way:
**the back-end tells the load balancer how loaded it is.** Apache doesn't
guess from response times or connection counts; each JBoss node computes a
*load factor* and pushes it to every Apache over a separate management
channel called **MCMP** (Mod-Cluster Management Protocol).

## 1. The MCMP conversation

MCMP is plain HTTP with custom methods, sent **from JBoss to httpd** on port
6666. In this project each JBoss pod talks to `httpd-0-mcmp:6666` and
`httpd-1-mcmp:6666`.

```
 jboss-0                                        httpd-0 (and, separately, httpd-1)
    |-- INFO ------------------------------------>|  "what do you know about me?"
    |-- CONFIG  JVMRoute=jboss-0 Host=10.244.1.7  |  register node + its HTTP connector
    |           Port=8080 Type=http Balancer=...->|
    |-- ENABLE-APP  Context=/demo Alias=... ----->|  start routing /demo to this node
    |                                             |
    |-- STATUS  Load=78 ------------------------->|  every 5 s (status-interval)
    |<------------------------------- Type=STATUS-RSP State=OK
    |-- STATUS  Load=41 ------------------------->|
    |   ...                                       |
    |-- STOP-APP / REMOVE-APP ------------------->|  on shutdown (pod terminating)
```

You can see these in the Apache access log:

```
10.244.1.7 - - [...] "INFO / HTTP/1.1" 200 -
10.244.1.7 - - [...] "CONFIG / HTTP/1.1" 200 -
10.244.1.7 - - [...] "ENABLE-APP / HTTP/1.1" 200 -
10.244.1.7 - - [...] "STATUS / HTTP/1.1" 200 64
```

There is no `ProxyPass` anywhere in the Apache config — the routes for
`/demo` are created dynamically from `CONFIG` + `ENABLE-APP`.

If an httpd restarts it loses its node table (it lives in shared memory). The
next `STATUS` from each JBoss gets an error reply, JBoss notices and re-sends
`CONFIG` / `ENABLE-APP`. In testing this took well under 30 seconds.

## 2. How JBoss computes the load factor

The `dynamic-load-provider` in `standalone.xml` samples each metric every
`status-interval` (5 s) and turns it into a value between 0 (idle) and 1
(saturated):

| metric | load value |
|---|---|
| `heap` | `used heap / max heap` |
| `busyness` | `in-flight requests / capacity (40)` |
| `cpu` | `system load average / #CPUs` |

1. **Weighted average of the metrics** (weights 2, 2, 1):

   ```
   load = (2*heap + 2*busyness + 1*cpu) / (2 + 2 + 1)
   ```

2. **Smoothed over time** (`history=4`, `decay=2`): the last 4 samples are
   averaged, each older one weighted half as much as the newer one
   (1, 1/2, 1/4, 1/8). One spike doesn't swing the balancer, but a sustained
   change shows up within 2–3 intervals (10–15 s).

3. **Converted to the factor sent to httpd:**

   ```
   Load = 100 - round(load * 100)        (clamped to 1..100)
   ```

   `100` = idle, `1` = saturated. Special values: `0` = standby node (only
   used when nothing else is available), `-1` = node in error.

## 3. How Apache picks a node

`mod_proxy_cluster` keeps, per node, the last reported `Load` (the worker's
*lbfactor*) and a count of how many requests it has routed to that node since
the last status update (`elected`). For each new request **without a sticky
session** it picks the node with the lowest

```
(elected_since_last_status * 1000) / lbfactor  +  lbstatus
```

Practically: **traffic is shared in proportion to the load factors**. A node
reporting `Load=80` gets about four times as many new requests as one
reporting `Load=20`.

Requests **with** a session cookie (`JSESSIONID=....jboss-0`) go straight to
the node named after the dot — the *JVMRoute*, which is the pod name here.
Because both Apaches receive the same `CONFIG`/`STATUS` messages from both
JBoss nodes, a sticky session works no matter which Apache the front-end
LoadBalancer sends you to.

## 4. Measured on the local compose stack

These are real numbers from `local/compose.yaml` while building this project
(`scripts/demo.sh` with `N=100`, `info.jsp`, no session, ~25 s after applying the load):

| Scenario | jboss-0 Load | jboss-1 Load | jboss-0 share | jboss-1 share |
|---|---|---|---|---|
| Both idle | 69 | 78 | 47 % | 53 % |
| jboss-0 retains ~190 MB extra heap (`hog.jsp`) | 54 | 80 | 41 % | 59 % |
| jboss-1 holds 30 long requests (`slow.jsp`) | 88 | 24 | 78 % | 22 % |

Measured on the home-lab cluster (Proxmox VMs, 2 workers × 2 vCPU,
`scripts/demo.sh` with `N=100`):

| Scenario | jboss-0 Load | jboss-1 Load | jboss-0 share | jboss-1 share |
|---|---|---|---|---|
| Baseline (worker-1, where jboss-1 runs, had a higher load average) | 93 | 37–46 | 78 % | 22 % |
| 250 MB heap retained on jboss-0 | 70 | 25–33 | 59 % | 41 % |
| jboss-1 holds 30 long requests | 93 | 7–14 | 82 % | 18 % |

The baseline was not 50/50 because the `cpu` metric is the *node's* load
average, and worker-1 was busier. mod_cluster routed traffic away from it
before any artificial load was added.

Absolute numbers will differ between runs (different CPU, the
`cpu` metric is the node's load average), but the shape is the same.

## 5. Tuning knobs

| Want… | Change |
|---|---|
| faster reaction | lower `status-interval` (JBoss) and `LBstatusRecalTime` (httpd); lower `history` |
| smoother / less twitchy | raise `history`, keep `decay=2` |
| CPU to matter more | raise `cpu` weight (but remember it's per K8s node, not per pod) |
| balance on request count only | use only `busyness`, or the `requests` metric with a `capacity` (req/s) |
| equal split regardless of load | replace `dynamic-load-provider` with `<simple-load-provider factor="1"/>` |
