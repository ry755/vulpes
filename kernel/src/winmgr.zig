const std = @import("std");
const event = @import("event.zig");
const gfx = @import("gfx.zig");
const heap = @import("heap.zig");

const Window = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    event_start: ?*event.QueueNode,
    event_end: ?*event.QueueNode,
    framebuffer: *gfx.Framebuffer,
};

pub var current_window: ?*Window = null;

pub var bg_framebuffer_data = std.mem.zeroes([640 * 480 * 4]u8);
pub var bg_framebuffer = gfx.Framebuffer{
    .next = null,
    .child = null,
    .data = &bg_framebuffer_data,
    .x = 0,
    .y = 0,
    .width = 640,
    .height = 480,
    .pitch = 640 * 4,
    .bpp = 32,
    .dirty = gfx.Rectangle{ .x1 = 0, .y1 = 0, .x2 = 0, .y2 = 0 },
    .has_alpha = false,
};

pub fn initialize() void {
    gfx.invalidate_whole_framebuffer(&bg_framebuffer);
    gfx.main_framebuffer.child = &bg_framebuffer;
}

pub fn new_window(x: u32, y: u32, width: u32, height: u32) !*Window {
    var window: *Window = try heap.allocator.create(Window);
    errdefer heap.allocator.destroy(window);
    window.*.x = x;
    window.*.y = y;
    window.*.width = width;
    window.*.height = height;
    window.*.event_start = null;
    window.*.event_end = null;
    window.*.framebuffer = try heap.allocator.create(gfx.Framebuffer);
    errdefer heap.allocator.destroy(window.*.framebuffer);
    window.*.framebuffer.*.next = null;
    window.*.framebuffer.*.child = null;
    const framebuffer_data = try heap.allocator.alloc(u8, width * height * 4);
    window.*.framebuffer.*.data = framebuffer_data.ptr;
    errdefer heap.allocator.destroy(window.*.framebuffer.*.data);
    window.*.framebuffer.*.x = x;
    window.*.framebuffer.*.y = y;
    window.*.framebuffer.*.width = width;
    window.*.framebuffer.*.height = height;
    window.*.framebuffer.*.pitch = width * 4;
    window.*.framebuffer.*.bpp = 32;
    window.*.framebuffer.*.dirty = gfx.Rectangle{ .x1 = 0, .y1 = 0, .x2 = 0, .y2 = 0 };
    window.*.framebuffer.*.has_alpha = false;

    @memset(window.*.framebuffer.*.data[0 .. width * height * 4], 0);
    gfx.invalidate_whole_framebuffer(window.*.framebuffer);

    // insert the new window into the linked list of framebuffers
    const old_next = bg_framebuffer.next;
    bg_framebuffer.next = window.*.framebuffer;
    window.*.framebuffer.next = old_next;

    set_window(window);

    return window;
}

pub fn destroy_window(window: *Window) void {
    // remove this window from the linked list of framebuffers
    bg_framebuffer.next = window.*.framebuffer.*.next;

    heap.allocator.destroy(window.*.framebuffer.*.data);
    heap.allocator.destroy(window.*.framebuffer);
    heap.allocator.destroy(window);
}

pub fn set_window(window: *Window) void {
    gfx.set_framebuffer(window.*.framebuffer);
    current_window = window;
}

pub fn new_event(window: *Window, window_event: event.Event) !void {
    const node = try heap.allocator.create(event.QueueNode);
    node.* = .{ .data = window_event, .next = null };
    if (window.event_end) |e| e.next = node else window.event_start = node;
    window.event_end = node;
}

pub fn get_next_event(window: *Window) event.Event {
    const s = window.event_start orelse return event.Event{
        .event_type = event.EventType.empty,
        .parameters = std.mem.zeroes([8]u32),
    };
    defer heap.allocator.destroy(s);
    if (s.next) |next| {
        window.event_start = next;
    } else {
        window.event_start = null;
        window.event_end = null;
    }
    return s.data;
}
