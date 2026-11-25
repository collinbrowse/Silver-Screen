#!/usr/bin/env python3
"""Prints the UDID of this checkout's own iPhone simulator, creating it on first use.

Parallel Claude sessions each work in a worktree under `.claude/worktrees/<name>`. When
every one of them picks "the first booted iPhone", they all install onto, test on, and
reset the same device. Each checkout gets its own simulator instead:

  SilverScreen <worktree>       a linked worktree (`.claude/worktrees/<worktree>`)
  SilverScreen SilverScreen     the main checkout (its folder name)
  ... + " Duo"                  with --duo, an iPhone Duo for fold/unfold checks

That is the `<Repo> <worktree>[ Duo]` naming `~/.claude/scripts/devtrim.mjs` uses to shut
down a simulator whose worktree has gone idle and to delete it once the worktree is gone.

  python3 scripts/worktree-simulator.py           # print the UDID
  python3 scripts/worktree-simulator.py --boot    # ... booted and ready
  python3 scripts/worktree-simulator.py --name    # print the name only (creates nothing)

A new simulator is the highest-numbered plain "iPhone N" on the newest iOS runtime that
has one. Exits 1 with a message on stderr when no iOS runtime is installed.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def checkout_names(root: str = ROOT) -> tuple[str, str]:
    """('SilverScreen', 'my-feature') for .../SilverScreen/.claude/worktrees/my-feature."""
    marker = "/.claude/worktrees/"
    if marker in root:
        repo, rest = root.split(marker, 1)
        return os.path.basename(repo), rest.split("/")[0]
    name = os.path.basename(root.rstrip("/"))
    return name, name


def simulator_name(root: str = ROOT, duo: bool = False) -> str:
    repo, checkout = checkout_names(root)
    return f"{repo} {checkout}" + (" Duo" if duo else "")


def simctl_json(*args: str) -> dict:
    out = subprocess.check_output(["xcrun", "simctl", "list", *args, "-j"], text=True, stderr=subprocess.DEVNULL)
    return json.loads(out)


def version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", version or ""))


def find_device(name: str) -> str | None:
    """The UDID of an available simulator with exactly this name (newest runtime wins)."""
    runtimes = {r["identifier"]: r.get("version", "") for r in simctl_json("runtimes").get("runtimes", [])}
    matches = [
        (version_key(runtimes.get(runtime, "")), device["udid"])
        for runtime, devices in (simctl_json("devices", "available").get("devices") or {}).items()
        for device in devices or []
        if device.get("name") == name and device.get("isAvailable") is not False
    ]
    return max(matches)[1] if matches else None


def plain_iphone_rank(type_name: str) -> int | None:
    match = re.fullmatch(r"iPhone (\d+)", type_name)
    return int(match.group(1)) if match else None


def pick_type(duo: bool) -> tuple[str, str]:
    """(device type id, runtime id) for a new simulator."""
    runtimes = [
        r for r in simctl_json("runtimes").get("runtimes", [])
        if r.get("platform", "iOS") == "iOS" and "iOS" in r.get("identifier", "") and r.get("isAvailable") is not False
    ]
    runtimes.sort(key=lambda r: version_key(r.get("version", "")), reverse=True)
    for runtime in runtimes:
        types = [t for t in runtime.get("supportedDeviceTypes", []) if t.get("productFamily") == "iPhone"]
        if duo:
            chosen = next((t for t in types if "Duo" in t.get("name", "")), None)
        else:
            plain = [t for t in types if plain_iphone_rank(t.get("name", "")) is not None]
            chosen = max(plain, key=lambda t: plain_iphone_rank(t["name"]), default=None)
        if chosen:
            return chosen["identifier"], runtime["identifier"]
    for runtime in runtimes if not duo else []:  # no plain "iPhone N": any iPhone but a Duo
        for t in runtime.get("supportedDeviceTypes", []):
            if t.get("productFamily") == "iPhone" and "Duo" not in t.get("name", ""):
                return t["identifier"], runtime["identifier"]
    raise LookupError("no iOS simulator runtime with an " + ("iPhone Duo" if duo else "iPhone") + " is installed")


def ensure(name: str, duo: bool) -> str:
    # Two hooks or sessions in the same checkout must not each create a copy.
    lock_path = os.path.join(tempfile.gettempdir(), "worktree-simulator-" + re.sub(r"[^A-Za-z0-9._-]", "_", name) + ".lock")
    with open(lock_path, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        udid = find_device(name)
        if udid:
            return udid
        type_id, runtime_id = pick_type(duo)
        return subprocess.check_output(["xcrun", "simctl", "create", name, type_id, runtime_id], text=True).strip()


def boot(udid: str) -> None:
    subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
    subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture_output=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--duo", action="store_true", help="this checkout's iPhone Duo instead of its iPhone")
    parser.add_argument("--boot", action="store_true", help="boot it and wait until it is ready")
    parser.add_argument("--name", action="store_true", help="print the simulator's name and exit")
    args = parser.parse_args()

    name = simulator_name(duo=args.duo)
    if args.name:
        print(name)
        return 0
    try:
        udid = ensure(name, args.duo)
    except (OSError, subprocess.CalledProcessError, LookupError, ValueError) as error:
        print(f"worktree-simulator: cannot find or create {name!r}: {error}", file=sys.stderr)
        return 1
    if args.boot:
        boot(udid)
    print(udid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
