
# Topology

This network topology connects a wireless development workstation and a 10-node Raspberry Pi 3B compute cluster into a single local subnet managed by a GL.iNet SFT1200 Opal Router. The workstation utilizes a 5GHz Wi-Fi link to send administrative controls, while the 10 Raspberry Pi nodes are divided evenly across two TrendNet 8-port 10/100 Mbps unmanaged switches (5 nodes per switch). Each switch hooks directly into a dedicated Ethernet port on the router, providing a clean, balanced wiring structure designed to support cluster-wide K3s orchestration, distributed database sharding, and parallel application scaling.

We will use this topology to build a 10 node Raspberry Pi 3B cluster, and bring it up as a K3S cluster as well.

```text
                               ┌────────────────────────────────┐
                               │       GL.iNet SFT1200          │
                               │         Opal Router            │
                               └───────┬────────┬───────┬───────┘
                                       │        │       │
                        (5GHz Wi-Fi)   │        │       │   (100Mbps Ethernet)
                  ┌────────────────────┘        │       └────────────────────┐
                  │                             │                            │
                  ▼                             ▼ (100Mbps Ethernet)           ▼
     ┌────────────────────────┐        ┌─────────────────┐          ┌─────────────────┐
     │     Lenovo T14 Gen 1   │        │ TrendNet 8-Port │          │ TrendNet 8-Port │
     │     (Dev Workstation)  │        │    Switch #1    │          │    Switch #2    │
     └────────────────────────┘        └─┬─┬─┬─┬─┬───────┘          └─┬─┬─┬─┬─┬───────┘
                                         │ │ │ │ │                    │ │ │ │ │
                                         ▼ ▼ ▼ ▼ ▼                    ▼ ▼ ▼ ▼ ▼
                                        [Pi 01 - 05]                 [Pi 06 - 10]
```

.

# Goal

This file walks you through building the "main" image for the Pis (ubuntu server 26.04), setting up necessary software, cloning to the other 9 Pis, and adjusting the clones, to bring up the RPi3 cluster. It then walks through setting the cluster up as a K3S cluster as well.

.

# "main" image

## Flash the SD Card

To establish a uniform baseline across our 10-node cluster, we will flash a single MicroSD (uSD) card with **Ubuntu 26.04 Server (arm64)**. This card will serve as our "main" image. We use the headless Server variant to keep our base OS footprint minimal (under 100MB RAM idle), leaving the maximum amount of the Pi 3B's 1GB memory available for K3s workloads.

### 1. Install Raspberry Pi Imager on Linux
Install the official Raspberry Pi Imager tool on your developer workstation
```bash
sudo apt update
sudo apt install raspberrypi-imager

```

### 2. Launch the Application

You can search for "Raspberry Pi Imager" in your desktop environment's application launcher, or fire it up directly from the terminal:

```bash
rpi-imager &

```

### 3. Selection Steps to Flash Ubuntu 26.04 Server

Insert your first 32GB uSD card into your developer workstation, open the Imager tool, and execute the following configuration loop precisely:

1. **Raspberry Pi Device:** Click **CHOOSE DEVICE** and select **Raspberry Pi 3** from the list.
2. **Operating System:** Click **CHOOSE OS**.
* Navigate to: **Other general-purpose OS** ──> **Ubuntu** ──> **Ubuntu Server 26.04 LTS (64-bit)**.
* *Critical Note:* Ensure you select the **64-bit (arm64) Server architecture**, not the 32-bit (armhf) version or Desktop flavor, to meet K3s structural pre-requisites.

3. **Storage:** Click **CHOOSE STORAGE** and carefully select your target 32GB uSD card from the drive menu.
4. **OS Customization:** A prompt will appear asking if you want to apply OS customization settings. Click **EDIT SETTINGS**. Under the *General* tab:
* Set the initial hostname to `pi-main`.
* Configure your default username (e.g., `ubuntu`) and set a secure password.
* Under the *Services* tab, check **Enable SSH** and select **Allow password authentication**.
* Click **SAVE**.

5. **Write:** Click **NEXT** and confirm the write operations. The utility will download the OS binary, format the partitions, flash the image, and run a block verification cycle.

