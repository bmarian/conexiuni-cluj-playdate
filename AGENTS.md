# conexiuni-cluj-playdate Agent Guide

Playdate port of [conexiuni-cluj](../conexiuni-cluj): Cluj-Napoca public
transit, on Panic's [Playdate](https://play.date) handheld.

## Networking

The app is fully offline. It never shows live vehicle positions and never
makes a network call while browsing. Wi-Fi exists for exactly one thing: an
explicit **sync** that downloads a full data snapshot and stores it on the
device with `playdate.datastore`. Every screen after that reads local data
only — no per-screen fetches, no loading spinners tied to the network.

- Sync calls `GET /api/playdate/export` (see below) once via
  `playdate.network.http`, `json.decode`s the response, and
  `playdate.datastore.write`s the decoded table plus a `synced_at`
  timestamp. Subsequent boots `playdate.datastore.read` that table — fast,
  no JSON parsing, no network.
- The Simulator routes network calls through the host machine directly, so
  it's a reasonable stand-in for a Wi-Fi-connected device.
- Main Menu shows `synced_at` and prompts to re-sync if it's over a day old
  (see Screens). Sync itself needs a loading/error/retry state; nothing else
  does.
- No fallback data ships in the `.pdx` — first launch has nothing to browse
  until the first sync completes. Worth a bundled fallback snapshot later if
  that first-run gap is annoying in practice.

## Goal

Recreate parts of the web app's interface on a 400x240 1-bit screen with
d-pad/crank/button input, browsed entirely offline after a sync, and make it
feel alive — animated and a little cute, not just a data browser:

1. Browse routes (short name, long name, color-as-pattern) and stops.
2. Favorite a route and a stop for one-tap access from the Main Menu.
3. Route detail: an animated bus driving along a flat schematic line of
   stops, direction-aware (drives right for one direction, left for the
   other), plus the CTP timetable (weekdays/Saturday/Sunday, explicit times
   or frequency windows).
4. Stop detail: routes serving a stop and each one's timetable.

Out of scope for v1: live vehicles, OTP trip planning, news, sharing, PWA
install, themes, geographic maps (the route view is a schematic line, not
lat/lon).

## Relationship To conexiuni-cluj

Sibling repo at `../conexiuni-cluj`. Read its
[AGENTS.md](../conexiuni-cluj/AGENTS.md) and
[docs/API.md](../conexiuni-cluj/docs/API.md) before touching the API — reuse
its field names and sentinel conventions.

Backend changes belong in `conexiuni-cluj`, not here. This repo is
Lua/Playdate-only.

## Screens

```
Main Menu: synced-N-ago banner, ★ favorite route, ★ favorite stop,
           all routes, all stops
   ├──▶ Route List ──▶ Route Detail: crank-scrollable stop line, buses
   │                                 approximated from the schedule, timetable
   └──▶ Stop List  ──▶ Stop Detail: routes serving it, each w/ timetable
```

Route Detail is not decorative animation — the crank pans a flat line of
named stops (all of them, not a windowed subset), and one bus icon is drawn
per currently-scheduled trip at its approximate position: today's
`timetable` departure time for the active direction, plus each stop's
cumulative `offset_seconds`, gives an elapsed-time interpolation between the
two stops a trip should currently be between. A route with frequent headway
can show several buses at once; outside service hours it shows none. This
is still fully offline — it's schedule math against the device's clock, not
live vehicle data.

Stop names render diagonally below the line (an offscreen image per unique
name, drawn with `image:drawRotated`) instead of horizontally, so stops sit
close together (currently `SPACING = 56`) without every name needing to be
truncated to fit its own slice. Each stop also shows "Nm" above the line:
minutes of schedule distance from one reference active trip (the first one
in `activeTrips()` — with several buses running there's no single correct
reference, first is just the simplest choice). `LABEL_ANGLE`'s sign
(clockwise-vs-counterclockwise cascade direction) was picked by reasoning
about the rotation math, not by looking at a render — flip its sign if the
labels cascade the wrong way on screen.

Text rendering notes:

- The default system font has no glyphs for Romanian diacritics (ă/â/î/ș/ț
  and cedilla variants ş/ţ). `lib/text.lua`'s `Text.clean()` transliterates
  to ASCII before any synced string (route/stop names, headsigns) reaches a
  drawText* call — apply it at every new call site that renders synced text.
