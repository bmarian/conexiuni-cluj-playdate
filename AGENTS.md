# conexiuni-cluj-playdate Agent Guide

Playdate port of [conexiuni-cluj](../conexiuni-cluj): Cluj-Napoca public
transit, on Panic's [Playdate](https://play.date) handheld.

## Networking

The app is fully offline. It never shows live vehicle positions and never
makes a network call while browsing. Wi-Fi exists for exactly one thing: an
explicit **sync** that downloads a full data snapshot to a file on the
device. Every screen after that reads local data only — no per-screen
fetches, no loading spinners tied to the network.

**The export is ~1MB, and that size dictates the whole design.** Measured
against the live endpoint: 991 KB, 107 routes, 793 stops.

- `lib/api.lua`'s `Api.download` streams the response body straight to a
  file, a chunk per read callback. It never builds the body as a Lua string
  and never decodes it.
- **Do not put the snapshot in `playdate.datastore`.** `datastore.write`
  serializes the table back to JSON, and doing that to a megabyte of routes
  blocked the update loop long enough for the device to report *"loop
  stalled for more than 10s"*. The original version decoded the response and
  wrote it to the datastore, which is decode + encode + write of ~1MB inside
  one frame. The datastore is still right for the small stuff — favourites,
  and the `synced_at` timestamp — which is what it's used for now.
- `Store.load()` does the one remaining decode, `json.decodeFile` on
  `snapshot.json`. That measured **22 ms in the Simulator**, so parsing was
  never the problem; re-encoding was.
- A download lands on `snapshot.download` and is only renamed into place on
  success, so a failed sync leaves the previous snapshot intact instead of
  truncating it.
- Timing, measured through the Simulator: ~5.2s total, of which the first
  **~4s is DNS, TLS and the server building the export** — the first read
  callback lands at ~3965 ms and all 991 KB arrives in the last ~1.2s. That
  is why `SyncScene` says "Connecting" until the first byte and only then
  switches to "Downloading" with a progress bar; a bar sitting at zero for
  four seconds reads as a hang.
- The Simulator routes network calls through the host machine directly, so
  it's a reasonable stand-in for a Wi-Fi-connected device — but it is on a
  much faster link, so treat its timings as a floor.
- Main Menu shows `synced_at` and prompts to re-sync if it's over a day old
  (see Screens). Sync itself needs connecting/downloading/reading/error
  states; nothing else does.
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

Route Detail is not decorative animation — the line pans across a flat row
of named stops, and one bus icon is drawn per currently-scheduled trip at
its approximate position: today's `timetable` departure time for the active
direction, plus that stop's entry in the current hour's
`hourly_offset_seconds` array, gives an elapsed-time interpolation between
the two stops a trip should currently be between. A route with frequent
headway can show several buses at once; outside service hours it shows none.
This is still fully offline — it's schedule math against the device's clock,
not live vehicle data.

The **"in" direction is drawn right-to-left** — the same geometry mirrored
about the screen. Flipping direction otherwise redraws a line that looks
identical with different names on it; mirroring makes the change obvious at
a glance. Left/Right step toward the stop you're pointing at, which is the
opposite index once mirrored, and the position bar runs the same way as the
line rather than contradicting it. The bus icon is flipped to match: the
pixelarticons bus faces right (its roof stops short of the body on that
side, a raked windscreen), so on the mirrored direction it is drawn with
`Graphics.kImageFlippedX` or it drives backwards.

**An empty line is usually correct, not a bug.** Route 57 on a Sunday runs a
~35 minute headway over a ~28 minute route, so for roughly a fifth of the
day nothing is in transit; 36 of the 107 routes have no Sunday service at
all and 33 none on Saturday. The export itself is clean — offset arrays
always match their stop counts, all 24 hours are present, offsets are
monotonic — so when the line is empty, say why: `noBusesText()` in
`RouteScene` shows "next departure 11:05", "last departure was 19:35", or
"no service today" rather than a bare "no buses running right now", which
reads like a broken screen.

