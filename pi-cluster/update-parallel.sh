#!/usr/bin/env bash

LOG_DIR="/tmp/pi-update-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$LOG_DIR"
echo "Starting parallel updates across pi-01.lan through pi-10.lan. Logs: ${LOG_DIR}"
echo "------------------------------------------------------------------------"

pids=()
nodes_arr=()

for i in {01..10}; do
    NODE="pi-${i}.lan"
    nodes_arr+=("$NODE")
    log_file="${LOG_DIR}/${NODE}.log"

    (
        ssh -n "ubuntu@${NODE}" "sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Progress-Fancy=0 update && sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Progress-Fancy=0 upgrade -y && sudo apt-get clean && sudo apt-get autoclean -y && sudo apt-get autoremove --purge -y" \
            2>&1 | sed -u "s/^/[${NODE}] /" | tee "$log_file"
        exit "${PIPESTATUS[0]}"
    ) &
    pids+=($!)
done

failures=0
for idx in "${!pids[@]}"; do
    pid="${pids[$idx]}"
    node="${nodes_arr[$idx]}"
    if wait "$pid"; then
        echo "[DONE] ${node} succeeded (log: ${LOG_DIR}/${node}.log)"
    else
        echo "[FAIL] ${node} exited with an error (log: ${LOG_DIR}/${node}.log)"
        failures=$((failures + 1))
    fi
done

echo "------------------------------------------------------------------------"
echo "Parallel update finished. Failures: ${failures}/${#nodes_arr[@]}"
