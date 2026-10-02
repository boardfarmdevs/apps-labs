#!/usr/bin/env bash
# The services that stay: the runtime, which after a VM boot brings Boardfarm, the routers
# and the LAN clients back in order (LXD does not start the routers itself, boot.autostart
# is off: their bridges are Docker's and have to exist first), and the bundle server the
# routers fetch applications from.
set -euo pipefail
exec </dev/null

install -d /var/lib/apps-lab/apps
install -m 0644 /opt/apps-lab/guest/apps-lab.service /etc/systemd/system/apps-lab.service
install -m 0644 /opt/apps-lab/guest/apps-lab-apps.service /etc/systemd/system/apps-lab-apps.service
systemctl daemon-reload
systemctl enable apps-lab.service
systemctl enable --now apps-lab-apps.service
printf '%s\n' 'runtime-installed' > /var/lib/apps-lab/runtime.status
