const std = @import("std");

const cbor = @import("cbor.zig");

const CborValue = cbor.CborValue;
const ObjectMap = cbor.ObjectMap;

test "CBOR float serialization" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    const pi: f64 = 3.14159;
    try CborValue.initFloat(pi).serialize(buf.writer());

    try std.testing.expectEqual(@as(u8, 0xFB), buf.items[0]);

    const number_bytes = buf.items[1..9];
    const stored_bits = std.mem.bigToNative(u64, std.mem.bytesToValue(u64, number_bytes));
    const stored_value = @as(f64, @bitCast(stored_bits));

    try std.testing.expectApproxEqAbs(pi, stored_value, 0.00001);
}

test "CBOR serialization" {
    const allocator = std.testing.allocator;

    var obj = ObjectMap.init(allocator);
    defer obj.deinit();

    try obj.put("null", CborValue.initNull());
    try obj.put("bool", CborValue.initBoolean(true));
    try obj.put("int", CborValue.initInteger(42));
    try obj.put("float", CborValue.initFloat(3.14));
    try obj.put("string", CborValue.initString("test"));

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try CborValue.initObject(obj).serialize(buf.writer());

    const expected = [_]u8{
        0xa5,
        0x64,
        'n',
        'u',
        'l',
        'l',
        0xf6,
        0x64,
        'b',
        'o',
        'o',
        'l',
        0xf5,
        0x63,
        'i',
        'n',
        't',
        0x18,
        42,
        0x65,
        'f',
        'l',
        'o',
        'a',
        't',
        0xfb,
        0x40,
        0x09,
        0x1e,
        0xb8,
        0x51,
        0xeb,
        0x85,
        0x1f,
        0x66,
        's',
        't',
        'r',
        'i',
        'n',
        'g',
        0x64,
        't',
        'e',
        's',
        't',
    };

    try std.testing.expectEqualSlices(u8, &expected, buf.items);
}

test "CBOR negative integers" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try CborValue.initInteger(-42).serialize(buf.writer());

    const expected = [_]u8{
        0x38, 41,
    };

    try std.testing.expectEqualSlices(u8, &expected, buf.items);
}

test "CBOR array" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    const arr = [_]CborValue{
        CborValue.initInteger(1),
        CborValue.initString("test"),
        CborValue.initBoolean(true),
    };

    try CborValue.initArray(&arr).serialize(buf.writer());

    const expected = [_]u8{
        0x83,
        0x01,
        0x64,
        't',
        'e',
        's',
        't',
        0xf5,
    };

    try std.testing.expectEqualSlices(u8, &expected, buf.items);
}

test "Complex CBOR serialization" {
    const allocator = std.testing.allocator;
    var root = ObjectMap.init(allocator);
    defer root.deinit();

    {
        var metadata = ObjectMap.init(allocator);
        try metadata.put("version", CborValue.initInteger(2));
        try metadata.put("created_at", CborValue.initString("2024-01-07T12:00:00Z"));
        try metadata.put("is_valid", CborValue.initBoolean(true));
        try root.put("metadata", CborValue.initObject(metadata));
    }

    const mixed_array = [_]CborValue{
        CborValue.initNull(),
        CborValue.initInteger(-123),
        CborValue.initFloat(2.718281828),
        CborValue.initString("hello"),
        CborValue.initBoolean(false),
    };
    try root.put("mixed_array", CborValue.initArray(&mixed_array));

    {
        var settings = ObjectMap.init(allocator);
        try settings.put("debug_mode", CborValue.initBoolean(true));
        try settings.put("max_retries", CborValue.initInteger(3));
        try settings.put("timeout_ms", CborValue.initInteger(5000));

        const log_levels = [_]CborValue{
            CborValue.initString("error"),
            CborValue.initString("warning"),
            CborValue.initString("info"),
        };
        try settings.put("log_levels", CborValue.initArray(&log_levels));
        try root.put("settings", CborValue.initObject(settings));
    }

    try root.put("app_name", CborValue.initString("test_app"));
    try root.put("port", CborValue.initInteger(8080));
    try root.put("enabled", CborValue.initBoolean(true));

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try CborValue.initObject(root).serialize(buf.writer());

    const expected = [_]u8{
        0xA6,

        0x68,
        'm',
        'e',
        't',
        'a',
        'd',
        'a',
        't',
        'a',
        0xA3,

        0x67,
        'v',
        'e',
        'r',
        's',
        'i',
        'o',
        'n',
        0x02,

        0x6A,
        'c',
        'r',
        'e',
        'a',
        't',
        'e',
        'd',
        '_',
        'a',
        't',
        0x74,
        '2',
        '0',
        '2',
        '4',
        '-',
        '0',
        '1',
        '-',
        '0',
        '7',
        'T',
        '1',
        '2',
        ':',
        '0',
        '0',
        ':',
        '0',
        '0',
        'Z',

        0x68,
        'i',
        's',
        '_',
        'v',
        'a',
        'l',
        'i',
        'd',
        0xF5,

        0x6B,
        'm',
        'i',
        'x',
        'e',
        'd',
        '_',
        'a',
        'r',
        'r',
        'a',
        'y',
        0x85,
        0xF6,
        0x38,
        0x7A,
        0xFB,
        0x40,
        0x05,
        0xBF,
        0x0A,
        0x8B,
        0x04,
        0x91,
        0x9B,
        0x65,
        'h',
        'e',
        'l',
        'l',
        'o',
        0xF4,

        0x68,
        's',
        'e',
        't',
        't',
        'i',
        'n',
        'g',
        's',
        0xA4,

        0x6A,
        'd',
        'e',
        'b',
        'u',
        'g',
        '_',
        'm',
        'o',
        'd',
        'e',
        0xF5,

        0x6B,
        'm',
        'a',
        'x',
        '_',
        'r',
        'e',
        't',
        'r',
        'i',
        'e',
        's',
        0x03,

        0x6A,
        't',
        'i',
        'm',
        'e',
        'o',
        'u',
        't',
        '_',
        'm',
        's',
        0x19,
        0x13,
        0x88,

        0x6A,
        'l',
        'o',
        'g',
        '_',
        'l',
        'e',
        'v',
        'e',
        'l',
        's',
        0x83,
        0x65,
        'e',
        'r',
        'r',
        'o',
        'r',
        0x67,
        'w',
        'a',
        'r',
        'n',
        'i',
        'n',
        'g',
        0x64,
        'i',
        'n',
        'f',
        'o',

        0x68,
        'a',
        'p',
        'p',
        '_',
        'n',
        'a',
        'm',
        'e',
        0x68,
        't',
        'e',
        's',
        't',
        '_',
        'a',
        'p',
        'p',

        0x64,
        'p',
        'o',
        'r',
        't',
        0x19,
        0x1F,
        0x90,

        0x67,
        'e',
        'n',
        'a',
        'b',
        'l',
        'e',
        'd',
        0xF5,
    };

    try std.testing.expectEqualSlices(u8, &expected, buf.items);
}

