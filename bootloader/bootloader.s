[bits 16]
    org     0x7c00
    mov     ax, cs
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     esp, 0x7c00
    call    get_memory_map
    call    load_kernel
    jmp     goto_pm

get_memory_map:
    mov     di, 0x7e00
    mov     dword [es:di], 0
    add     di, 4
    xor     ebx, ebx

.getting_mm:
    ; Call int 0x15 0xe820 function, edx = 'SMAP'
    mov     edx, 0x534d4150
    mov     eax, 0xe820
    mov     ecx, 24
    int     0x15

    ; Check result
    jc      .get_mm_error
    cmp     eax, 0x534d4150
    jne     .get_mm_error
    jecxz   .skip_entry
    ; Get entry success
    add     di, 24
    inc     dword [es:0x7e00]

.skip_entry:
    ; There is no more entry when ebx == 0
    cmp     ebx, 0
    je      .get_mm_done
    jmp     .getting_mm

.get_mm_error:
    hlt

.get_mm_done:
    ret

load_kernel:
    push    bp
    mov     bp, sp
    sub     sp, 4
    mov     ax, 0x1000
    mov     es, ax
    mov     ax, 1
    mov     bx, 0

.reading_sectors:
    mov     word [bp - 4], ax
    mov     word [bp - 2], bx
    mov     cl, 1
    call    read_sector

    mov     ax, word [bp - 4]
    cmp     ax, 128
    jz      .load_success
    inc     ax
    mov     bx, word [bp - 2]
    add     bx, 512
    jmp     .reading_sectors

.load_success:
    add     sp, 4
    pop     bp
    ret

; ax: start sector number
; cl: sector count
; es:bx pointer to buffer
read_sector:
    push    bp
    mov     bp, sp
    sub     sp, 2
    mov     byte [bp - 2], cl
    push    bx

    mov     bl, 18
    div     bl
    inc     ah
    mov     dh, al
    and     dh, 1
    shr     al, 1
    mov     ch, al
    pop     bx
    mov     cl, ah
    mov     dl, 0

.retry_reading:
    mov     ah, 2
    mov     al, byte [bp - 2]
    int     13h
    jc      .retry_reading

    add     sp, 2
    pop     bp
    ret

goto_pm:
    cli
    lgdt    [gdtr]
    ; Open A20
    in      al, 0x92
    or      al, 2
    out     0x92, al
    ; Enable PE
    mov     eax, cr0
    or      al, 1
    mov     cr0, eax
    jmp     0x8:protected_mode

[bits 32]
protected_mode:
    ; Prepare video selector
    mov     ax, 0x18
    mov     gs, ax
    ; Other selectors
    mov     ax, 0x10
    mov     ds, ax
    mov     es, ax
    mov     fs, ax
    mov     ss, ax
    call    expand_kernel
    ; Set address of memory map to ebx
    mov     ebx, 0x7e00
    ; Jump into kernel
    jmp     eax

; eax: return value, store entry address
expand_kernel:
    push    ebp
    mov     ebp, esp
    sub     esp, 12

    ; Kernel file pointer
    mov     eax, 0x10000
    ; Entry address
    mov     ebx, dword [eax + 24]
    mov     dword [ebp - 4], ebx
    ; Program head offset
    mov     ebx, dword [eax + 28]
    ; Program head size
    mov     dx, word [eax + 42]
    mov     word [ebp - 10], dx
    ; Program head number
    mov     cx, word [eax + 44]

.expand_all_segments:
    mov     dword [ebp - 8], ebx
    mov     word [ebp - 12], cx
    call    expand_segment
    mov     ebx, dword [ebp - 8]
    movzx   edx, word [ebp - 10]
    add     ebx, edx
    mov     cx, word [ebp - 12]
    dec     cx
    jnz     .expand_all_segments

.expand_kernel_success:
    ; Entry address as return value
    mov     eax, dword [ebp - 4]
    add     esp, 12
    pop     ebp
    ret

; eax: elf file buffer pointer
; ebx: current program head offset
expand_segment:
    add     ebx, eax
    ; Type
    mov     ecx, dword [ebx]
    cmp     ecx, 1
    jz      .expand
    cmp     ecx, 6
    jz      .expand
    jmp     .expand_segment_success

.expand:
    ; File Offset
    mov     ecx, dword [ebx + 4]
    lea     esi, [eax + ecx]
    ; Virtual address
    mov     edi, dword [ebx + 8]
    ; File size
    mov     ecx, dword [ebx + 16]
    cld
    rep     movsb
    ; Clear remain memory
    mov     ecx, dword [ebx + 20]
    sub     ecx, dword [ebx + 16]
    jz      .expand_segment_success

.fill_zero:
    mov     byte [edi], 0
    inc     edi
    loop    .fill_zero

.expand_segment_success:
    ret

gdt_start:
    ; Unused
    dd      0
    dd      0
    ; Code descriptor
    dw      0xFFFF
    dw      0x0
    db      0x0
    db      0x9a
    db      0xC0
    db      0x0
    ; Data descriptor
    dw      0xFFFF
    dw      0x0
    db      0x0
    db      0x92
    db      0xC0
    db      0x0
    ; Video descriptor
    dw      0xFFFF
    dw      0x8000
    db      0x0B
    db      0x92
    db      0xC0
    db      0x0
gdt_len equ $ - gdt_start

gdtr:
    dw     gdt_len - 1
    dd     gdt_start

    times   510 - ($ - $$) db 0
    dw      0xaa55
