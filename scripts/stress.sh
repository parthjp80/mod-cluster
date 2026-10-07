#!/usr/bin/env bash
# Put artificial load on ONE JBoss pod so its mod_cluster load factor drops
# and Apache starts sending it less traffic.
#
#   scripts/stress.sh jboss-0 heap 250     # retain ~250 MB heap   (heap metric)
#   scripts/stress.sh jboss-1 busy 30 120  # 30 requests held 120 s (busyness metric)
#   scripts/stress.sh jboss-0 cpu 120      # spin 2 threads 120 s   (cpu metric = node load avg)
#   scripts/stress.sh jboss-0 release      # free the retained heap
#
# Requests go straight to the pod IP (inside the pod), NOT through Apache,
# so the load lands on exactly the pod you name.
set -euo pipefail
NS="${NS:-modcluster}"
POD="${1:?pod name, e.g. jboss-0}"
WHAT="${2:?heap|busy|cpu|release}"

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

run() { with_timeout 90 kubectl -n "$NS" exec "$POD" -c jboss -- sh -c "$1"; }

case "$WHAT" in
  heap)    run "curl -s -m 60 \"http://\$POD_IP:8080/demo/hog.jsp?mb=${3:-250}\"" ;;
  release) run "curl -s -m 60 \"http://\$POD_IP:8080/demo/hog.jsp?release=1\"" ;;
  cpu)     run "curl -s -m 10 \"http://\$POD_IP:8080/demo/burn.jsp?sec=${3:-120}&threads=2\"" ;;
  busy)
    COUNT="${3:-30}"; SECS="${4:-120}"
    # fire-and-forget: the curls keep running inside the pod after exec returns
    run "for i in \$(seq 1 ${COUNT}); do curl -s -m $((SECS + 30)) \"http://\$POD_IP:8080/demo/slow.jsp?sec=${SECS}\" >/dev/null 2>&1 & done"
    echo "node=${POD} holding ${COUNT} requests for ${SECS}s" ;;
  *) echo "unknown load type: $WHAT" >&2; exit 1 ;;
esac
