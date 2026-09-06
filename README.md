# conexiuni-cluj-playdate

Playdate port of [conexiuni-cluj](https://bus.bmarian.online): Cluj-Napoca
transit routes, stops, and timetables, fetched live over Wi-Fi from the real
API. See [AGENTS.md](AGENTS.md) for architecture and status.

## Prerequisites

- [Playdate SDK](https://play.date/dev/)
- `PLAYDATE_SDK_PATH` env var pointing at the SDK install
- `%PLAYDATE_SDK_PATH%/bin` on `PATH` (for `pdc` / `PlaydateSimulator`)

## Setup

```bash
git clone https://github.com/bmarian/conexiuni-cluj-playdate
cd conexiuni-cluj-playdate
git submodule update --init
```

The submodule (`library/playdate-luacats`) is only for editor autocomplete;
not needed to build or run.

## Build and run

```bash
pdc source ConexiuniCluj.pdx
PlaydateSimulator ConexiuniCluj.pdx
```

No local backend needed — the app talks to the deployed API directly.

`pdc` has no watch mode. `tools/watch.ps1` polls `source/` and rebuilds on
change; keep the Simulator open and press Ctrl-R (Cmd-R on Mac) after each
rebuild to reload without relaunching:

```powershell
./tools/watch.ps1
```

## Screenshots

Anything that draws should be checked from a render, not from the code.
`tools/screenshots.ps1` builds a copy of `source/` with a harness as its
entry point, boots the app against fake data, walks every screen and writes
a PNG of each to `screenshots/`:

```powershell
./tools/screenshots.ps1
```

## Third-party

- [Noble Engine](https://noblerobot.github.io/NobleEngine) (MIT), vendored
  at `source/libraries/noble/` — scenes, transitions, input.
- [pixelarticons](https://github.com/halfmage/pixelarticons) (MIT) — the
  icon set. Sources in `tools/pixelarticons/`, rasterized to 1-bit PNGs by
  `python tools/icons.py`.
- Fonts in `source/fonts/` are Playdate SDK fonts (Roobert, Asheville).

## Editor autocomplete

`playdate.*` is a native API with no Lua source, so a language server can't
infer its types on its own. `.luarc.json` points `lua-language-server` at
the vendored [playdate-luacats](https://github.com/notpeter/playdate-luacats)
stubs. Editors that read `.luarc.json` (Zed, VS Code + sumneko.lua, Neovim)
pick this up automatically once the submodule is initialized.

## Deploying to a device

Not tried yet. Build the `.pdx`, then install via `pdutil` or by copying it
to the mounted Playdate over USB — see Panic's [device docs](https://play.date/dev/).
