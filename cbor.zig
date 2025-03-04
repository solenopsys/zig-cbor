const std = @import("std");

pub const Error = error{
    StringTooLong,
    IntegerTooLarge,
    InvalidValue,
    OutOfMemory,
};

pub const CborValue = union(enum) {
    const Self = @This();

    Null,
    Boolean: bool,
    Integer: i64,
    Float: f64,
    String: []const u8,
    Array: []const Self,
    Object: ObjectMap,

    pub fn initNull() Self {
        return .Null;
    }

    pub fn initBoolean(value: bool) Self {
        return .{ .Boolean = value };
    }

    pub fn initInteger(value: i64) Self {
        return .{ .Integer = value };
    }

    pub fn initFloat(value: f64) Self {
        return .{ .Float = value };
    }

    pub fn initString(value: []const u8) Self {
        return .{ .String = value };
    }

    pub fn initArray(value: []const Self) Self {
        return .{ .Array = value };
    }

    pub fn initObject(value: ObjectMap) Self {
        return .{ .Object = value };
    }

    pub fn serialize(self: Self, writer: anytype) Error!void {
        switch (self) {
            .Null => try writer.writeByte(0xF6),
            .Boolean => |b| try writer.writeByte(if (b) 0xF5 else 0xF4),
            .Integer => |i| try serializeInteger(i, writer),
            .Float => |f| try serializeFloat(f, writer),
            .String => |s| try serializeString(s, writer),
            .Array => |a| try serializeArray(a, writer),
            .Object => |o| try o.serialize(writer),
        }
    }
};

pub const ObjectMap = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    map: std.StringArrayHashMap(CborValue),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .map = std.StringArrayHashMap(CborValue).init(allocator),
        };
    }

    pub fn put(self: *Self, key: []const u8, value: CborValue) !void {
        const key_owned = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_owned);

        if (self.map.getKey(key)) |existing_key| {
            self.allocator.free(existing_key);
        }

        try self.map.put(key_owned, value);
    }

    pub fn clone(self: Self) !Self {
        var new_map = Self.init(self.allocator);
        errdefer new_map.deinit();

        var it = self.map.iterator();
        while (it.next()) |entry| {
            try new_map.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        return new_map;
    }

    pub fn serialize(self: Self, writer: anytype) Error!void {
        const size = @as(u8, @intCast(self.map.count()));
        try writer.writeByte(0xA0 | size);

        var it = self.map.iterator();
        while (it.next()) |entry| {
            try serializeString(entry.key_ptr.*, writer);
            try entry.value_ptr.*.serialize(writer);
        }
    }

    pub fn deinit(self: *Self) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);

            switch (entry.value_ptr.*) {
                .Object => |*obj| obj.deinit(),
                else => {},
            }
        }
        self.map.deinit();
    }
};

fn writeU16BigEndian(writer: anytype, value: u16) !void {
    const high_byte: u8 = @truncate(value >> 8);
    const low_byte: u8 = @truncate(value);
    try writer.writeByte(high_byte);
    try writer.writeByte(low_byte);
}

fn serializeInteger(value: i64, writer: anytype) Error!void {
    if (value >= 0) {
        if (value <= 23) {
            try writer.writeByte(@intCast(value));
        } else if (value <= std.math.maxInt(u8)) {
            try writer.writeByte(0x18);
            try writer.writeByte(@intCast(value));
        } else if (value <= std.math.maxInt(u16)) {
            try writer.writeByte(0x19);
            try writeU16BigEndian(writer, @intCast(value));
        } else if (value <= std.math.maxInt(u32)) {
            try writer.writeByte(0x1A);
            const bytes = std.mem.toBytes(@as(u32, @intCast(value)));
            for (bytes) |byte| {
                try writer.writeByte(byte);
            }
        } else {
            try writer.writeByte(0x1B);
            const bytes = std.mem.toBytes(@as(u64, @intCast(value)));
            for (bytes) |byte| {
                try writer.writeByte(byte);
            }
        }
    } else {
        const abs = if (value == std.math.minInt(i64))
            @as(u64, std.math.maxInt(i64)) + 1
        else
            @as(u64, @intCast(-value - 1));

        if (abs <= 23) {
            try writer.writeByte(@as(u8, @intCast(0x20 | abs)));
        } else if (abs <= std.math.maxInt(u8)) {
            try writer.writeByte(0x38);
            try writer.writeByte(@as(u8, @intCast(abs)));
        } else if (abs <= std.math.maxInt(u16)) {
            try writer.writeByte(0x39);
            const be_value = std.mem.nativeToBig(u16, @intCast(abs));
            try writer.writeAll(std.mem.asBytes(&be_value));
        } else if (abs <= std.math.maxInt(u32)) {
            try writer.writeByte(0x3A);
            const be_value = std.mem.nativeToBig(u32, @intCast(abs));
            try writer.writeAll(std.mem.asBytes(&be_value));
        } else {
            try writer.writeByte(0x3B);
            const be_value = std.mem.nativeToBig(u64, @intCast(abs));
            try writer.writeAll(std.mem.asBytes(&be_value));
        }
    }
}
fn serializeFloat(value: f64, writer: anytype) Error!void {
    try writer.writeByte(0xFB);

    const be_value = std.mem.nativeToBig(u64, @as(u64, @bitCast(value)));
    const be_bytes = std.mem.asBytes(&be_value);

    try writer.writeAll(be_bytes);
}

fn serializeString(value: []const u8, writer: anytype) Error!void {
    const len = value.len;
    if (len < 24) {
        try writer.writeByte(@as(u8, @intCast(0x60 | len)));
    } else if (len <= std.math.maxInt(u8)) {
        try writer.writeByte(0x78);
        try writer.writeByte(@as(u8, @intCast(len)));
    } else if (len <= std.math.maxInt(u16)) {
        try writer.writeByte(0x79);
        const bytes = std.mem.toBytes(@as(u16, @intCast(len)));
        try writer.writeAll(&bytes);
    } else {
        return Error.StringTooLong;
    }
    try writer.writeAll(value);
}

fn serializeArray(value: []const CborValue, writer: anytype) Error!void {
    const len = value.len;
    if (len < 24) {
        try writer.writeByte(@as(u8, @intCast(0x80 | len)));
    } else if (len <= std.math.maxInt(u8)) {
        try writer.writeByte(0x98);
        try writer.writeByte(@as(u8, @intCast(len)));
    } else if (len <= std.math.maxInt(u16)) {
        try writer.writeByte(0x99);
        const bytes = std.mem.toBytes(@as(u16, @intCast(len)));
        try writer.writeAll(&bytes);
    } else {
        return Error.StringTooLong;
    }

    for (value) |item| {
        try item.serialize(writer);
    }
}
