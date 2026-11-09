# CleanStream

Part of [Campground](https://github.com/AHouseOfBards/Campground-Jellyfin), a set of Jellyfin plugins.

A Jellyfin 12.x plugin that makes every app start fast, play the original whenever the connection allows, and adjust
quality smoothly when it doesn't. It's built never to make a playback that would have worked worse.

**Status: probe release.** It only records how each app requests and plays video. It never changes playback.
- The plan: [docs/CleanStream-design.md](docs/CleanStream-design.md)
- The detailed algorithms: [docs/CleanStream-technical.md](docs/CleanStream-technical.md)

CleanStream was called BetterPlay up to 0.2. Updating from BetterPlay keeps your settings and logs.

## Install
1. Jellyfin Dashboard → Plugins → Repositories → **+**
2. Name `CleanStream`, URL `https://raw.githubusercontent.com/AHouseOfBards/CleanStream/main/manifest.json`
   (the old BetterPlay URL still works).
3. Catalog → CleanStream → Install, then restart Jellyfin.

Requires Jellyfin 12.0 or newer (12.x).

## Dashboard
Open Dashboard → **CleanStream** (in the server menu, or Plugins → CleanStream). It shows:
- **Status:** version, mode, whether each hook is working on your server, key server settings, and warnings (such as
  a missing Known proxies entry).
- **Settings:** mode, what to record, and log retention.
- **Recent playback:** per playback, the health read from the player's request timing (Healthy / At risk / Stalled),
  the buffer ahead, late requests, seeks and data sent.
- **Recent events:** filter by kind; click one to see everything recorded.
- **Log files:** download a day's log.

## Modes
- **Off**: does nothing.
- **Watch only** (default): records playback data and never changes playback.

## For admins
- `GET /CleanStream/Status`: version, mode, hooks, server settings snapshot.
- `GET /CleanStream/Probe?minutes=30&kind=playbackinfo|start|progress|stop|delivery|image`: recent events.
- `GET /CleanStream/Sessions?minutes=180`: one line per playback, with its health.

All of these need an admin API key. The `/BetterPlay/...` routes still work until after 0.3. Logs are written to
`plugins/configurations/CleanStream/probe/*.jsonl`.

## Build
`.\build.ps1 -Version 0.3.0.0 -Changelog "..." [-Publish]` (needs the .NET 10 SDK).
