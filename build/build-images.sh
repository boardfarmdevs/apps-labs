#!/usr/bin/env bash
# Build the router images of the apps lab: rdk-generic-broadband-image for the machine
# qemux86bpibroadband, once per application framework, each in its own build directory.
#
#   build-images.sh [dac|lcm|both]
#
# dac  the apps toolkit's default runtime (DSM, Dobby, crun)
# lcm  the prpl lifecycle manager (meta-amx, meta-lcm; build/lcm.conf)
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace=${TREE:-$root/yocto}
evidence=$workspace/build-evidence
manifest=$root/manifest/apps-lab.xml
threads=${BUILD_THREADS:-$(nproc)}
downloads=${BUILD_DOWNLOADS:-$HOME/oe/downloads}
sstate=${BUILD_SSTATE:-$HOME/oe/sstate-cache}
machine=qemux86bpibroadband
target=rdk-generic-broadband-image
selection=${1:-both}
marker_begin='# >>> apps-lab framework settings, written by build-images.sh'
marker_end='# <<< apps-lab framework settings'

case "$selection" in dac|lcm|both) ;; *) echo 'usage: build-images.sh [dac|lcm|both]' >&2; exit 2 ;; esac
[[ "$threads" =~ ^[1-9][0-9]*$ ]] || { echo 'BUILD_THREADS must be a positive integer' >&2; exit 2; }
test -f "$workspace/meta-cmf-bananapi/setup-environment-refboard-rdkb" || {
    echo "Missing RDK BPI setup script in $workspace/meta-cmf-bananapi." >&2
    echo "Run build/bootstrap-sources.sh first." >&2
    exit 1
}
mkdir -p "$evidence" "$downloads" "$sstate"
"$root/build/verify-pins.py" "$manifest" "$workspace"

cat > "$workspace/clean-build.conf" <<EOF
BB_NUMBER_THREADS:forcevariable = "$threads"
PARALLEL_MAKE:forcevariable = "-j $threads"
DL_DIR:forcevariable = "$downloads"
SSTATE_DIR:forcevariable = "$sstate"
SSTATE_MIRRORS:forcevariable = ""
EOF

# The framework's settings are a marked block in conf/local.conf and the LCM layers in
# conf/bblayers.conf, so that a plain bitbake in the build directory builds the same image.
configure_framework() {
    local flavor=$1 layer
    sed -i "/^${marker_begin}\$/,/^${marker_end}\$/d" conf/local.conf
    if [ "$flavor" = lcm ]; then
        { printf '%s\n' "$marker_begin"; cat "$root/build/lcm.conf"; printf '%s\n' "$marker_end"; } >> conf/local.conf
        for layer in meta-amx meta-lcm; do
            test -f "$workspace/$layer/conf/layer.conf"
            grep -Fq "\${RDKROOT}/$layer\"" conf/bblayers.conf ||
                printf 'BBLAYERS += "${RDKROOT}/%s"\n' "$layer" >> conf/bblayers.conf
        done
    else
        # meta-cmf-filogic's setup adds meta-amx whenever the workspace has it. The DAC
        # image is the RDK EasyMesh lab's image, which is built without it.
        sed -i -E '/RDKROOT\}\/meta-(amx|lcm)"/d' conf/bblayers.conf
    fi
}

for flavor in dac lcm; do
    [ "$selection" = both ] || [ "$selection" = "$flavor" ] || continue
    build=build-$machine-$flavor
    runtime=$(printf '%s' "$flavor" | tr '[:lower:]' '[:upper:]')
    record=$evidence/$flavor-$(date -u +%Y%m%dT%H%M%SZ)
    mkdir -p "$record"
    printf '%s\n' "$record" > "$evidence/latest-$flavor"
    printf 'Preparing the %s image (%s, %s); evidence: %s\n' "$flavor" "$target" "$build" "$record"
    (
        trap 'status=$?; printf "%s\n" "$status" > "$record/exit-code"; date -u +%FT%TZ > "$record/finished"' EXIT
        cd "$workspace"
        date -u +%FT%TZ > "$record/started"
        git -C "$root" rev-parse HEAD > "$record/lab-commit" 2>/dev/null || echo uncommitted > "$record/lab-commit"
        cp "$manifest" "$record/manifest.xml"
        cp clean-build.conf "$record/"
        if [ -f "$build/conf/local.conf" ] && grep -q '##RDK_FLAVOR##' "$build/conf/local.conf"; then
            mv "$build/conf" "$record/incomplete-conf"
        fi
        set +e +u +o pipefail
        MACHINE="$machine" BPI_IMG_TYPE=nand source meta-cmf-bananapi/setup-environment-refboard-rdkb "$build" > "$record/setup.log" 2>&1
        setup_status=$?
        set -euo pipefail
        [ "$setup_status" -eq 0 ] || {
            echo "RDK environment setup failed; see $record/setup.log" >&2
            tail -60 "$record/setup.log" >&2
            exit "$setup_status"
        }
        ! grep -q '##RDK_FLAVOR##' conf/local.conf
        grep -Fq 'meta-cmf-bananapi-vcpe' conf/bblayers.conf
        configure_framework "$flavor"
        bitbake -R "$workspace/clean-build.conf" -e "$target" > "$record/environment.txt" 2> "$record/environment.err"
        grep -Fx "DL_DIR=\"$downloads\"" "$record/environment.txt"
        grep -Fx "SSTATE_DIR=\"$sstate\"" "$record/environment.txt"
        grep -Fx 'SSTATE_MIRRORS=""' "$record/environment.txt"
        grep -Ex "(export )?RDK_BB_APPS_TOOLKIT_CRUNTIME=\"$runtime\"" "$record/environment.txt"
        cp conf/local.conf conf/bblayers.conf "$record/"
        printf 'Starting BitBake for %s (%s); log: %s/build.log\n' "$target" "$flavor" "$record"
        bitbake -R "$workspace/clean-build.conf" "$target" 2>&1 | tee "$record/build.log"
        image=$(readlink -f "tmp/deploy/images/$machine/$target-$machine.lxc.tar.bz2")
        test -f "$image"
        printf '%s\n' "$image" > "$record/image"
        sha256sum "$image" > "$record/images.sha256"
        cp "tmp/deploy/images/$machine/$target-$machine.manifest" "$record/packages.manifest"
    )
done
