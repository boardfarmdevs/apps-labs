# Applications: references and candidates

Where the frameworks and their example applications come from, and which
applications the lab plans to build and run. A survey, made before any
application has run in the lab: what is verified is said so, the rest is the
plan for phases 3 and 4 of [the plan](plan.md).

## The frameworks' repositories

| Repository | What it is | In the lab |
| --- | --- | --- |
| [rdkcentral/meta-rdk-broadband-apps](https://github.com/rdkcentral/meta-rdk-broadband-apps) ([docs](https://rdkcentral.github.io/meta-rdk-broadband-apps/)) | The Broadband Apps toolkit: the layer that adds DAC or LCM to an RDK-B image (`RDK_BB_APPS_TOOLKIT_CRUNTIME`), `Device.SoftwareModules.` over USP, and the guides for building and deploying an application | pinned in `manifest/apps-lab.xml`; both images are built with it |
| [rdkcentral/DSM](https://github.com/rdkcentral/DSM) | DAC's software module manager: execution environments, deployment units and execution units; a packager (tar bundles from a directory or over HTTP) and a runtime (Dobby); `dsmcli`; the rbus provider | in the DAC image (`dsm`, `dsmcli`, `/etc/dsm.config`) |
| [rdkcentral/Dobby](https://github.com/rdkcentral/Dobby) | The container daemon around crun, with its plugins (`rdkPlugins` in a bundle's `config.json`, `ociVersion` `1.0.2-dobby`) and `DobbyTool` | in the DAC image |
| [rdkcentral/BundleGen](https://github.com/rdkcentral/BundleGen) | Turns an OCI image into a Dobby bundle for a platform, from the application's metadata and a platform template | used by the SDK below |
| [rdkcentral/meta-dac-sdk-broadband](https://github.com/rdkcentral/meta-dac-sdk-broadband) | The application SDK for RDK-B: a Yocto layer whose `dac-image-base` class builds an application as an OCI image and, with BundleGen, as a bundle; three example applications | the source of the lab's Yocto-built examples |
| [rdkcentral/rdk-speedtest-cli](https://github.com/rdkcentral/rdk-speedtest-cli) | A speed test client on iperf3 that reports through rbus and telemetry | the SDK's `speedtest` example |
| [rdkcentral/meta-dac-sdk](https://github.com/rdkcentral/meta-dac-sdk), [rdkcentral/dac-examples-src](https://github.com/rdkcentral/dac-examples-src) | The SDK and example sources for RDK video devices (Wayland, EGL, SDL, browsers) | not for a router |
| [prpl meta-lcm](https://gitlab.com/prpl-foundation/prplrdkb/metalayers/meta-lcm), [prpl meta-amx](https://gitlab.com/prpl-foundation/prplrdkb/metalayers/meta-amx) | LCM: cthulhu (containers), timingila (the `SoftwareModules` data model), celephais (bundles) or rlyeh (images), on the Ambiorix stack with `ba-cli` | pinned in `manifest/apps-lab.xml`; the LCM image is built with them |
| [BroadbandForum/obuspa](https://github.com/BroadbandForum/obuspa) | The USP agent; `obuspa -c` is a controller on the device itself | in both images, with RDK's `usp-pa` vendor plugin |
| [meta-cmf-bananapi-vcpe](https://github.com/boardfarmdevs/meta-cmf-bananapi-vcpe) `examples/`, `classes/dac-bundle-image.bbclass`, `recipes-apps/` | Three ways to make a bundle for the x86 router image, and what LCM needs to run in a container ([doc/dac-lcm](https://github.com/boardfarmdevs/meta-cmf-bananapi-vcpe/tree/main/doc/dac-lcm)) | the lab's starting point |

## What an application is

For both frameworks as the lab builds them (LCM with `lcm-bundles` and
`crun-backend`): an **OCI bundle**, a tar with `rootfs/` and `config.json` at its
top level, fetched from a URL and run by crun.

- The router's userspace is **i686**. A bundle's binaries are 32-bit x86: built
  with the router's toolchain, taken from the router's own root filesystem, or
  from a `linux/386` image. Static (musl) binaries, as the toolkit recommends,
  avoid the question of libraries.
- For Dobby, `config.json` says `"ociVersion": "1.0.2-dobby"` and can name
  `rdkPlugins` (logging to the journal, networking); the SDK's applications also
  carry an `appmetadata.json` (identity, memory, network access) that BundleGen
  turns into that `config.json`.
- For cthulhu, the container's first process should write to stdout regularly
  (the layer's `lcm-webapp` example has a heartbeat for that).

## Candidates

| Application | What it shows | Source | Build |
| --- | --- | --- | --- |
| `hello` | the smallest bundle: a shell loop that prints a heartbeat | the layer's `examples/hello-app` | busybox and glibc from the router image's own root filesystem; built once here (`hello.tar`, 3.8 MB), not yet installed |
| `tictactoe` | a web application: lighttpd serving a page on a port | the layer's `dac-image-tictactoe` | Yocto, `dac-bundle-image` class, in the router's build |
| `lcm-webapp` | the same from a registry image, with the heartbeat cthulhu wants | the layer's `examples/lcm-webapp`, `examples/from-registry` | `docker buildx` for `linux/386`, exported and wrapped as a bundle |
| `shell` | an application to look around a container from | `meta-dac-sdk-broadband` `dac-image-shell` | Yocto, the SDK's `dac-image-base` |
| `iperf3` | a network application with arguments: throughput from inside a container to the WAN or LAN side | `meta-dac-sdk-broadband` `dac-image-iperf3` | Yocto, the SDK's `dac-image-base`; the lab's WAN gateway or LAN client as the server |
| `speedtest` | an application that uses the router's rbus and telemetry from inside its container | `meta-dac-sdk-broadband` `dac-image-speedtest`, `rdk-speedtest-cli` | Yocto, the SDK; needs the bus mounted into the container |
| any public image | the registry path the toolkit describes | Docker Hub, GHCR (`i386/alpine`, `i386/busybox`, …) | `examples/from-registry` |

The first two phases of applications use `hello` and `tictactoe` on both
routers: they need nothing from the SDK. The SDK's three follow, built for the
router's machine rather than for the Raspberry Pi the SDK names; whether its
classes work unchanged in this workspace (they want `image-oci` from
meta-virtualization and BundleGen with a platform template for the router) is
not tried yet.

## Managing them

The toolkit's own verification, on a Banana Pi, is the sequence the lab's tests
will follow on both routers:

```sh
rbuscli method_values "Device.SoftwareModules.InstallDU()" \
    URL string http://<server>/<bundle>.tar ExecutionEnvRef string default
rbuscli method_values "Device.SoftwareModules.ExecutionUnit.1.SetRequestedState()" \
    RequestedState string Active
dmcli eRT getv Device.SoftwareModules.
DobbyTool list
rbuscli method_values "Device.SoftwareModules.ExecutionUnit.1.SetRequestedState()" \
    RequestedState string Idle
```

and its counterparts: `dsmcli du.install|eu.start|eu.stop` on DAC,
`ba-cli "Device.SoftwareModules.InstallDU(URL=…, UUID=…, ExecutionEnvRef=Device.SoftwareModules.ExecEnv.1.)"`
on LCM, `obuspa -c operate` and `obuspa -c get` over USP on both. The toolkit's
guide notes one DSM fix its DAC needs
([DSM 73c6a95](https://github.com/rdkcentral/DSM/commit/73c6a952786c8a7660b44389f96612e9a912456f));
whether the pinned image has it is checked when the first application is
installed.
