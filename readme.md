# CBOR Serializer in Zig

A lightweight and efficient CBOR (Concise Binary Object Representation) serializer implemented in Zig.

## Features
- Fast and compact serialization of data into CBOR format
- Fully written in Zig for high performance and low memory usage
- Supports encoding basic data types (integers, strings, arrays, maps, etc.)
- Minimal dependencies

## Installation
Clone the repository and include it in your Zig project:
```sh
git clone https://github.com/solenopsys/cborzig.git
cd cborzig
```

## Usage
Import the serializer and use it in your Zig project:
```zig
const std = @import("std");
const cbor = @import("cbor.zig");

const CborValue = cbor.CborValue;
const ObjectMap = cbor.ObjectMap;

pub fn main() !void {
    var allocator = std.heap.page_allocator;

    var obj = ObjectMap.init(allocator);
    defer obj.deinit();

    try obj.put("message", CborValue.initString("Hello, CBOR!"));
    try obj.put("number", CborValue.initInteger(42));
    try obj.put("flag", CborValue.initBoolean(true));

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try CborValue.initObject(obj).serialize(buf.writer());
    std.debug.print("Serialized CBOR: {any}\n", .{buf.items});
}
```

## Roadmap
- [ ] Support for floating-point numbers
- [ ] CBOR decoding functionality
- [ ] Support for custom data types

## License
This project is licensed under the MIT License.

