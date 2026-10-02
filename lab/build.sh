#!/usr/bin/env bash
# The apps lab VM, from the lab host: build it from the router images, operate it, check it.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lab.env
source "$root/lab/lab.env"
name=$APPS_LAB_NAME
storage=${APPS_LAB_STORAGE:-$name-pool}
evidence=${TREE:-$root/yocto}/build-evidence
guest=/opt/apps-lab
guest_assets=$guest/assets
settings=(APPS_LAB_NAME APPS_LAB_ROUTERS BOARDFARM_COMMIT ROUTER_CPUS ROUTER_MEMORY
    ROUTER_ROOT ROUTER_POOL ROUTER_POOL_SIZE)

usage() {
    cat <<EOF
usage: $0 COMMAND

Commands:
  build                create the VM, provision it, deploy the routers, reboot it and check it
  start | stop | restart
                       the VM; start also brings the lab up in order
  status               the VM, Boardfarm's containers and the routers
  check                the acceptance check, per router: WAN, DHCP, internet, LAN, framework
  update               the lab's scripts, settings and current images into the running VM;
                       the routers stay as they are
  deploy [--fresh] [ROUTER...]
                       update, then the named routers (default: all) deployed again from their
                       images; --fresh: with an empty /nvram
  apps                 the bundles of out/apps (apps/build.sh) onto the VM's bundle server;
                       prints the URL each router installs them from
  test ROUTER [--path native|rbus|usp] [--bundle NAME]
                       the application lifecycle on a router (tests/lifecycle.py): install,
                       start, stop, uninstall over each management path
  router NAME [CMD...] a shell, or a command, in a router
  delete               delete the VM (its storage pool stays)

The routers ($APPS_LAB_ROUTERS) take their images from the last
build of their framework (build/build-images.sh), or from
  APPS_LAB_DAC_IMAGE=/path/to/X86EMLTRBPIBB_....rootfs.lxc.tar.bz2
  APPS_LAB_LCM_IMAGE=/path/to/X86EMLTRBPIBB_....rootfs.lxc.tar.bz2

Overrides (defaults in lab/lab.env):
  APPS_LAB_NAME=$name  APPS_LAB_CPUS=$APPS_LAB_CPUS  APPS_LAB_MEMORY=$APPS_LAB_MEMORY  APPS_LAB_DISK=$APPS_LAB_DISK
  APPS_LAB_NETWORK=$APPS_LAB_NETWORK  APPS_LAB_STORAGE=$storage (created as a dir pool if absent)
  APPS_LAB_ROUTERS="name:framework:cpe ..." (a subset builds a lab with fewer routers)
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || { echo "required command is missing: $1" >&2; exit 1; }
}

instance_exists() { lxc info "$name" >/dev/null 2>&1; }
instance_state() { lxc info "$name" 2>/dev/null | sed -n 's/^Status: //p'; }
run_root() { lxc exec "$name" -- "$@"; }

wait_agent() {
    local attempt
    for attempt in $(seq 1 120); do
        lxc exec "$name" -- true >/dev/null 2>&1 && return 0
        sleep 2
    done
    echo "$name did not expose its LXD VM agent after 240 seconds" >&2
    return 1
}

frameworks() {    # the frameworks the configured routers need, once each
    local router
    for router in $APPS_LAB_ROUTERS; do
        printf '%s\n' "$router" | cut -d: -f2
    done | sort -u
}

image_for() {    # the image of a framework: given, or the last successful build's
    local framework=$1 variable record image
    variable=APPS_LAB_$(printf '%s' "$framework" | tr '[:lower:]' '[:upper:]')_IMAGE
    image=${!variable:-}
    if [ -z "$image" ]; then
        record=$(cat "$evidence/latest-$framework" 2>/dev/null) || {
            echo "no $framework image: build/build-images.sh $framework, or set $variable" >&2
            return 1
        }
        [ "$(cat "$record/exit-code" 2>/dev/null)" = 0 ] || {
            echo "the last $framework build did not succeed ($record)" >&2
            return 1
        }
        image=$(cat "$record/image")
    fi
    test -f "$image" || { echo "no such image: $image" >&2; return 1; }
    printf '%s\n' "$image"
}

