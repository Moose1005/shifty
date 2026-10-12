//! TODO(GCAL-AUTH): OAuth2 loopback (installed-app) flow.
//!  1. Read client_id/secret from env or config (keep OUT of git).
//!  2. Listen on 127.0.0.1:<random port> (std.net + std.http.Server).
//!  3. Open https://accounts.google.com/o/oauth2/v2/auth?...redirect_uri=http://127.0.0.1:PORT&scope=https://www.googleapis.com/auth/calendar.events&response_type=code&access_type=offline&prompt=consent
//!  4. Catch the GET with ?code=..., then POST to https://oauth2.googleapis.com/token (std.http.Client — TLS here is the risky part; see README note about libcurl fallback).
//!  5. Save {refresh_token, ...} to ~/.config/shifty/token.json with 0600.
//!  6. Refresh access tokens lazily (they die in 1h).

pub fn ensureToken() void {
    @panic("TODO(GCAL-AUTH)");
}
