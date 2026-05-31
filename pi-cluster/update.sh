# ./broadcast.sh sudo myupdate.sh

# Above option will work, but won't stream output realitme
# So instead we do the below. 
# This loses parallelism, but gives us streaming output.

for i in {01..10}; do
  echo "========================================================================"
  echo " >>> MAINTENANCE CYCLE: pi-$i.lan <<<"
  echo "========================================================================"
  
  ssh -t ubuntu@pi-$i.lan "sudo myupdate.sh"
  echo ""
done