Once the verification finishes, eject the uSD card from your workstation. 

.

## First Boot

The uSD card can now be inserted into a Raspberry Pi 3B and booted. Note that even though Gemini claimed first boot can be headless, that did not work for me. The pi wouldn't show up on the client list of the router. But connecting a monitor and keyboard, and rebooting the pi made it show up.

Next, ssh into pi-main.lan 
```bash
ssh ubuntu@pi-main.lan
```

Then apt update and apt upgrade
```bash
sudo apt update
sudo apt upgrade -y
sudo apt clean -y
sudo apt autoclean -y
sudo apt autoremove -y
```

You might be prevented from upgrade because the unattended upgrade is running. In that case, to see its status, use
```bash
sudo tail -f /var/log/unattended-upgrades/unattended-upgrades.log
```
and
```bash
sudo tail -f /var/log/unattended-upgrades/unattended-upgrades-dpkg.log
```

.

## Optimizing the "main" image

With the initial system update completed, we will install the base software dependencies required for container runtime management and remote graphical interfaces across our 10-node cluster layout.

### 0. Remove Canonical's snap / snapd
To reclaim critical memory overhead and eliminate unnecessary storage loops on our resource-constrained 1GB Pi nodes, we purge Canonical's underlying container package manager, its runtime dependencies, and all accompanying background tracking daemons.

First, identify any active snaps deployed by default:
```bash
snap list

```

Wipe out any existing payload snaps discovered in the step above sequentially, making sure to discard the core frameworks last (use the `--purge` flag to completely strip local caches):

```bash
# Clear any default application layers first (e.g., lxd if present - there was noe)
sudo snap remove --purge lxd

# Purge the remaining underlying snap runtime components if present - wasn't
sudo snap remove --purge core22

# Remove snapd - this was needed
sudo snap remove --purge snapd

```

Once the payload container queues are totally empty, cleanly remove the core system daemon binaries, its APT integration hooks, and sweep away any orphan configuration paths left in your system partition:

```bash
# Purge the package database entries
sudo apt purge -y snapd

# Scrub the filesystem of orphaned directory artifacts
sudo rm -rf ~/snap /var/snap /var/lib/snapd

```
### 1. Base Software Installation
Run the following command to pull down the core runtime engines and graphical application packages:

```bash
sudo apt update && sudo apt install -y \
  docker.io \
  xauth \
  xfce4-taskmanager \
  mousepad \
  btop \
  iotop \
  lm-sensors 
sudo usermod -aG docker $USER
```
Then reboot the pi
```bash
sudo shutdown -r now
```

#### Software Architecture Decisions:

* **Docker:** Installed as an alternative containerization engine backend baseline, allowing container execution natively on the host alongside K3s's internal runtimes.
* **XAuth:** Installs the necessary X11 authority engineering mechanisms to safely stream window rendering parameters across an `ssh -X` or `ssh -Y` connection back to your development workstation.
* **Text Editor (Mousepad vs. Pluma vs. VS Code):** We choose **Mousepad** (the default XFCE editor). It is stripped of heavy runtime plugins, making it vastly lighter than Pluma (MATE). Running VS Code natively on a Pi 3B is extreme overkill for this hardware layer; it consumes upwards of 600–800MB RAM just to open an empty workspace, which would exhaust the node's 1GB memory capacity.
* **System Monitor (btop vs. htop/Flatpak):** We explicitly choose **btop** to fill our visual monitoring requirements while completely bypassing Flatpak and heavy graphical desktop frontends. While `htop` is a useful baseline text utility, `btop` provides a highly accurate, interactive dashboard interface that streams live per-core wave graphs, network interface usage, and memory tiers over standard SSH tunnels without requiring X11 rendering structures.
* **Storage Diagnostics (iotop):** Operating a multi-node Kubernetes cluster directly on uSD media presents an extreme storage bottleneck due to frequent state writes to the datastore backend. We include **iotop** as a standalone diagnostic tool to capture real-time, process-level I/O metrics across the host interface, allowing us to immediately isolate containers or applications that cross unsafe read/write thresholds before they induce storage latency cascades.

