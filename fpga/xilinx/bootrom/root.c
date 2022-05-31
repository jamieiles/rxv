#include "common.h"
#include "string.h"
#include "printk.h"
#include "uart.h"
#include "fat.h"
#include "disk.h"
#include "sd.h"
#include "spi.h"
#include <stdint.h>

static const char *banner =
    "\n\n"
    " ███████   ██     ██ ██      ██\n"
    "░██░░░░██ ░░██   ██ ░██     ░██\n"
    "░██   ░██  ░░██ ██  ░██     ░██\n"
    "░███████    ░░███   ░░██    ██\n"
    "░██░░░██     ██░██   ░░██  ██\n"
    "░██  ░░██   ██ ░░██   ░░████\n"
    "░██   ░░██ ██   ░░██   ░░██\n"
    "░░     ░░ ░░     ░░     ░░\n";
static const uint32_t entrypoint = 0x80000000;

struct boot_file {
    const uint16_t *name;
    uint32_t load_address;
    int required;
};

void panic(const char *str)
{
    putstr(str);
    putstr("\n");

    for (;;)
        continue;
}

static void jump_payload(void)
{
    asm volatile(
        "fence.i\n\t"
        "jr %0" ::"r"(entrypoint));
}

static const struct boot_file boot_files[] = {
    {.name = u"OPENSBI.BIN", .load_address = 0x80000000, .required = 1},
    {.name = u"IMAGE.BIN", .load_address = 0x80400000, .required = 0},
    {}};

static int load_one_file(struct fat_superblock *sb,
                         const uint16_t *name,
                         uint32_t load_address)
{
    unsigned long offs = fat_root_dir_offs(sb);
    int err = -1;

    for (;;) {
        struct fat_dirent dirent = {};

        err = fat_read_dirent(sb, &dirent, &offs);
        if (err == -1)
            return err;

        if (!wstrcmp(dirent.name, name)) {
            if (!fat_dirent_is_dir(&dirent)) {
                printk("Reading %ls (%u bytes)\n", name, dirent.size);
                fat_read_buf(sb, &dirent, (void *)load_address, dirent.size, 0);
                putstr("\n");

                return 0;
            }
        }
    }

    return 0;
}

static int load_files(struct fat_superblock *sb)
{
    const struct boot_file *bf = boot_files;
    int rc = 0;

    while (bf->name) {
        rc = load_one_file(sb, bf->name, bf->load_address);
        if (rc && bf->required) {
            printk("ERROR: required file %ls not found\n", bf->name);
            return -1;
        } else if (rc) {
            printk("Skipping optional not-present file %ls\n", bf->name);
            rc = 0;
        }

        ++bf;
    }

    return rc;
}

void root(void)
{
    static unsigned char sector_buf[512];
    unsigned long start = 0, size = 0;
    struct fat_superblock sb;

    uart_init();

    putstr(banner);
    putstr("BootROM " __DATE__ " " __TIME__ "\n");

    sd_init();

    putstr("Finding boot partition\n");
    find_boot_partition(&start, &size);
    putstr("Reading boot sector\n");
    if (read_sector(start, sector_buf))
        panic("unable to read fatfs sector");

    sb.partition_lba = start;
    fat_decode_boot_sect(sector_buf, &sb);

    if (load_files(&sb))
        panic("failed to load");
    putstr("Loaded, jumping to entry point\n");
    jump_payload();

    __builtin_unreachable();
}
