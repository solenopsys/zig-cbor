const std = @import("std");
const json = std.json;
const time = std.time;
const expect = std.testing.expect;

// Определяем структуру для тестирования
const JsonItem = struct {
    id: u32,
    value: []const u8,
    active: bool,
    score: f64,
};

const JsonMetadata = struct {
    created: []const u8,
    version: []const u8,
    tags: [][]const u8,
};

const JsonConfig = struct {
    maxRetries: u32,
    timeout: u32,
    features: struct {
        logging: bool,
        caching: bool,
        compression: bool,
    },
};

const JsonData = struct {
    name: []const u8,
    items: []JsonItem,
    metadata: JsonMetadata,
    config: JsonConfig,
};

const ITERATIONS: u32 = 1000;

pub fn main() !void {
    // Инициализация аллокатора
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    defer {
        const deinit_status = general_purpose_allocator.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: Memory leak detected\n", .{});
    }

    // Получение пути к файлу из аргументов командной строки
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const file_path = "./test_data/test.json";

    // Чтение файла JSON
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const json_string = try gpa.alloc(u8, file_size);
    defer gpa.free(json_string);

    const bytes_read = try file.readAll(json_string);
    if (bytes_read != file_size) {
        return error.FileReadError;
    }

    std.debug.print("File size: {d} bytes\n", .{file_size});
    std.debug.print("Iterations: {d}\n", .{ITERATIONS});

    // Измерение динамической десериализации
    const start_dynamic_deserialize = std.time.microTimestamp();
    var i: u32 = 0;
    while (i < ITERATIONS) : (i += 1) {
        const parsed = try json.parseFromSlice(json.Value, gpa, json_string, .{});
        parsed.deinit();
    }
    const end_dynamic_deserialize = std.time.microTimestamp();

    const dynamic_deserialize_us = end_dynamic_deserialize - start_dynamic_deserialize;
    const dynamic_deserialize_ms = @as(f64, @floatFromInt(dynamic_deserialize_us)) / 1000.0;
    const dynamic_deserialize_avg_ms = dynamic_deserialize_ms / @as(f64, @floatFromInt(ITERATIONS));

    std.debug.print("Dynamic deserialization total time: {d:.4} ms\n", .{dynamic_deserialize_ms});
    std.debug.print("Dynamic deserialization average time: {d:.4} ms\n", .{dynamic_deserialize_avg_ms});

    // Измерение структурной десериализации
    var structured_worked = false;
    const start_structured_deserialize = std.time.microTimestamp();
    i = 0;
    while (i < ITERATIONS) : (i += 1) {
        const parsed_struct = json.parseFromSlice(JsonData, gpa, json_string, .{}) catch |err| {
            std.debug.print("Note: Structured parsing failed with error: {}\n", .{err});
            return;
        };
        parsed_struct.deinit();
    }
    structured_worked = true;
    const end_structured_deserialize = std.time.microTimestamp();

    const structured_deserialize_us = end_structured_deserialize - start_structured_deserialize;
    const structured_deserialize_ms = @as(f64, @floatFromInt(structured_deserialize_us)) / 1000.0;
    const structured_deserialize_avg_ms = structured_deserialize_ms / @as(f64, @floatFromInt(ITERATIONS));

    std.debug.print("Structured deserialization total time: {d:.4} ms\n", .{structured_deserialize_ms});
    std.debug.print("Structured deserialization average time: {d:.4} ms\n", .{structured_deserialize_avg_ms});

    // Измерение сериализации
    const start_serialize = std.time.microTimestamp();
    i = 0;
    while (i < ITERATIONS) : (i += 1) {
        // Сначала десериализуем динамический JSON
        const parsed = try json.parseFromSlice(json.Value, gpa, json_string, .{});
        defer parsed.deinit();

        // Затем сериализуем
        var string = std.ArrayList(u8).init(gpa);
        defer string.deinit();
        try json.stringify(parsed.value, .{}, string.writer());
    }
    const end_serialize = std.time.microTimestamp();

    const serialize_us = end_serialize - start_serialize;
    const serialize_ms = @as(f64, @floatFromInt(serialize_us)) / 1000.0;
    const serialize_avg_ms = serialize_ms / @as(f64, @floatFromInt(ITERATIONS));

    std.debug.print("Serialization total time: {d:.4} ms\n", .{serialize_ms});
    std.debug.print("Serialization average time: {d:.4} ms\n", .{serialize_avg_ms});

    // Рассчет пропускной способности
    const dynamic_deserialize_throughput = @as(f64, @floatFromInt(file_size * ITERATIONS)) / (dynamic_deserialize_ms / 1000) / 1_000_000;
    const serialize_throughput = @as(f64, @floatFromInt(file_size * ITERATIONS)) / (serialize_ms / 1000) / 1_000_000;

    std.debug.print("Dynamic deserialization throughput: {d:.2} MB/s\n", .{dynamic_deserialize_throughput});

    if (structured_worked) {
        const structured_deserialize_throughput = @as(f64, @floatFromInt(file_size * ITERATIONS)) / (structured_deserialize_ms / 1000) / 1_000_000;
        std.debug.print("Structured deserialization throughput: {d:.2} MB/s\n", .{structured_deserialize_throughput});
    }

    std.debug.print("Serialization throughput: {d:.2} MB/s\n", .{serialize_throughput});
}

// Вспомогательная функция для определения, можно ли использовать структурный парсинг
fn isSimpleJsonExample(allocator: std.mem.Allocator, json_string: []const u8) !bool {
    // Сначала проверяем, имеет ли JSON ожидаемую структуру
    const parsed = try json.parseFromSlice(json.Value, allocator, json_string, .{});
    defer parsed.deinit();

    const root = parsed.value;

    // Проверяем, является ли корневой элемент объектом
    if (root != .object) return false;

    // Проверяем наличие основных полей нашей структуры
    return if (root.object.get("name") != null and
        root.object.get("items") != null and
        root.object.get("metadata") != null and
        root.object.get("config") != null) true else false;
}