# Boardfarm at the pinned commit, as a bundle: the VM needs no access to its repository.
boardfarm_bundle() {
    local output=$1 cache=$root/out/cache/boardfarm-lab-staging.git ref=refs/heads/apps-lab-export
    if [ ! -d "$cache" ]; then
        install -d "$(dirname "$cache")"
        git clone -q --bare "$BOARDFARM_SOURCE" "$cache"
    fi
    git -C "$cache" cat-file -e "$BOARDFARM_COMMIT^{commit}" 2>/dev/null ||
        git -C "$cache" fetch -q "$BOARDFARM_SOURCE" '+refs/heads/*:refs/heads/*'
    git -C "$cache" update-ref "$ref" "$BOARDFARM_COMMIT"
    git -C "$cache" bundle create -q "$output" "$ref"
    git -C "$cache" update-ref -d "$ref"
    git bundle verify -q "$output"
}

prepare_assets() {
    local assets=$1/assets framework image variable
    install -d "$assets"
    boardfarm_bundle "$assets/boardfarm-lab-staging.bundle"
    for framework in $(frameworks); do
        image=$(image_for "$framework")
        cp --reflink=auto "$image" "$assets/"
        basename "$image" > "$assets/image-$framework"
    done
    tar -C "$root/lab" -cf "$assets/apps-lab.tar" boardfarm scripts guest
    tar -C "$root" -rf "$assets/apps-lab.tar" tests
    for variable in "${settings[@]}"; do
        printf '%s="%s"\n' "$variable" "${!variable}"
    done > "$assets/apps-lab.env"
    git -C "$root" describe --always --dirty 2>/dev/null > "$assets/lab-commit" || echo uncommitted > "$assets/lab-commit"
    (cd "$assets" && sha256sum -- * > SHA256SUMS)
}

