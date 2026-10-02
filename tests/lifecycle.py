#!/usr/bin/env python3
"""The application lifecycle on a router of the apps lab, over each management path.

    lifecycle.py ROUTER [--path native|rbus|usp ...] [--bundle NAME]

Run in the lab VM (lab/build.sh test ROUTER ...). It first starts the framework
again with nothing installed. Then, for every path, it installs the bundle from
the VM's bundle server, starts it, stops it and uninstalls it through that path
alone, and after each step observes the result where it shows: the data model
over rbus, the container runtime, the application's output.

The paths, on a DAC router (DSM, Dobby):
    native   dsmcli
    rbus     rbuscli on Device.SoftwareModules.
    usp      obuspa -c, the USP controller on the router itself

Exit status 0 when every check passed.
"""

import argparse
import re
import shlex
import subprocess
import sys
import time

PATHS = ("native", "rbus", "usp")
DM = "Device.SoftwareModules."
# What the bundles write to stdout, to recognise their output in the journal.
OUTPUT = {"hello": "hello-from-dsm"}


def lab_routers():
    """name -> (framework, cpe), from the lab's settings."""
    settings = open("/etc/default/apps-lab").read()
    listed = re.search(r'^APPS_LAB_ROUTERS="([^"]*)"', settings, re.M).group(1)
    return {name: (framework, int(cpe)) for name, framework, cpe in (r.split(":") for r in listed.split())}


class Router:
    def __init__(self, name, framework, cpe):
        self.name, self.framework, self.cpe = name, framework, cpe
        self.server = f"http://10.{100 + cpe}.0.1:8080"

    def sh(self, command, check=False):
        """Run a shell command in the router; its output, stderr included."""
        result = subprocess.run(
            ["lxc", "exec", self.name, "--", "sh", "-c", command],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, check=False,
        )
        if check and result.returncode:
            raise RuntimeError(f"{command}: {result.stdout}{result.stderr}".strip())
        return result.stdout + result.stderr

    def data_model(self):
        """Device.SoftwareModules. as rbus has it: path -> value."""
        values, name = {}, None
        for line in self.sh(f"rbuscli getvalues {DM}").splitlines():
            key, _, value = line.partition(":")
            if key.strip() == "Name":
                name = value.strip()
            elif key.strip() == "Value" and name:
                values[name], name = value.strip(), None
        return values

    def rows(self, table, field):
        """A table's instances: instance number -> the value of one of its fields."""
        pattern = re.compile(re.escape(DM + table) + r"\.(\d+)\." + re.escape(field) + "$")
        return {int(m.group(1)): value for path, value in self.data_model().items() if (m := pattern.match(path))}

    def instance(self, table, field, value):
        """The instance number of the row whose field has this value, or None."""
        return next((number for number, found in self.rows(table, field).items() if found == value), None)


