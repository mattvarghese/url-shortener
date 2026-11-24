#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 [scp options...] <source> <dest_path>"
    echo "  Upload file:    $0 myupdate.sh /tmp/myupdate.sh"
    echo "  Upload dir:     $0 -r ./config /home/ubuntu/config"
    echo "  Download file:  $0 /etc/os-release ./os-release"
    exit 1
fi

# Last argument is the target path; everything before it is passed to scp
DEST="${!#}"
ARGS=("${@:1:$#-1}")
SRC="${ARGS[$((${#ARGS[@]}-1))]}"
OPTS=("${ARGS[@]:0:$((${#ARGS[@]}-1))}")

failures=0

for i in {01..10}; do
    host="pi-${i}.lan"
    echo "=== ${host} ==="

    if [[ "$SRC" == *"://"* || "$SRC" == *"@"*:* ]]; then
        # Remote-to-local copy: <remote_path> -> ./<dest_dir>/<host>_<filename> or <dest_file>.<host>
        remote_src="${SRC#*:}"
        if [ -d "$DEST" ]; then
            base_name="$(basename "$remote_src")"
            target="${DEST%/}/${host}_${base_name}"
        else
            target="${DEST}.${host}"
        fi
        if scp ${OPTS[@]+"${OPTS[@]}"} "ubuntu@${host}:${remote_src}" "$target"; then
            echo "[OK] ${host} -> ${target}"
        else
            echo "[ERR] ${host}"
            failures=$((failures + 1))
        fi
    else
        # Local-to-remote copy: <local_src> -> ubuntu@pi-XX.lan:<dest>
        if scp ${OPTS[@]+"${OPTS[@]}"} "${ARGS[@]}" "ubuntu@${host}:${DEST}"; then
            echo "[OK] ${host}:${DEST}"
        else
            echo "[ERR] ${host}:${DEST}"
            failures=$((failures + 1))
        fi
    fi
done

echo "----------------------------------------"
echo "Completed with ${failures} failure(s)."

