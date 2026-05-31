#!/usr/bin/env bash

# Exit immediately if no arguments are provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <command>"
    echo "Example: $0 free -h"
    echo "Example: $0 \"df -h | grep sda\""
    exit 1
fi

# Ensure hosts.ini exists in the same folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${SCRIPT_DIR}/hosts.ini"

if [ ! -f "$INVENTORY" ]; then
    echo "Error: hosts.ini not found in ${SCRIPT_DIR}"
    exit 1
fi

# Verify the SSH agent has keys loaded so it runs hands-free
if ! ssh-add -l >/dev/null 2>&1; then
    echo "Warning: No unlocked keys found in your ssh-agent."
    echo "You may want to run: ssh-add ~/.ssh/id_ed25519"
    echo "------------------------------------------------"
fi

# Run the command and append a clean, colored separator line after every host block
ansible pis -i "$INVENTORY" -m shell -a "$*" | sed "s/\(pi-[0-1][0-9].lan |.*\)/\n========================================================================\n\1/"