class Dac:
    """DSM and Dobby. An execution unit's name is the container's name in Dobby and the
    identifier of its output in the journal."""

    environment = "default"

    def __init__(self, router):
        self.router = router
        self.agent_restarts = 0

    def dsmcli(self, arguments):
        return self.router.sh(f"cd /home/root && DSM_CONFIG_FILE=/etc/dsm.config dsmcli {arguments}")

    def operate(self, command):
        """A USP operation on the router's own controller.

        The agent (usp-pa) can lose track of a table: seen with an execution unit that
        existed when the agent started, was removed, and came back with the same instance
        number. The agent then counts no rows and refuses the row's methods ("instances
        are invalid") until it is started again. The test counts that as a failure of its
        own and then starts the agent again, so that the rest of the path is still
        exercised.
        """
        deadline = time.monotonic() + 15
        while True:
            reply = self.router.sh(f'obuspa -c operate "{command}"')
            if "instances are invalid" not in reply:
                return reply
            if time.monotonic() >= deadline:
                break
            time.sleep(2)
        self.agent_restarts += 1
        self.router.sh("systemctl restart usp-pa")
        wait(lambda: "=>" in self.router.sh(f"obuspa -c get {DM}ExecEnvNumberOfEntries"), 60)
        return self.router.sh(f'obuspa -c operate "{command}"')

    def install(self, path, url):
        if path == "native":
            return self.dsmcli(f"du.install {self.environment} {shlex.quote(url)}")
        if path == "rbus":
            return self.router.sh(
                f'rbuscli method_values "{DM}InstallDU()" URL string {shlex.quote(url)} '
                f"ExecutionEnvRef string {self.environment}"
            )
        return self.operate(f"{DM}InstallDU(URL={url},ExecutionEnvRef={self.environment})")

    def set_state(self, path, unit, state):
        if path == "native":
            return self.dsmcli(f"eu.{'start' if state == 'Active' else 'stop'} {unit}")
        number = self.router.instance("ExecutionUnit", "Name", unit)
        method = f"{DM}ExecutionUnit.{number}.SetRequestedState"
        if path == "rbus":
            return self.router.sh(f'rbuscli method_values "{method}()" RequestedState string {state}')
        return self.operate(f"{method}(RequestedState={state})")

    def uninstall(self, path, url):
        if path == "native":
            return self.dsmcli(f"du.uninstall {shlex.quote(url)}")
        number = self.router.instance("DeploymentUnit", "URL", url)
        method = f"{DM}DeploymentUnit.{number}.Uninstall()"
        if path == "rbus":
            return self.router.sh(f'rbuscli method_noargs "{method}"')
        return self.operate(method)

    def problem(self):
        """What keeps the framework from managing applications at all, if anything."""
        for unit in ("dobby", "dsm"):
            if self.router.sh(f"systemctl is-active {unit}").strip() != "active":
                return f"{unit} does not run"
        return ""

    def reset(self):
        """Start DSM again with nothing installed, and the USP agent after it.

        DSM does not always come back to a state a test can start from: it is not
        started again when it has crashed (its unit says Restart=no), and a package it
        found on disk when it started stays "already installed" in its memory after it
        is uninstalled.
        """
        self.router.sh(
            "systemctl stop dsm; rm -rf /home/root/destination/* /home/root/destination/.[!.]*; "
            "systemctl start dsm; systemctl restart usp-pa"
        )
        wait(lambda: not self.problem() and self.router.rows("ExecEnv", "Name"), 60)
        wait(lambda: "=>" in self.router.sh(f"obuspa -c get {DM}ExecEnvNumberOfEntries"), 60)

    def leftovers(self):
        """What is installed or left behind: deployment units and files."""
        units = sorted(self.router.rows("DeploymentUnit", "URL").values())
        files = self.router.sh("ls -A /home/root/destination 2>/dev/null").split()
        return units + files

    def container_runs(self, unit):
        return bool(re.search(rf"\|\s*{re.escape(unit)}\s*\|\s*running", self.router.sh("DobbyTool list")))

    def output_since(self, unit, started, text):
        journal = self.router.sh(f"journalctl --no-pager -o cat SYSLOG_IDENTIFIER={unit} --since @{started}")
        return [line for line in journal.splitlines() if text in line]

    def files(self, bundle):
        return self.router.sh(f"ls -d /home/root/destination/{bundle} 2>/dev/null").strip()


FRAMEWORKS = {"dac": Dac}


class Run:
    def __init__(self):
        self.failures = 0

    def check(self, what, passed, detail=""):
        print(f"  {'PASS' if passed else 'FAIL'}  {what}{f' ({detail})' if detail and not passed else ''}", flush=True)
        self.failures += not passed
        return passed


def wait(condition, seconds=60, every=1.0):
    """The condition's first true value within the time, else its last value."""
    deadline = time.monotonic() + seconds
    while True:
        value = condition()
        if value or time.monotonic() >= deadline:
            return value
        time.sleep(every)


