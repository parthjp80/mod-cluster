#!/usr/bin/env bash
# Guided end-to-end demo of load-based balancing.
#   1. baseline   : both nodes idle -> traffic split roughly evenly
#   2. heap       : jboss-0 retains heap -> its load factor drops -> gets less traffic
#   3. busy       : jboss-1 holds 30 requests -> it gets very little traffic
set -euo pipefail
cd "$(dirname "$0")"
N="${N:-200}"
pause() { echo; echo ">>> waiting ${1}s for STATUS messages (every 5 s) to update httpd..."; sleep "$1"; }

echo "### 1. Baseline";                    ./status.sh; ./traffic.sh "$N"

echo; echo "### 2. Heap pressure on jboss-0"; ./stress.sh jboss-0 heap 250
pause 25;                                   ./status.sh; ./traffic.sh "$N"
./stress.sh jboss-0 release

echo; echo "### 3. Busy threads on jboss-1"; ./stress.sh jboss-1 busy 30 90
pause 25;                                   ./status.sh; ./traffic.sh "$N"

echo; echo "Done. Loads recover within ~30 s once the slow requests finish."
