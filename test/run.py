"""Run the headless checks: vanilla + Space Age + flib + this mod + srq-test. Prints srq-test.txt."""
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MOD = HERE.parent
ROOT = MOD.parent
sys.path.insert(0, str(ROOT))
from factorio_paths import PATHS  # noqa: E402

from factorio_paths import run_dir  # noqa: E402
RUN = run_dir(Path(__file__).resolve().parent / "run")
MODS = RUN / "srq-mods"
FLIB = PATHS["user_mods"].glob("flib_*.zip")

if MODS.exists():
    shutil.rmtree(MODS)
MODS.mkdir(parents=True)
shutil.copytree(MOD, MODS / "smart-research-queue", ignore=shutil.ignore_patterns("test", ".git"))
shutil.copytree(HERE / "srq-test", MODS / "srq-test")
shutil.copy(max(FLIB), MODS)
names = ["base", "elevated-rails", "quality", "space-age", "flib", "smart-research-queue", "srq-test"]
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in names]
                                                 + [{"name": "srq-guitest", "enabled": False}]}))

save = RUN / "srq-test.zip"
result = RUN / "script-output" / "srq-test.txt"
save.unlink(missing_ok=True)
result.unlink(missing_ok=True)
common = [str(PATHS["factorio_exe"]), "--config", str(RUN / "config.ini"), "--mod-directory", str(MODS)]
for args in (["--create", str(save)], ["--benchmark", str(save), "--benchmark-ticks", "400", "--disable-audio"]):
    p = subprocess.run(common + args, capture_output=True, text=True, encoding="utf-8", errors="replace")
    errors = [l for l in p.stdout.splitlines() if "Error" in l or "error" in l.lower() and "0 errors" not in l]
    if p.returncode or errors:
        print("\n".join(p.stdout.splitlines()[-40:]))
        sys.exit(1)
print(result.read_text() if result.exists() else "no result file")
