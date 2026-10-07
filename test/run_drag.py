"""Drag to reorder in a real client through the fnative loader (vanilla + flib + fnative-std + this mod + a driver
with a mocked mouse). Screenshots: test/run/script-output/srq-drag-*.png. The game window closes itself."""
import json, os, shutil, subprocess, sys, time
from pathlib import Path

from factorio_paths import PATHS

HERE = Path(__file__).resolve().parent
MOD = HERE.parent
ROOT = MOD.parent
from factorio_paths import run_dir  # noqa: E402
RUN = run_dir(Path(__file__).resolve().parent / "run")
MODS = RUN / "srq-drag-mods"
# an fnative checkout, built (https://github.com/watdafawx/fnative): FNATIVE_DIR, else native/ beside this mod
FNATIVE = Path(os.environ.get("FNATIVE_DIR") or ROOT / "native")
if not (FNATIVE / "dist" / "factorio-native.exe").exists():
    sys.exit(f"needs a built fnative at {FNATIVE} (set FNATIVE_DIR)")
OUT = RUN / "script-output"
shutil.rmtree(MODS, ignore_errors=True)
MODS.mkdir(parents=True)
shutil.copytree(MOD, MODS / "smart-research-queue", ignore=shutil.ignore_patterns("test", ".git"))
shutil.copytree(FNATIVE / "mods" / "fnative-std", MODS / "fnative-std")
shutil.copytree(HERE / "srq-dragtest", MODS / "srq-dragtest")
(MODS / "srq-dragtest" / "info.json").write_text(json.dumps({"name": "srq-dragtest", "version": "0.0.1",
    "title": "srq drag test", "author": "mtopfox", "factorio_version": "2.0", "dependencies": ["base", "smart-research-queue"]}))
shutil.copy(max(PATHS["user_mods"].glob("flib_*.zip")), MODS)
names = ["base", "elevated-rails", "quality", "space-age", "flib", "fnative-std", "smart-research-queue", "srq-dragtest"]
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in names]}))
for f in OUT.glob("srq-drag-*"):
    f.unlink()
save = RUN / "srq-drag.zip"
save.unlink(missing_ok=True)
launch = [str(FNATIVE / "dist" / "factorio-native.exe"), "--config", str(RUN / "config.ini"), "--mod-directory", str(MODS)]
subprocess.run(launch + ["--create", str(save)], capture_output=True)
game = subprocess.Popen(launch + ["--load-game", str(save)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
start = time.time()
while time.time() - start < 240 and not (OUT / "srq-drag-done.txt").exists() and game.poll() is None:
    time.sleep(1)
time.sleep(2)
game.kill()
print((OUT / "srq-drag-result.txt").read_text() if (OUT / "srq-drag-result.txt").exists() else "no result")
print("screenshots:", sorted(f.name for f in OUT.glob("srq-drag-*.png")))