Only **three stops are on screen at a time**. Each owns a 132px slot and
draws its name horizontally, wrapped over up to two lines, inside 124px of
it — so a label can never be wider than its slot and two labels can never
collide, whatever the synced name turns out to be. 124px is not arbitrary:
`Memorandumului`, the longest single word in the Cluj stop list, measures
123px in `Theme.FONT_BIG`. An earlier version fitted a dozen stops on at
once by rendering names diagonally at 11px; it was unreadable, and it
overlapped. Fewer stops and a bigger face is the deliberate trade. Each stop
also shows "Nm" above the line: minutes of schedule distance from one
reference active trip (the first one in `activeTrips()` — with several buses
running there's no single correct reference, first is just the simplest
choice).

### The look is one file

`lib/theme.lua` owns every visual decision: four fonts with fixed roles, the
header/content/footer split every scene uses, and the widgets scenes are
assembled from (`Theme.row`, `Theme.badge`, `Theme.header`, `Theme.footer`,
the scrollbars, `Theme.emptyState`). **Scenes do not invent their own chrome
or their own type scale.** If a screen needs something new it goes in
`Theme` so every screen gets it — that's what stops the app drifting back
into five screens that each look like a different app.

Fonts, by role, and nothing else draws text:

| Constant | Font | `getHeight()` | digit ink | Used for |
|---|---|---|---|---|
| `FONT_TITLE` | Roobert 11 Bold | 22 | rows 2–16 (15px) | headers, badges, hour column |
| `FONT_BODY` | system font | 20 | rows 1–14 (14px) | list rows, timetable cells |
| `FONT_BIG` | Asheville Sans 14 Bold | 20 | rows 1–14 (14px) | stop names on the route line |
| `FONT_SMALL` | Noble Sans 8×9 | 9 | rows 1–7 (7px) | footer hints, chips, accessories |

**`getHeight()` is the line box, not the glyphs, and the difference is large
enough to wreck a layout.** Roobert reports 22px for an 11px-looking face.
Sizing a badge as `getHeight() + 6` gave a 28px box — exactly the height of
the whole header bar, and taller than a 21px timetable row, which it visibly
overlapped. The ink also sits about 2px *above* the box's middle, so
centering on `getHeight()` alone draws every label slightly high.

`Theme` therefore carries an `INK` table of measured `{top, height}` per
font: `Theme.textCentered` centers the ink rather than the box, and
`Theme.badgeHeight` sizes from it (23px for `FONT_TITLE`). The numbers came
from rendering digits offscreen and scanning rows for black pixels with
`image:sample()` — if a font is swapped, re-measure rather than guess.

Where a badge still won't fit — the timetable's 21px hour rows — use a
different marker instead of shrinking it: the current hour gets a caret in
the left margin, which costs no vertical room and leaves the black fill to
mean "selected".

### Ordering

`Store.load()` sorts routes and stops once, right after decoding, so every
screen and every count agrees rather than each list sorting its own way.
Both use `Text.sortKey`, which strips diacritics, lowercases, and zero-pads
every run of digits to six places. That turns natural ordering back into a
plain string compare: `25` before `25N` before `26` before `100`, and the M-prefixed
metropolitan routes land after the numbered ones because digits sort before
letters in ASCII. Verified against the live data — the list starts
`1 3 4 5 5N 6 7 8 8L 9 10 12 14 18` and ends `M51 M51U M52 M61 M71 M81`.
Sorting is decorate-sort-undecorate (`Store.sortInPlace`); building the key
inside the comparator would redo that work on every one of the ~7000
comparisons 793 stops need.

