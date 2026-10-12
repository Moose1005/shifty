//! TODO(GCAL-EVENTS): convert core.Shift + Config into a Calendar event.
//! Key fields:
//!   summary:        "Work 15:00-23:00" (or just "Work")
//!   location:       config.office_address
//!   start/end:      RFC3339 with offset — DST-safe. Parse `date`+minutes in
//!                   config.timezone. DO NOT assume fixed -05:00/-04:00; use a
//!                   tz database (link libc localtime, or vendor tzdata).
//!   reminders:      overrides from config.reminders_minutes (method: popup)
//!   colorId:        random from config.palette (seed once per month for a
//!                   stable look, or per-shift — decide, document)
//!   extendedProperties.private.shiftKey: deterministic hash of
//!                   (calendar_id, date, start, end) — query by it before
//!                   inserting so re-running the app is idempotent.
//! Insert via POST /calendar/v3/calendars/{id}/events or events.import with
//! your own id — both beat blind insert for dedupe.

const std = @import("std");

pub fn buildEventJson() void {
    _ = std;
    @panic("TODO(GCAL-EVENTS)");
}
