# K3s Setup — Detailed Walkthrough

## Overview
This directory contains two Ansible playbooks:
- `pre-k3s-hardening.yml` — prepares every Pi 3B node before K3s is installed.
- `install-k3s.yml` — installs the K3s control plane on one master and agents on the rest.

Inventory groups come from `../hosts.ini`:
- `[pis]` — all 10 nodes
- `[k3s_master]` — `pi-03.lan` (single server/control plane)
- `[k3s_workers]` — the other 9 nodes

---

## `pre-k3s-hardening.yml`

### Play header
```yaml
- name: Pre-K3s hardening for Pi 3B nodes
  hosts: pis          # runs on all 10 nodes
  become: true        # use sudo
```

### Task 1 — Ensure cgroup tokens in cmdline.txt
```yaml
- name: Ensure cgroup tokens in /boot/firmware/cmdline.txt
  ansible.builtin.shell: |
    set -e
    F=/boot/firmware/cmdline.txt
    grep -q 'cgroup_enable=memory' "$F" || sed -i 's/$/ cgroup_enable=memory cgroup_memory=1/' "$F"
  args:
    executable: /bin/bash
  register: cg
  changed_when: cg.rc == 0
```
- `hosts: pis` targets all nodes.
- `become: true` runs as root.
- `shell` runs a bash snippet:
  - `set -e` → fail on any error.
  - `F=...` → path to the Pi boot command line.
  - `grep -q 'cgroup_enable=memory'` → checks if the token already exists.
  - `|| sed -i 's/$/ .../'` → only if missing, append both tokens to the end of the single cmdline line.
- `register: cg` stores the result (rc, stdout, etc.).
- `changed_when: cg.rc == 0` marks the task as "changed" when the command succeeded (rc 0). (Note: rc 0 happens even when grep matched and nothing was appended; this is a minor imprecision but harmless.)

Why: K3s/containerd refuses to start without memory cgroups enabled on the kernel command line on Raspberry Pi OS / Ubuntu firmware boot.

### Task 2 — Disable swap now
```yaml
- name: Disable swap now
  ansible.builtin.command: swapoff -a
  changed_when: false
  failed_when: false
```
- Runs `swapoff -a` to turn off all swap immediately.
- `changed_when: false` → never report as changed (idempotent-ish reporting).
- `failed_when: false` → don't fail the play if swap was already off.

Why: swapping on a uSD card causes severe I/O latency; with 1GB RAM we want predictable memory pressure, not disk thrash.

### Task 3 — Remove swap entries from fstab
```yaml
- name: Remove swap entries from fstab
  ansible.builtin.lineinfile:
    path: /etc/fstab
    regexp: '\sswap\s'
    state: absent
```
- `lineinfile` with `state: absent` deletes any line matching the regex `\sswap\s` (a swap mount line).
- Ensures swap stays off after reboot.

### Task 4 — Set swappiness
```yaml
- name: Set swappiness
  ansible.posix.sysctl:
    name: vm.swappiness
    value: "1"
    state: present
    reload: true
```
- Sets `vm.swappiness=1` in `/etc/sysctl.conf` (or sysctl.d) and applies it live via `sysctl --system` (`reload: true`).
- Makes the kernel avoid swapping unless absolutely necessary.

### Task 5 — Reboot if cmdline changed
```yaml
- name: Reboot nodes to apply cgroups
  ansible.builtin.reboot:
    reboot_timeout: 300
  when: cg.changed
```
- `reboot` module reboots the node and waits for SSH to come back.
- `reboot_timeout: 300` → wait up to 5 minutes.
- `when: cg.changed` → only reboot if the cgroup edit actually changed the file.

---

## `install-k3s.yml`

### Play 1 — Master install
```yaml
- name: Install K3s server on master
  hosts: k3s_master       # only pi-03.lan
  become: true
```

