# JOURNAL — shifty devlog

One entry per work session. Kimi writes what it did/thought; you append your
build results, errors, opinions. Future-you reads this to remember why
decisions were made.

---

## 001 — 2026-10-11 — Step 1 done on paper: the CSV parser

**Built:**
- `src/core/parser_csv.zig` — full implementation (was a stub). State machine:
  scan lines → detect week header (Sunday..Saturday at odd cols) → next row is
  date numbers → name rows, case-insensitive match → 2 cols per day.
- `src/core/types.zig` — `Shift` got a `weekdayOf()` for pretty printing.
- `src/main.zig` — real CLI: `--name --year --month --in`, prints a shift table.
- Unit tests in parser_csv.zig: overnight math, parseTime forms, synthetic
  two-week mini-sheet.

**Bug caught before first compile:** sheet has single-digit-hour times
("7:00:00"). Original parseTime assumed fixed-width "HH:" — would have died on
Moe's Oct 17 shift. Fixed by splitting at the first colon. Lesson: never
assume fixed-width fields in Excel exports. Test `parseTime("7:00")` guards it.

**Rule set (from the real Oct 2026 export, verified by hand):**
- Day *d* = columns 1+2d (start) and 2+2d (end). Rows are ragged — missing
  trailing commas are normal, index defensively.
- Repeated header blocks per week; blank separator rows; optional UTF-8 BOM.
- Overnight rule: end <= start → end_date = next day (handles 23:00→7:00
  AND the weird 23:00→3:00 short shifts).
- Half-filled day (start but no end) = hard error, never guess.

**Moe, Oct 2026, expected parser output — 15 shifts** (verify against this):
Oct 6,7,8 @ 15:00-23:00 / Oct 13,14,15 @ 15:00-23:00 / Oct 17 @ 07:00-15:00 /
Oct 19 @ 15:00-23:00 / Oct 22,23,24 @ 15:00-23:00 / Oct 25 @ 23:00-07:00(+1) /
Oct 27 @ 23:00-07:00(+1) / Oct 29,30 @ 23:00-07:00(+1).

**NOT yet compiled.** No Zig in the build sandbox — first compile is on your
machine. Code targets **Zig 0.14.x** API (`ArrayList.init/.append/.deinit`,
`readFileAlloc`). If your zig is 0.15+, ArrayList went unmanaged — paste the
error, I'll migrate.

**Your homework (build + test runner role):**
1. `sudo pacman -S zig` — then `zig version`, want 0.14.x
2. `zig build test` — paste output (expect 3 passed tests)
3. `zig build run -- --name Moe --year 2026 --month 10 --in "samples/2026 Schedule (Oct).csv"` — paste output, expect the 15 shifts above
4. Append results below under your name.

---

