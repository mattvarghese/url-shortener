#!/usr/bin/env bash

# Examples
#
# To find temperatures
#    Do once: ./serialcast.sh sudo apt install -y lm-sensors
# Then: ./serialcast.sh sensors
#
# To check for thermal throttling
# $ ./serialcast.sh sudo vcgencmd get_throttled
#
# To check space usage
# $ ./serialcast.sh df -h
#


# Ensure hosts.ini exists in the same folder to dynamically grab our hostnames
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${SCRIPT_DIR}/hosts.ini"

if [ ! -f "$INVENTORY" ]; then
    echo "Error: hosts.ini not found in ${SCRIPT_DIR}"
    exit 1
fi

# Grab all arguments passed to the script
REMOTE_COMMAND="$@"

# Error handling if no command was passed
if [ -z "$REMOTE_COMMAND" ]; then
    echo "Error: No command specified."
    echo "Usage: $0 <command>"
    echo "Example: $0 sudo myupdate"
    exit 1
fi

# Extract hostnames dynamically from the [pis] block in hosts.ini
# This filters out inventory comments, empty lines, and section headers
NODES=$(awk '/^\[pis\]/{flag=1;next}/^\[/{flag=0}flag && NF && !/^#/{print $1}' "$INVENTORY")

if [ -z "$NODES" ]; then
    echo "Error: No nodes found under the [pis] section in hosts.ini"
    exit 1
fi

# Iterate through each node sequentially with fully streamed, interactive TTY allocation
for NODE in $NODES; do
    echo "========================================================================"
    date
    echo " >>> EXECUTING ON: $NODE <<<"
    echo " Command: $REMOTE_COMMAND"
    echo "========================================================================"
    echo ""
    
    # -t forces TTY allocation for interactive output/color
    # ubuntu@ establishes the default connection user
    ssh -t "ubuntu@${NODE}" "$REMOTE_COMMAND"
    
    echo ""
done

echo "========================================================================"
date
echo "Serial broadcast complete across all accessible nodes!"
echo "========================================================================"
echo ""
