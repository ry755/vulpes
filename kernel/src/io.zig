pub inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "N{dx}" (port),
    );
}

pub inline fn insl(port: u16, address: *void, count: u32) void {
    var a = address;
    var c = count;
    asm volatile ("cld; rep insl"
        : [address1] "={edi}" (a),
          [count1] "={ecx}" (c),
        : [port] "{edx}" (port),
          [address2] "0" (a),
          [count2] "1" (c),
        : "memory", "cc"
    );
}

pub inline fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "N{dx}" (port),
    );
}

pub inline fn outsl(port: u16, address: *void, count: u32) void {
    var a = address;
    var c = count;
    asm volatile ("cld; rep outsl"
        : [address1] "={esi}" (a),
          [count1] "={ecx}" (c),
        : [port] "{edx}" (port),
          [address2] "0" (a),
          [count2] "1" (c),
        : "cc"
    );
}
