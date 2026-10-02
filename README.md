# Apps labs

**Site:** <https://boardfarmdevs.github.io/apps-labs/>

Virtual labs that demonstrate the application frameworks of RDK-B: **DAC**
(Downloadable Application Containers, the RDK default) and **LCM** (prpl
Lifecycle Management). An apps lab is an RDK-B router, the Banana Pi
`bpibroadband` image rebuilt for x86, running as a container in a lab VM with a
Boardfarm WAN and LAN, into which an application is installed and started
through the data model: rbus, the frameworks' own tools and USP.

One VM, `apps-lab`, runs both at once:

| Router | Framework | Boardfarm slot |
| --- | --- | --- |
| `bpibroadband-dac` | DSM and Dobby, OCI bundles run by crun | CPE 1: `dhcp-cpe1`, `wan-cpe1`, `lan-cpe1` |
| `bpibroadband-lcm` | timingila and cthulhu on Ambiorix, OCI bundles run by crun | CPE 2: `dhcp-cpe2`, `wan-cpe2`, `lan-cpe2` |

An application is a container (crun) in a container (the router, nested LXD) in
a VM (the lab) on a bare-metal host.

The labs follow the RDK EasyMesh lab of the
[EasyMesh labs](https://github.com/boardfarmdevs/easymesh-labs)
([meta-cmf-bananapi-vcpe](https://github.com/boardfarmdevs/meta-cmf-bananapi-vcpe)):
the same Yocto layer at a pinned commit, the same pinned upstream sources, the
same Boardfarm, the same build stages.

## Documentation

| | |
| --- | --- |
| [doc/plan.md](doc/plan.md) | what is built, how it derives from the EasyMesh lab, the phases and their status |
| [doc/build.md](doc/build.md) | build the images and the VM, operate and check the lab |

## Quick start

On an Ubuntu 22.04 x86-64 host prepared as for the EasyMesh lab (`repo`, GNU tar
1.34 and `lz4c` in `~/hosttools/bin`, the shared `~/oe/downloads` and
`~/oe/sstate-cache`, LXD with `/dev/kvm`):

```sh
export PATH="$HOME/hosttools/bin:$HOME/bin:$PATH"
build/bootstrap-sources.sh        # the Yocto workspace in yocto/, at the pinned commits
build/build-images.sh both        # the DAC and the LCM router image
lab/build.sh build                # the VM apps-lab with both routers, checked
lab/build.sh status
lab/build.sh router bpibroadband-dac        # a shell in a router
```

## Layout

| | |
| --- | --- |
| `manifest/` | `apps-lab.xml`: every source the images are built from, at a commit |
| `build/` | the Yocto workspace and the two image builds |
| `lab/` | the VM: `build.sh` on the host, `scripts/` and `guest/` in the VM, `boardfarm/` its two-CPE configuration, `lab.env` its pins and sizes |
| `doc/` | the plan and the guides |
| `site/`, `pages/` | the landing page and its build; `.github/workflows/pages.yml` publishes it |
| `yocto/`, `out/`, `tmp/` | the Yocto workspace, build outputs and reference clones; not in the repository |
