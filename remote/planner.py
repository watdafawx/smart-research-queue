"""Smart Research Queue's remote planner: picks auto research from outside the game (fse remote mods).

    python remote/planner.py           (--watch: saving this file restarts it, the game keeps going)

While it runs, auto research asks it instead of the strategy (and falls back to the strategy if it doesn't answer
within 2 s). Its own strategy, "unlocks": the cheapest step toward your first goal, else the technology that unlocks
the most per science spent (recipes count full, other effects half); infinite technologies last.

Needs the fse loader + fse-bridge and fse's Python SDK (fse_remote.py in fse's py folder: FSE_HOME, or found below).
"""
import os
import sys
from pathlib import Path


def _sdk():
    here = Path(__file__).resolve()
    places = [Path(os.environ["FSE_HOME"]) / "py"] if os.environ.get("FSE_HOME") else []
    places += [p / "fse" / "py" for p in here.parents]  # (this repo's layout: fse/ beside mods/)
    for drive in "CDEFGH":
        for lib in ("SteamLibrary", "Program Files (x86)/Steam", "Program Files/Steam"):
            places.append(Path(f"{drive}:/{lib}/steamapps/common/Factorio/fse/py"))
    for p in places:
        if (p / "fse_remote.py").exists():
            sys.path.insert(0, str(p))
            return
    sys.exit("fse_remote.py not found: set FSE_HOME to the fse folder (the one with web-token.txt)")


_sdk()
from fse_remote import Remote  # noqa: E402

r = Remote("srq-planner")


def cost(c):
    packs = sum(p["amount"] for p in c.get("packs") or []) or 1
    return max(c.get("count", 1), 1) * max(c.get("ticks", 1), 1) * packs


def value(c):
    return c.get("unlocks", 0) + 0.5 * (c.get("effects", 0) - c.get("unlocks", 0))


def choose(info):
    cands = list(info.get("candidates") or [])
    if not cands:
        return None, "nothing to research"
    finite = [c for c in cands if not c.get("infinite")]
    cands = finite or cands
    goals = list(info.get("goals") or [])
    toward = [c for c in cands if c.get("goal")]
    if toward:
        first = min(goals.index(c["goal"]) if c["goal"] in goals else 99 for c in toward)
        pool = [c for c in toward if (goals.index(c["goal"]) if c["goal"] in goals else 99) == first]
        best = min(pool, key=cost)
        return best, f"toward {best['goal']}"
    if info.get("goals_only"):
        return None, "goals only, none left"
    best = max(cands, key=lambda c: (value(c) / cost(c), -cost(c)))
    return best, f"{best.get('unlocks', 0)} recipes, cost {cost(best):.0f}"


@r.on("srq/need_pick")
def need_pick(ev):
    force = ev["data"]["force"]
    best, why = choose(r.call("srq", "candidates", force) or {})
    r.call("srq", "pick_remote", force, best and best["name"])
    print(f"{force}: {best['name'] if best else '-'} ({why})", flush=True)


if __name__ == "__main__":
    r.run(watch="--watch" in sys.argv)
