//! RS256 (RSA PKCS#1 v1.5 + SHA-256) signing, implemented from primitives.
//! Zig 0.17 removed public RSA signing from std, so: PEM -> DER -> (n, d)
//! -> EMSA-PKCS1-v1_5 padding -> modular exponentiation via std.math.big.int.
//! Only what Google service-account JWTs need: sign. No verify, no keygen.

const std = @import("std");

pub const Error = error{
    BadPem,
    BadDer,
    OutOfMemory,
};

const b64url = std.base64.url_safe_no_pad;
const b64std = std.base64.standard;

pub const PrivateKey = struct {
    n: std.math.big.int.Managed,
    d: std.math.big.int.Managed,

    pub fn deinit(self: *PrivateKey) void {
        self.n.deinit();
        self.d.deinit();
    }
};

/// Decode a PEM private key (PKCS#8 wrapping PKCS#1, as Google emits).
pub fn parsePrivateKey(allocator: std.mem.Allocator, pem: []const u8) Error!PrivateKey {
    const begin = "-----BEGIN PRIVATE KEY-----";
    const end = "-----END PRIVATE KEY-----";
    const b = std.mem.indexOf(u8, pem, begin) orelse return Error.BadPem;
    const e = std.mem.indexOf(u8, pem, end) orelse return Error.BadPem;
    var buf: [8192]u8 = undefined;
    var n: usize = 0;
    for (pem[b + begin.len .. e]) |c| {
        if (c == '\n' or c == '\r' or c == ' ') continue;
        if (n >= buf.len) return Error.BadPem;
        buf[n] = c;
        n += 1;
    }
    var der_buf: [6144]u8 = undefined;
    const der_len = b64std.Decoder.calcSizeForSlice(buf[0..n]) catch return Error.BadPem;
    if (der_len > der_buf.len) return Error.BadPem;
    b64std.Decoder.decode(der_buf[0..der_len], buf[0..n]) catch return Error.BadPem;
    return parsePkcs8(allocator, der_buf[0..der_len]);
}

const Tlv = struct { tag: u8, value: []const u8 };

fn readTlv(bytes: []const u8, pos: *usize) Error!Tlv {
    if (pos.* + 2 > bytes.len) return Error.BadDer;
    const tag = bytes[pos.*];
    pos.* += 1;
    var len: usize = bytes[pos.*];
    pos.* += 1;
    if (len & 0x80 != 0) {
        const nbytes = len & 0x7f;
        if (nbytes == 0 or pos.* + nbytes > bytes.len) return Error.BadDer;
        len = 0;
        for (bytes[pos.*..][0..nbytes]) |b| len = len * 256 + b;
        pos.* += nbytes;
    }
    if (pos.* + len > bytes.len) return Error.BadDer;
    const value = bytes[pos.*..][0..len];
    pos.* += len;
    return .{ .tag = tag, .value = value };
}

/// INTEGER -> big int (strip leading zero sign byte if present).
fn intFromDer(allocator: std.mem.Allocator, tlv: Tlv) Error!std.math.big.int.Managed {
    if (tlv.tag != 0x02) return Error.BadDer;
    var v = tlv.value;
    if (v.len > 1 and v[0] == 0) v = v[1..];
    var r = try std.math.big.int.Managed.initSet(allocator, 0);
    errdefer r.deinit();
    for (v) |byte| {
        try r.shiftLeft(&r, 8);
        try r.add(&r, &try std.math.big.int.Managed.initSet(allocator, byte));
    }
    return r;
}

fn parsePkcs8(allocator: std.mem.Allocator, der: []const u8) Error!PrivateKey {
    var pos: usize = 0;
    const outer = try readTlv(der, &pos); // SEQUENCE
    if (outer.tag != 0x30) return Error.BadDer;
    var ipos: usize = 0;
    _ = try readTlv(outer.value, &ipos); // version INTEGER
    _ = try readTlv(outer.value, &ipos); // algorithm SEQUENCE
    const octets = try readTlv(outer.value, &ipos); // privateKey OCTET STRING
    if (octets.tag != 0x04) return Error.BadDer;
    // PKCS#1 RSAPrivateKey: SEQ { v, n, e, d, ... }
    var ppos: usize = 0;
    const seq = try readTlv(octets.value, &ppos);
    if (seq.tag != 0x30) return Error.BadDer;
    var spos: usize = 0;
    _ = try readTlv(seq.value, &spos); // v
    const n_tlv = try readTlv(seq.value, &spos);
    _ = try readTlv(seq.value, &spos); // e
    const d_tlv = try readTlv(seq.value, &spos);
    var key = PrivateKey{
        .n = try intFromDer(allocator, n_tlv),
        .d = try intFromDer(allocator, d_tlv),
    };
    errdefer key.deinit();
    return key;
}

