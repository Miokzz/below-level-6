#!/usr/bin/env python3
"""Run meaningful engine regressions and fail on errors even if Godot exits zero."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SUITES = [
    "environment/check_facility.gd",
    "environment/check_elevator.gd",
    "ai/verify_controller_ai.gd",
    "ai/verify_facility_pursuit.gd",
    "narrative/verify_scares.gd",
    "tools/test_progression_state.gd",
    "tools/test_ui.gd",
    "tests/test_session.gd",
    "tests/test_session_recovery.gd",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--native", action="store_true", help="Also perform actual E/button playthrough in a native window; requires a display")
    args = parser.parse_args()
    version = subprocess.check_output([args.godot, "--version"], text=True).strip()
    if not version.startswith("4.5.2."):
        parser.error(f"Expected Godot 4.5.2; got {version}")
    output = ROOT / "test-output" / "verification"
    output.mkdir(parents=True, exist_ok=True)
    (ROOT / "test-output" / ".gdignore").touch()
    tasks = [("audio-assets", [sys.executable, "tools/test_audio_assets.py"])]
    tasks.append(("import", [args.godot, "--headless", "--editor", "--import", "--quit"]))
    for script in SUITES:
        tasks.append((Path(script).stem, [args.godot, "--headless", "--fixed-fps", "60", "--script", script]))
    # Audio completion must follow the actual audio clock, not accelerated frames.
    tasks.append(("audio", [args.godot, "--headless", "--script", "tools/test_audio.gd"]))
    tasks.append(("main", [args.godot, "--headless", "--quit-after", "10"]))
    if args.native:
        tasks.append(("playthrough", [args.godot, "--fixed-fps", "60", "--script", "tests/test_playthrough.gd"]))
    failed = []
    for name, command in tasks:
        print(f"Running {name}...", flush=True)
        result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
        (output / f"{name}.log").write_text(result.stdout)
        if result.returncode or re.search(r"SCRIPT ERROR:|ERROR:|FAIL(?:ED|URE)?\b|instances leaked|resources still in use", result.stdout):
            failed.append(name)
            print(result.stdout)
        else:
            print(f"PASS {name}")
    print(f"Verification: {len(tasks) - len(failed)}/{len(tasks)} suites passed. Logs: {output}")
    return bool(failed)


if __name__ == "__main__":
    sys.exit(main())
