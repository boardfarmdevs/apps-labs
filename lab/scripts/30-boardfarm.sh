#!/usr/bin/env bash
# Boardfarm's providers for the lab's CPE slots: per slot a Kea server and a WAN gateway on
# br-wan10<n>, and a LAN client on br-lan20<n>. The first run builds Boardfarm's images.
set -euo pipefail
exec </dev/null

. /etc/default/apps-lab
repo=/opt/boardfarm/boardfarm-lab-staging

test "$(git -C "$repo" rev-parse HEAD)" = "$BOARDFARM_COMMIT"
systemctl enable --now docker

/usr/local/sbin/apps-lab-runtime boardfarm

for i in $(seq 1 "$(jq -r .deployment.num_cpes "$repo/lab/apps-lab.json")"); do
    ip link show "br-wan$((100 + i))" >/dev/null
    ip link show "br-lan$((200 + i))" >/dev/null
done
test "$(cat /var/lib/apps-lab/boardfarm.status)" = boardfarm-ready
