format ELF64

section ".bss" writeable
    snake_x       dq 30, 29, 28, 27, 26, 25, 24, 23, 22, 21
                  rq 246
    snake_y       dq 15, 15, 15, 15, 15, 15, 15, 15, 15, 15
                  rq 246
    snake_len     dq 10
    rows          dq 0
    cols          dq 0
    dir           dq 0    ; 0 = right, 1 = up, 2 = left, 3 = down
    head          dq 0
    saved_termios rb 60
    termios_saved db 0    ; whether the termios has been saved
    input_buffer  rb 4096 ; raw term input is only 4096 characters
    input_buffer_len = $ - input_buffer


section ".text" executable

RIGHT = 0
UP    = 1
LEFT  = 2
DOWN  = 3

TIOCGWINSZ = 0x5413
TCGETS     = 0x5401
TCSETSF    = 0x5404
ECHO       = 0x0008
ICANON     = 0x0002
BRKINT     = 0x0002
ICRNL      = 0x0100
ISTRIP     = 0x0020
IXON       = 0x0400

STDIN_FD  = 0
STDOUT_FD = 1
STDERR_FD = 2

SYS_READ       = 0x00
SYS_WRITE      = 0x01
SYS_EXIT       = 0x3c
SYS_IOCTL      = 0x10
SYS_NANOSLEEP  = 0x23

CSI equ 0x1b, "["

; return
;     rax = rows
;     rbx = columns
window_size:
    push rbp
    mov rbp, rsp

    sub rsp, 8           ; Allocate struct winsize
    mov rax, SYS_IOCTL
    mov rdi, STDOUT_FD
    mov rsi, TIOCGWINSZ
    mov rdx, rsp
    syscall

    ; rax -> ws_row
    mov rax, [rsp]
    shr rax, 0
    and rax, 0xffff
    ; rbx -> ws_col
    mov rbx, [rsp]
    shr rbx, 16
    and rbx, 0xffff

    mov rsp, rbp
    pop rbp
    ret

; rax is input
print_dec:
    push rbp
    mov rbp, rsp

    mov rcx, 0
.loop:
    mov rdx, 0
    mov r8, 10
    div r8

    add edx, '0'
    ; push char onto stack
    sub rsp, 1
    mov [rsp], dl
    inc rcx

    test eax, eax
    jnz .loop

    mov rax, SYS_WRITE
    mov rdi, STDOUT_FD
    mov rsi, rsp
    mov rdx, rcx
    syscall

    mov rsp, rbp
    pop rbp
    ret

draw_screen:
    push rbp
    mov rbp, rsp

    ; move to origin
    mov rax, SYS_WRITE
    mov rdi, STDOUT_FD
    mov rsi, move_origin
    mov rdx, move_origin_len
    syscall

    ; clear the screen
    mov rax, SYS_WRITE
    mov rdi, STDOUT_FD
    mov rsi, clear_screen
    mov rdx, clear_screen_len
    syscall

    ; draw snake
    mov rcx, [snake_len]
    test rcx, rcx
    jz .loop_end
.loop:
    push rcx

    ; print "\033"
    mov rax, SYS_WRITE
    mov rdi, STDOUT_FD
    mov rsi, csi
    mov rdx, csi_len
    syscall

    mov rcx, [rsp]
    mov rax, qword [snake_y+(rcx-1)*8]
    call print_dec
    mov rcx, [rsp]

    mov rax, ';'
    push rax

    mov rax, SYS_WRITE
    mov rdi, STDOUT_FD
    mov rsi, rsp
    mov rdx, 1
    syscall
    pop rax

    mov rcx, [rsp]
    mov rax, qword [snake_x+(rcx-1)*8]
    shl rax, 1
    call print_dec

    mov rax, SYS_WRITE
    mov rdi, STDOUT_FD
    mov rsi, snake_print_end
    mov rdx, snake_print_end_len
    syscall

    pop rcx
    dec rcx
    test rcx, rcx
    jnz .loop
.loop_end:

    mov rsp, rbp
    pop rbp
    ret

update_snake:
    push rbp
    mov rbp, rsp

    mov rcx, [head]
    mov r8, [snake_x+rcx*8]
    mov r9, [snake_y+rcx*8]

    cmp [dir], RIGHT
    jne .up
    ; move right
    inc r8
    jmp .done
.up:
    cmp [dir], UP
    jne .left
    ; move up
    dec r9
    jmp .done
.left:
    cmp [dir], LEFT
    jne .down
    ; move left
    dec r8
    jmp .done
.down:
    cmp [dir], DOWN
    jne .done
    ; move down
    inc r9
.done:

    ; Get the tail by doing
    ; (head + snake_len - 1) % snake_len
     add rcx, [snake_len]
     sub rcx, 1
     mov rdx, 0
     mov rax, rcx
     div qword [snake_len]
     mov rcx, rdx


    ; Get the tail
    ; (if head == 0 { snake_len } else { head }) - 1
;     mov rcx, [head]
;     test rcx, rcx
;     jnz .not_zero
;     mov rcx, [snake_len]
; .not_zero:
;     sub rcx, 1

    ; update old tail to be the new values
    mov [snake_x+rcx*8], r8
    mov [snake_y+rcx*8], r9

    ; update the head to be the new location
    mov [head], rcx

    mov rsp, rbp
    pop rbp
    ret


sleep:
    push rbp
    mov rbp, rsp

    pushq 50_000_000 ; 500 ms
    pushq 0

    mov rax, SYS_NANOSLEEP
    mov rdi, rsp
    mov rsi, 0
    syscall

    mov rsp, rbp
    pop rbp
    ret

