const std = @import("std");
const event = @import("event.zig");
const gfx = @import("gfx.zig");
const heap = @import("heap.zig");
const mouse = @import("mouse.zig");
const writer = @import("serial.zig").writer;

pub const Window = struct {
    next: ?*Window,
    prev: ?*Window,
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

pub fn update() void {
    const e = event.get_next_event();
    if (current_window) |w| {
        new_event(w, e) catch {};
    }
}

pub fn window_under_cursor() ?*Window {
    var window_to_check: ?*Window = current_window;
    while (window_to_check != null) {
        if ((mouse.coordinates.x >= window_to_check.?.*.x) and
            (mouse.coordinates.y >= window_to_check.?.*.y) and
            (mouse.coordinates.x <= window_to_check.?.*.x + window_to_check.?.*.width) and
            (mouse.coordinates.y <= window_to_check.?.*.y + window_to_check.?.*.height))
        {
            return window_to_check.?;
        }
        window_to_check = window_to_check.?.*.next;
    }
    return null;
}

pub fn new_window(x: u32, y: u32, width: u32, height: u32) !*Window {
    const window: *Window = try heap.allocator.create(Window);
    errdefer heap.allocator.destroy(window);
    window.*.next = null;
    window.*.prev = null;
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
    errdefer heap.allocator.free(framebuffer_data);
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

    bring_window_to_foreground(window);
    set_drawing_window(window);

    return window;
}

pub fn destroy_window(window: *Window) void {
    // move this window to the front of the stack
    // this is required for the code below
    bring_window_to_foreground(window);

    // remove this window from the linked list of framebuffers
    var list: ?*gfx.Framebuffer = &bg_framebuffer;
    while (list.?.*.next != null) {
        if (list.?.*.next == window.*.framebuffer) {
            list.?.*.next = list.?.*.next.?.*.next;
            break;
        }
        list = list.?.*.next;
    }

    // remove this window from the linked list of windows
    current_window = current_window.?.next;
    if (current_window != null)
        current_window.?.prev = null;

    heap.allocator.free(window.*.framebuffer.*.data[0 .. window.*.framebuffer.*.width * window.*.framebuffer.*.height * 4]);
    heap.allocator.destroy(window.*.framebuffer);
    heap.allocator.destroy(window);

    var w: ?*Window = current_window;
    writer.print("w ", .{}) catch unreachable;
    while (w != null) {
        writer.print("{*}", .{w}) catch unreachable;
        w = w.?.*.next;
        if (w != null)
            writer.print("->", .{}) catch unreachable;
    }
    writer.print("\n", .{}) catch unreachable;

    var fb: ?*gfx.Framebuffer = &bg_framebuffer;
    writer.print("fb ", .{}) catch unreachable;
    while (fb != null) {
        writer.print("{*}", .{fb}) catch unreachable;
        fb = fb.?.*.next;
        if (fb != null)
            writer.print("->", .{}) catch unreachable;
    }
    writer.print("\n", .{}) catch unreachable;

    gfx.invalidate_whole_framebuffer_chain(&bg_framebuffer);
}

pub fn start_dragging_window(window: *Window) void {
    const point = gfx.Point{
        .x = mouse.coordinates.x -% window.x,
        .y = mouse.coordinates.y -% window.y,
    };
    while (mouse.buttons.left) {
        window.*.x = mouse.coordinates.x -% point.x;
        window.*.y = mouse.coordinates.y -% point.y;
        window.*.framebuffer.*.x = mouse.coordinates.x -% point.x;
        window.*.framebuffer.*.y = mouse.coordinates.y -% point.y;
        gfx.invalidate_whole_framebuffer(window.*.framebuffer);
    }
    gfx.invalidate_whole_framebuffer_chain(&bg_framebuffer);
}

pub fn move_window_to(window: *Window, point: *const gfx.Point) void {
    window.*.x = point.*.x;
    window.*.y = point.*.y;
    window.*.framebuffer.*.x = point.*.x;
    window.*.framebuffer.*.y = point.*.y;
    gfx.invalidate_whole_framebuffer_chain(&bg_framebuffer);
}

pub fn set_drawing_window(window: *Window) void {
    gfx.set_framebuffer(window.*.framebuffer);
}

pub fn bring_window_to_foreground(window: *Window) void {
    // bring this window to the front
    if (current_window != null) {
        move_window_to_front(window);
    } else {
        bg_framebuffer.next = window.*.framebuffer;
        current_window = window;
    }
    gfx.invalidate_whole_framebuffer_chain(&bg_framebuffer);

    var w: ?*Window = current_window;
    writer.print("w ", .{}) catch unreachable;
    while (w != null) {
        writer.print("{*}", .{w}) catch unreachable;
        w = w.?.*.next;
        if (w != null)
            writer.print("->", .{}) catch unreachable;
    }
    writer.print("\n", .{}) catch unreachable;

    var fb: ?*gfx.Framebuffer = &bg_framebuffer;
    writer.print("fb ", .{}) catch unreachable;
    while (fb != null) {
        writer.print("{*}", .{fb}) catch unreachable;
        fb = fb.?.*.next;
        if (fb != null)
            writer.print("->", .{}) catch unreachable;
    }
    writer.print("\n", .{}) catch unreachable;
}

pub fn new_event(window: *Window, window_event: event.Event) !void {
    const node = try heap.allocator.create(event.QueueNode);
    node.* = .{ .data = window_event, .next = null };
    if (window.event_end) |e| e.next = node else window.event_start = node;
    window.event_end = node;
}

pub fn get_next_event(window: *Window) event.Event {
    const s = window.*.event_start orelse return event.Event{
        .event_type = event.EventType.empty,
        .parameters = std.mem.zeroes([8]u32),
    };
    defer heap.allocator.destroy(s);
    if (s.next) |next| {
        window.*.event_start = next;
    } else {
        window.*.event_start = null;
        window.*.event_end = null;
    }
    return s.data;
}

fn move_window_to_front(window: *Window) void {
    if (current_window == window) return;

    // move the passed window's fb to the end
    var list: ?*gfx.Framebuffer = &bg_framebuffer;
    while (list.?.*.next != null) {
        if (list.?.*.next == window.*.framebuffer)
            list.?.*.next = list.?.*.next.?.*.next;
        list = list.?.*.next;
    }
    list.?.*.next = window.*.framebuffer;
    window.*.framebuffer.*.next = null;

    // move the passed window to the beginning
    const prev = window.*.prev;
    if (prev != null)
        prev.?.*.next = window.*.next;
    if (window.*.next != null)
        window.*.next.?.*.prev = prev;
    window.*.next = current_window;
    current_window.?.*.prev = window;
    window.*.prev = null;
    current_window = window;
}