- `gfx.drawTextInRect(text, x, y, w, h, ...)` produced no visible output at
  all in testing (v3.1.1 Simulator) despite matching the documented
  signature — `gfx.drawTextAligned` and `gfx.drawText` did not have this
  problem. Prefer those two; if a bounded/truncating box is genuinely
  needed, verify `drawTextInRect` renders anything before relying on it, or
  use `Text.truncate(s, maxLen)` plus a plain draw instead.
- Use `playdate.ui.gridview` (`CoreLibs/ui`) for scrollable lists rather
  than hand-rolled scroll/selection math — see `screens/listscreen.lua`. It
  handles clipping and animated scroll for free.
- `drawTextAligned`/`drawText` are unclipped — nothing stops adjacent
  labels from overlapping (found this the hard way: stop names at fixed
  `SPACING` intervals along Route Detail's line rendered as unreadable
  overlapping soup once long names exceeded the gap between stops).
  `Text.truncateToWidth(s, maxWidth)` measures with `gfx.getTextSize` and
  truncates to fit — use it for any label sharing horizontal space with
  neighbors, not just where a bounding box would have caught it.

Controls: d-pad up/down moves the selection, crank fast-scrolls long lists
(proportional, not per-notch), A drills in, B goes back one screen. Menu
button stays reserved for the system menu.

All data below comes from local storage after sync — see New Endpoint.

| Screen | Shows |
|---|---|
| Main Menu | `synced_at`, recommend re-sync if >24h old; favorite route/stop shortcuts (empty state if none set yet); All Routes / All Stops |
| Route List | all routes, short/long name, color |
| Route Detail | crank-scrollable stop line, schedule-approximated buses, CTP timetable (hour-grouped grid, day tabs, like the web app's `RouteView`); button/menu-item to set as favorite |
| Stop List | all stop names, sorted client-side |
| Stop Detail | routes serving the stop, each with its timetable; set as favorite |

Favorites are on-device only (`playdate.datastore`, a separate small file
from the synced snapshot) — a route/stop ID plus enough to render the Main
Menu shortcut without touching the full dataset.

## Endpoint: `GET /api/playdate/export`

Implemented in `conexiuni-cluj` (`backend/handlers/playdate_export.go`,
`backend/models/playdate_export.go`), registered in `register.go`, and
documented in `conexiuni-cluj/docs/API.md`. One call, fetched only during
sync, containing everything every screen needs:

```json
{
  "generated_at": "2026-09-06T12:00:00Z",
  "routes": [
    {
      "route_id": 14,
      "route_short_name": "25",
      "route_long_name": "Str. Bucium - Str. Unirii",
      "route_color": "#462EE0",
      "directions": {
        "out": {
          "headsign": "Snagov Nord",
          "stops": [{ "stop_id": 1, "stop_name": "..." }],
          "hourly_offset_seconds": { "0": [0, 130], "8": [0, 210], "...": "keys 0-23, one array per hour, an hour can be missing" }
        },
        "in": { "headsign": "Disp. Clabucet", "stops": [{ "stop_id": 2, "stop_name": "..." }], "hourly_offset_seconds": { "0": [0, 125] } }
      },
      "timetable": { "...": "full Timetable object, same shape as GET /api/timetable" }
    }
  ],
  "stops": [
    { "stop_id": 155, "stop_name": "Unirii", "stop_lat": 46.76896, "stop_lon": 23.62968 }
  ]
}
```

Notes:

- `routes[].directions` comes from `/api/stop_times?route_short_name=`
  (group by `trip_id`, sort by `stop_sequence`; `_0` suffix is `out`, `_1`
  is `in`) joined with `stop_headsign` for names — no separate stop lookup
  needed server-side either.
- `hourly_offset_seconds[hour][i]` is `stops[i]`'s cumulative offset for
  that hour's estimate (running sum of the per-segment `offset_arrival_time`
  values `ref_hour=` would give). **Broken out by hour, not a single
  number** — segment travel-time profiles vary by time of day, and this
  snapshot is synced once and browsed for up to a day, so a single
  "as of sync time" value would be visibly wrong by evening. When
  approximating a bus's position (see Screens above), use the array for the
  device's *current* hour (`playdate.getTime().hour`), not whatever hour it
  was at sync time. An hour key can be absent — fall back to the nearest
  present hour, or `"0"`, rather than assuming all 24 exist. This makes
  export generation ~24x the per-route `GET /api/stop_times` work; expect
  this endpoint to take noticeably longer than the rest of the API to
  respond.
- `timetable` per route is the existing `GetTimetable` result, unchanged.
  Skip routes with no departures at all, same as `/api/stop_info` already
  does.
