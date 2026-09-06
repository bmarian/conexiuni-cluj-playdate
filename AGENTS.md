# conexiuni-cluj-playdate Agent Guide

Playdate port of [conexiuni-cluj](../conexiuni-cluj): Cluj-Napoca public
transit, on Panic's [Playdate](https://play.date) handheld.

## Networking

Most Playdate games assume no connectivity. This one doesn't: the device
makes live HTTPS calls to the real conexiuni-cluj API over Wi-Fi via
`playdate.network.http`, the same way the web frontend does. No offline
bundle, no build-time data fetch.

- `net.http.new(host, 443, true, reason)` against `bus.bmarian.online`.
  `net.http.new` returns falsy if the user denies network access — always
  check it.
- The Simulator routes network calls through the host machine directly, so
  it's a reasonable stand-in for a Wi-Fi-connected device.
- Every screen needs a loading/error/retry state — Wi-Fi may be absent, slow,
  or the API unreachable. No fallback to cached/bundled data yet; caching
  last-good responses to `playdate.datastore` is a possible later addition.
- Prefer existing endpoints (`/api/routes`, `/api/stops`, `/api/stop_info`,
  `/api/timetable`) over adding new ones. Only add a Playdate-specific
  endpoint if a screen needs several round trips an existing endpoint can't
  cover in one call.

## Goal

Recreate parts of the web app's interface on a 400x240 1-bit screen with
d-pad/crank/button input, fetched live:

1. Browse routes (short name, long name, color-as-pattern).
2. Route detail: stops in order, CTP timetable (weekdays/Saturday/Sunday,
   explicit times or frequency windows).
3. Browse/search stops, see routes serving a stop and its timetable
   (`stop_info` in the web app).
4. Later: polled vehicle positions (no SSE equivalent in the HTTP API, so
   this means polling `/api/vehicles` on a timer).
5. Later: a vector route-shape map (line segments, no tiles/basemap).

Out of scope for v1: OTP trip planning, news, sharing, PWA install, themes.

## Relationship To conexiuni-cluj

Sibling repo at `../conexiuni-cluj`. Read its
[AGENTS.md](../conexiuni-cluj/AGENTS.md) and
[docs/API.md](../conexiuni-cluj/docs/API.md) before touching the API — reuse
its field names and sentinel conventions.

Backend changes belong in `conexiuni-cluj`, not here. This repo is
Lua/Playdate-only.

## Possible New Endpoint: `GET /api/playdate/summary`

Not implemented, not required to keep building screens against existing
endpoints. Only add it (in `conexiuni-cluj/backend/handlers/`, registered in
`register.go`) if a screen needs data that `/api/stop_info` or similar
can't provide in one call, or an existing response is too large/awkward for
the device's Lua JSON decoder. If built, keep it a plain live GET — no
build-time bundling, no snapshot semantics.

## Repo Map

```text
conexiuni-cluj-playdate/
├── AGENTS.md
├── README.md
├── .gitignore
├── .luarc.json            lua-language-server config
├── library/
│   └── playdate-luacats/  git submodule: Lua type stubs for the SDK
├── source/
│   ├── pdxinfo            name, bundleID, version
│   └── main.lua           entry point, update loop, live API calls
└── tools/
    └── watch.ps1          rebuilds on source change (no watch mode in pdc)
```

## Build And Run

Requires `PLAYDATE_SDK_PATH` set and `$PLAYDATE_SDK_PATH/bin` on `PATH`.

```bash
pdc source ConexiuniCluj.pdx
PlaydateSimulator ConexiuniCluj.pdx
```

`ConexiuniCluj.pdx` is a build artifact (gitignored); rebuild from `source/`
rather than editing it directly.

`pdc` has no watch mode. `tools/watch.ps1` polls `source/` and rebuilds on
change. The Simulator itself has a Restart shortcut (Ctrl-R / Cmd-R) that
reloads the currently open `.pdx` from disk — no relaunch needed after a
rebuild.

## Editor Setup

`playdate.*` is native (C), so there's no Lua source for a language server to
infer types from. `library/playdate-luacats` (git submodule) supplies
LuaCATS stubs; `.luarc.json` points `workspace.library` at it and sets
`runtime.version` to `Lua 5.4`. Editors that read `.luarc.json` (Zed, VS Code
+ sumneko.lua, Neovim) pick this up automatically — requires
`git submodule update --init` first.

## Current Status

Phase 0: network smoke test in `source/main.lua` — checks Wi-Fi status, does
a live `GET /api/routes`, shows status on screen. No real UI yet.

Next:

1. Route list: `GET /api/routes`.
2. Route detail: `GET /api/trips?route_id=` + `GET /api/timetable?route_short_name=`.
3. Stop search + detail: `GET /api/stops` + `GET /api/stop_info?stop_id=`.
4. Later: polled vehicles, route-shape map, on-device caching.

## Testing And Verification

No automated test suite. After changes:

- `pdc source ConexiuniCluj.pdx` must exit `0`.
- Launch `PlaydateSimulator`, confirm no crash, confirm network calls reach
  `bus.bmarian.online` (allow the permission prompt on first run), confirm
  the changed screen behaves as expected.
- If a backend endpoint changes, keep this file and
  `conexiuni-cluj/docs/API.md` in sync.
