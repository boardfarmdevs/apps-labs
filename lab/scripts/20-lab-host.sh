#!/usr/bin/env bash
# The lab host inside the VM: the pinned Boardfarm checkout with its tools, and the nested
# LXD storage pool for the routers.
set -euo pipefail
# LXC commands can read a non-terminal stdin as YAML; keep the VM agent's stream away.
exec </dev/null

. /etc/default/apps-lab
assets=${APPS_LAB_ASSETS:-/opt/apps-lab/assets}
workspace=/opt/boardfarm
repo=$workspace/boardfarm-lab-staging

install -d "$workspace"
if [ ! -d "$repo/.git" ]; then
    git clone -q "$assets/boardfarm-lab-staging.bundle" "$repo"
fi
git -C "$repo" fetch -q "$assets/boardfarm-lab-staging.bundle" 'refs/heads/*:refs/remotes/bundle/*'
git -C "$repo" checkout -q -B apps-lab "$BOARDFARM_COMMIT"
test "$(git -C "$repo" rev-parse HEAD)" = "$BOARDFARM_COMMIT"
test -z "$(git -C "$repo" status --porcelain --untracked-files=no)"

if [ ! -x "$workspace/.venv/bin/python" ]; then
    python3 -m venv --prompt bf-venv "$workspace/.venv"
fi
"$workspace/.venv/bin/pip" install -q -e "$repo"
test -x "$workspace/.venv/bin/bf-lab"

# The lab's own configuration and inventory, next to the checkout's (untracked there).
install -m 0644 /opt/apps-lab/boardfarm/apps-lab.json "$repo/lab/apps-lab.json"
install -m 0644 /opt/apps-lab/boardfarm/inventory.json "$repo/inventories/apps-lab.json"
printf '%s\n' \
    'export BF_LAB_CONFIG=apps-lab.json' \
    'export BF_INVENTORY=apps-lab.json' \
    "export PATH=$workspace/.venv/bin:/usr/local/sbin:\$PATH" \
    > /etc/profile.d/apps-lab.sh

if ! lxc storage show default >/dev/null 2>&1; then
    lxd init --auto --storage-backend dir
fi
if ! lxc storage show "$ROUTER_POOL" >/dev/null 2>&1; then
    lxc storage create "$ROUTER_POOL" btrfs size="$ROUTER_POOL_SIZE"
fi

printf '%s\n' 'lab-host-ready' > /var/lib/apps-lab/host.status
