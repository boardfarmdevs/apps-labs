#!/usr/bin/env bash
# Build the lab's applications as OCI bundles (rootfs/ and config.json in a flat tar) into
# out/apps/, from where lab/build.sh apps puts them on the VM's bundle server.
#
#   apps/build.sh [NAME...]      default: every application below
#
# Both are made of programs taken from the DAC router image's own root filesystem, so
# they match the router's i686 userspace by construction and need no toolchain:
#
# hello      the layer's examples/hello-app: a shell loop that prints a heartbeat
# tictactoe  a web page: lighttpd, with the modules and libraries it needs, serving the
#            layer's tic-tac-toe page on port 8090 (apps/tictactoe/)
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace=${TREE:-$root/yocto}
layer=$workspace/meta-cmf-bananapi-vcpe
out=$root/out/apps
all=(hello tictactoe)

router_rootfs() {    # the root filesystem tarball of the last successful DAC image build
    local record image
    record=$(cat "$workspace/build-evidence/latest-dac")
    [ "$(cat "$record/exit-code")" = 0 ] || { echo "the last DAC build did not succeed ($record)" >&2; return 1; }
    image=$(cat "$record/image")
    image=${image%.lxc.tar.bz2}.tar.gz
    test -f "$image" || { echo "no root filesystem tarball: $image" >&2; return 1; }
    printf '%s\n' "$image"
}

# The router's root filesystem, unpacked once per run (regular files and links only).
unpacked=
router_tree() {
    if [ -z "$unpacked" ]; then
        unpacked=$(mktemp -d "$root/out/rootfs.XXXXXX")
        trap 'rm -rf -- "$unpacked"' EXIT
        tar -xzf "$(router_rootfs)" -C "$unpacked" --no-same-owner \
            ./bin ./lib ./usr/lib ./usr/sbin ./usr/bin 2>/dev/null || true
        test -x "$unpacked/bin/busybox.nosuid"
    fi
}

# Copy programs and libraries from the router's tree into a bundle's rootfs, with every
# shared library they need (the NEEDED entries, followed to the end).
copy_with_libraries() {    # DESTINATION /path/in/router...
    local destination=$1 path needed library seen=" " queue=("${@:2}")
    while [ "${#queue[@]}" -gt 0 ]; do
        path=${queue[0]}
        queue=("${queue[@]:1}")
        case "$seen" in *" $path "*) continue ;; esac
        seen="$seen$path "
        test -e "$unpacked$path" || { echo "not in the router image: $path" >&2; return 1; }
        install -D -m 0755 "$(readlink -f "$unpacked$path")" "$destination$path"
        while read -r needed; do
            for library in "/lib/$needed" "/usr/lib/$needed"; do
                if [ -e "$unpacked$library" ]; then
                    queue+=("$library")
                    continue 2
                fi
            done
            echo "$path needs $needed, which the router image does not have" >&2
            return 1
        done < <(readelf -d "$unpacked$path" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')
    done
    # the dynamic loader the programs name
    install -D -m 0755 "$(readlink -f "$unpacked/lib/ld-linux.so.2")" "$destination/lib/ld-linux.so.2"
}

pack() {    # NAME BUNDLE_DIRECTORY: the flat layout the frameworks unpack
    python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$2/config.json"
    tar -C "$2" --owner=0 --group=0 --numeric-owner -cf "$out/$1.tar" rootfs config.json
}

build_hello() {
    sh "$layer/examples/hello-app/build-bundle.sh" "$(router_rootfs)" "$out" >/dev/null
}

build_tictactoe() {
    local bundle applet
    router_tree
    bundle=$(mktemp -d "$root/out/tictactoe.XXXXXX")
    install -d "$bundle/rootfs"/{bin,dev,proc,sys,tmp,var,etc,srv/tictactoe}
    copy_with_libraries "$bundle/rootfs" /bin/busybox.nosuid /usr/sbin/lighttpd \
        /usr/lib/mod_indexfile.so /usr/lib/mod_dirlisting.so /usr/lib/mod_staticfile.so
    mv "$bundle/rootfs/bin/busybox.nosuid" "$bundle/rootfs/bin/busybox"
    for applet in sh echo sleep kill hostname cat ls ps; do
        ln -s busybox "$bundle/rootfs/bin/$applet"
    done
    install -m 0644 "$layer"/recipes-apps/tictactoe-content/files/{index.html,style.css,script.js} \
        "$bundle/rootfs/srv/tictactoe/"
    install -m 0644 "$root/apps/tictactoe/lighttpd.conf" "$bundle/rootfs/srv/tictactoe/lighttpd.conf"
    install -m 0755 "$root/apps/tictactoe/entrypoint.sh" "$bundle/rootfs/entrypoint.sh"
    install -m 0644 "$root/apps/tictactoe/config.json" "$bundle/config.json"
    pack tictactoe "$bundle"
    rm -rf -- "$bundle"
}

[ $# -gt 0 ] || set -- "${all[@]}"
mkdir -p "$out"
for name in "$@"; do
    declare -F "build_$name" >/dev/null || { echo "unknown application: $name (known: ${all[*]})" >&2; exit 2; }
    "build_$name"
    tar -tf "$out/$name.tar" | grep -qx './config.json\|config.json'
    printf '%s  %s\n' "$(du -h "$out/$name.tar" | cut -f1)" "$out/$name.tar"
done
