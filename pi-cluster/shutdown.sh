#!/usr/bin/env bash

# Ensure hosts.ini exists in the same folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${SCRIPT_DIR}/hosts.ini"

if [ ! -f "$INVENTORY" ]; then
    echo "Error: hosts.ini not found in ${SCRIPT_DIR}"
    exit 1
fi

# Determine arguments to pass. Default to immediate halt if none are given.
# if [ $# -eq 0 ]; then
#     SHUTDOWN_ARGS="-h now"
# else
#     SHUTDOWN_ARGS="$@"
# fi
SHUTDOWN_ARGS="$@"

# Safety Confirmation Prompt
echo "========================================================================"
echo " WARNING: You are about to broadcast a global shutdown command!"
echo " Target Command: sudo shutdown $SHUTDOWN_ARGS"
echo "========================================================================"
read -p "Are you absolutely sure you want to proceed? (y/N): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Operation aborted by user."
    exit 0
fi

echo "Broadcasting 'shutdown $SHUTDOWN_ARGS' to all cluster nodes..."

# Execute via Ansible with sudo elevation (--become)
ansible pis -i "$INVENTORY" -m shell -a "shutdown $SHUTDOWN_ARGS" --become
