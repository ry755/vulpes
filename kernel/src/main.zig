const std = @import("std");
const builtin = std.builtin;
const event = @import("event.zig");
const fat = @import("fat.zig");
const gdt = @import("gdt.zig");
const gfx = @import("gfx.zig");
const ide = @import("ide.zig");
const idt = @import("idt.zig");
const isr = @import("isr.zig");
const kbd = @import("kbd.zig");
const mbr = @import("mbr.zig");
const mouse = @import("mouse.zig");
const multiboot = @import("multiboot.zig");
const pic = @import("pic.zig");
const ps2 = @import("ps2.zig");
const serial = @import("serial.zig");
const timer = @import("timer.zig");
const winmgr = @import("winmgr.zig");
const writer = serial.writer;

extern fn enter_user_program() callconv(.C) void;

export fn kernel_main(multiboot_info: *multiboot.MultibootInfo) void {
    gdt.initialize();
    serial.initialize();
    timer.initialize();
    pic.initialize();
    ide.initialize();
    ps2.initialize();
    mouse.initialize();
    gfx.initialize(
        @truncate(multiboot_info.framebuffer_addr),
        multiboot_info.framebuffer_pitch,
        multiboot_info.framebuffer_bpp,
        0x1E1E2E,
        multiboot_info.framebuffer_red_field_position,
        multiboot_info.framebuffer_green_field_position,
        multiboot_info.framebuffer_blue_field_position,
    );
    idt.initialize();
    mbr.initialize();
    fat.initialize(
        0,
        &ide.read,
        &ide.write,
        mbr.mbr.partitions[0].lba_first_sector,
    );
    fat.global_fat.mount("0:", true) catch @panic("failed to mount 0:");
    defer fat.global_fat.unmount("0:");
    read_font("0:/font.bin");
    read_bg("0:/bg.raw");
    winmgr.initialize();

    writer.print("kernel initialization done\n", .{}) catch unreachable;
    //test_loop();

    const load_address: [*]u8 = @ptrFromInt(0x01000000);
    var test_file = fat.fatfs.File.openRead("0:/test.bin");
    var file = test_file catch @panic("failed to open test.bin!");
    defer file.close();
    var file_reader = file.reader();
    _ = file_reader.read(load_address[0..512]) catch @panic("failed to read test.bin!");

    writer.print("entering user program\n", .{}) catch unreachable;
    enter_user_program();
    writer.print("returned from user program\n", .{}) catch unreachable;

    while (true) {}
}

pub fn panic(message: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
    writer.print("\nPANIC!\n{s}\n", .{message}) catch unreachable;
    gfx.set_framebuffer(&winmgr.bg_framebuffer);
    gfx.move_to(&gfx.Point{ .x = 0, .y = 0 });
    gfx.set_color(0xFFFFFF, 0xFF0000);
    gfx.writer.print("PANIC! {s}", .{message}) catch unreachable;
    while (true) {}
}

fn test_loop() noreturn {
    _ = winmgr.new_window(64, 64, 256, 128) catch @panic("failed to create new window");
    gfx.move_to(&gfx.Point{ .x = 0, .y = 0 });
    gfx.draw_string("hello world!\na: add window\nr: remove window\ns: swap window");

    while (true) {
        if (winmgr.current_window) |w| {
            const we = winmgr.get_next_event(w);
            switch (we.event_type) {
                .key_down => {
                    switch (kbd.scancode_to_ascii(@truncate(we.parameters[0]))) {
                        'a' => {
                            var window = winmgr.new_window(mouse.coordinates.x, mouse.coordinates.y, 256, 128) catch @panic("failed to create new window");
                            gfx.move_to(&gfx.Point{ .x = 0, .y = 0 });
                            gfx.draw_string("hello world!\n");
                            gfx.writer.print("i am {*}", .{window}) catch unreachable;
                        },
                        'r' => {
                            winmgr.destroy_window(w);
                        },
                        's' => {
                            if (winmgr.window_under_cursor()) |w2| {
                                writer.print("window under cursor: {*}\n", .{w2}) catch unreachable;
                                winmgr.set_drawing_window(w2);
                                winmgr.bring_window_to_foreground(w2);
                            }
                        },
                        else => {},
                    }
                },
                .mouse_down => {
                    winmgr.start_dragging_window(w);
                },
                else => {},
            }
        }
    }
}

fn read_font(path: [:0]const u8) void {
    var font_file = fat.fatfs.File.openRead(path);
    var font = font_file catch @panic("failed to open font.bin!");
    defer font.close();
    var font_reader = font.reader();
    _ = font_reader.read(&gfx.default_font_data) catch @panic("failed to read font.bin!");
}

fn read_bg(path: [:0]const u8) void {
    var bg_file = fat.fatfs.File.openRead(path);
    var bg = bg_file catch return;
    defer bg.close();
    var bg_reader = bg.reader();
    _ = bg_reader.read(&winmgr.bg_framebuffer_data) catch return;
    gfx.invalidate_whole_framebuffer_chain(&winmgr.bg_framebuffer);
}
