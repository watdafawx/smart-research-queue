"""The remote planner end to end (fse remote mods): a headless server through fse's launcher (dist, or FSE_DIR) with
fse-bridge, this mod and test/srq-remote, ticking in real time; remote/planner.py as a separate process.

Checks: auto research without a planner; a game event sent out (subscribe); the planner's pick in the queue; the
planner hot reloaded by saving its file (a syntax error refused first); a planner that doesn't answer (the strategy
picks after 2 s); no planner at all (the strategy picks at once). Exit code 1 = a check failed."""
import json
import os
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
MOD = HERE.parent
ROOT = MOD.parent
FSE = ROOT.parent / "fse"
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(FSE / "py"))
from factorio_paths import PATHS, run_dir, stage_mods, user_mod, BASE_MODS  # noqa: E402
from fse_remote import Remote  # noqa: E402

DIST = Path(os.environ.get("FSE_DIR") or FSE / "dist")
RUN = run_dir(HERE / "run")
MODS = RUN / "remote-mods"
F = "player"
results = []


def check(name, ok, detail=""):
    results.append(ok)
    print(("PASS " if ok else "FAIL ") + name + (f" :: {detail}" if detail else ""), flush=True)


def wait(fn, timeout, step=0.1):
    end = time.time() + timeout
    while time.time() < end:
        v = fn()
        if v:
            return v
        time.sleep(step)
    return fn()


# ---- the game -------------------------------------------------------------------------------------------------
stage_mods(MODS, {"smart-research-queue": MOD, "srq-remote": HERE / "srq-remote",
                  "fse-bridge": FSE / "mods" / "fse-bridge", "flib": user_mod("flib")})
env = dict(os.environ, FSE_WEB_TOKEN="srq-remote-test", FSE_OVERLAY="0", FSE_MENU_BUTTON="0")
env.pop("FSE_OFF", None)
common = [str(DIST / "fse-launcher.exe"), "--config", str(RUN / "config.ini"), "--mod-directory", str(MODS)]
save = RUN / "srq-remote.zip"
save.unlink(missing_ok=True)
subprocess.run(common + ["--create", str(save)], capture_output=True, env=env)
settings = RUN / "server-settings.json"
cfg = json.loads((PATHS["game_data"] / "server-settings.example.json").read_text(encoding="utf-8"))
cfg.update({"name": "srq-remote", "visibility": {"public": False, "lan": False}, "require_user_verification": False,
            "autosave_interval": 0, "auto_pause": False})
