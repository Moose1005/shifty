//! Service-account auth: JWT bearer flow (RFC 7523). Stateless: mint a fresh
//! access token per run from the SA key — no cache, no refresh tokens.

const std = @import("std");
extern "c" fn time(t: ?*anyopaque) c_long;
const c_time = time;
const rs256 = @import("rs256.zig");

pub const Error = error{
    KeyReadFailed,
    KeyParseFailed,
    TokenRequestFailed,
    BadTokenResponse,
    Internal,
    OutOfMemory,
};

pub const ServiceAccountKey = struct {
    client_email: []const u8,
    private_key: []const u8, // PEM, with \n escapes as in the JSON
    token_uri: []const u8,
};

pub const TokenResponse = struct {
    access_token: []const u8,
    token_type: []const u8,
    expires_in: i64,
};

pub fn loadKey(allocator: std.mem.Allocator, io: std.Io, path: []const u8) Error!std.json.Parsed(ServiceAccountKey) {
    const text = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, std.Io.Limit.limited(64 * 1024)) catch {
        return Error.KeyReadFailed;
    };
    defer allocator.free(text);
    return std.json.parseFromSlice(ServiceAccountKey, allocator, text, .{
        .ignore_unknown_fields = true, // google's JSON has extra fields (key id etc.)
        .allocate = .alloc_always,
    }) catch return Error.KeyParseFailed;
}

/// Build + sign the JWT, exchange it for an access token.
pub fn accessToken(
    allocator: std.mem.Allocator,
    io: std.Io,
    key_path: []const u8,
) Error!TokenResponse {
    var parsed = try loadKey(allocator, io, key_path);
    defer parsed.deinit();
    const key = parsed.value;

    // std.json already turned the JSON \n escapes into real newlines.
    var priv = rs256.parsePrivateKey(allocator, key.private_key) catch return Error.KeyParseFailed;
    defer priv.deinit();

    // JWT: header.claims.signature (base64url each)
    const header = "{\"alg\":\"RS256\",\"typ\":\"JWT\"}";
    // C time() — exists in both glibc and UCRT; std.Io.Clock is broken on
    // windows-gnu in 0.17 (std.c clock_gettime binding mismatch)
    const now: i64 = @intCast(c_time(null));
    var claims_buf: [512]u8 = undefined;
    const claims = std.fmt.bufPrint(&claims_buf, "{{\"iss\":\"{s}\",\"scope\":\"https://www.googleapis.com/auth/calendar.events\",\"aud\":\"{s}\",\"iat\":{d},\"exp\":{d}}}", .{
        key.client_email,
        key.token_uri,
        now,
        now + 3600,
    }) catch return Error.Internal;

    const b64 = std.base64.url_safe_no_pad;
    const h_len = b64.Encoder.calcSize(header.len);
    const c_len = b64.Encoder.calcSize(claims.len);
    var h_buf: [128]u8 = undefined;
    var c_buf: [1024]u8 = undefined;
    _ = b64.Encoder.encode(&h_buf, header);
    _ = b64.Encoder.encode(&c_buf, claims);

    var signing_buf: [1400]u8 = undefined;
    const signing_input = std.fmt.bufPrint(&signing_buf, "{s}.{s}", .{ h_buf[0..h_len], c_buf[0..c_len] }) catch return Error.Internal;

    var sig: [512]u8 = undefined;
    rs256.sign(allocator, &priv, signing_input, &sig) catch return Error.Internal;
    const k = (priv.n.toConst().bitCountAbs() + 7) / 8;
    const sig_b64_len = b64.Encoder.calcSize(k);
    var sig_buf: [1024]u8 = undefined;
    _ = b64.Encoder.encode(&sig_buf, sig[0..k]);

    var jwt_buf: [2600]u8 = undefined;
    const jwt = std.fmt.bufPrint(&jwt_buf, "{s}.{s}.{s}", .{ h_buf[0..h_len], c_buf[0..c_len], sig_buf[0..sig_b64_len] }) catch return Error.Internal;

    // POST grant_type + assertion
    var body_buf: [4096]u8 = undefined;
    const body = std.fmt.bufPrint(&body_buf, "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion={s}", .{jwt}) catch return Error.Internal;

    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const result = client.fetch(.{
        .location = .{ .url = key.token_uri },
        .method = .POST,
        .payload = body,
        .response_writer = &aw.writer,
    }) catch return Error.TokenRequestFailed;
    if (result.status != .ok) return Error.TokenRequestFailed;

    const TokenJson = struct {
        access_token: ?[]const u8 = null,
        token_type: ?[]const u8 = null,
        expires_in: ?i64 = null,
        @"error": ?[]const u8 = null,
        @"error_description": ?[]const u8 = null,
    };
    const parsed_resp = std.json.parseFromSlice(TokenJson, allocator, aw.written(), .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_if_needed,
    }) catch return Error.BadTokenResponse;
    defer parsed_resp.deinit();
    if (parsed_resp.value.access_token) |at| {
        return .{
            .access_token = try allocator.dupe(u8, at),
            .token_type = try allocator.dupe(u8, parsed_resp.value.token_type orelse "Bearer"),
            .expires_in = parsed_resp.value.expires_in orelse 3600,
        };
    }
    std.debug.print("google says: {s}: {s}\n", .{ parsed_resp.value.@"error" orelse "?", parsed_resp.value.@"error_description" orelse "" });
    return Error.BadTokenResponse;
}
