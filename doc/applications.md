# Applications: references, candidates, first results

Where the frameworks and their example applications come from, which
applications the lab plans to build and run, and what the first application
showed on the DAC router. What is verified is said so; the rest is the plan for
phases 3 to 5 of [the plan](plan.md).

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
| `hello` | the smallest bundle: a shell loop that prints a heartbeat | the layer's `examples/hello-app` | `apps/build.sh hello`: busybox and glibc from the router image's own root filesystem (3.7 MB); runs on the DAC router, see below |
| `tictactoe` | a web application: lighttpd serving the layer's tic-tac-toe page on port 8090, with a heartbeat on stdout; the container shares the router's network, so the page is at the router's addresses | the layer's `tictactoe-content`; `apps/tictactoe/` (server configuration, entrypoint, `config.json`) | `apps/build.sh tictactoe`: lighttpd, its modules and the libraries they need, from the router image's own root filesystem (7.3 MB); runs on the DAC router, the LAN client gets the page |
| `lcm-webapp` | the same from a registry image, with the heartbeat cthulhu wants | the layer's `examples/lcm-webapp`, `examples/from-registry` | `docker buildx` for `linux/386`, exported and wrapped as a bundle |
| `shell` | an application to look around a container from | `meta-dac-sdk-broadband` `dac-image-shell` | Yocto, the SDK's `dac-image-base` |
| `iperf3` | a network application with arguments: throughput from inside a container to the WAN or LAN side | `meta-dac-sdk-broadband` `dac-image-iperf3` | Yocto, the SDK's `dac-image-base`; the lab's WAN gateway or LAN client as the server |
| `speedtest` | an application that uses the router's rbus and telemetry from inside its container | `meta-dac-sdk-broadband` `dac-image-speedtest`, `rdk-speedtest-cli` | Yocto, the SDK; needs the bus mounted into the container |
| any public image | the registry path the toolkit describes | Docker Hub, GHCR (`i386/alpine`, `i386/busybox`, …) | `examples/from-registry` |

The first two, `hello` and `tictactoe`, need neither the SDK nor a toolchain:
`apps/build.sh` assembles them from programs of the router image itself and
follows their shared libraries (`readelf`), so they match the router's userspace
by construction. The SDK's three follow, built for the
router's machine rather than for the Raspberry Pi the SDK names; whether its
classes work unchanged in this workspace (they want `image-oci` from
meta-virtualization and BundleGen with a platform template for the router) is
not tried yet.

## Build and serve

```sh
apps/build.sh               # the lab's applications as bundles, into out/apps/
lab/build.sh apps           # onto the VM's bundle server; prints each router's URLs
```

The VM serves `/var/lib/apps-lab/apps` over HTTP on port 8080
(`apps-lab-apps.service`). A router reaches it on its WAN side, at the VM's
address on the router's WAN bridge: `http://10.101.0.1:8080/hello.tar` from
`bpibroadband-dac`, `http://10.102.0.1:8080/hello.tar` from `bpibroadband-lcm`.
The acceptance check includes that the router reaches it.

## First results: `hello` on the DAC router (1 October 2026)

By hand, in `bpibroadband-dac` (`lab/build.sh router bpibroadband-dac`), each
step observed:

