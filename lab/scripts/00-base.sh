#!/usr/bin/env bash
# The VM's base: packages, Docker for Boardfarm, nested LXD for the routers.
set -euo pipefail
exec </dev/null

export DEBIAN_FRONTEND=noninteractive
# Report pending service restarts but leave them to the reboot at the end of the build.
export NEEDRESTART_MODE=l
lxd_channel=${APPS_LAB_LXD_CHANNEL:-latest/stable}

apt-get -o DPkg::Lock::Timeout=600 update
apt-get -o DPkg::Lock::Timeout=600 install -y --no-install-recommends \
    bridge-utils \
    btrfs-progs \
    bzip2 \
    ca-certificates \
    curl \
    docker-compose-v2 \
    docker.io \
    fakeroot \
    git \
    iproute2 \
    iptables \
    iputils-ping \
    jq \
    net-tools \
    python3-venv \
    sshpass \
    tcpdump \
    uidmap

systemctl enable --now docker

snap list lxd >/dev/null 2>&1 || snap install lxd --channel="$lxd_channel"
# Keep the revision the lab was built and accepted with.
snap refresh --hold=forever lxd
snap start lxd
lxd waitready
lxc version

install -d -m 0755 /var/lib/apps-lab
printf '%s\n' 'base-ready' > /var/lib/apps-lab/base.status