push_inputs() {
    local assets=$1/assets file
    run_root install -d "$guest_assets" /var/lib/apps-lab
    for file in "$assets"/*; do
        lxc file push -q "$file" "$name$guest_assets/$(basename "$file")"
    done
    run_root bash -euo pipefail -c "
        cd $guest_assets
        sha256sum -c --quiet SHA256SUMS
        rm -rf $guest/boardfarm $guest/scripts $guest/guest $guest/tests
        tar -xf apps-lab.tar -C $guest
        install -m 0644 apps-lab.env /etc/default/apps-lab
        install -m 0755 $guest/guest/apps-lab-router $guest/guest/apps-lab-runtime \
            $guest/guest/apps-lab-check $guest/guest/apps-labctl /usr/local/sbin/
    "
}

step() {
    printf '\n=== %s %s\n' "$(date +%T)" "$*"
    run_root bash "$guest/scripts/$1" "${@:2}"
}

ensure_storage_pool() {
    lxc storage show "$storage" >/dev/null 2>&1 && return 0
    echo "Creating LXD storage pool $storage (dir)"
    lxc storage create "$storage" dir
}

build_vm() {
    # stage is global: the EXIT trap that removes it runs after this function has returned
    require_command git
    require_command lxc
    require_command sha256sum
    ! instance_exists || { echo "$name already exists; delete it explicitly before a build" >&2; exit 1; }
    install -d "$root/out"
    stage=$(mktemp -d "$root/out/stage.XXXXXX")
    trap 'rm -rf -- "$stage"' EXIT
    prepare_assets "$stage"

    ensure_storage_pool
    lxc init "$APPS_LAB_IMAGE" "$name" --vm --storage "$storage" \
        --config limits.cpu="$APPS_LAB_CPUS" --config limits.memory="$APPS_LAB_MEMORY" </dev/null
    lxc config device set "$name" root size "$APPS_LAB_DISK"
    lxc config device override "$name" eth0 network="$APPS_LAB_NETWORK" >/dev/null
    lxc config set "$name" boot.autostart false
    lxc start "$name"
    wait_agent
    # The image's first boot runs its own package work; let it finish before the lab's.
    run_root cloud-init status --wait >/dev/null 2>&1 || true
    push_inputs "$stage"

    step 05-no-automatic-updates.sh
    step 00-base.sh
    step 20-lab-host.sh
    step 30-boardfarm.sh
    step 40-routers.sh --fresh
    step 50-runtime.sh

    # The lab has to come back by itself: reboot, let the runtime service rebuild it, check.
    printf '\n=== %s reboot and check\n' "$(date +%T)"
    lxc restart "$name" --timeout 300
    wait_agent
    run_root systemctl start apps-lab.service
    run_root /usr/local/sbin/apps-lab-check
    lxc config set "$name" user.apps-lab.commit "$(cat "$stage/assets/lab-commit")"
}

start_vm() {
    instance_exists
    [ "$(instance_state)" = RUNNING ] || lxc start "$name"
    wait_agent
    run_root systemctl start apps-lab.service
}

stop_vm() {
    instance_exists
    [ "$(instance_state)" != RUNNING ] || lxc stop "$name" --timeout 300
}

status_vm() {
    lxc list "^$name\$" -c nst4m --format table
    if [ "$(instance_state)" = RUNNING ]; then
        wait_agent
        run_root /usr/local/sbin/apps-labctl status
    fi
}

check_vm() {
    start_vm
    run_root /usr/local/sbin/apps-lab-check "$@"
}

# The lab's scripts, its settings and the current images into the running VM.
update_vm() {
    instance_exists
    [ "$(instance_state)" = RUNNING ] || { echo "$name is not running: $0 start" >&2; exit 1; }
    wait_agent
    install -d "$root/out"
    stage=$(mktemp -d "$root/out/stage.XXXXXX")
    trap 'rm -rf -- "$stage"' EXIT
    prepare_assets "$stage"
    push_inputs "$stage"
    step 05-no-automatic-updates.sh
    step 20-lab-host.sh
    step 50-runtime.sh
    lxc config set "$name" user.apps-lab.commit "$(cat "$stage/assets/lab-commit")"
}

deploy_routers() {
    update_vm
    step 30-boardfarm.sh
    step 40-routers.sh "$@"
    [ "${1:-}" != --fresh ] || shift
    run_root /usr/local/sbin/apps-lab-check "$@"
}

# The built bundles (apps/build.sh, out/apps/*.tar) onto the VM's bundle server.
push_apps() {
    local bundle router rname framework cpe found=false
    instance_exists
    [ "$(instance_state)" = RUNNING ] || { echo "$name is not running: $0 start" >&2; exit 1; }
    wait_agent
    run_root install -d /var/lib/apps-lab/apps
    for bundle in "$root"/out/apps/*.tar; do
        [ -f "$bundle" ] || continue
        lxc file push -q "$bundle" "$name/var/lib/apps-lab/apps/$(basename "$bundle")"
        found=true
    done
    "$found" || { echo 'no bundles in out/apps: apps/build.sh' >&2; exit 1; }
    run_root systemctl is-active --quiet apps-lab-apps.service
    for router in $APPS_LAB_ROUTERS; do
        IFS=: read -r rname framework cpe <<< "$router"
        for bundle in "$root"/out/apps/*.tar; do
            printf '%s: http://10.%s.0.1:8080/%s\n' "$rname" "$((100 + cpe))" "$(basename "$bundle")"
        done
    done
}

# The application lifecycle test on a router, with the tests as they are in this checkout.
test_router() {
    [ $# -ge 1 ] || { echo "usage: $0 test ROUTER [--path native|rbus|usp] [--bundle NAME]" >&2; exit 2; }
    instance_exists
    [ "$(instance_state)" = RUNNING ] || { echo "$name is not running: $0 start" >&2; exit 1; }
    wait_agent
    run_root rm -rf "$guest/tests"
    lxc file push -q -r "$root/tests" "$name$guest/"
    run_root python3 "$guest/tests/lifecycle.py" "$@"
}

router_shell() {
    local router=${1:?router name}
    shift
    [ $# -gt 0 ] || set -- bash -l
    if [ -t 0 ]; then
        exec lxc exec "$name" -t -- lxc exec "$router" -- "$@"
    fi
    exec lxc exec "$name" -- lxc exec "$router" -- "$@"
}

delete_vm() {
    instance_exists
    lxc list "^$name\$" -c nst4m --format table
    echo "deleting only the LXD VM: $name"
    lxc delete "$name" --force
}

case "${1:-}" in
    build) build_vm ;;
    start) start_vm ;;
    stop) stop_vm ;;
    restart) stop_vm; start_vm ;;
    status) status_vm ;;
    check) check_vm "${@:2}" ;;
    update) update_vm ;;
    deploy) deploy_routers "${@:2}" ;;
    apps) push_apps ;;
    test) test_router "${@:2}" ;;
    router) router_shell "${@:2}" ;;
    delete) delete_vm ;;
    -h|--help|help|'') usage ;;
    *) usage >&2; exit 2 ;;
esac
