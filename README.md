# shifty

Bespoke, local-only work-schedule -> Google Calendar importer. No LLM, no cloud
service sees your team's sheet: the CSV is parsed on your machine and only YOUR
parsed shifts leave the box (to Google Calendar, over TLS).

## Milestones (build in this order)

1. **[PARSER]** `src/core/parser_csv.zig` — parse the weekly-matrix CSV export
   into `[]Shift`. Handle: repeated header blocks, blank separator rows, ragged
   rows (missing trailing commas), UTF-8 BOM, overnight shifts (end < start),
   case-insensitive name match. Nothing hardcoded: your name lives in config.
2. **[CONFIG]** `src/core/config.zig` — load `config.json` (name, year, month,
   office address, tz, reminder offsets). Fail loudly on missing fields.
3. **[GCAL-AUTH]** `src/gcal/auth.zig` — OAuth2 loopback flow: localhost
   listener, open browser, catch redirect, exchange code, cache refresh token
   in `~/.config/shifty/token.json` mode 0600.
4. **[GCAL-EVENTS]** `src/gcal/event.zig` + `client.zig` — build event JSON
   (location, random colorId from palette 1-11, popup reminders: day before,
   day of, 1h before). Idempotency: deterministic event id via
   `calendar.events.import` or hash-based extended property so re-runs don't
   duplicate.
5. **[TUI]** `src/tui/render.zig` — hand-rolled VT100 layer: week grid, preview
   before write, confirm prompt.
6. **[GUI]** `src/gui/app.zig` — raylib. Cross-compile Windows binary from
   Arch: `zig build -Dtarget=x86_64-windows-gnu`.
7. **[XLSX]** `src/core/xlsx.zig` — real .xlsx via miniz + XML (optional; CSV
   export is the supported input for v1).

## Usage (target)

    shifty --config config.json --in "2026 Schedule (Oct).csv" --dry-run
    shifty --config config.json --in "2026 Schedule (Oct).csv" --write

## Sheet format assumptions (from real export)

- File is CSV (UTF-8, no BOM preferred; BOM is stripped).
- Repeating week blocks: header row (Sunday..Saturday), date-number row,
  then name rows. Each day = TWO columns: start, end. 24h times.
- Blank rows between blocks; row length varies (ragged). Never trust column
  count — index by `1 + 2*day`.

See `samples/` for a real (sanitized-format) export.