Icons come from [pixelarticons](https://github.com/halfmage/pixelarticons)
(MIT). The SVGs used are vendored in `tools/pixelarticons/` and rasterized
to 1-bit PNGs by `tools/icons.py` (pure Python, no dependencies — the pack
is axis-aligned rectangles on a 24×24 grid, so a scanline fill reproduces it
exactly). Re-run `python tools/icons.py` after changing that file's `ICONS`
table; `lib/icons.lua` loads the results. A curve-based pack like Lucide was
the wrong choice here: downscaled vectors turn to mush on a 1-bit screen,
and these are already pixel art.

Text rendering notes:

- The default system font has no glyphs for Romanian diacritics (ă/â/î/ș/ț
  and cedilla variants ş/ţ). `lib/text.lua`'s `Text.clean()` transliterates
  to ASCII before any synced string (route/stop names, headsigns) reaches a
  drawText* call — apply it at every new call site that renders synced text.
- `gfx.drawTextInRect(text, x, y, w, h, ...)` produced no visible output at
  all in testing (v3.1.1 Simulator) despite matching the documented
  signature — `gfx.drawTextAligned` and `gfx.drawText` did not have this
  problem. That's why `Text.wrapToWidth()` is hand-rolled rather than
  leaning on the SDK's wrapping.
- `drawTextAligned`/`drawText` are unclipped — nothing stops adjacent labels
  from overlapping. `Text.truncateToWidth(s, maxWidth, font)` and
  `Text.wrapToWidth(s, maxWidth, maxLines, font)` measure **in the font the
  text will actually be drawn in** and cut to fit; measuring in one font and
  drawing in another is exactly how labels end up colliding. Every widget in
  `Theme` already does this, so anything built out of `Theme` is safe by
  construction.
- Use `playdate.ui.gridview` (`CoreLibs/ui`) for long scrollable lists — see
  `scenes/ListScene.lua`. `Noble.Menu` is a gridview subclass but draws every
  item at once, which is right for the four-item Main Menu and wrong for a
  hundred routes.

Controls: A drills in, B goes back one screen, the crank scrolls (lists) or
free-pans (the route line). On the route line left/right steps one stop and
up/down flips direction — the line is horizontal, so left/right moving along
it is the only mapping that reads right. Menu button stays reserved for the
system menu, which is where "favorite route"/"favorite stop" live: the four
buttons are all spoken for, and per-screen extras are what that menu is for.

### Stop Detail is a departure board

`StopScene` answers one question — *which bus is next from here* — and is
built accordingly:

- **One row per route AND direction.** A route passing both ways is two
  different answers, so it gets two rows with different headsigns.
- **Times are at this stop**, not at the route's origin: the trip's departure
  plus this stop's cumulative offset. Standing halfway along a route, the
  origin time is the wrong number.
- **Trips that terminate here are dropped** (`index == #direction.stops`).
  Without that, a terminus shows a board full of buses arriving to go out of
  service — real times you cannot board. Disp. Bucium, the busiest stop with
  31 route/direction pairs, listed three of them before this filter.
- **Only what's still to come today**, sorted soonest first. A route whose
  last bus has gone has nothing to say on a screen this size.
- Relative under the hour ("6m", or "now" inside a minute), absolute beyond
  it ("14:38"): three minutes is a countdown, three hours is an appointment.
- Each row shows **as many times as fit**, decided per row — a long route
  number and a long headsign eat into the same width, and the destination
  wins (`MIN_LABEL_W`).
- A is a drill-in to that route **in the direction shown** (`RouteScene`
  takes an optional `dirKey`).

The scan is done in `scene:init` rather than kept as a permanent stop→routes
index: all 107 routes × 2 directions for the busiest stop measured **2 ms**
in the Simulator, and the snapshot is already the big thing in memory.

### Times past midnight

CTP publishes a service day that runs past midnight the GTFS way: the 01:05
night bus is listed as **`25:05`**, so its departures keep sorting after the
23:00 one instead of jumping to the top of the timetable. Sort and do
arithmetic on the raw value; draw `Text.clockLabel(s)`, which wraps the hour
modulo 24. `RouteScene`'s active-trip math also rolls a negative elapsed
forward by a day, or a night bus never registers as running once the clock
passes midnight. `Store.offsetsForHour` already handles it for free — hour
25 is distance 0 from hour 1 in its wrap-around search.

**Upstream data warning:** four routes carry hours far beyond a night
service — route 25 has departures up to `46:45`, route 43 jumps straight
from `12:00` to `35:00`. Those are not past-midnight times (46 % 24 = 22)
and are almost certainly a GTFS parsing bug in `conexiuni-cluj`, not
something this app can repair. They render as whatever `% 24` gives, which
makes them look plausible but wrong; only 25N and 54N are genuine night
services. Worth fixing at the source.

### Empty days

143 of the route/day/direction combinations in the export have **no
departures at all** — most routes don't run on Sundays. `TimetableScene`
forces focus onto the day tabs whenever the grid is empty (`setDay`,
`stepHour`, `stepDeparture`), because with nothing in the grid to move
between, the d-pad does nothing and B becomes the only way off the screen.
Any new focus-based screen needs the same care: **there must always be
something the d-pad can move.**

The timetable needs two things from one d-pad — switch day, and pick a
departure — so **focus moves between the tab strip and the grid** instead of
adding a modifier. Left/Right switches day on the tabs and steps departure
to departure in the grid (rolling over between hours); Up from the top row
returns to the tabs, Down from the tabs enters the grid. The active tab
grows a ring while it has focus, and the footer hints change with it. The
grid opens on the next departure after the current time, not at the top.

All data below comes from local storage after sync — see New Endpoint.

| Scene | Shows |
|---|---|
| `SyncScene` | the only screen that touches the network; status, error, A to retry |
| `MainMenuScene` | `synced_at` banner (warns if >24h old); favorite route/stop rows, showing the favorite's name once set; All Routes / All Stops with counts |
| `ListScene` | both lists — routes (number badge + long name), stops (pin + name); remembers its selected row across a drill-down |
| `RouteScene` | three-stop window of the line, schedule-approximated buses, direction toggle, position readout |
| `TimetableScene` | day tabs + hour-grouped grid; **every departure is individually selectable**, and A on one opens `TripScene` |
| `TripScene` | one departure, stop by stop: what time "the 13:37" reaches every stop on the way |
| `StopScene` | departure board: which bus leaves from here next, soonest first |

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

[Noble Engine](https://noblerobot.github.io/NobleEngine) (MIT) runs the show:
scene lifecycle, the update loop, input routing, and transitions. It's
vendored at `source/libraries/noble/` (commit `93ffd6e`) rather than
submoduled, pruned of the docs and the Noble Robot logo so `pdc` only sees
things it can compile. Upstream expects exactly that path, so don't move it.

- Every screen is a `NobleScene` subclass in `source/scenes/`, with
  `init`/`start`/`update`/`drawBackground`/`exit` and a scene-level
  `inputHandler` table. Scenes draw their whole screen in `drawBackground`
  and own no sprites.
- `source/lib/nav.lua` — the back stack Noble doesn't have. `Nav.push` /
  `Nav.pop` / `Nav.reset` record the scene class plus the properties it was
  entered with, so B can rebuild the previous screen. It also refuses to
  move while a transition is running: Noble silently ignores a transition
  requested mid-transition, and updating the stack anyway would leave B
  going somewhere the user never was.
- `Nav.start` passes `alwaysRedraw = true` in Noble's config **explicitly**.
  Noble only calls `Graphics.sprite.setAlwaysRedraw` for keys present in the
  config table you hand it, and the SDK default is off — with scenes that
  draw everything in `drawBackground` and own no sprites, nothing ever marks
  the screen dirty and the display freezes on the first frame after a
  transition. This cost an afternoon; leave it in.
- `source/lib/theme.lua` — every visual decision (see Screens above).
- `source/lib/icons.lua` — loads the generated pixelarticons PNGs.
- `source/lib/api.lua` — wraps the `net.http.new`/`get`/callback dance into
  `Api.get(...)`. Used only by `SyncScene`; nothing else touches the network.
- `source/lib/store.lua` — `sync()` (calls `Api.get`, decodes, writes the
  dataset + `synced_at` via `playdate.datastore`), `load()` (reads it back),
  favorite get/set helpers, and `offsetsForHour()` (picks the right
  `hourly_offset_seconds` array, falling back to the nearest hour present).

`Noble.Text.FONT_MEDIUM` is `nil` — upstream points it at a font that was
never finished and isn't in the repo. `Theme` defines its own font constants;
don't reach for Noble's.

## Repo Map

```text
conexiuni-cluj-playdate/
├── AGENTS.md
├── README.md
├── .gitignore
├── .luarc.json               lua-language-server config
├── library/
│   └── playdate-luacats/     git submodule: Lua type stubs for the SDK
├── source/
│   ├── pdxinfo               name, bundleID, version
│   ├── main.lua              imports + Nav.start; Noble owns the loop
│   ├── libraries/noble/      vendored Noble Engine (MIT)
│   ├── fonts/                Roobert 11 Bold, Asheville Sans 14 Bold (SDK)
│   ├── images/icons/         generated by tools/icons.py -- don't hand-edit
│   ├── lib/
│   │   ├── theme.lua         fonts, chrome, widgets: the whole visual system
│   │   ├── nav.lua           back stack over Noble's one-way transitions
│   │   ├── icons.lua         icon image loader/cache
│   │   ├── text.lua          diacritics, width-aware truncation and wrapping
│   │   ├── api.lua           net.http request/callback wrapper (sync only)
│   │   └── store.lua         sync/load/favorites, hourly offset lookup
│   └── scenes/
│       ├── SyncScene.lua     the only screen that touches the network
│       ├── MainMenuScene.lua synced-at banner, favorites, the two lists
│       ├── ListScene.lua     both scrollable lists (routes and stops)
│       ├── RouteScene.lua    three-stop window of the line + buses
│       ├── TimetableScene.lua day tabs + selectable departure grid
│       ├── TripScene.lua     one departure, stop by stop
│       ├── StopScene.lua     departure board for one stop
└── tools/
    ├── watch.ps1             rebuilds on source change (no watch mode in pdc)
    ├── screenshots.ps1       renders every screen to screenshots/
    ├── screenshots/main.lua  the harness screenshots.ps1 builds
    ├── icons.py              pixelarticons SVG -> 1-bit PNG
    └── pixelarticons/        the vendored SVGs it reads (MIT)
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

- `GET /api/playdate/export` implemented in `conexiuni-cluj` (`backend/handlers/playdate_export.go`,
  `backend/models/playdate_export.go`). No dedicated cache table — it fans
  out over the already-cached `GetRoutes`/`GetTrips`/`GetStopTimes`/`GetTimetable`/`GetStops`,
  same tradeoff `stop_info` makes. **A running backend needs a restart to
  pick this endpoint up.**
- Rebuilt on Noble Engine, with `lib/theme.lua` as the single visual system
  and pixelarticons throughout. Every scene renders correctly with real
  Romanian names — verified from actual renders via `tools/screenshots.ps1`,
  not by eye over the code.
- All six screens are built, Stop Detail included.
- Favorites can be set from the system menu on Route/Stop Detail, and the
  Main Menu shows the favorite's name once one is set.

The sync path has been run end to end against the live endpoint through the
Simulator: 991 KB downloaded, decoded, sorted and browsed, with the route
list, timetable and trip times checked from real renders.

Next:

1. Run it on hardware and confirm the sync timings hold there — the
   Simulator is on a much faster link and CPU.
2. Later: on-device caching refinements, a bundled fallback snapshot for
   first launch before any sync.

## Testing And Verification

No unit tests. After changes:

- `pdc source ConexiuniCluj.pdx` must exit `0`.
- **If you touched anything that draws, run `tools/screenshots.ps1` and
  look at the PNGs.** It builds a copy of `source/` with
  `tools/screenshots/main.lua` as the entry point, boots the real engine
  against fake data with the worst-case Romanian stop names, walks the whole
  nav stack and writes a screenshot per screen to `screenshots/` (gitignored).
  A runtime error is rendered into `ERROR.png` rather than lost to the
  Simulator console, which a script can't read.

  This exists because UI here was once shipped unlooked-at and the labels
  overlapped. Reading the drawing code is not verification; the screenshots
  are. Add a step to the harness's `steps` list when you add a screen.
- Launch `PlaydateSimulator` by hand for anything input- or network-shaped.
  Only `SyncScene` touches the network (allow the permission prompt on first
  run) — every other screen works with Wi-Fi off once a sync has happened.
- `python tools/icons.py` after changing its `ICONS` table; commit the
  regenerated PNGs.
- If a backend endpoint changes, keep this file and
  `conexiuni-cluj/docs/API.md` in sync.