enter_raw_mode:
    push rbp
    mov rbp, rsp


    ; tcgetattr(fd, &saved_termios)
    mov rax, SYS_IOCTL
    mov rdi, STDIN_FD
    mov rsi, TCGETS
    mov rdx, saved_termios
    syscall

    ; termios_saved = true
    mov [termios_saved], 1

    ; Copy termios_saved to the stack
    sub rsp, 60
    mov rax, SYS_IOCTL
    mov rdi, STDIN_FD
    mov rsi, TCGETS
    mov rdx, rsp
    syscall

    ; echo off, canonical mode off
    ; buf.c_lflag &= ~(ECHO | ICANON)
    and dword [rsp+12], not (ECHO or ICANON)

    ; buf.c_cc[VMIN] = 0
    VMIN = 6
    VTIME = 6
    mov byte [rsp+17+VMIN], 0
    mov byte [rsp+17+VTIME], 0

    ; tcsetattr(fd, TCSAFLUSH, &buf)
    mov rax, SYS_IOCTL
    mov rdi, STDIN_FD
    mov rsi, TCSETSF
    mov rdx, rsp
    syscall
    add rsp, 60

    mov rsp, rbp
    pop rbp
    ret

reset_tty:
    push rbp
    mov rbp, rsp

    cmp [termios_saved], 1
    jne .return

    ; tcsetattr(fd, TCSAFLUSH, &buf)
    mov rax, SYS_IOCTL
    mov rdi, STDIN_FD
    mov rsi, TCSETSF
    mov rdx, saved_termios
    syscall

.return:
    mov rsp, rbp
    pop rbp
    ret

read_input:
    push rbp
    mov rbp, rsp

    ; read byte from stdin
    mov rax, SYS_READ
    mov rdi, STDIN_FD
    mov rsi, input_buffer
    mov rdx, input_buffer_len
    syscall
    mov rdx, rax

    ; push last entered character onto the stack
    dec rdx
    mov dl, [input_buffer+rdx]

; h -> left
    cmp dl, 'h'
    jne .down

    ; skip if already going horizontally
    mov rdx, [dir]
    and rdx, 1
    test rdx, rdx
    jz .done

    mov [dir], LEFT
    jmp .done
.down:
; j -> down
    cmp dl, 'j'
    jne .up

    ; skip if already going vertically
    mov rdx, [dir]
    and rdx, 1
    test rdx, rdx
    jnz .done

    mov [dir], DOWN
    jmp .done
.up:
; k -> up
    cmp dl, 'k'
    jne .right

    ; skip if already going vertically
    mov rdx, [dir]
    and rdx, 1
    test rdx, rdx
    jnz .done

    mov [dir], UP
    jmp .done
.right:
; l -> right
    cmp dl, 'l'
    jne .quit

    ; skip if already going horizontally
    mov rdx, [dir]
    and rdx, 1
    test rdx, rdx
    jz .done

    mov [dir], RIGHT
    jmp .done
.quit:
    cmp dl, 'q'
    jne .done
    call quit ; -> !
.done:

    mov rsp, rbp
    pop rbp
    ret

check_collisions:
    push rbp
    mov rbp, rsp

    mov r9, [head]
    mov r8, [snake_x+r9*8]
    mov r9, [snake_y+r9*8]

; check for overlap
    mov rcx, [snake_len]
    test rcx, rcx
    jz .loop_end
.loop:
    push rcx

    cmp rcx, [head]
    je .continue

    mov rax, [snake_x+rcx*8]
    cmp rax, r8
    jne .continue

    mov rax, [snake_y+rcx*8]
    cmp rax, r9
    jne .continue

    jmp die

.continue:
    pop rcx
    dec rcx
    test rcx, rcx
    jnz .loop
.loop_end:

    test r8, r8
    jz die

    test r9, r9
    jz die

    cmp r8, [cols]
    jae die

    cmp r9, [rows]
    jae die


    mov rsp, rbp
    pop rbp
    ret
    

; NEVER RETURNS
quit:
    call reset_tty

    mov rax, SYS_EXIT
    mov rdi, 0
    syscall

die:
    call draw_screen

    ; You died message
    mov rax, SYS_WRITE
    mov rdi, STDOUT_FD
    mov rsi, you_died
    mov rdx, you_died_len
    syscall
    
    call quit

public _start
_start:
    mov rax, SYS_WRITE
    mov rdi, STDOUT_FD
    mov rsi, hide_cursor
    mov rdx, hide_cursor_len
    syscall

    call window_size
    mov [rows], rax
    add [rows], 2
    mov [cols], rbx
    add [cols], 2
    shr qword [cols], 1

    call enter_raw_mode

.loop:
    call draw_screen
    call update_snake
    call check_collisions
    call sleep
    
    call read_input
    jmp .loop

    call quit ; -> !

newline: db 10
newline_len = $ - newline

csi: db CSI
csi_len = $ - csi

move_origin: db CSI, "0;0H"
move_origin_len = $ - move_origin

clear_screen: db CSI, "2J"
clear_screen_len = $ - clear_screen

snake_print_end: db "H██"
snake_print_end_len = $ - snake_print_end

hide_cursor: db CSI, "?25l"
hide_cursor_len = $ - hide_cursor

you_died: db CSI, "999999;0H", CSI, "31mYou Died!", CSI, "0m", 10
you_died_len = $ - you_died
