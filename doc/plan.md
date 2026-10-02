# Apps labs: plan

The apps labs demonstrate the two application frameworks of RDK-B in a virtual
lab: **DAC** (Downloadable Application Containers, the RDK default) and **LCM**
(prpl Lifecycle Management, also supported). An *apps lab* is an RDK-B router
(the Banana Pi `bpibroadband` image, rebuilt for x86) running as a container in
a lab VM, connected to a Boardfarm WAN and LAN, into which an application is
installed and started through the data model.

Status and results are at the end of this file and are kept current.

## What is built

One LXD VM, `apps-lab`, on the lab host (rev140). In it:

| | DAC router | LCM router |
| --- | --- | --- |
| Container | `bpibroadband-dac` | `bpibroadband-lcm` |
| Image | `rdk-generic-broadband-image`, apps toolkit runtime `DAC` | the same image, apps toolkit runtime `LCM` |
| Framework | DSM + Dobby, OCI bundles run by crun | timingila + cthulhu on the Ambiorix (AMX) stack, OCI bundles run by crun |
| Boardfarm slot | CPE 1 | CPE 2 |
| WAN | `br-wan101`, 10.101.0.0/24, `dhcp-cpe1` (Kea) and `wan-cpe1` (gateway, NAT) | `br-wan102`, 10.102.0.0/24, `dhcp-cpe2` and `wan-cpe2` |
| LAN | `br-lan201`, client `lan-cpe1` | `br-lan202`, client `lan-cpe2` |

Both routers run at the same time. Each takes its WAN address from its own Kea
server on `erouter0`, reaches the internet through its own WAN gateway, and
serves its own LAN client by DHCP from `brlan0`.

The nesting is four deep: an application container (crun), in a router container
(nested LXD, privileged), in the lab VM (LXD), on the bare-metal host.

```
rev140 (bare metal, LXD)
└── apps-lab (LXD VM, Ubuntu 24.04)
    ├── Docker: Boardfarm
    │   ├── dhcp-cpe1, wan-cpe1 ── br-wan101 ──┐
    │   ├── dhcp-cpe2, wan-cpe2 ── br-wan102 ──│──┐
    │   ├── lan-cpe1 ── br-lan201 ──┐          │  │
    │   └── lan-cpe2 ── br-lan202 ──│──┐       │  │
    └── nested LXD                  │  │       │  │
        ├── bpibroadband-dac  eth2 ─┘  │  eth0 ┘  │   (eth0 → erouter0, eth2 in brlan0)
        │   └── app (Dobby/crun)       │          │
        └── bpibroadband-lcm  eth2 ────┘  eth0 ───┘
            └── app (cthulhu/crun)
```

## Where it comes from: the EasyMesh labs

