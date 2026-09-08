#!/usr/bin/env python3
"""Download pinned official Godot binaries and verify SHA512 before extraction."""
import argparse
import hashlib
import os
from pathlib import Path
import platform
import shutil
import urllib.request
import zipfile

VERSION = "4.5.2-stable"
BASE = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}/"
ROOT = Path(__file__).resolve().parents[1]


def download_verified(name, checksums):
    destination = ROOT / ".tools" / name
    if not destination.exists():
        print(f"Downloading {name}", flush=True)
        temporary = destination.with_suffix(destination.suffix + ".download")
        with urllib.request.urlopen(BASE + name) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output)
        temporary.replace(destination)
    digest = hashlib.sha512()
    with destination.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != checksums[name]:
        raise RuntimeError(f"SHA512 mismatch: {destination}; remove this archive and retry")
    print(f"SHA512 verified: {name}")
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--templates", action="store_true", help="Also install Windows and Linux x64 export templates (~1.35 GB download)")
    options = parser.parse_args()
    system = platform.system()
    if system not in ("Linux", "Windows") or platform.machine().lower() not in ("x86_64", "amd64"):
        parser.error("This helper supports Linux/Windows x64; install Godot 4.5.2 manually on other platforms.")
    (ROOT / ".tools").mkdir(exist_ok=True)
    sums = urllib.request.urlopen(BASE + "SHA512-SUMS.txt").read().decode()
    checksums = {line.split()[-1].lstrip("*"): line.split()[0] for line in sums.splitlines() if line.strip()}
    suffix = "linux.x86_64.zip" if system == "Linux" else "win64.exe.zip"
    archive = download_verified(f"Godot_v{VERSION}_{suffix}", checksums)
    target = ROOT / ".tools" / "godot"
    target.mkdir(exist_ok=True)
    with zipfile.ZipFile(archive) as bundle:
        for entry in bundle.infolist():
            name = Path(entry.filename).name
            if name.startswith("Godot_") and not entry.is_dir():
                executable = target / name
                executable.write_bytes(bundle.read(entry))
                executable.chmod(0o755)
    if options.templates:
        archive = download_verified(f"Godot_v{VERSION}_export_templates.tpz", checksums)
        target = ROOT / ".tools" / "templates"
        target.mkdir(exist_ok=True)
        names = ["version.txt", "windows_debug_x86_64.exe", "windows_release_x86_64.exe", "windows_debug_x86_64_console.exe", "windows_release_x86_64_console.exe", "linux_debug.x86_64", "linux_release.x86_64"]
        with zipfile.ZipFile(archive) as bundle:
            for name in names:
                (target / name).write_bytes(bundle.read("templates/" + name))
                if name.startswith("linux_"):
                    (target / name).chmod(0o755)
    print(f"Godot 4.5.2 ready in {ROOT / '.tools'}")


if __name__ == "__main__":
    main()
