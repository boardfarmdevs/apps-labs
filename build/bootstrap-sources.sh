#!/usr/bin/env bash
# Create or update the Yocto workspace (yocto/) at the commits manifest/apps-lab.xml pins.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace=${TREE:-$root/yocto}
manifest=$root/manifest/apps-lab.xml
jobs=${BUILD_THREADS:-$(nproc)}

command -v repo >/dev/null 2>&1 || {
    echo 'repo is missing; see the host setup in doc/build.md' >&2
    exit 1
}
test -f "$manifest"
mkdir -p "$workspace"
cd "$workspace"

if [ ! -d .repo ]; then
    repo init -u https://code.rdkcentral.com/r/manifests -b kirkstone -m rdkb-bpi-nosrc.xml
fi
install -m 0644 "$manifest" .repo/manifests/apps-lab.xml
repo init -m apps-lab.xml
repo sync -j"$jobs" --no-clone-bundle

# The layer's RF medium submodule: the controller image takes its topology page from it.
# Its URL is relative to the layer's origin, which a repo checkout does not have, so it
# is resolved here against the remote repo fetched the layer from.
layer=meta-cmf-bananapi-vcpe
layer_url=$(git -C "$layer" config --get "remote.$(git -C "$layer" remote | head -n 1).url")
git -C "$layer" submodule init gen/medium
git -C "$layer" config submodule.gen/medium.url "${layer_url%/*}/easymesh-medium.git"
git -C "$layer" submodule update gen/medium
test "$(git -C "$layer/gen/medium" rev-parse HEAD)" = "$(git -C "$layer" rev-parse HEAD:gen/medium)"

"$root/build/verify-pins.py" "$manifest" "$workspace"
