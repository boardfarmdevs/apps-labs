#!/usr/bin/env python3
"""The documentation check, run by the Pages workflow from the repository's root:

    python3 pages/check-docs.py

Every relative link in a tracked Markdown file names a file or directory that exists.
(After the EasyMesh labs' check-docs.py, without their labs block.)
"""

import pathlib
import re
import subprocess
import sys
from urllib.parse import unquote

LINK = re.compile(r"\]\(([^)\s]+)\)")
FENCE = re.compile(r"^(```|~~~).*?^\1", re.S | re.M)


def relative_links(root):
    listed = subprocess.run(
        ["git", "-C", str(root), "ls-files", "*.md"], capture_output=True, text=True, check=True
    ).stdout.split()
    problems = []
    for name in listed:
        path = root / name
        if not path.exists():
            continue
        text = FENCE.sub("", path.read_text(errors="replace"))
        for match in LINK.finditer(text):
            target = match.group(1).split("#", 1)[0].split("?", 1)[0]
            if not target or re.match(r"^[a-z][a-z0-9+.-]*:", target) or target.startswith("<"):
                continue
            if not (path.parent / unquote(target)).exists():
                problems.append(f"{name}: broken link {match.group(1)}")
    return problems


def main():
    problems = relative_links(pathlib.Path.cwd())
    for problem in problems:
        print(problem, file=sys.stderr)
    print(f"check-docs: {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