### 2. Dynamic GUI/TTY Text Editor Configuration

To ensure text editing commands automatically scale based on your connection state, append the following logic to the bottom of your shell configuration. This detects if an X11 forwarding stream is open and forces `sudoedit` to present either the graphical **Mousepad** app or fallback directly to a native terminal layout.

Run the following command to inject this behavior directly into your profile:

```bash
cat << 'EOF' >> ~/.bashrc

# Sudoedit setup
alias mp="mousepad"
export VISUAL="mousepad"

EOF

```

You could source the file to apply the environment configurations to your current terminal session, but instead exit out of SSH and re-login with X
```bash
ssh -Y ubuntu@pi-main.lan
```

Next, `sudoedit /root/.bashrc` and add this to the end:
```bash
# ==========================================================
# Custom functions
zeroclean() {
  echo "before clean.."
  ls
  echo "cleaning.."
  dd if=/dev/zero of=zerofile.userclean bs=4M status=progress
  sync
  echo "with zerofile.userclean.."
  ls
  echo "deleting zerofile.userclean.."
  rm zerofile.userclean
  sync
  echo "after delete.."
  ls
  echo "all done!"
}
myupdate() {
  echo ""
  date
  echo "apt update && apt upgrade -y"
  echo ""
  apt update && apt upgrade -y
  echo ""
  date
  echo "apt clean; apt autoclean -y; apt autoremove --purge -y;"
  echo ""
  apt clean; apt autoclean -y; apt autoremove --purge -y
  echo ""
  date
  echo "all done!"
}
# ==========================================================
```
.

## Preparing the "main" Image for Cloning

Before we can safely extract this uSD card and clone it across the remaining 9 cluster nodes, we must generalize the filesystem. If left un-cleared, every single cloned node will broadcast duplicate internal system identifiers and cached network configuration requests, causing machine-id and local DNS naming collisions on your network.

### 1. Clear Machine IDs and Unique Identifiers
Run the following sequence to truncate systemd machine IDs and remove cached D-Bus states so they regenerate uniquely on each hardware node's next boot:

```bash
# Truncate the machine-id files (do not delete the files themselves)
sudo truncate -s 0 /etc/machine-id
sudo truncate -s 0 /var/lib/dbus/machine-id

```

### 2. Purge Cached DHCP Leases and Cloud-Init Network States

Clear out old lease history to ensure that your clones don't try to inherit `pi-main`'s dynamic router tracking history:

```bash
# Clean network runtime allocations
sudo rm -rf /var/lib/dhcp/dhclient.*
sudo rm -rf /var/lib/NetworkManager/dhclient-*
sudo rm -rf /var/lib/netplan/*.yaml.bak
sudo rm -rf /var/lib/cloud/instance

```

### 3. Strip SSH Host Keys

To maintain pristine crypto-security boundaries across your network topology, remove the host-specific key pairs. The `openssh-server` daemon will automatically detect their absence on next boot and safely generate a new unique key set for each Pi:

```bash
sudo rm -f /etc/ssh/ssh_host_*

```

### 4. Adjust Cloud-Init Configuration
```bash
sudoedit /etc/cloud/cloud.cfg
```
find `preserve_hostname: false` and change it to `preserve_hostname: true`

### 5. Final Power Down

Shut down the main node immediately. It is now ready to be safely removed from the board for disk duplication.

```bash
sudo shutdown -h now

```

.

## Cloning the uSD Cards

Instead of copying the entire raw 32GB footprint of the master card ten separate times, we will perform a high-speed sector-limited clone. We will use a graphical partition tool to shrink our active filesystem down under a tight 5GB boundary. This allows us to use `dd` with a fixed block count, reading and writing only the first 5GB of data. This cuts out 27GB of dead space per card, drastically accelerating our deployment timeline while completely avoiding flash size variance traps.

