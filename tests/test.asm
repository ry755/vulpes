    bits 32
    org 0x01000000

    mov eax, 1     ; new_window
    push dword 128 ; height
    push dword 128 ; width
    push dword 32  ; y
    push dword 32  ; x
    int 48
    add esp, 16
    mov dword [window], eax

    mov eax, 9        ; draw_string
    push dword string ; str
    int 48
    add esp, 4

event_loop:
    mov eax, 8          ; get_next_window_event
    push dword event    ; event
    push dword [window] ; window
    int 48
    add esp, 8

    cmp dword [event], 3 ; mouse_down
    jne event_loop

    ; if we reach this point then a mouse_down event was sent
    mov eax, 5          ; start_dragging_window
    push dword [window] ; window
    int 48
    add esp, 4
    jmp event_loop

    ret

align 4
window: dd 0
string:
    db "hello world!", 10
    db "this is a user", 10
    db "program!", 0
align 4
event:
    dd 0
event_parameters:
    times 8 dd 0
