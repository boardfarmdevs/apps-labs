#!/usr/bin/env python3
"""Finish a built Pages site: .nojekyll and build.json.

    python3 pages/finish-site.py [SITE]          (default dist/site)

- writes .nojekyll and build.json (repository, revision, pages);
- fails when the site has no index.html or a page links to a local file the site
  does not have.

The repository name comes from GITHUB_REPOSITORY in Actions, else from the
origin remote. (The EasyMesh labs' finish-site.py also adds their labs bar; the
apps labs are not one of those sites.)
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
LOCAL = re.compile(r"""(?:href|src)=["']([^"'#?]+)""", re.I)


def git(*args):
    return subprocess.run(
        ["git", "-C", str(ROOT), *args], capture_output=True, text=True, check=False
    ).stdout.strip()


def repository():
    slug = os.environ.get("GITHUB_REPOSITORY") or re.sub(
        r"^.*github\.com[:/]|\.git$", "", git("remote", "get-url", "origin")
    )
    owner, _, name = slug.partition("/")
    if not owner or not name:
        raise SystemExit(f"cannot tell the repository ({slug!r})")
    return owner, name


def finish(site):
    if not (site / "index.html").is_file():
        raise SystemExit(f"{site}: no index.html; build the site first")
    owner, name = repository()
    pages, missing = [], []
    for page in sorted(site.rglob("*.html")):
        relative = page.relative_to(site).as_posix()
        pages.append(relative)
        for target in LOCAL.findall(page.read_text(encoding="utf-8")):
            if re.match(r"^[a-z][a-z0-9+.-]*:|^//", target):
                continue
            if not (page.parent / unquote(target)).exists():
                missing.append(f"{relative}: {target}")
    if missing:
        raise SystemExit("the site links to files it does not have:\n  " + "\n  ".join(missing))
    (site / ".nojekyll").touch()
    revision = os.environ.get("GITHUB_SHA") or git("rev-parse", "HEAD")
    build = {"repository": f"{owner}/{name}", "revision": revision, "pages": pages}
    (site / "build.json").write_text(json.dumps(build, indent=2) + "\n")
    print(f"{site}: {len(pages)} page(s); {owner}/{name} @ {revision[:12]}")


if __name__ == "__main__":
    finish(Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "dist" / "site").resolve())