test "CBOR serialization with nested object 2" {
    const allocator = std.testing.allocator;

    var root = ObjectMap.init(allocator);
    defer root.deinit();

    {
        var nested = ObjectMap.init(allocator);
        try nested.put("flag_true", CborValue.initBoolean(true));
        try nested.put("flag_false", CborValue.initBoolean(false));
        try nested.put("empty_str", CborValue.initString(""));

        try root.put("nested", CborValue.initObject(nested));
    }

    try root.put("answer", CborValue.initInteger(42));
    try root.put("pi_approx", CborValue.initFloat(3.14159));

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try CborValue.initObject(root).serialize(buf.writer());

    const expected = [_]u8{
        0xa3,
        0x66,
        'n',
        'e',
        's',
        't',
        'e',
        'd',
        0xa3,
        0x69,
        'f',
        'l',
        'a',
        'g',
        '_',
        't',
        'r',
        'u',
        'e',
        0xf5,
        0x6a,
        'f',
        'l',
        'a',
        'g',
        '_',
        'f',
        'a',
        'l',
        's',
        'e',
        0xf4,
        0x69,
        'e',
        'm',
        'p',
        't',
        'y',
        '_',
        's',
        't',
        'r',
        0x60,
        0x66,
        'a',
        'n',
        's',
        'w',
        'e',
        'r',
        0x18,
        0x2a,
        0x69,
        'p',
        'i',
        '_',
        'a',
        'p',
        'p',
        'r',
        'o',
        'x',
        0xfb,
        0x40,
        0x09,
        0x21,
        0xf9,
        0xf0,
        0x1b,
        0x86,
        0x6e,
    };

    try std.testing.expectEqualSlices(u8, &expected, buf.items);
}

test "Мetadata CBOR serialization" {
    const allocator = std.testing.allocator;

    var meta_obj = ObjectMap.init(allocator);
    defer meta_obj.deinit();

    try meta_obj.put("name", CborValue.initString("test.txt"));
    try meta_obj.put("description", CborValue.initString("Test file"));
    try meta_obj.put("size", CborValue.initInteger(451));
    try meta_obj.put("contentType", CborValue.initString("text/plain"));

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try CborValue.initObject(meta_obj).serialize(buf.writer());

    const expected = [_]u8{
        0xA4,
        0x64,
        'n',
        'a',
        'm',
        'e',
        0x68,
        't',
        'e',
        's',
        't',
        '.',
        't',
        'x',
        't',
        0x6b,
        'd',
        'e',
        's',
        'c',
        'r',
        'i',
        'p',
        't',
        'i',
        'o',
        'n',
        0x69,
        'T',
        'e',
        's',
        't',
        ' ',
        'f',
        'i',
        'l',
        'e',
        0x64,
        's',
        'i',
        'z',
        'e',
        0x19,
        0x01,
        0xc3,
        0x6b,
        'c',
        'o',
        'n',
        't',
        'e',
        'n',
        't',
        'T',
        'y',
        'p',
        'e',
        0x6a,
        't',
        'e',
        'x',
        't',
        '/',
        'p',
        'l',
        'a',
        'i',
        'n',
    };

    try std.testing.expectEqualSlices(u8, &expected, buf.items);

    if (meta_obj.map.get("size")) |size| {
        switch (size) {
            .Integer => |value| try std.testing.expectEqual(@as(i64, 451), value),
            else => try std.testing.expect(false),
        }
    } else {
        try std.testing.expect(false);
    }

    for (buf.items, 0..) |byte, i| {
        if (byte != expected[i]) {
            std.debug.print("Mismatch at position {}: expected 0x{X:0>2}, got 0x{X:0>2}\n", .{ i, expected[i], byte });
            break;
        }
    }
}