#### Task 1.1 — Install K3s server
```yaml
- name: Install K3s server
  ansible.builtin.shell: |
    set -e
    curl -sfL https://get.k3s.io | sh -
  args:
    executable: /bin/bash
  creates: /usr/local/bin/k3s
```
- Downloads and runs the official K3s installer, which installs K3s as a systemd service (`k3s.service`) and starts it.
- `creates: /usr/local/bin/k3s` → skips if already installed (idempotency guard).

#### Task 1.2 — Wait for node-token
```yaml
- name: Wait for node-token
  ansible.builtin.wait_for:
    path: /var/lib/rancher/k3s/server/node-token
    timeout: 120
```
- Blocks until the server has written its join token file (up to 2 minutes).

#### Task 1.3 — Read node token
```yaml
- name: Read node token
  ansible.builtin.slurp:
    src: /var/lib/rancher/k3s/server/node-token
  register: node_token_raw
```
- `slurp` reads the file and base64-encodes it into `node_token_raw.content`.

#### Task 1.4 — Expose token as fact
```yaml
- name: Expose token as fact
  ansible.builtin.set_fact:
    k3s_token: "{{ node_token_raw.content | b64decode | trim }}"
    k3s_url: "https://{{ inventory_hostname }}:6443"
```
- Decodes the token and trims whitespace; stores as a host fact `k3s_token` on the master.
- `k3s_url` records the API endpoint (not strictly used later, but documented).

### Play 2 — Agent install
```yaml
- name: Install K3s agents on workers
  hosts: k3s_workers
  become: true
  vars:
    k3s_master_host: "{{ hostvars[groups['k3s_master'][0]]['inventory_hostname'] }}"
    k3s_token: "{{ hostvars[groups['k3s_master'][0]]['k3s_token'] }}"
```
- `hostvars[groups['k3s_master'][0]]` looks up the first (only) master host's variables, including the `k3s_token` fact set in Play 1. This is how the token flows from master to workers.

#### Task 2.1 — Install K3s agent
```yaml
- name: Install K3s agent
  ansible.builtin.shell: |
    set -e
    curl -sfL https://get.k3s.io | K3S_URL="https://{{ k3s_master_host }}:6443" K3S_TOKEN="{{ k3s_token }}" sh -
  args:
    executable: /bin/bash
  creates: /usr/local/bin/k3s
```
- Same installer, but with `K3S_URL` and `K3S_TOKEN` env vars → installs in agent mode and joins the master.
- `creates` guard skips re-install.

### Play 3 — Fetch kubeconfig
```yaml
- name: Fetch kubeconfig to control machine
  hosts: k3s_master
  become: true
```

#### Task 3.1 — Copy kubeconfig
```yaml
- name: Copy kubeconfig to control machine
  ansible.builtin.fetch:
    src: /etc/rancher/k3s/k3s.yaml
    dest: ./k3s.yaml
    flat: true
```
- `fetch` copies a file from the remote master to the Ansible control machine (your base laptop), flattening the path to `./k3s.yaml` (next to the playbook).

#### Task 3.2 — Rewrite server URL
```yaml
- name: Rewrite server URL in kubeconfig
  ansible.builtin.replace:
    path: ./k3s.yaml
    regexp: 'https://127\.0\.0\.1:6443'
    replace: "https://{{ inventory_hostname }}:6443"
  delegate_to: localhost
  become: false
```
- The default kubeconfig points at `127.0.0.1:6443` (localhost on the master). This rewrites it to `https://pi-03.lan:6443` so your laptop can reach the API server.
- `delegate_to: localhost` + `become: false` → runs the edit on your control machine (where the fetched file lives), without sudo.

---

## How to run
```bash
cd pi-cluster
ansible-playbook -i hosts.ini k3s/pre-k3s-hardening.yml
ansible-playbook -i hosts.ini k3s/install-k3s.yml
```

## Verify
```bash
export KUBECONFIG=pi-cluster/k3s.yaml
kubectl get nodes
```
All 10 should show `Ready`.
