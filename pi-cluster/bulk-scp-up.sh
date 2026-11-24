#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 [scp options...] <local_source...> <remote_dest>"
    echo "  Upload file: $0 myupdate.sh /tmp/myupdate.sh"
    echo "  Upload dir:  $0 -r ./config /home/ubuntu/config"
    exit 1
fi

DEST="${!#}"
ARGS=("${@:1:$#-1}")
failures=0

for i in {01..10}; do
    host="pi-${i}.lan"
    echo "=== ${host} ==="
    if scp "${ARGS[@]}" "ubuntu@${host}:${DEST}"; then
        echo "[OK] ${host}:${DEST}"
    else
        echo "[ERR] ${host}:${DEST}"
        failures=$((failures + 1))
    fi
done

echo "----------------------------------------"
echo "Upload finished with ${failures} failure(s)."