### 1. Shrink the Master Filesystem on Your Workstation
1. Remove the master uSD card from `pi-main` and insert it into your Lenovo T14 workstation.
2. Open **`gparted`** (or your preferred graphical partition utility) on your workstation.
3. Select your uSD card device from the top-right dropdown menu (e.g., `/dev/sda` or `/dev/mmcblk0`).
4. Select the primary Linux data partition (`ext4`), right-click, and select **Resize/Move**.
5. Shrink the partition down to a safe boundary below 5GB—ideally **3.7 GB** (`4400 MB`)—leaving the remaining space unallocated.
6. Click the green checkmark (**Apply All Operations**) to rewrite the partition tables.

### 2. Read the Truncated Base segment onto Your Workstation
Identify your master card's raw block name using `lsblk`. Run `dd` with a strict block limit to extract *only* the first 5GB space containing our data payload, completely ignoring the trailing unallocated dead sectors:

```bash
# Unmount any partitions automatically mounted by your OS desktop environment
sudo umount /dev/sda*

# Read exactly 5GB of data (1024 blocks of 4MB) to a local raw image file
sudo dd if=/dev/sda of=pi_cluster_5g_base.img bs=4M count=1280 status=progress && sync

```

### 3. Bulk Write the Shrunk Image to the Clone Cards

Eject the master card. For each of your remaining 9 blank 32GB uSD cards, insert them into your workstation one by one, unmount any default system hooks, and flash them using the speed-optimized 5GB payload file:

```bash
# 1. Unmount default desktop partitions before running
sudo umount /dev/sda*

# 2. Stream the tight 5GB footprint directly onto the target card
sudo dd if=pi_cluster_5g_base.img of=/dev/sda bs=4M status=progress && sync

# 3. Probe partitions again
sudo partprobe /dev/sda

# 4. Force parted to expand partition #2 to fill 100% of the physical media
sudo parted /dev/sda resizepart 2 100%

# 5. Run a quick check to satisfy the filesystem resizer
sudo e2fsck -f -y /dev/sda2

# 6. Expand the underlying ext4 filesystem data layers into the newly added space
sudo resize2fs /dev/sda2

```

### 4. Generate SSH Host Keys Offline for Headless Rack Readiness
Because we stripped the original SSH host keys during generalization, the operating system would normally attempt to rebuild them on its initial boot loop. On a headless, display-less node, this can occasionally race ahead of the network interface initialization, causing a `Connection refused` error on your first login attempt. 

To guarantee that your headless rack nodes allow immediate connection over your 5GHz Wi-Fi administrative tunnel, generate the cryptographic key pairs directly from your workstation right now while the partition is still open:

```bash
# 1. Create a temporary target directory and mount the primary root filesystem (`sda2`) of your newly cloned card:
sudo mkdir -p /mnt/pi_root
sudo mount /dev/sda2 /mnt/pi_root

# 2. Force `ssh-keygen` to mint standard system cryptographic sets (RSA, ECDSA, ED25519) directly into the target card's configuration directory path:
sudo ssh-keygen -A -f /mnt/pi_root

# 3. Verify the files are safely in place with their strict system ownership settings intact:
ls -l /mnt/pi_root/etc/ssh/ssh_host_*

# 4. Unmount the path cleanly to flush the memory caches and prevent block corruption:
sudo umount /mnt/pi_root

```

*(Physically label each card `Pi 01` through `Pi 10` with a piece of tape as soon as it drops out of the burner to stay organized during hardware rack mounting!)*

.

## Post-Clone Adjustments & Initial Boot

Because your GL.iNet Opal Router automatically maps your clients natively to local DNS via `<hostname>.lan`, we do not need to configure complex static IP allocation tables or touch network files. Instead, we simply boot the nodes, expand their storage back to maximum capacity, and change their hostnames.

To avoid naming collisions on your local network interface, boot and configure your cards sequentially using the following loop:

### 1. Boot Node 01

Insert the first cloned card into your designated Master node, hook it into Switch #1, and power it on. Because we cleared the machine identifiers, the local router will initially discover it under its default unconfigured name.

SSH into the node from your workstation:

```bash
ssh -Y ubuntu@pi-main.lan

```

### 2. Assign the Local Hostname

