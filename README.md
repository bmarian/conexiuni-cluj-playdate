# conexiuni-cluj-playdate

Playdate port of [conexiuni-cluj](https://bus.bmarian.online): Cluj-Napoca
transit routes, stops and timetables. The app downloads a snapshot of the
export over Wi-Fi and browses it offline.

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

The submodule (`library/playdate-luacats`) is only for editor autocomplete.
It is not needed to build or run.

## Build and run

```bash
pdc source ConexiuniCluj.pdx
PlaydateSimulator ConexiuniCluj.pdx
```

The app talks to the deployed API, so there is no local backend to start.

`pdc` has no watch mode. `tools/watch.ps1` polls `source/` and rebuilds on
change; keep the Simulator open and press Ctrl-R (Cmd-R on Mac) after each
rebuild to reload without relaunching:

```powershell
./tools/watch.ps1
```
