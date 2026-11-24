#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo ""
date
echo "apt-get update && apt-get upgrade -y"
echo ""
apt-get update && apt-get upgrade -y

echo ""
date
echo "apt-get clean && apt-get autoclean -y && apt-get autoremove --purge -y"
echo ""
apt-get clean && apt-get autoclean -y && apt-get autoremove --purge -y

echo ""
date
echo "all done!"
