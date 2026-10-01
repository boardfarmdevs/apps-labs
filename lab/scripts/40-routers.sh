#!/usr/bin/env bash
# Deploy the lab's routers, each from its framework's image on its Boardfarm slot, and bring
# their LAN clients up.
#
#   40-routers.sh [--fresh] [NAME...]     default: every router of APPS_LAB_ROUTERS
set -euo pipefail
exec </dev/null

. /etc/default/apps-lab
assets=${APPS_LAB_ASSETS:-/opt/apps-lab/assets}
fresh=
if [ "${1:-}" = --fresh ]; then
    fresh=--fresh
    shift
fi

test "$(cat /var/lib/apps-lab/boardfarm.status)" = boardfarm-ready

selected() {
    [ "$#" -eq 1 ] && return 0
    local name=$1 wanted
    shift
    for wanted in "$@"; do
        [ "$wanted" != "$name" ] || return 0
    done
    return 1
}

deployed=()
for router in $APPS_LAB_ROUTERS; do
    IFS=: read -r name framework cpe <<< "$router"
    selected "$name" "$@" || continue
    image=$(cat "$assets/image-$framework")
    /usr/local/sbin/apps-lab-router deploy "$name" "$framework" "$cpe" "$assets/$image" $fresh
    deployed+=("$name")
done
[ "${#deployed[@]}" -gt 0 ] || { echo 'no router selected' >&2; exit 2; }

for name in "${deployed[@]}"; do
    /usr/local/sbin/apps-lab-router wait "$name"
done
/usr/local/sbin/apps-lab-runtime lan
printf '%s\n' 'routers-ready' > /var/lib/apps-lab/routers.status
