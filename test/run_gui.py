"""Open the queue window in a real game client (vanilla + Space Age) and screenshot it. --themed: with fse-std
(from fse/mods beside mods/): its theme, the settings behind the gear, Auto Research as a drawer, inside again.
Screenshots land in test/run/script-output/srq-gui-*.png (results in srq-gui.txt). The game window closes itself."""
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
MOD = HERE.parent
ROOT = MOD.parent
sys.path.insert(0, str(ROOT))
from factorio_paths import PATHS  # noqa: E402

from factorio_paths import run_dir, watch_game  # noqa: E402
RUN = run_dir(Path(__file__).resolve().parent / "run")
MODS = RUN / "srq-mods"
OUT = RUN / "script-output"

MODS.mkdir(parents=True, exist_ok=True)
THEMED = "--themed" in sys.argv
for name in ("smart-research-queue", "srq-guitest", "fse-std"):
    if (MODS / name).exists():
        shutil.rmtree(MODS / name)
shutil.copytree(MOD, MODS / "smart-research-queue", ignore=shutil.ignore_patterns("test", ".git"))
shutil.copytree(HERE / "srq-guitest", MODS / "srq-guitest")
if THEMED:
    shutil.copytree(ROOT.parent / "fse" / "mods" / "fse-std", MODS / "fse-std")
flib = max(PATHS["user_mods"].glob("flib_*.zip"))
for old in MODS.glob("flib_*.zip"):  # (a game update can need a newer flib: keep only the user's newest)
    if old.name != flib.name:
        old.unlink()
if not (MODS / flib.name).exists():
    shutil.copy(flib, MODS)
shutil.rmtree(MODS / "zzzz-test-skip-intro", ignore_errors=True)  # (remade for this game version when it starts)
names = ["base", "elevated-rails", "quality", "space-age", "flib", "smart-research-queue", "srq-guitest"] + (
    ["fse-std"] if THEMED else [])
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in names]
                                                 + [{"name": "srq-test", "enabled": False}]}))

for f in OUT.glob("srq-gui*"):
    f.unlink()
save = RUN / "srq-gui.zip"
save.unlink(missing_ok=True)
common = [str(PATHS["factorio_exe"]), "--config", str(RUN / "config.ini"), "--mod-directory", str(MODS)]
subprocess.run(common + ["--create", str(save)], capture_output=True, check=True)

# Steam restarts a directly started game (dropping our arguments) unless it looks Steam-launched
env = dict(os.environ, SteamAppId="427520", SteamGameId="427520")
game = watch_game(common + ["--load-game", str(save.resolve())], env=env)
start = time.time()
while time.time() - start < 150 and not (OUT / "srq-gui-done.txt").exists() and game.poll() is None:
    time.sleep(1)
time.sleep(3)
game.kill()
log = (RUN / "factorio-current.log").read_text(encoding="utf-8", errors="replace").splitlines()
errors = [l for l in log if "Error" in l or "non-recoverable" in l]
if (OUT / "srq-gui.txt").exists():
    print((OUT / "srq-gui.txt").read_text())
print("screenshots:", sorted(f.name for f in OUT.glob("srq-gui-*.png")))
print("errors:", "\n".join(errors[-10:]) or "none")
