#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${SCRIPT_DIR}/hosts.ini"
INTERVAL_MINUTES="${1:-5}"

if [ ! -f "$INVENTORY" ]; then
    echo "Error: hosts.ini not found in ${SCRIPT_DIR}"
    exit 1
fi

NODES=$(awk '/^\[pis\]/{flag=1;next}/^\[/{flag=0}flag && NF && !/^#/{print $1}' "$INVENTORY")

if [ -z "$NODES" ]; then
    echo "Error: No nodes found under the [pis] section in hosts.ini"
    exit 1
fi

idx=1
pids=()

for NODE in $NODES; do
    delay=$((idx * INTERVAL_MINUTES))
    echo "Scheduling reboot on ${NODE} in +${delay} minutes..."

    (
        ssh -n "ubuntu@${NODE}" "sudo shutdown -r +${delay}"
        rc=$?
        if [ $rc -eq 0 ]; then
            echo "[OK] ${NODE}: reboot scheduled in +${delay}m"
        else
            echo "[ERR] ${NODE}: ssh/shutdown exited with status ${rc}"
        fi
    ) &
    pids+=($!)

    idx=$((idx + 1))
done

for pid in "${pids[@]}"; do
    wait "$pid"
done

echo "All staggered reboots have been scheduled."
