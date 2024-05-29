// currently only the PIT is supported

const std = @import("std");
const event = @import("event.zig");
const gfx = @import("gfx.zig");
const io = @import("io.zig");
const isr = @import("isr.zig");
const mouse = @import("mouse.zig");
const winmgr = @import("winmgr.zig");
const writer = @import("serial.zig").writer;

var ticks: u64 = 0;
var mouse_coords: gfx.Point = .{ .x = 0, .y = 0 };
var mouse_coords_old: gfx.Point = undefined;
var mouse_buttons: mouse.Buttons = .{ .left = false, .middle = false, .right = false };
var mouse_buttons_old: mouse.Buttons = undefined;

pub fn initialize() void {
    // mode 2
    io.outb(0x43, 0x36);

    // 100 Hz
    io.outb(0x40, 11931 & 0x00FF);
    io.outb(0x40, (11931 & 0xFF00) >> 8);

    isr.install_handler(0, interrupt_handler);
}

pub fn interrupt_handler() void {
    ticks = @addWithOverflow(ticks, 1)[0];
    if (ticks % 2 == 0) {
        mouse_coords = mouse.coordinates;
        mouse_buttons = mouse.buttons;
        if (mouse_coords.x != mouse_coords_old.x or
            mouse_coords.y != mouse_coords_old.y)
        {
            gfx.move_cursor(&mouse_coords);
            mouse_coords_old = mouse_coords;
        }

        if (mouse_buttons.left != mouse_buttons_old.left) {
            var event_params = std.mem.zeroes([8]u32);
            event_params[0] = 0;
            const e = event.Event{
                .event_type = if (mouse_buttons.left) .mouse_down else .mouse_up,
                .parameters = event_params,
            };
            event.new_event(e) catch writer.print("failed to create new mouse event!\n", .{}) catch unreachable;
        }

        if (mouse_buttons.middle != mouse_buttons_old.middle) {
            var event_params = std.mem.zeroes([8]u32);
            event_params[0] = 1;
            const e = event.Event{
                .event_type = if (mouse_buttons.middle) .mouse_down else .mouse_up,
                .parameters = event_params,
            };
            event.new_event(e) catch writer.print("failed to create new mouse event!\n", .{}) catch unreachable;
        }

        if (mouse_buttons.right != mouse_buttons_old.right) {
            var event_params = std.mem.zeroes([8]u32);
            event_params[0] = 2;
            const e = event.Event{
                .event_type = if (mouse_buttons.right) .mouse_down else .mouse_up,
                .parameters = event_params,
            };
            event.new_event(e) catch writer.print("failed to create new mouse event!\n", .{}) catch unreachable;
        }

        gfx.blit_buffered_framebuffer_to_hw();
    }
    winmgr.update();
}

pub fn get_ticks() u64 {
    return ticks;
}
