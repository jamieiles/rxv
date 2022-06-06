#include "common.h"
#include "string.h"
#include "printk.h"
#include "uart.h"
#include "sd.h"
#include "spi.h"
#include <stdint.h>

#define SD_NCR 64
#define DATA_START_TOKEN 0xfe

static void sd_initial_clocks(void)
{
    unsigned char buf[16];
    int i;

    for (i = 0; i < sizeof(buf); ++i)
        buf[i] = 0xff;

    spi_xfer(buf, sizeof(buf), SPI_F_NO_CS);
}

struct spi_cmd {
    unsigned char cmd;
    unsigned char arg[4];
    unsigned char crc;

    const unsigned char *data;
    unsigned long tx_datalen;
    unsigned long rx_datalen;
};

struct r1_response {
    unsigned char v;
};

#define R1_ERROR_MASK 0xfe

static void spi_do_command(const struct spi_cmd *cmd, int flags)
{
    size_t m, cmdlen;

    cmdlen = 1 + 6 + cmd->tx_datalen + cmd->rx_datalen + SD_NCR;

    /* The command. */
    spi_cmd_buf[0] = 0xff;

    spi_cmd_buf[1] = cmd->cmd;
    for (m = 0; m < 4; ++m)
        spi_cmd_buf[2 + m] = cmd->arg[m];
    spi_cmd_buf[6] = cmd->crc;
    /* Transmit data. */
    for (m = 0; m < cmd->tx_datalen; ++m)
        spi_cmd_buf[7 + m] = cmd->data[m];
    /* Initialize receive buffer so we don't shift out new, garbage data. */
    for (m = 7 + cmd->tx_datalen; m < cmdlen; ++m)
        spi_cmd_buf[m] = 0xff;

    spi_xfer(spi_cmd_buf, cmdlen, flags);
}

static const unsigned char *find_r1_response(struct r1_response *r1)
{
    const unsigned char *p = spi_cmd_buf + 7;

    r1->v = 0;
    while (p < spi_cmd_buf + sizeof(spi_cmd_buf) && *p == 0xff)
        ++p;

    if (p == spi_cmd_buf + sizeof(spi_cmd_buf))
        return NULL;

    r1->v = *p;

    return p;
}

static int send_reset(void)
{
    struct spi_cmd cmd = {
        .cmd = 0x40,
        .crc = 0x95,
        .rx_datalen = 1,
    };
    struct r1_response r1;

    spi_do_command(&cmd, 0);
    if (!find_r1_response(&r1))
        return -1;

    if (!(r1.v & 0x1)) {
        return -1;
    }

    return r1.v & R1_ERROR_MASK;
}

static int send_if_cond(void)
{
    struct spi_cmd cmd = {
        .cmd = 0x48,
        .crc = 0x87,
        .arg = {0x00, 0x00, 0x01, 0xaa},
        .rx_datalen = 1,
    };
    struct r1_response r1;

    spi_do_command(&cmd, 0);
    if (!find_r1_response(&r1))
        return -1;

    return r1.v & R1_ERROR_MASK;
}

static int send_read_ocr(void)
{
    struct spi_cmd cmd = {
        .cmd = 0x7a,
        .rx_datalen = 5,
    };
    struct r1_response r1;

    spi_do_command(&cmd, 0);
    if (!find_r1_response(&r1))
        return -1;

    return r1.v & R1_ERROR_MASK;
}

static int send_acmd(void)
{
    struct spi_cmd cmd = {
        .cmd = 0x77,
        .arg = {0x00, 0x00, 0x00, 0x00},
        .rx_datalen = 1,
    };
    struct r1_response r1;

    spi_do_command(&cmd, 0);
    if (!find_r1_response(&r1))
        return -1;

    return r1.v & R1_ERROR_MASK;
}

static int sd_wait_ready(void)
{
    struct r1_response r1 = {};

    do {
        struct spi_cmd cmd = {
            .cmd = 0x69,
            .arg = {0x40, 0x00, 0x00, 0x00},
            .rx_datalen = 1,
        };
        int rc = send_acmd();

        if (rc)
            return rc;

        spi_do_command(&cmd, 0);
        if (!find_r1_response(&r1))
            return -1;

        if (r1.v & R1_ERROR_MASK)
            return r1.v & R1_ERROR_MASK;
    } while (r1.v & 0x1);

    return 0;
}

static int sd_set_blocklen(void)
{
    struct spi_cmd cmd = {
        .cmd = 0x50,
        /* BLOCK_SIZE bytes */
        .arg = {0x00, 0x00, 0x02, 0x00},
        .rx_datalen = 1,
    };
    struct r1_response r1;

    spi_do_command(&cmd, 0);
    if (!find_r1_response(&r1))
        return -1;

    return r1.v & R1_ERROR_MASK;
}

static void copy_block(unsigned char *dst, const unsigned char *src)
{
    unsigned m;

    for (m = 0; m < BLOCK_SIZE; ++m)
        dst[m] = src[m];
}

int read_sector(unsigned long address, unsigned char *dst)
{
    struct spi_cmd cmd = {
        .cmd = 0x51,
        .arg = {(address >> 24) & 0xff, (address >> 16) & 0xff,
                (address >> 8) & 0xff, (address >> 0) & 0xff},
        .rx_datalen = 1,
    };
    struct r1_response r1;
    const unsigned char *r1ptr;

    spi_do_command(&cmd, SPI_F_HOLD_CS);
    r1ptr = find_r1_response(&r1);
    if (!r1ptr) {
        putstr("failed to find r1 response\n");
        return -1;
    }
    if (r1.v & R1_ERROR_MASK) {
        putstr("read sector failed\n");
        return -1;
    }

    do {
        spi_cmd_buf[0] = 0xff;
        spi_xfer(spi_cmd_buf, 1, SPI_F_HOLD_CS);
    } while (spi_cmd_buf[0] != DATA_START_TOKEN);

    int i;
    // Block + CRC (ignored)
    for (i = 0; i < BLOCK_SIZE + 2; ++i)
        spi_cmd_buf[i] = 0xff;
    spi_xfer(spi_cmd_buf, BLOCK_SIZE + 2, 0);

    copy_block(dst, spi_cmd_buf);

    return 0;
}

void sd_init(void)
{
    int c = -1;

    spi_init();

    while (c != 0) {
        sd_initial_clocks();
        c = send_reset();
    }
    putstr("SD card idle\n");
    if (send_if_cond() || send_read_ocr() || sd_wait_ready() ||
        sd_set_blocklen())
        panic("unable to initialize SD card");
}