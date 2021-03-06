#include <kernel/gdt.h>
#include <kernel/idt.h>
#include <kernel/pic.h>
#include <kernel/pit.h>
#include <kernel/klib.h>
#include <mm/pmm.h>

static void isr_timer()
{
    static char c = 0;
    display_char(20, 10, c++);
}

/* C entry */
void cstart(void *mm)
{
    init_gdt();
    init_idt();
    init_pic();
    init_pit(50);
    init_pmm((memory_map_entry_t *)((uint32_t *)mm + 1), *(uint32_t *)mm);

    pic_register_isr(IRQ0, isr_timer);
}
