# Build and operate the apps lab

Three stages, each its own script, as in the RDK EasyMesh lab: the pinned
sources, the router images, the lab VM. The image build does not create a VM
and the VM build does not run BitBake.

| Stage | Script | Output |
| --- | --- | --- |
| Sources | `build/bootstrap-sources.sh` | the Yocto workspace `yocto/` at the commits of `manifest/apps-lab.xml` |
| Images | `build/build-images.sh dac\|lcm\|both` | one `*.rootfs.lxc.tar.bz2` per framework, with its evidence |
| Lab VM | `lab/build.sh build` | the LXD VM `apps-lab` with both routers, checked |

## Host

An Ubuntu 22.04 x86-64 host with hardware virtualization, prepared as for the
EasyMesh lab ([its build guide](https://github.com/boardfarmdevs/meta-cmf-bananapi-vcpe/blob/main/doc/easymesh/build/README.md)
has the commands): the Yocto host packages, `repo` in `~/bin`, GNU tar 1.34 and
`lz4c` in `~/hosttools/bin`, credentials for RDK Central in `~/.netrc`, and LXD
with `/dev/kvm`. A first LCM build needs most of the 300 GiB that guide asks for.

```sh
export PATH="$HOME/hosttools/bin:$HOME/bin:$PATH"
```

The download and sstate caches are shared with the other labs
(`~/oe/downloads`, `~/oe/sstate-cache`; `BUILD_DOWNLOADS` and `BUILD_SSTATE`
name others). Everything else stays in this directory.

## Sources

```sh
build/bootstrap-sources.sh
```

It initializes `yocto/` with `repo`, installs `manifest/apps-lab.xml` as the
manifest, syncs, checks out the layer's `gen/medium` submodule and verifies that
every project is at its pinned commit. Run it again after a pin changes.

To move a pin: change the `revision` in `manifest/apps-lab.xml`, run the
bootstrap, build both images, build a VM, and commit the manifest once the lab
passes its check.

## Images

```sh
build/build-images.sh both      # or: dac, lcm
```

Both are `rdk-generic-broadband-image` for the machine `qemux86bpibroadband`,
each in its own build directory:

| Framework | Build directory | What differs |
| --- | --- | --- |
| `dac` | `yocto/build-qemux86bpibroadband-dac` | nothing: the apps toolkit's default runtime. Without `meta-amx`, which the BSP's setup adds whenever the workspace has it, so that the image is the EasyMesh lab's and comes from its sstate. |
| `lcm` | `yocto/build-qemux86bpibroadband-lcm` | `meta-amx` and `meta-lcm` in `conf/bblayers.conf`, and `build/lcm.conf` as a marked block in `conf/local.conf` |

Each build leaves a record in `yocto/build-evidence/<framework>-<time>/`
(`latest-<framework>` names the last): the manifest, the configuration, the
environment, the log, the exit code, the image's path and checksum, its package
list. The VM build takes the image of the last successful build.

To work in a build directory by hand, one framework per terminal:

```sh
cd yocto
MACHINE=qemux86bpibroadband BPI_IMG_TYPE=nand \
  source meta-cmf-bananapi/setup-environment-refboard-rdkb build-qemux86bpibroadband-lcm
bitbake -R ../clean-build.conf rdk-generic-broadband-image
```

`build-images.sh` is what puts the framework's settings there; run it once for a
new build directory.

## Lab VM

```sh
lab/build.sh build
```

It creates the VM (`lab/lab.env`: Ubuntu 24.04, 4 CPUs, 8 GiB, 40 GiB, the
storage pool `apps-lab-pool`), pushes the images, the pinned Boardfarm as a
bundle and the lab's scripts into it, and runs the numbered steps of
`lab/scripts/`:

| Step | |
| --- | --- |
| `00-base.sh` | packages, Docker, nested LXD (held at its revision) |
| `20-lab-host.sh` | the Boardfarm checkout and its tools, the lab's configuration, the routers' LXD pool |
| `30-boardfarm.sh` | `bf-lab setup` for two CPE slots: Kea, WAN gateway and LAN client each |
| `40-routers.sh` | `apps-lab-router deploy` per router, then the LAN clients |
| `50-runtime.sh` | the service that brings the lab back on boot |

Then it reboots the VM, lets the runtime service reconstruct the lab, and runs
the acceptance check. A lab with one router, while the other image is not built
yet:

```sh
APPS_LAB_ROUTERS="bpibroadband-dac:dac:1" lab/build.sh build
lab/build.sh deploy bpibroadband-lcm      # later: the second router, into the running VM
```

## Operate

```sh
lab/build.sh status
lab/build.sh check                          # every router; or: check bpibroadband-dac
lab/build.sh stop
lab/build.sh start
lab/build.sh router bpibroadband-lcm        # a shell in a router
lab/build.sh router bpibroadband-dac rbuscli getvalues Device.SoftwareModules.
lab/build.sh deploy                         # new images, or changed lab scripts, into the VM
lab/build.sh deploy --fresh bpibroadband-dac   # that router again, as a new device
lab/build.sh delete
```

In the VM (`lxc exec apps-lab -- bash`): `apps-labctl status|check|sh NAME`,
`apps-lab-router list`, and Boardfarm's own tools (`bf-lab status`, with the
environment of `/etc/profile.d/apps-lab.sh`).

A plain `deploy` keeps a router's `/nvram` (a directory of the VM,
`/var/lib/apps-lab/nvram/<router>`), so the router stays the same device.
`delete` removes only the VM; its storage pool stays for the next build.

## What the lab adds to a router

`apps-lab-router deploy` creates the router from the image as it is, and adds
two things in its root filesystem (see "Found on the way" in the
[plan](plan.md)):

- `apps-lab-lan-port.service`, which keeps the LAN port `eth2` a port of `brlan0`;
- `/etc/usp-pa/oktopus-mqtt-obuspa.txt`, the factory reset file the USP agent
  starts from: no remote controller.

## The check

`apps-lab-check`, per router:

- the container runs;
- `erouter0` has an address in the slot's WAN network, from the slot's Kea server;
- the default route is the slot's WAN gateway, and the router reaches the
  internet by address and by name;
- `brlan0` has its address and the LAN port is in it;
- the slot's LAN client has a lease from the router and reaches the router and
  the internet through it;
- the framework's services and the USP agent run, and `Device.SoftwareModules.`
  answers on rbus and on USP (`obuspa -c get`).

Then Boardfarm's own `bf-lab status`: every provider answers on Docker and on SSH.

## Addresses

| | CPE 1 (`bpibroadband-dac`) | CPE 2 (`bpibroadband-lcm`) |
| --- | --- | --- |
| WAN bridge and network | `br-wan101`, 10.101.0.0/24 | `br-wan102`, 10.102.0.0/24 |
| Kea server | `dhcp-cpe1`, 10.101.0.10 | `dhcp-cpe2`, 10.102.0.10 |
| WAN gateway | `wan-cpe1`, 10.101.0.20 | `wan-cpe2`, 10.102.0.20 |
| LAN bridge | `br-lan201` | `br-lan202` |
| LAN client | `lan-cpe1` | `lan-cpe2` |
| Router LAN | 10.0.0.1/24 on `brlan0`, port `eth2` | 10.0.0.1/24 on `brlan0`, port `eth2` |

The two LANs have the same addresses and never meet: each is its own bridge.
