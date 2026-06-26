#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def git(*args: str) -> bytes:
    return subprocess.check_output(["git", *args], cwd=ROOT)


def main() -> None:
    digest = hashlib.sha256()
    try:
        digest.update(git("rev-parse", "HEAD"))
        digest.update(git("diff", "--binary", "HEAD", "--", "."))
        untracked = git("ls-files", "--others", "--exclude-standard", "-z").split(b"\0")
    except (subprocess.CalledProcessError, FileNotFoundError):
        digest.update(b"non-git-worktree")
        untracked = []

    for raw_path in sorted(path for path in untracked if path):
        relative = raw_path.decode("utf-8", errors="surrogateescape")
        digest.update(b"\0path\0")
        digest.update(raw_path)
        path = ROOT / relative
        if path.is_file():
            digest.update(b"\0content\0")
            digest.update(path.read_bytes())
    print(digest.hexdigest())


if __name__ == "__main__":
    main()