- `stops` is the plain stop list trimmed to what the device needs: drop
  `stop_desc`/`stop_code`/`location_type` (always empty/`0` per
  `docs/API.md`). Needed for Stop List and for building a stop→routes index
  on-device for Stop Detail (scan `routes[].directions[*].stops` once after
  sync; no need for the server to send that mapping separately).
- Drop entirely: live vehicles, shapes, news, `plan_routes` — nothing here
  needs them.
- This will be the largest response in the API (all 105 routes' stop lists
  and timetables at once, likely several hundred KB). Measure it once built;
  consider whether the Playdate HTTP client can request/handle a compressed
  response, or whether splitting into `/api/playdate/export/routes` +
  `/api/playdate/export/stops` is worth it, only if the single fetch proves
  slow or memory-heavy on-device.
- Cache it like the other static endpoints (same TTL family as
  `TRANZY_DEFAULT_DAILY_QUOTA`-driven data) since it's built from data that's
  already cached. Keep this file and `conexiuni-cluj/docs/API.md` in sync
  once built.

## App Architecture

- `source/lib/api.lua` — wraps the `net.http.new`/`get`/callback dance from
  the current smoke test into `api.get(path, onSuccess, onError)`. Used only
  by the sync screen; no other screen touches the network.
- `source/lib/store.lua` — `sync()` (calls `api.get`, decodes, writes the
  dataset + `synced_at` via `playdate.datastore`), `load()` (reads it back),
  and favorite get/set helpers on their own datastore key.
- A simple screen-stack: each screen is a plain table with `enter`,
  `update`, `draw`, and button handlers; a nav stack drives B-to-go-back.
  No need for a framework — `CoreLibs/object.lua` classes are enough if
  screens want shared behavior (e.g. a scrollable-list base).
- `CoreLibs/animation` / `CoreLibs/animator` for the Route Detail bus
  (position + easing) rather than hand-rolled frame counters.

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
│   ├── main.lua           entry point, update loop, screen stack
│   ├── lib/
│   │   ├── api.lua        net.http request/callback wrapper (sync only)
│   │   ├── store.lua      sync/load/favorites via playdate.datastore
│   │   └── text.lua       strips Romanian diacritics before any drawText*
│   └── screens/
│       ├── sync.lua       the only screen that touches the network
│       ├── mainmenu.lua   synced-at banner, favorites, All Routes/All Stops
│       ├── listscreen.lua generic scrollable list (Route List, Stop List)
│       ├── routedetail.lua stop line + animated bus + timetable
│       └── comingsoon.lua placeholder (Stop Detail not built yet)
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

First offline-shaped build exists:

- `GET /api/playdate/export` implemented in `conexiuni-cluj` (`backend/handlers/playdate_export.go`,
  `backend/models/playdate_export.go`). No dedicated cache table — it fans
  out over the already-cached `GetRoutes`/`GetTrips`/`GetStopTimes`/`GetTimetable`/`GetStops`,
  same tradeoff `stop_info` makes. **A running backend needs a restart to
  pick this endpoint up.**
- Screen stack, `lib/api.lua`, `lib/store.lua`, and all screens except Stop
  Detail: Sync, Main Menu, a generic List screen (Route List / Stop List),
  Route Detail (scrolling stop line + animated bus + direction toggle +
  timetable). Stop Detail is `ComingSoonScreen` for now — selecting a stop
  (from the list or a favorite) shows a placeholder instead of crashing.
- Favoriting a stop has no UI yet (only reads an existing favorite); setting
  one from Route/Stop Detail isn't wired up.

Not yet verified in the Simulator — compiles clean (`pdc`) but hasn't been
run end to end against a live sync.

Next:

1. Run it, fix what breaks (field-name mismatches between the new Go struct
   and the Lua consumer are the likeliest bug class here).
2. Stop Detail, mirroring Route Detail's structure (list of routes serving
   the stop, each with its timetable).
3. Wire up "set as favorite" from Route Detail and (once built) Stop Detail.
4. Later: on-device caching refinements, a bundled fallback snapshot for
   first launch before any sync, `CoreLibs/animation` for the bus if the
   hand-rolled frame counter feels stiff.

## Testing And Verification

No automated test suite. After changes:

- `pdc source ConexiuniCluj.pdx` must exit `0`.
- Launch `PlaydateSimulator`, confirm no crash, confirm the changed screen
  behaves as expected. Only the sync screen touches the network (allow the
  permission prompt on first run) — every other screen should work with
  Wi-Fi off once a sync has happened at least once.
- If a backend endpoint changes, keep this file and
  `conexiuni-cluj/docs/API.md` in sync.