settings.write_text(json.dumps(cfg))
game = subprocess.Popen(common + ["--start-server", str(save), "--server-settings", str(settings),
                                  "--port", "34297", "--bind", "127.0.0.1"],
                        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

r = Remote("srq-test", token="srq-remote-test")
procs = [game]


def call(*a):
    return r.call(*a)


def auto_pick():
    return next((n["name"] for n in call("srq", "queue", F) if n["auto"]), None)


def clients():
    return call("fse-remote", "clients") or []


lines = []


def planner(path, *args):
    p = subprocess.Popen([sys.executable, "-u", str(path), *args], env=dict(env, FSE_WEB_TOKEN="srq-remote-test"),
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8")
    procs.append(p)

    def read():
        for line in p.stdout:
            lines.append(line.rstrip())
            print("  planner>", line.rstrip(), flush=True)
    threading.Thread(target=read, daemon=True).start()
    return p


def kill_tree(p):
    subprocess.run(["taskkill", "/T", "/F", "/PID", str(p.pid)], capture_output=True)


def line_after(n, prefix, timeout=10):
    """the first planner line from index n on that starts with prefix"""
    return wait(lambda: next((s for s in lines[n:] if s.startswith(prefix)), None), timeout)


def finish():
    return call("srq-remote-test", "finish", F)


try:
    def up():
        try:
            return call("$game", "status")["tick"] > 0
        except Exception:
            return False
    if not wait(up, 180, 0.5):
        print((RUN / "factorio-current.log").read_text(errors="replace")[-3000:])
        raise SystemExit("FAIL the game didn't come up")

    call("srq-remote-test", "prepare", F)

    # 1. no planner: the strategy picks
    local = wait(auto_pick, 10)
    check("without a planner, the strategy picks", bool(local), local)

    # 2. a game event out
    _, since = r.poll(wait_ms=0)
    call("$game", "subscribe", "on_research_finished")
    done = finish()
    events, _ = wait(lambda: (lambda e: e if e[0] else None)(r.poll(since, 2000)), 5) or ([], None)
    names = [(e["name"], (e["data"].get("research") or {}).get("name")) for e in events]
    check("subscribed game event sent out", ("game/on_research_finished", done) in names, names)

    # 3. the planner (a copy, to edit it later), watched
    work = RUN / "planner"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    src = (MOD / "remote" / "planner.py").read_text(encoding="utf-8")
    (work / "planner.py").write_text(src, encoding="utf-8")
    planner(work / "planner.py", "--watch")
    check("planner connects", bool(wait(lambda: "srq-planner" in clients(), 15)), clients())
    n = len(lines)
    finish()
    said = line_after(n, f"{F}: ")
    picked = said and said.split(": ", 1)[1].split(" ", 1)[0]
    got = wait(lambda: auto_pick() == picked and picked, 5)
    check("the planner's pick is queued", bool(picked) and got == picked, f"said {said!r}, queue {auto_pick()}")
    check("its candidates come from srq.candidates", len(call("srq", "candidates", F)["candidates"]) > 0)

    # 4. hot reload: a syntax error is refused, a good edit restarts it, the game never stops
    tick0 = call("$game", "status")["tick"]
    n = len(lines)
    (work / "planner.py").write_text(src.replace("def cost(c):", "def cost(c)"), encoding="utf-8")
    check("a syntax error is refused", bool(line_after(n, "[fse-remote", 5) and
                                              any("syntax error" in s for s in lines[n:])), lines[n:])
    n = len(lines)
    (work / "planner.py").write_text(src.replace('print(f"{force}: ', 'print(f"v2 {force}: '), encoding="utf-8")
    check("a saved edit restarts the planner", bool(wait(lambda: any("restarting" in s for s in lines[n:]), 5)))
    check("it connects again", bool(wait(lambda: any("connected as" in s for s in lines[n:]), 15)))
    n = len(lines)
    finish()
    said = line_after(n, f"v2 {F}: ")
    picked = said and said.split(": ", 1)[1].split(" ", 1)[0]
    check("the new code picks", bool(picked) and wait(lambda: auto_pick() == picked, 5), said)
    check("the game kept ticking", call("$game", "status")["tick"] > tick0)

    # 5. a planner that doesn't answer: the strategy after 2 s
    kill_tree(procs.pop())
    stop = threading.Event()
    deaf = Remote("srq-planner", token="srq-remote-test")
    deaf.on("nothing/")(lambda ev: None)

    def deaf_loop():
        since = None
        while not stop.is_set():
            _, since = deaf.poll(since, 500)
    threading.Thread(target=deaf_loop, daemon=True).start()
    wait(lambda: "srq-planner" in clients(), 5)
    t0 = time.time()
    finish()
    got = wait(auto_pick, 8, 0.05)
    took = time.time() - t0
    check("an unanswering planner: the strategy picks after ~2 s", bool(got) and 1.5 <= took <= 6, f"{got} after {took:.1f} s")

    # 6. the planner gone: no waiting
    stop.set()
    wait(lambda: "srq-planner" not in clients(), 8)
    t0 = time.time()
    finish()
    got = wait(auto_pick, 5, 0.05)
    took = time.time() - t0
    check("no planner: the strategy picks at once", bool(got) and took < 1.2, f"{got} after {took:.1f} s")
finally:
    for p in procs:
        kill_tree(p)

log = (RUN / "factorio-current.log").read_text(errors="replace")
errors = [line for line in log.splitlines() if " Error " in line]
check("no errors in the game log", not errors, errors[:3])
print("ALL PASS" if all(results) else f"{results.count(False)} FAILED")
sys.exit(0 if all(results) else 1)
