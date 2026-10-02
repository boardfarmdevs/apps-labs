#!/usr/bin/env bash
# Build the lab's applications as OCI bundles (rootfs/ and config.json in a flat tar) into
# out/apps/, from where lab/build.sh apps puts them on the VM's bundle server.
#
#   apps/build.sh [NAME...]      default: every application below
#
# hello   the layer's examples/hello-app: a shell loop that prints a heartbeat, made of
#         busybox and glibc taken from the DAC router image's own root filesystem, so it
#         matches the router's i686 userspace by construction
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace=${TREE:-$root/yocto}
layer=$workspace/meta-cmf-bananapi-vcpe
out=$root/out/apps
all=(hello)

router_rootfs() {    # the root filesystem tarball of the last successful DAC image build
    local record image
    record=$(cat "$workspace/build-evidence/latest-dac")
    [ "$(cat "$record/exit-code")" = 0 ] || { echo "the last DAC build did not succeed ($record)" >&2; return 1; }
    image=$(cat "$record/image")
    image=${image%.lxc.tar.bz2}.tar.gz
    test -f "$image" || { echo "no root filesystem tarball: $image" >&2; return 1; }
    printf '%s\n' "$image"
}

build_hello() {
    sh "$layer/examples/hello-app/build-bundle.sh" "$(router_rootfs)" "$out" >/dev/null
}

[ $# -gt 0 ] || set -- "${all[@]}"
mkdir -p "$out"
for name in "$@"; do
    declare -F "build_$name" >/dev/null || { echo "unknown application: $name (known: ${all[*]})" >&2; exit 2; }
    "build_$name"
    tar -tf "$out/$name.tar" | grep -qx './config.json\|config.json'
    printf '%s  %s\n' "$(du -h "$out/$name.tar" | cut -f1)" "$out/$name.tar"
done
