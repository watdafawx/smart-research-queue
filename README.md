# Smart Research Queue

A Factorio 2.0 mod: [Ultimate Research Queue](https://mods.factorio.com/mod/UltimateResearchQueue)'s research
queue with [Auto Research](https://mods.factorio.com/mod/auto-research) built in.

- **Queue** technologies; their prerequisites come along. The first entries are mirrored into the game's own
  research queue, and changes made there come back.
- **Reorder**: Ctrl + click a queued technology, then click where it goes. With the
  [fnative](https://github.com/watdafawx/fnative) loader and its `fnative-std` mod, you can drag entries instead.
  Moves keep the queue researchable: prerequisites stay in front, dependents behind.
- **Auto research** (side panel): when the queue runs dry, research continues from your **goals** first, then by
  strategy (balanced, fast, slow, cheap, expensive, random), using only the science packs you allow, or only the
  ones you actually made in the last hour.
- Goals and a blacklist, from the technology details or the side panel; defaults from per-player settings.
- Auto Research's remote interface, so other mods that drive it keep working.

Replaces Ultimate Research Queue and Auto Research (marked incompatible, so the game won't load them together).
Works with big modpacks: technology data is cached once per load.

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