| Step | Command | Result |
| --- | --- | --- |
| Install | `dsmcli du.install default http://10.101.0.1:8080/hello.tar` | the deployment unit is `Installed`, the bundle is under `/home/root/destination/hello`, an execution unit (`Kn`) is `Idle` |
| Start | `dsmcli eu.start Kn` | `DobbyTool list` shows the container `running`; the journal has its output, `hello-from-dsm #1 pid=1 host=Kn uname=Linux 6.8.0-142-generic i686` |
| Stop, over rbus | `rbuscli method_values "Device.SoftwareModules.ExecutionUnit.1.SetRequestedState()" RequestedState string Idle` | `Stopping EU`; the status is `Idle`, Dobby has no container |
| Start, over USP | `obuspa -c operate "Device.SoftwareModules.ExecutionUnit.1.SetRequestedState(RequestedState=Active)"` | the operation completes; the status is `Active`, the container runs again |
| Read, over USP | `obuspa -c get Device.SoftwareModules.` | the execution environments, the deployment unit with its URL and status, the execution unit |
| Install, over rbus | `rbuscli method_values "Device.SoftwareModules.InstallDU()" URL string http://10.101.0.1:8080/hello.tar ExecutionEnvRef string default` | reaches DSM (`Package already installed`, as it was) |
| Uninstall | `dsmcli du.uninstall http://10.101.0.1:8080/hello.tar` | the bundle is removed from `/home/root/destination` |

So an application runs four deep, a crun container in the router container in
the VM on the host, and all three management paths reach it.

## The lifecycle test

```sh
lab/build.sh test bpibroadband-dac            # every path; or --path native|rbus|usp
```

`tests/lifecycle.py`, run in the VM. It starts the framework again with nothing
installed, then for each path (`native`: `dsmcli`; `rbus`: `rbuscli`; `usp`:
`obuspa -c`) installs `hello` from the bundle server, starts it, stops it and
uninstalls it through that path alone. After each step it observes the result
where it shows: the deployment and execution units over rbus, the container in
Dobby, the application's output in the journal, the bundle's files.

On `bpibroadband-dac` every check passes on all three paths, for `hello` twice
in a row and for `tictactoe` (`--bundle tictactoe`), where the test also has the
slot's LAN client fetch the page from the router's LAN address while the
application runs, and finds it gone after the stop (1 October 2026). Uninstall works over rbus (`rbuscli method_noargs
"Device.SoftwareModules.DeploymentUnit.{i}.Uninstall()"`) and over USP as well.

## What this DSM does differently

From its documentation or from the data model, for whoever uses the DAC router:

- **Bundles come over HTTP only.** `dsmcli du.install default hello` with
  `hello.tar` in `/home/root/repo` fails with `Local install not implemented,
  please use http`, and leaves a deployment unit in the state `Undefined` that
  `du.uninstall` does not remove.
- **A deployment unit's identity is its URL**: `du.uninstall` takes the URL the
  unit was installed from.
- **The references between the tables are off by one**: the second deployment
  unit, installed in the first execution environment with the first execution
  unit, reports `ExecutionEnvRef` `…ExecEnv.2` and `ExecutionUnitList`
  `…ExecutionUnit.2`.
- The execution unit's name is generated (`Kn`, `NX`, …), not the bundle's; it
  is the container's name in Dobby and the identifier of its output in the
  journal.
- **DSM crashed once on an uninstall** (`terminate called after throwing an
  instance of 'std::length_error'`), after its execution unit had been started
  and stopped over USP; not reproduced since. Its unit says `Restart=no`, so the
  framework is gone until `systemctl start dsm`.
- **After a restart DSM can keep a package it no longer has**: started with a
  package on disk, then told to uninstall it, it removes the files and the rows
  but answers every later install of that URL with `Package already installed`.
  Stopping DSM, emptying `/home/root/destination` and starting it again clears
  it (what the test does before it begins).
- **The USP agent can lose track of the execution units**: with a unit present
  when `usp-pa` started, then uninstalled and installed again, the agent counted
  no execution units and refused `SetRequestedState()` on the new one
  (`instances are invalid`) until it was started again. With the table empty at
  the agent's start, as in the test, it follows every install and uninstall.
- The fix the toolkit's guide asks for
  ([DSM 73c6a95](https://github.com/rdkcentral/DSM/commit/73c6a952786c8a7660b44389f96612e9a912456f))
  is in the image: the pinned `meta-rdk` builds DSM at `be204cb`, its merge.

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
on LCM, `obuspa -c operate` and `obuspa -c get` over USP on both.