## Ideas backlog (parked, not scheduled)
- `Open` row coverage stats (--show-open): how many unfilled shifts/mo
- Fuzzy name match fallback if exact match fails (typo'd name in a future sheet)
- Multi-month export support (parser already loops blocks — mostly free)
- ODS/xlsx input via miniz+XML (the journey expansion pack)
- TUI: Material-ish tonal palette in 256-color, rounded box glyphs
- GUI: M3 Tonal Spot palette generation from a seed color, spring animations


## 002 — 2026-10-12 — Logic validated (pre-compile)

Python equivalence check of the FIXED parser (single-digit hours handled via
colon-split, matching the Zig fix from 001) against the real Oct 2026 export:
15 shifts, identical to the hand-verified table. Overnight detection correct
on 23:00->07:00 pairs (incl. the short 23:00->3:00 form seen on other rows).
Negative paths verified: unknown name -> NameNotFound, headerless file ->
NoWeekBlocks. Python was used for this one check only — never ships in the
project; all runtime code stays Zig.

Status: logic proven on paper, Zig untested on hardware. Next action is
user-side: compile on Windows, paste results here.


## 003 — 2026-10-11 — First real build: two failures, both expected kinds

User build on Windows, Zig 0.17.0 (winget current). Failures:
1. build.zig.zon fingerprint was a placeholder (0xa1b2c3d4...). Zig rejected it
   and printed a valid suggestion; top 32 bits are name-derived (hash of
   "shifty" = 0xfdc89831), bottom 32 random. Fixed with compiler-suggested
   0xfdc898314c2facdd.
2. Toolchain drift: code targets 0.14 std; 0.17 renamed/moved ArrayList
   (unmanaged default), GeneralPurposeAllocator -> DebugAllocator, std.io
   restructure, build.zig module API. Decision: pin zig 0.14.1 side-by-side
   for now; 0.17 migration is a separate scheduled session AFTER step 1 is
   green. Don't pay two costs at once.

Lesson recorded: placeholder values in build manifests always get caught on
first compile — good, that's the system working. And zig version pinning is
not optional in pre-1.0 Zig; every 2-3 minor versions break std APIs.


## 004 — 2026-10-12 — Ported to Zig 0.17.0

Migration complete; 5/5 unit tests green on real zig 0.17.0 (verified in
sandbox before a tmp wipe). Forced changes, each a real 0.17 std change:
1. build.zig: addExecutable/addTest take .root_module; b.args deleted — run
   the binary directly from zig-out/bin/ instead.
2. ArrayList unmanaged: `.empty` init, allocator passed to every append/deinit.
3. GeneralPurposeAllocator -> std.heap.DebugAllocator.
4. std.io.getStdOut() -> std.fs.File.stdout().writer(&buf) + flush().
5. std.mem.trimLeft -> trimStart.
6. std.time.epoch.Date deleted -> wrote our own civil Date (nextDay, weekday
   via days_from_civil). CAUGHT MY OWN BUG: divided by 146097 instead of 400
   in the era calc; the new date unit test nailed it (2026-10-11 must be a
   Sunday). Tests > confidence.
7. readFileAlloc -> openFile + readToEndAlloc.
8. std.process.argsAlloc -> Args.Iterator (lazily decodes WTF-16 on Windows).
Sandbox lessons: /mnt is noexec, /tmp gets wiped between sessions — compiler
now lives at ~/zig-x86_64-linux-0.17.0 with a tarball backup.


## 007 — 2026-10-12 — STEP 1 COMPLETE: 0.17-verified end to end

Full verification on real zig 0.17.0 (sandbox):
- `zig build test` RC=0 (5/5)
- native binary on real Oct 2026 export: 15 shifts, exact match to hand-verified table
- native binary on synthetic sample: 5 shifts, exact match
- `zig build -Dtarget=x86_64-windows-gnu` RC=0 -> shifty.exe cross-compiled from Linux

The 0.17 stdout endgame: Io.File.Writer is concrete, has NO print; Writer
interface plumbing (initInterface/drain) overkill for a CLI. std.debug.print
verified-present on both OSes -> used for output. LESSON: std.Io rewrite is
the deepest 0.17 break; Step 2 builds src/out.zig helper ONCE with tests
instead of inline plumbing.

Complete 0.14->0.17 migration roster: root_module build API (+b.args deleted),
unmanaged ArrayList, DebugAllocator, std.Io.Writer/File (stdout plumbing),
std.time.epoch.Date deleted (own civil Date + days_from_civil, incl. catching
my own /146097 vs /400 bug via test), trimLeft->trimStart,
readFileAlloc->Io.Dir.cwd().readFileAlloc(io, path, alloc, Limit.limited(n)),
argsAlloc->main(init: std.process.Init) + Args.Iterator (std.os.argv and a
std.process.args global: BOTH gone).

Privacy: real schedule scrubbed from git history (filter-branch + force push,
confirmed absent from GitHub tree); repo uses samples/synthetic-oct-2026.csv.

NEXT: Step 2 — config.json loader (src/core/config.zig), wired into main.

<!-- YOUR ENTRIES BELOW -->
