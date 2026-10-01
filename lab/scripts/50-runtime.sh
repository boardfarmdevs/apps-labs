#!/usr/bin/env bash
# The runtime service: after a VM boot it brings Boardfarm, the routers and the LAN clients
# back in order. LXD does not start the routers itself (boot.autostart is off): their
# bridges are Docker's and have to exist first.
set -euo pipefail
exec </dev/null

install -m 0644 /opt/apps-lab/guest/apps-lab.service /etc/systemd/system/apps-lab.service
systemctl daemon-reload
systemctl enable apps-lab.service
printf '%s\n' 'runtime-installed' > /var/lib/apps-lab/runtime.status