/// Modular exponentiation: result = base^exp mod modulus (square-and-multiply).
fn modpow(
    allocator: std.mem.Allocator,
    result: *std.math.big.int.Managed,
    base_in: *const std.math.big.int.Managed,
    exp_in: *const std.math.big.int.Managed,
    modulus: *const std.math.big.int.Managed,
) !void {
    result.* = try std.math.big.int.Managed.initSet(allocator, 1);
    var base = try std.math.big.int.Managed.init(allocator);
    defer base.deinit();
    try base.copy(base_in.toConst());
    var exp = try std.math.big.int.Managed.init(allocator);
    defer exp.deinit();
    try exp.copy(exp_in.toConst());
    var tmp = try std.math.big.int.Managed.init(allocator);
    defer tmp.deinit();
    var q = try std.math.big.int.Managed.init(allocator);
    defer q.deinit();

    while (!exp.toConst().eqlZero()) {
        // if exp odd: result = result*base mod n
        if (exp.toConst().limbs[0] & 1 == 1) {
            try tmp.mul(&result.*, &base);
            try result.*.divFloor(&q, &tmp, modulus);
        }
        // base = base^2 mod n
        try tmp.mul(&base, &base);
        try base.divFloor(&q, &tmp, modulus);
        try exp.shiftRight(&exp, 1);
    }
}

const sha256_prefix = [_]u8{ 0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20 };

/// Sign msg with the key: RSASSA-PKCS1-v1_5 (RFC 8017). Returns k-byte signature.
pub fn sign(allocator: std.mem.Allocator, key: *const PrivateKey, msg: []const u8, out: []u8) Error!void {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(msg, &hash, .{});

    // k = byte length of modulus
    const bits = key.n.toConst().bitCountAbs();
    const k = (bits + 7) / 8;
    if (out.len < k) return Error.BadDer;

    // EM = 0x00 0x01 PS(0xFF) 0x00 T, where T = prefix || hash
    const t_len = sha256_prefix.len + hash.len;
    if (k < t_len + 11) return Error.BadDer;
    const ps_len = k - t_len - 3;
    var em = try allocator.alloc(u8, k);
    defer allocator.free(em);
    em[0] = 0x00;
    em[1] = 0x01;
    @memset(em[2 .. 2 + ps_len], 0xff);
    em[2 + ps_len] = 0x00;
    @memcpy(em[3 + ps_len ..][0..sha256_prefix.len], &sha256_prefix);
    @memcpy(em[3 + ps_len + sha256_prefix.len ..][0..hash.len], &hash);

    // sig = EM^d mod n
    var m = try std.math.big.int.Managed.initSet(allocator, 0);
    defer m.deinit();
    for (em) |byte| {
        try m.shiftLeft(&m, 8);
        try m.add(&m, &try std.math.big.int.Managed.initSet(allocator, byte));
    }
    var sig = try std.math.big.int.Managed.init(allocator);
    defer sig.deinit();
    try modpow(allocator, &sig, &m, &key.d, &key.n);

    // to big-endian bytes (via hex: pad to 2k chars, decode)
    const hex = sig.toConst().toStringAlloc(allocator, 16, .lower) catch return Error.BadDer;
    defer allocator.free(hex);
    if (hex.len > 2 * k) return Error.BadDer;
    var byte_i: usize = k; // fill from the right
    var hex_i: usize = hex.len;
    while (hex_i >= 2) {
        hex_i -= 2;
        byte_i -= 1;
        const hi = std.fmt.charToDigit(hex[hex_i], 16) catch return Error.BadDer;
        const lo = std.fmt.charToDigit(hex[hex_i + 1], 16) catch return Error.BadDer;
        out[byte_i] = (hi << 4) | lo;
    }
    if (byte_i > 0) @memset(out[0..byte_i], 0);
}

test "modpow classic RSA example" {
    // p=61 q=53 n=3233 e=17 d=2753 (Wikipedia RSA example)
    var n = try std.math.big.int.Managed.initSet(std.testing.allocator, 3233);
    defer n.deinit();
    var d = try std.math.big.int.Managed.initSet(std.testing.allocator, 2753);
    defer d.deinit();
    var m = try std.math.big.int.Managed.initSet(std.testing.allocator, 65);
    defer m.deinit();
    var r = try std.math.big.int.Managed.init(std.testing.allocator);
    defer r.deinit();
    try modpow(std.testing.allocator, &r, &m, &d, &n);
    // 65^2753 mod 3233 = 2790
    var expect = try std.math.big.int.Managed.initSet(std.testing.allocator, 2790);
    defer expect.deinit();
    try std.testing.expectEqual(std.math.Order.eq, r.toConst().order(expect.toConst()));
}

test "base64url decode of known vector" {
    // "hello zig" -> aGVsbG8gemln
    var buf: [32]u8 = undefined;
    const n = try b64url.Decoder.decode(&buf, "aGVsbG8gemln");
    try std.testing.expectEqualStrings("hello zig", buf[0..n]);
}
