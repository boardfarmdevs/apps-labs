#!/usr/bin/env python3
"""Check that every project of the workspace is at the commit the manifest pins.

    verify-pins.py MANIFEST WORKSPACE
"""

import pathlib
import subprocess
import sys
import xml.etree.ElementTree as tree


def main():
    manifest, workspace = map(pathlib.Path, sys.argv[1:])
    for project in tree.parse(manifest).findall("project"):
        directory = workspace / project.get("path", project.get("name"))
        expected = project.get("revision")
        actual = subprocess.check_output(
            ["git", "-C", str(directory), "rev-parse", "HEAD"], text=True
        ).strip()
        if actual != expected:
            raise SystemExit(f"Pinned source mismatch: {directory}: {actual} != {expected}")
    print("Pinned source tree verified.")


if __name__ == "__main__":
    main()
