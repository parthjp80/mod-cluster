#!/usr/bin/env bash
# Send N session-less requests through the Apache front-end and count which
# JBoss node (and which Apache) served them.
#
#   scripts/traffic.sh            # 200 requests to the LoadBalancer IP
#   scripts/traffic.sh 500
#   URL=http://192.168.1.64 scripts/traffic.sh 100
set -euo pipefail
NS="${NS:-modcluster}"
N="${1:-200}"

if [[ -z "${URL:-}" ]]; then
  IP=$(kubectl -n "$NS" get svc httpd-frontend -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  [[ -n "$IP" ]] || { echo "httpd-frontend has no external IP yet (set URL=...)" >&2; exit 1; }
  URL="http://${IP}"
fi

echo "Sending ${N} requests to ${URL}/demo/info.jsp ..."
for _ in $(seq 1 "$N"); do
  curl -s -m 5 "${URL}/demo/info.jsp" || echo "node=ERROR proxy=ERROR"
done | awk '
  { for (i = 1; i <= NF; i++) { split($i, kv, "="); f[kv[1]] = kv[2] }
    node[f["node"]]++; proxy[f["proxy"]]++; total++ }
  END {
    print "\nper JBoss node:"; for (k in node)  printf "  %-10s %5d  (%4.1f%%)\n", k, node[k],  100 * node[k]  / total
    print "per Apache:";      for (k in proxy) printf "  %-10s %5d  (%4.1f%%)\n", k, proxy[k], 100 * proxy[k] / total
  }'
