# Smart Research Queue

A Factorio 2.0 mod: [Ultimate Research Queue](https://mods.factorio.com/mod/UltimateResearchQueue)'s research
queue with [Auto Research](https://mods.factorio.com/mod/auto-research) built in.

- **Queue** technologies; their prerequisites come along. The first entries are mirrored into the game's own
  research queue, and changes made there come back.
- **Reorder**: Ctrl + click a queued technology, then click where it goes. With the
  [FSE](https://github.com/watdafawx/fse) loader and its `fse-std` mod, you can drag entries instead.
  Moves keep the queue researchable: prerequisites stay in front, dependents behind.
- **Auto research** (side panel): when the queue runs dry, research continues from your **goals** first, then by
  strategy (balanced, fast, slow, cheap, expensive, random), using only the science packs you allow, or only the
  ones you actually made in the last hour.
- Goals and a blacklist, from the technology details or the side panel; defaults from per-player settings.
- Auto Research's remote interface, so other mods that drive it keep working.

Replaces Ultimate Research Queue and Auto Research (marked incompatible, so the game won't load them together).
Works with big modpacks: technology data is cached once per load.

## Remote planner

With the [FSE](https://github.com/watdafawx/fse) loader and its `fse-bridge` mod, auto research can be picked by a
program outside the game: `python remote/planner.py` (add `--watch` to restart it whenever you save it). While it
runs, auto research asks it instead of the strategy, and falls back to the strategy if it doesn't answer within 2 s.
Its own strategy: the cheapest step toward your first goal, else the technology that unlocks the most per science
spent; infinite technologies last. Edit `choose()` in it to plan your own way: the game keeps running.

Write one in any language: it long-polls fse's web API for the event `srq/need_pick` (`{force}`), reads
`remote.call("srq", "candidates", force)` and answers `remote.call("srq", "pick_remote", force, name)` (see FSE's
README, "Remote mods"). `test/run_remote.py` checks it end to end.

## Themes

The research queue window follows the theme each player picks in [FSE std](https://github.com/watdafawx/fse#themes)'s theme window (its button on the shortcut bar), when FSE std 0.6+ is installed: 12 themes, colours edited live with the FSE loader. Without FSE std it looks as before.

With FSE std 0.6.7+ the window is laid out as our other mods' windows: the gear by the close button holds its settings (Docked, show disabled technologies, show control hints, Theme..., Centre it), and Auto Research hangs as a drawer on its right edge (untick Docked to have it as a column inside the window). Clearing the queue and un-researching ask first.

![The research queue window in Vulcanus and Aquilo](images/themes.jpg)

## Install

Copy this folder into your mods folder (`%APPDATA%\Factorio\mods`) as `smart-research-queue`, or clone it there:

```
git clone https://github.com/watdafawx/smart-research-queue
```

Needs [flib](https://mods.factorio.com/mod/flib). `test\run.py` runs the headless tests (set `FACTORIO_EXE` if the
game isn't in a usual Steam library).

## License

MIT. Smart Research Queue is a fork of Ultimate Research Queue (Caleb Heuer) and Auto Research; both licenses are in
[LICENSE](LICENSE).