Update the node's hostname identity. We will use a tight, standard numbering scheme (`pi-01` through `pi-10`). Run this command on the target node (replace `pi-XX` with your target node name, e.g., `pi-01`):

```bash
sudo hostnamectl set-hostname pi-01

```

### 3. Reboot to Register with the Router

Force a quick reboot to refresh the entire filesystem envelope and register the new name:

```bash
sudo shutdown -r now

```

Verify your workstation can now cleanly resolve the node directly over your 5GHz Wi-Fi link without knowing its IP:

```bash
ssh ubuntu@pi-01.lan

```

### 4. Repeat for Nodes 02 through 10

Repeat this quick sequence one by one for the remaining cards. Once all 10 cards are completed, your entire network foundation is established, fully updated, optimized, expanded, and ready for global **K3s/Ansible** automated cluster deployment orchestration!

.

## Power up the cluster

At this point, all 10 uSD cards are on the 10 pis. We can bring up the pis now. When we do so, we see `pi-01.lan` through `pi-10.lan` active on the router's client list. We can ssh into them with password right now. 

.

# Generate & Map SSH Keys for Automated Orchestration

Instead of typing your password 10 separate times, your workstation uses an asymmetric SSH key pair to authenticate securely with the cluster layout. We will protect this key with a secure passphrase and manage it using a background agent. This gives you the security of encrypted storage alongside the hands-free speed needed for Ansible orchestration.

## 1. Configure the SSH Agent Natively on Your Workstation

To ensure you only have to unlock your key once per session, add this logic to your shell profile. This tells your environment to automatically discover or initialize a background agent process whenever you launch a terminal:

```bash
cat << 'EOF' >> ~/.bashrc

# Automatically start and manage the SSH Agent session
if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)" > /dev/null
fi
EOF

```

Source the file to active it immediately in your current window:

```bash
source ~/.bashrc

```

## 2. Check or Generate Your High-Security SSH Key

On your **Lenovo T14 terminal**, verify whether an active identity file already exists:

```bash
ls -l ~/.ssh/id_ed25519

```

If missing, mint a high-security, lightweight Ed25519 key pair. **When prompted, type a secure passphrase** to encrypt your private key on disk:

```bash
ssh-keygen -t ed25519 -C "dev-workstation"

```

## 3. Unlock Your Key for Your Current Desktop Session

Add your newly created private key to your active background agent. You will type your passphrase **once** here to decrypt it into your laptop's volatile RAM:

```bash
ssh-add ~/.ssh/id_ed25519

```

## 4. Blast Public Keys to All 10 Nodes (The Fast Way)

Execute this quick shell loop to install your laptop's **public key lock** (`~/.ssh/id_ed25519.pub`) across the entire rack array instantly. Your private key remains securely cached on your workstation and never leaves your laptop.

```bash
for i in {01..10}; do
  echo "--- Copying public key to pi-$i.lan ---"
  ssh-copy-id ubuntu@pi-$i.lan
done

```

*Note: You will be prompted to enter the standard password for each Pi one last time during this loop to approve installing the key.*

## 5. Test Hands-Free Connectivity

Verify you can now stream administrative controls directly into any node instantly without being challenged for passwords or passphrases:

```bash
ssh ubuntu@pi-01.lan "hostname && uptime"

```

.

# Install and Configure Ansible on Your Laptop

Ansible is completely agentless. It doesn't require installing any heavy background software on the resource-constrained 1GB Raspberry Pis; it just logs in over standard SSH, executes tasks, and disconnects.

## 1. Install Ansible Natively

Run this on your **Lenovo workstation**:

```bash
sudo apt update
sudo apt install -y ansible

```

## 2. Draft Your Hosts Inventory

Create an inventory tracking layout file named `hosts.ini`. Then paste your complete topology configuration mapping into it:

```ini
[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/id_ed25519

[pis]
pi-01.lan
pi-02.lan
pi-03.lan
pi-04.lan
pi-05.lan
pi-06.lan
pi-07.lan
pi-08.lan
pi-09.lan
pi-10.lan

[k3s_master]
pi-01.lan

[k3s_workers]
pi-02.lan
pi-03.lan
pi-04.lan
pi-05.lan
pi-06.lan
pi-07.lan
pi-08.lan
pi-09.lan
pi-10.lan

```

