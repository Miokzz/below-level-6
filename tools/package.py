#!/usr/bin/env python3
"""Export the playable game and include its engine/library notices in a ZIP."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--platform", choices=["windows", "linux", "all"], default="all")
    args = parser.parse_args()
    targets = {"windows": ("Windows Desktop", "BelowLevel6", "BELOW LEVEL 6.exe"), "linux": ("Linux", "BelowLevel6-Linux", "BELOW LEVEL 6.x86_64")}
    for platform_name, (preset, folder, executable) in targets.items():
        if args.platform not in (platform_name, "all"):
            continue
        destination = ROOT / "dist" / folder
        destination.mkdir(parents=True, exist_ok=True)
        result = subprocess.run([args.godot, "--headless", "--path", str(ROOT), "--export-release", preset], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log = ROOT / "test-output" / f"export-{platform_name}.log"
        log.parent.mkdir(exist_ok=True)
        log.write_text(result.stdout)
        if result.returncode or re.search(r"SCRIPT ERROR:|ERROR:", result.stdout):
            print(result.stdout)
            raise RuntimeError(f"Export failed; see {log}")
        built = destination / executable
        if not built.is_file() or built.stat().st_size < 10000000:
            raise RuntimeError(f"Missing or truncated export: {built}")
        if platform_name == "linux": built.chmod(0o755)
        shutil.copytree(ROOT / "docs" / "licenses", destination / "licenses", dirs_exist_ok=True)
        (destination / "START HERE.txt").write_text(
            f"BELOW LEVEL 6 — version 0.2.0\n\nRun {executable}. No editor or project setup required.\n"
            "WASD move / Mouse look / E use / SHIFT run / CTRL or C crouch / F light / ESC pause.\n"
            "Use NEW GAME. Work orders and environmental documents explain progression.\n"
            "Progress autosaves at safe checkpoints. Settings are stored separately.\n"
            "English audio/text. No microphone recording.\n\n"
            "Original project: https://github.com/Miokzz/below-level-6\n"
            "Godot Engine 4.5.2; third-party licenses are included in licenses/.\n", encoding="utf-8")
        archive = ROOT / "dist" / f"{folder}-0.2.0.zip"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as bundle:
            for path in sorted(destination.rglob("*")):
                if path.is_file(): bundle.write(path, Path(folder) / path.relative_to(destination))
        checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
        archive.with_suffix(".zip.sha256").write_text(f"{checksum}  {archive.name}\n")
        print(f"Packaged {archive} ({archive.stat().st_size / 1048576:.1f} MiB)")


if __name__ == "__main__":
    main()
