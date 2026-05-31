echo ""
date
echo "apt update && apt upgrade -y"
echo ""
apt update && apt upgrade -y
echo ""
date
echo "apt clean; apt autoclean -y; apt autoremove --purge -y"
echo ""
apt clean; apt autoclean -y; apt autoremove --purge -y
echo ""
date
echo "all done!"
