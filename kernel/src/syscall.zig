const event = @import("event.zig");
const gfx = @import("gfx.zig");
const winmgr = @import("winmgr.zig");
const writer = @import("serial.zig").writer;

var current_syscall_esp: u32 = undefined;
const syscalls = enum(u32) {
    new_window = 1,
    destroy_window = 2,
    bring_window_to_foreground = 3,
    set_drawing_window = 4,
    start_dragging_window = 5,
    move_window_to = 6,
    new_window_event = 7,
    get_next_window_event = 8,
    draw_string = 9,
};

pub fn syscall(eax: u32, esp: u32) u32 {
    current_syscall_esp = esp;
    const syscall_num = eax;
    asm volatile ("sti");
    writer.print("syscall_num: {x}, esp: {x}\n", .{ syscall_num, esp }) catch unreachable;
    switch (@as(syscalls, @enumFromInt(syscall_num))) {
        .new_window => {
            const x = fetch_syscall_u32(0);
            const y = fetch_syscall_u32(1);
            const width = fetch_syscall_u32(2);
            const height = fetch_syscall_u32(3);
            writer.print("calling winmgr.new_window({}, {}, {}, {})\n", .{ x, y, width, height }) catch unreachable;
            const window = winmgr.new_window(
                x,
                y,
                width,
                height,
            ) catch return 0;
            return @intFromPtr(window);
        },
        .destroy_window => {
            const window: *winmgr.Window = @ptrFromInt(fetch_syscall_u32(0));
            writer.print("calling winmgr.destroy_window({*})\n", .{window}) catch unreachable;
            winmgr.destroy_window(window);
        },
        .bring_window_to_foreground => {
            const window: *winmgr.Window = @ptrFromInt(fetch_syscall_u32(0));
            writer.print("calling winmgr.bring_window_to_foreground({*})\n", .{window}) catch unreachable;
            winmgr.bring_window_to_foreground(window);
        },
        .set_drawing_window => {
            const window: *winmgr.Window = @ptrFromInt(fetch_syscall_u32(0));
            writer.print("calling winmgr.set_drawing_window({*})\n", .{window}) catch unreachable;
            winmgr.set_drawing_window(window);
        },
        .start_dragging_window => {
            const window: *winmgr.Window = @ptrFromInt(fetch_syscall_u32(0));
            writer.print("calling winmgr.start_dragging_window({*})\n", .{window}) catch unreachable;
            winmgr.start_dragging_window(window);
        },
        .move_window_to => {
            const window: *winmgr.Window = @ptrFromInt(fetch_syscall_u32(0));
            const point: *gfx.Point = @ptrFromInt(fetch_syscall_u32(1));
            writer.print("calling winmgr.move_window_to({*}, {*})\n", .{ window, point }) catch unreachable;
            winmgr.move_window_to(window, point);
        },
        .new_window_event => {
            const window: *winmgr.Window = @ptrFromInt(fetch_syscall_u32(0));
            var event_parameters: [8]u32 = undefined;
            event_parameters[0] = fetch_syscall_u32(2);
            event_parameters[1] = fetch_syscall_u32(3);
            event_parameters[2] = fetch_syscall_u32(4);
            event_parameters[3] = fetch_syscall_u32(5);
            event_parameters[4] = fetch_syscall_u32(6);
            event_parameters[5] = fetch_syscall_u32(7);
            event_parameters[6] = fetch_syscall_u32(8);
            event_parameters[7] = fetch_syscall_u32(9);
            const window_event = event.Event{
                .event_type = @enumFromInt(fetch_syscall_u32(1)),
                .parameters = event_parameters,
            };
            writer.print("calling winmgr.new_event({*}, {})\n", .{ window, window_event }) catch unreachable;
            winmgr.new_event(window, window_event) catch
                writer.print("failed to create new window event!\n", .{}) catch unreachable;
        },
        .get_next_window_event => {
            const window: *winmgr.Window = @ptrFromInt(fetch_syscall_u32(0));
            writer.print("calling winmgr.get_next_event({*})... ", .{window}) catch unreachable;
            const e = winmgr.get_next_event(window);
            writer.print("got {}... ", .{e}) catch unreachable;
            const ptr: [*]u32 = @ptrFromInt(fetch_syscall_u32(1));
            writer.print("writing event data to {*}\n", .{ptr}) catch unreachable;
            ptr[0] = @intFromEnum(e.event_type);
            ptr[1] = e.parameters[0];
            ptr[2] = e.parameters[1];
            ptr[3] = e.parameters[2];
            ptr[4] = e.parameters[3];
            ptr[5] = e.parameters[4];
            ptr[6] = e.parameters[5];
            ptr[7] = e.parameters[6];
            ptr[8] = e.parameters[7];
        },
        .draw_string => {
            const str: [*:0]u8 = @ptrFromInt(fetch_syscall_u32(0));
            writer.print("calling gfx.draw_c_string({*})\n", .{str}) catch unreachable;
            gfx.draw_c_string(str);
        },
    }
    return 0;
}

fn fetch_u32(address: u32) u32 {
    const ptr: *u32 = @ptrFromInt(address);
    return ptr.*;
}

fn fetch_syscall_u32(n: u32) u32 {
    // fetch nth syscall argument
    return fetch_u32(current_syscall_esp + 28 + (4 * n));
}