.

# Run the First Cluster-Wide Orchestration

Let's run a live diagnostic check to prove your laptop controls the entire 10-node array.

## 1. Test the Global Ping

Execute an Ansible ad-hoc ping module test. This confirms Python is happy on the nodes and authentication handles correctly:

```bash
ansible pis -i hosts.ini -m ping

```

You should see a glorious wall of 10 green `"ping": "pong"` success status returns.

## 2. Check Global Resource Footprints

Let's see exactly how much memory your snap-purged base OS images are consuming before K3s lands:

```bash
ansible pis -i hosts.ini -m shell -a "free -h"

```

## 3. Create utility scripts

Create scripts such as `broadcast.sh`, `shutdown.sh` etc. as utility scripts.

To allow automation scripts to execute privilege elevation hands-free, we need to instruct the remote OS configuration to allow the `ubuntu` user to run `sudo` without password intervention.

### Step A: Setup passwordless sudo for `ubuntu`

Run this script from the command line

```bash
for i in {01..10}; do
  echo "--- Setting up passwordless sudo on pi-$i.lan ---"
  ssh -t ubuntu@pi-$i.lan "echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/90-ubuntu-user"
done

```

### Step B: "Cloud-Init" Update

If you only do the above, the next time you reboot the cluster cloud-init will wake up and completely overwrite or ignore the file we just created in Step A. To fix this, we must adjust cloud-init's core profile configuration file. 

```bash
./broadcast.sh "echo 'user: { name: ubuntu, sudo: [\"ALL=(ALL) NOPASSWD:ALL\"] }' | sudo tee /etc/cloud/cloud.cfg.d/99-custom-user.cfg"

```

### Step C: Test with the `shutdown.sh` script

Now that the authentication barriers are entirely cleared, test the parameterized shutdown script again using the reboot command:

```bash
./shutdown.sh -r

```

## 4. Create `apt upgrade` Utility

Earlier, we created a bash function `myupdate` in root's `.bashrc`. However, that doesn't work with `./broadcast.sh` because when we do `sudo myupdate`, our `.bashrc` is not sourced. To fix this, we will make a `myupdate.sh` script

### A. Save a script on your laptop

Create a local file named `myupdate.sh` in your workspace folder (`touch myupdate.sh`):

```bash
#!/usr/bin/env bash
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

```

### B. Copy the script to all 10 Pis using Ansible

Instead of trying to inject lines into a text file or struggle with complex nesting, use Ansible's built-in ad-hoc `copy` module to safely push the executable file straight to the system binary path on every node:

```bash
ansible pis -i hosts.ini -m copy -a "src=myupdate.sh dest=/usr/local/bin/myupdate.sh mode=0755" --become

```

#### 3. Execute it perfectly

Because `/usr/local/bin` is in the default execution `$PATH` for every user (including root), it is now a native system command. You can run it across the entire rack cleanly with a single, un-nested command string:

```bash
./broadcast.sh sudo myupdate.sh

```
We also create an `update.sh` script which does exactly this. We actually never need to run this, because there is the unattended upgrade. But it is nice to do the clean/autoclean/autoremove














---

## What's Next? (Pre-K3s Hardening Playbook)

Once your ping returns green across the board, we shouldn't manually run the K3s installers yet. The Raspberry Pi 3B has exactly 1GB of RAM, meaning a couple of minor OS optimization missteps will trigger memory leaks or cause kernel deadlocks under cluster loads.

Before installing K3s, our next step should be writing a single **Ansible Playbook** to automate the following system hardening steps across all 10 nodes:

1. **Enable cgroups** (Critical! K3s container engines will refuse to boot without `cgroups=memory` explicitly appended to `/boot/firmware/cmdline.txt`).
2. **Standardize SWAP allocations** (MicroSD cards will choke if swap spaces aren't tightly capped or configured cleanly to avoid thrashing cascades).
3. **Run `myupdate` baseline triggers** globally to verify total package parity.

Should we draft that pre-K3s preparation playbook file next?