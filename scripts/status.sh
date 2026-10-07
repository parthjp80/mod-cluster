#!/usr/bin/env bash
# Show what each Apache httpd currently knows about the JBoss nodes:
# node name, address, load factor reported by mod_cluster, status, and how
# many requests that httpd has sent to the node ("Elected").
#
#   scripts/status.sh            # one shot
#   scripts/status.sh -w         # refresh every 3 s
set -euo pipefail
NS="${NS:-modcluster}"

# Run a command with a time limit (macOS has no `timeout`). An occasional
# `kubectl exec` stream never returns; this keeps the scripts from hanging.
with_timeout() {
  local secs=$1; shift
  "$@" & local pid=$!
  ( sleep "$secs"; kill "$pid" 2>/dev/null ) & local watcher=$!
  local rc=0; wait "$pid" || rc=$?
  kill "$watcher" 2>/dev/null || true; wait "$watcher" 2>/dev/null || true
  return $rc
}

show() {
  for pod in httpd-0 httpd-1; do
    echo "== ${pod} =="
    with_timeout 20 kubectl -n "$NS" exec "$pod" -- curl -s -m 10 http://127.0.0.1:6666/mod_cluster_manager 2>/dev/null \
      | sed 's/<[^>]*>/ /g' \
      | awk '
          /Node [^ ]+ \(/ { match($0, /Node [^ ]+ \([^)]*\)/); node = substr($0, RSTART + 5, RLENGTH - 5) }
          /Balancer:/ {
            n = split($0, kv, ",")
            load = status = elected = "?"
            for (i = 1; i <= n; i++) {
              split(kv[i], p, ": ")
              gsub(/ /, "", p[1])
              if (p[1] == "Load")    load = p[2]
              if (p[1] == "Status")  status = p[2]
              if (p[1] == "Elected") elected = p[2]
            }
            printf "  %-40s load=%-4s status=%-5s elected=%s\n", node, load, status, elected
          }' \
      || echo "  (unreachable)"
  done
  echo "load: 1..100 (100 = idle, 1 = saturated), 0 = standby, -1 = error"
}

if [[ "${1:-}" == "-w" ]]; then
  while true; do clear; date; show; sleep 3; done
else
  show
fi
