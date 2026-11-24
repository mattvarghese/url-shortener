#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 [scp options...] <remote_path> <local_target_prefix>"
    echo "  Pull wildcard: $0 -r '/var/log/app/*' ./collected/logs"
    echo "  Pull file:     $0 /etc/os-release ./collected/os-release"
    exit 1
fi

DEST="${!#}"
DEST="${DEST%/}"
OPTS=("${@:1:$#-2}")
REMOTE_SRC="${@:$#-1:1}"
failures=0

for i in {01..10}; do
    num="$i"
    host="pi-${i}.lan"
    node_dir="${DEST}-${num}"

    mkdir -p "$node_dir"
    echo "=== ${host} -> ${node_dir} ==="

    # Quote the remote path so remote globs like /path/dir/* expand on the Pi, not locally
    if scp "${OPTS[@]}" "ubuntu@${host}:${REMOTE_SRC}" "${node_dir}/"; then
        echo "[OK] ${host} -> ${node_dir}/"
    else
        echo "[ERR] ${host} -> ${node_dir}/"
        failures=$((failures + 1))
    fi
done

echo "----------------------------------------"
echo "Download finished with ${failures} failure(s)."

