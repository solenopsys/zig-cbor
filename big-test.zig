const std = @import("std");
const testing = std.testing;
const json = std.json;
const base64 = std.base64;
const cbor = @import("cbor.zig");

const CborValue = cbor.CborValue;
const ObjectMap = cbor.ObjectMap;

test "CBOR serialization from JSON test suite" {
    const allocator = testing.allocator;

    // JSON test data
    const file_path = "./test_data/cbor_ts.json";

    // Чтение файла JSON
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const json_string = try allocator.alloc(u8, file_size);
    defer allocator.free(json_string);

    const bytes_read = try file.readAll(json_string);
    if (bytes_read != file_size) {
        return error.FileReadError;
    }

    const TestCase = struct {
        cbor: []const u8,
        hex: []const u8,
        roundtrip: bool,
        decoded: json.Value,
    };

    var parsed = try json.parseFromSlice([]TestCase, allocator, json_string, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    for (parsed.value) |test_case| {
        // print
        std.debug.print("cbor: {s} hex: {s}\n", .{ test_case.cbor, test_case.hex });
        // Skip cases marked as not supporting roundtrip
        if (!test_case.roundtrip) continue;

        // Правильное декодирование base64 CBOR
        const decoder = base64.standard.Decoder;
        const decoded_size = try decoder.calcSizeForSlice(test_case.cbor);
        const decoded_cbor = try allocator.alloc(u8, decoded_size);
        defer allocator.free(decoded_cbor);
        try decoder.decode(decoded_cbor, test_case.cbor);
        const expected_bytes = decoded_cbor[0..decoded_size];

        // Verify individual test cases based on their type
        switch (test_case.decoded) {
            .integer => |int_value| {
                var buf = std.ArrayList(u8).init(allocator);
                defer buf.deinit();

                try CborValue.initInteger(int_value).serialize(buf.writer());

                try testing.expectEqualSlices(u8, expected_bytes, buf.items);
            },
            .float => |num_value| {
                var buf = std.ArrayList(u8).init(allocator);
                defer buf.deinit();

                // Всегда сериализуем как float, если в JSON значение было определено как float
                // (даже если оно может быть представлено как целое число)
                try CborValue.initFloat(num_value).serialize(buf.writer());

                try testing.expectEqualSlices(u8, expected_bytes, buf.items);
            },
            .bool => |bool_value| {
                var buf = std.ArrayList(u8).init(allocator);
                defer buf.deinit();

                try CborValue.initBoolean(bool_value).serialize(buf.writer());
                try testing.expectEqualSlices(u8, expected_bytes, buf.items);
            },
            .null => {
                var buf = std.ArrayList(u8).init(allocator);
                defer buf.deinit();

                try CborValue.initNull().serialize(buf.writer());
                try testing.expectEqualSlices(u8, expected_bytes, buf.items);
            },
            .string => |str_value| {
                var buf = std.ArrayList(u8).init(allocator);
                defer buf.deinit();

                try CborValue.initString(str_value).serialize(buf.writer());
                try testing.expectEqualSlices(u8, expected_bytes, buf.items);
            },
            .array => |arr_value| {
                var buf = std.ArrayList(u8).init(allocator);
                defer buf.deinit();

                var cbor_arr = std.ArrayList(CborValue).init(allocator);
                defer {
                    for (cbor_arr.items) |*item| {
                        if (item.* == .Object) {
                            item.Object.deinit();
                        }
                    }
                    cbor_arr.deinit();
                }

                for (arr_value.items) |value| {
                    switch (value) {
                        .integer => |int_val| try cbor_arr.append(CborValue.initInteger(int_val)),
                        .float => |num_val| {
                            const float_val = num_val;
                            const int_val = @as(i64, @intFromFloat(float_val));

                            if (@as(f64, @floatFromInt(int_val)) == float_val) {
                                try cbor_arr.append(CborValue.initInteger(int_val));
                            } else {
                                try cbor_arr.append(CborValue.initFloat(float_val));
                            }
                        },
                        .string => |str_val| try cbor_arr.append(CborValue.initString(str_val)),
                        .bool => |bool_val| try cbor_arr.append(CborValue.initBoolean(bool_val)),
                        .null => try cbor_arr.append(CborValue.initNull()),
                        else => continue, // Skip complex cases
                    }
                }

                try CborValue.initArray(cbor_arr.items).serialize(buf.writer());
                try testing.expectEqualSlices(u8, expected_bytes, buf.items);
            },
            .object => |obj_value| {
                var buf = std.ArrayList(u8).init(allocator);
                defer buf.deinit();

                var cbor_obj = ObjectMap.init(allocator);
                defer cbor_obj.deinit();

                var it = obj_value.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const value = entry.value_ptr.*;

                    switch (value) {
                        .integer => |int_val| try cbor_obj.put(key, CborValue.initInteger(int_val)),
                        .float => |num_val| {
                            const float_val = num_val;
                            const int_val = @as(i64, @intFromFloat(float_val));

                            if (@as(f64, @floatFromInt(int_val)) == float_val) {
                                try cbor_obj.put(key, CborValue.initInteger(int_val));
                            } else {
                                try cbor_obj.put(key, CborValue.initFloat(float_val));
                            }
                        },
                        .string => |str_val| try cbor_obj.put(key, CborValue.initString(str_val)),
                        .bool => |bool_val| try cbor_obj.put(key, CborValue.initBoolean(bool_val)),
                        .null => try cbor_obj.put(key, CborValue.initNull()),
                        else => continue, // Skip complex cases
                    }
                }

                try CborValue.initObject(cbor_obj).serialize(buf.writer());
                try testing.expectEqualSlices(u8, expected_bytes, buf.items);
            },
            else => continue, // Skip unsupported types
        }
    }
}