The apps labs follow the RDK EasyMesh lab
([meta-cmf-bananapi-vcpe](https://github.com/boardfarmdevs/meta-cmf-bananapi-vcpe),
one project of [easymesh-labs](https://github.com/boardfarmdevs/easymesh-labs)).
That lab has three stages, each its own script, and the apps lab keeps them:

| Stage | RDK EasyMesh lab | Apps lab |
| --- | --- | --- |
| Pinned sources | `doc/easymesh/build/manifest.xml`: every upstream project at a commit, checked before a build | `manifest/apps-lab.xml`: the same pins, plus the layer itself and the prpl `meta-amx` and `meta-lcm` |
| Images | `build-images.sh controller\|extender`: one build directory per machine, the shared `~/oe/downloads` and `~/oe/sstate-cache`, evidence per build | `build/build-images.sh dac\|lcm`: one build directory per framework, the same caches and evidence |
| Lab VM | `gen/vm/lxd/build.sh build`: an LXD VM, numbered provisioning scripts run in it, a runtime service that reconstructs the lab on boot | `lab/build.sh build`: the same shape, far smaller |
| Router deploy | `gen/bpi.sh`: profile, deterministic MACs, `/nvram` bind, WAN and LAN bridges | `lab/guest/apps-lab-router`: the same, named per framework, plus what the image needs to be an apps router (below) |
| WAN | Boardfarm (`boardfarm-lab-staging`, pinned), one CPE, `dhcp` and `wan` only | the same Boardfarm commit, two CPEs, `dhcp`, `wan` and `lan` |

What the apps lab leaves out, because applications do not need it: the Linux 7
kernel and the patched `mac80211_hwsim` module, wmediumd, the extender image, the
Wi-Fi clients, the rooms and the optimizer. The routers get no radio
(`HWSIM_RADIOS=0` in the reference's terms); OneWifi has nothing to drive. If a
later test needs Wi-Fi, the radio pool comes back the way the EasyMesh lab builds
it.

What the apps lab adds: a second router, LAN clients, and the LCM image.

## Repository layout

```
apps-labs/
├── README.md
├── doc/                 this plan; the build and lab guides
├── manifest/            apps-lab.xml, the pinned repo manifest
├── build/               bootstrap-sources.sh, build-images.sh, lcm.conf
├── lab/                 the VM: build.sh (host side), lab.env (pins and sizes)
│   ├── boardfarm/       the lab configuration and inventory (two CPEs)
│   ├── scripts/         numbered provisioning steps, run in the VM
│   └── guest/           what stays in the VM: router deploy, runtime, check, units
├── apps/                the applications and their build (phase 4)
├── tests/               the lifecycle tests over rbus and USP (phase 5)
├── yocto/               the Yocto workspace (ignored)
├── out/                 build outputs (ignored)
└── tmp/                 reference clones (ignored)
```

Everything is under this directory, the Yocto workspace included. Only the
download and sstate caches are shared with the other labs (`~/oe/downloads`,
`~/oe/sstate-cache`), as in the EasyMesh lab.

## The images

Both are `rdk-generic-broadband-image` for the machine `qemux86bpibroadband`
(i686 userspace, no kernel, packaged as an LXD image, `*.rootfs.lxc.tar.bz2`).

**DAC** is the layer's default: `meta-rdk-broadband-apps` sets
`RDK_BB_APPS_TOOLKIT_CRUNTIME ?= "DAC"` and installs `dobby crun dsm usp-pa`.
The image the EasyMesh lab builds already is the DAC image, so with the same
pins this build comes almost entirely from sstate.

**LCM** is the same build with
([doc/dac-lcm](https://github.com/boardfarmdevs/meta-cmf-bananapi-vcpe/tree/main/doc/dac-lcm)):

```
BBLAYERS += meta-amx meta-lcm
RDK_BB_APPS_TOOLKIT_CRUNTIME = "LCM"
BBMASK_append = "|meta-lcm/recipes-devtools/cmake/"
DISTRO_FEATURES_remove = "lcm-images lxc-backend"
DISTRO_FEATURES_append = " lcm-bundles crun-backend "
```

The `DISTRO_FEATURES` change invalidates most of the sstate, so LCM has its own
build directory and its first build is a long one. The layer carries what LCM
needed in a container when its notes were written (cthulhu on cgroup v2 and
without loop mounts, the syslog-ng include, the usp-pa event loop fix, the
`mod-amxb-rbus` stub); with the newer LCM the toolkit now names, not all of it
still fits (see the open points).

Pins (`manifest/apps-lab.xml`):

- the upstream projects exactly as `doc/easymesh/build/manifest.xml` pins them at
  the layer commit below;
- `boardfarmdevs/meta-cmf-bananapi-vcpe` at `36e36052`, the commit the EasyMesh
  lab's last image was built from, with its `gen/medium` submodule (the image
  takes a page from it);
- `meta-amx` at `a089ac0d` (tag `prplware-v4.1.0-p1`) and `meta-lcm` at `bba4f3ed`
  (tag `prplware-v4.1.0`), the tags `meta-rdk-broadband-apps` names in
  `manifests/rdkbb-apps-lcm.xml`.

## The lab VM

`lab/build.sh build` creates the VM and runs the numbered steps in it:

| Step | What it does |
| --- | --- |
| `00-base.sh` | packages, Docker, nested LXD (held at the installed revision) |
| `20-lab-host.sh` | the pinned Boardfarm checkout and its tools, the lab's two-CPE configuration, the nested LXD pool |
| `30-boardfarm.sh` | Boardfarm's providers: `bf-lab setup`, then what the runtime does to make them stay right |
| `40-routers.sh` | `apps-lab-router deploy` for `bpibroadband-dac` and `bpibroadband-lcm`, then the LAN clients |
| `50-runtime.sh` | the runtime service that brings Boardfarm and the routers back on boot, and the bundle server |

Then it reboots the VM, lets the runtime service bring the lab back, and runs
the acceptance check.

The VM runs the stock Ubuntu 24.04 kernel. Sizes are in `lab/lab.env` (4 CPUs,
8 GiB, 40 GiB to start with). It has its own LXD pool, `apps-lab-pool`, like the
other labs.

The acceptance check (`apps-lab-check`, also `lab/build.sh check`), per router:

1. the container runs;
2. `erouter0` has an IPv4 address from the router's own Kea server, and the
   default route is the slot's WAN gateway;
3. the router reaches the internet by address and by name;
4. `brlan0` has its address with the LAN port in it, and the LAN client has a
   lease from it;
5. the LAN client reaches the router and, through it, the internet;
6. the framework is there: DSM and Dobby on the DAC router, cthulhu, timingila
   and celephais on the LCM router, the USP agent on both, and
   `Device.SoftwareModules.` answers on rbus and on USP;
7. the router reaches the VM's bundle server.

And once for the lab: Boardfarm's own `bf-lab status`.

## Managing applications

Both frameworks present TR-181 `Device.SoftwareModules.`: `InstallDU()`,
`DeploymentUnit.{i}.` (`Update()`, `Uninstall()`), `ExecutionUnit.{i}.`
(`SetRequestedState()`, `Restart()`), `ExecEnv.{i}.`. The lab reaches it three
ways, and the tests cover each:

| Path | DAC router | LCM router |
| --- | --- | --- |
| rbus | `rbuscli method_values "Device.SoftwareModules.InstallDU()" URL string … ExecutionEnvRef string default` | the same through `mod-amxb-rbus` |
| native CLI | `dsmcli du.install`, `eu.start`, `DobbyTool list` | `ba-cli "Device.SoftwareModules.InstallDU(URL=…, UUID=…, ExecutionEnvRef=Device.SoftwareModules.ExecEnv.1.)"` |
| USP | obuspa as the local controller: `obuspa -c operate "Device.SoftwareModules.InstallDU(…)"`, `obuspa -c get "Device.SoftwareModules."` | the same |

A remote USP controller (Boardfarm's `oktopus` service) is a later option; the
first tests use the controller on the router itself.

## Applications and their build

An application is an OCI bundle: `rootfs/` and `config.json` in a flat tar. The
layer has three ways to make one, and `apps/` will wrap them so that one command
builds every lab application and puts the bundles where the routers fetch them:

| Way | Source | Use |
| --- | --- | --- |
| from the router image | `examples/hello-app`: busybox and glibc taken from the image's own rootfs | the smallest application, certain to match the router's i686 userspace |
| from a registry | `examples/from-registry`: `docker pull --platform linux/386`, export, render `config.json` | any public image; `examples/lcm-webapp` is one built for it |
| from Yocto | `classes/dac-bundle-image.bbclass`, `dac-image-tictactoe` | an application built with the router's toolchain |

The bundles are served to the routers over HTTP from the VM, on the WAN side
(each router reaches the VM at its WAN bridge's address). The first applications
are the reference's own: `hello` (a heartbeat on stdout) and the tic-tac-toe web
page (lighttpd), each on both frameworks. RDK's own application SDK
(`meta-dac-sdk-broadband`) has three more, `shell`, `iperf3` and `speedtest`;
they and the frameworks' repositories are in [applications.md](applications.md).

## Tests

A suite in `tests/`, run in the VM, per router and per management path:
install, start, observe (the framework's own list, the process, the
application's output or page), stop, uninstall; then the faults (a URL that does
not exist, a bundle that does not start) and persistence across a router reboot.
Acceptance of the lab is that suite passing on both routers.

## Phases

| Phase | Outcome |
| --- | --- |
| 0 | this plan, the repository skeleton |
| 1 | the Yocto workspace at the pins; the DAC and the LCM image |
| 2 | the VM `apps-lab` with both routers WAN, DHCP and LAN connected: the first acceptance |
| 3 | the frameworks proven by hand: one application installed and started on each router |
| 4 | `apps/`: the application build and the bundle server |
| 5 | `tests/`: the lifecycle suite over rbus, the native CLIs and USP |
| 6 | the guides, the site, the repository on GitHub |

## Found on the way

What the first builds showed, and what the lab does about it. The first five are
defects of the image or of Boardfarm's containers that the lab works around in
its own scripts; they are candidates for a fix where they belong.

- **The image removes `eth1`.** Some ten seconds into its boot the router deletes
  an interface named `eth1` (the LAN port the layer's own HAL bridges into
  `brlan0`); what does it is not found yet. The lab's LAN port is `eth2`, and
  `apps-lab-router` installs a unit in the router that keeps it a port of
  `brlan0`. The RDK EasyMesh lab has the same `eth2`, kept in `brlan0` from its VM.
- **The USP agent does not start.** `vcpe-init` points obuspa's factory reset file
  at `/etc/usp-pa/oktopus-mqtt-obuspa.txt` on every boot and removes its
  database; the image has no such file. `apps-lab-router` writes one: an agent
  without a remote controller. With it, `obuspa -c get Device.SoftwareModules.`
  answers.
- **Boardfarm's WAN gateway routes nowhere after `bf-lab setup`.** Connected to
  its WAN network while it runs, the container has Docker's gateway on that
  network as its default route instead of the management network it masquerades
  on. The runtime checks the route as part of readiness and puts it right. (The
  EasyMesh lab does not meet this: its VM build reboots before anything needs
  the internet.)
- **A restarted Boardfarm container can come up with its interfaces swapped.**
  bf-lab starts each container on its management network and connects the slot's
  WAN or LAN network afterwards, so that the first is `eth0` and the second
  `eth1`. Started by Docker with both (a restart, a VM boot), a container can get
  them the other way round, and its init then flushes and configures the wrong
  one: seen on a LAN client, a Kea server and a WAN gateway, and the reason a VM
  boot ended in a full `bf-lab setup`. After a setup the runtime connects every
  slot network again with its interface name fixed to `eth1`
  (`com.docker.network.endpoint.ifname`, Docker 28 and later), which holds across
  restarts, and it checks that `eth0` is the management interface as part of
  readiness.
- **Kea does not start after a power-off**, either family: its PID files stay in
  the container. The runtime removes them and starts the container again (the
  EasyMesh lab does the same for DHCPv4).
- **`bf-lab status` as a gate.** It fails until the LAN clients' sshd runs, which
  is only after they have waited for a lease. The runtime has its own readiness
  test and the acceptance check runs `bf-lab status` at the end.
- **`meta-amx` in the DAC build.** The BSP's setup adds it to `bblayers.conf`
  whenever the workspace has it; `build-images.sh` takes it out again for DAC.

## Open points

- **Wi-Fi.** The routers run without a radio. OneWifi and the EasyMesh services
  are in the image and have nothing to drive; they are left as they are.
- **The LCM build** has not been done on this host from these pins; the recipe
  for it comes from the layer's `doc/dac-lcm`, which was written against the LCM
  of prplOS 3.1.0, while the apps toolkit now names prplware 4.1.0. The first
  difference showed in cthulhu (the layer's cgroup v2 patch no longer applies to
  code that has its own cgroup v2 support); more may follow, in the build and at
  run time. Fixes go to the layer when they are the layer's.
- **Both runtimes in one image** is not possible: the toolkit selects one at
  build time, hence two images and two routers.
- **`/apps` storage.** The toolkit wants a dedicated writable partition for
  application images and data; in the lab that is a directory on the router's
  root disk, sized in `lab/lab.env`.
- **The shared host.** rev140 also runs an EasyMesh lab VM; an image build loads
  the host and can disturb that lab's traffic checks while it runs.

## Status

As of 1 October 2026.

| Phase | Status |
| --- | --- |
| 0 | done |
| 1 | both images are built. DAC in 14 minutes, from the EasyMesh lab's sstate but for two recipes. LCM from source (12 % of its sstate was there), with three changes to the layer's recipe for it (`build/lcm.conf`): the cthulhu cgroup patch left out, `timingila-celephais` at v1.1.0, `shadow` in the image |
| 2 | the VM `apps-lab` runs on rev140 with `bpibroadband-dac` and `bpibroadband-lcm`: the check passes for both (WAN, DHCP, internet, LAN client, the framework's services, the USP agent, the bundle server), and the lab comes back by itself when the VM is stopped and started (verified twice, with the DAC router). A build of the VM from nothing with the scripts as they are now is still to be repeated |
| 3 | done on both routers: `hello` and `tictactoe` installed, started, stopped and uninstalled over the framework's own tool, rbus and USP ([applications.md](applications.md)) |
| 4 | `apps/build.sh` builds `hello` and `tictactoe` from the router image's own programs; the VM serves the bundles. RDK's SDK examples are to come |
| 5 | `tests/lifecycle.py` (`lab/build.sh test ROUTER`): every check passes on the DAC router; on the LCM router all but the execution unit's `Status`, which lags. Faults and persistence are to come |
| 6 | the site is published, with the application's life animated |