def lifecycle(run, router, framework, path, bundle):
    url = f"{router.server}/{bundle}.tar"
    unit_status = lambda unit: router.rows("ExecutionUnit", "Status").get(router.instance("ExecutionUnit", "Name", unit))
    installed = lambda: router.rows("DeploymentUnit", "Status").get(router.instance("DeploymentUnit", "URL", url))
    print(f"{router.name} ({router.framework}), {path}: {url}")

    problem = framework.problem() or ", ".join(framework.leftovers())
    if not run.check("the framework runs and has nothing installed", not problem, problem):
        framework.reset()    # a crash, or what the path before left behind
        if framework.problem() or framework.leftovers():
            return
    if not run.check("the router can fetch the bundle", "200" in router.sh(f"curl -sI --max-time 5 {url} | head -n 1")):
        return
    units_before = set(router.rows("ExecutionUnit", "Name").values())

    reply = framework.install(path, url)
    if not run.check("install: the deployment unit is Installed", wait(lambda: installed() == "Installed"), reply.strip()[-200:]):
        return
    new_units = wait(lambda: set(router.rows("ExecutionUnit", "Name").values()) - units_before, 30)
    if not run.check("install: it has one new execution unit", len(new_units or ()) == 1, str(new_units)):
        return
    unit = new_units.pop()
    run.check(f"install: the execution unit {unit} is Idle", wait(lambda: unit_status(unit) == "Idle", 30), str(unit_status(unit)))
    run.check("install: the bundle's files are on the router", bool(framework.files(bundle)))

    started = int(router.sh("date +%s").strip())
    reply = framework.set_state(path, unit, "Active")
    run.check("start: the execution unit is Active", wait(lambda: unit_status(unit) == "Active", 30), reply.strip()[-200:])
    run.check("start: the runtime has the container running", wait(lambda: framework.container_runs(unit), 30))
    if bundle in OUTPUT:
        lines = wait(lambda: framework.output_since(unit, started, OUTPUT[bundle]), 30)
        run.check("start: the application writes its output", bool(lines))
        if lines:
            print(f"        {lines[-1].strip()}")

    reply = framework.set_state(path, unit, "Idle")
    run.check("stop: the execution unit is Idle", wait(lambda: unit_status(unit) == "Idle", 30), reply.strip()[-200:])
    run.check("stop: the runtime has no such container", wait(lambda: not framework.container_runs(unit), 30))

    reply = framework.uninstall(path, url)
    if path == "usp":
        run.check(
            "usp: the agent knew every new row without being started again",
            framework.agent_restarts == 0, f"started again {framework.agent_restarts} time(s)",
        )
    run.check("uninstall: the deployment unit is gone", wait(lambda: not installed(), 30), reply.strip()[-200:])
    run.check(
        "uninstall: its execution unit is gone",
        wait(lambda: unit not in router.rows("ExecutionUnit", "Name").values(), 30),
    )
    run.check("uninstall: the bundle's files are gone", wait(lambda: not framework.files(bundle), 30))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("router")
    parser.add_argument("--path", action="append", choices=PATHS, help="default: every path")
    parser.add_argument("--bundle", default="hello")
    args = parser.parse_args()
    routers = lab_routers()
    if args.router not in routers:
        raise SystemExit(f"{args.router} is not one of the lab's routers ({', '.join(routers)})")
    framework_name, cpe = routers[args.router]
    if framework_name not in FRAMEWORKS:
        raise SystemExit(f"the {framework_name} framework has no lifecycle test yet")
    router = Router(args.router, framework_name, cpe)
    framework = FRAMEWORKS[framework_name](router)
    run = Run()
    print(f"{router.name}: starting the framework again with nothing installed")
    framework.reset()
    for path in args.path or PATHS:
        lifecycle(run, router, framework, path, args.bundle)
    print("lifecycle: every check passed" if not run.failures else f"lifecycle: {run.failures} check(s) failed")
    return 1 if run.failures else 0


if __name__ == "__main__":
    sys.exit(main())
