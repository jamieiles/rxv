#pragma once

#include "common.h"

extern unsigned char spi_cmd_buf[32 * 1024];

#define SPI_F_NO_CS (1 << 0)
#define SPI_F_HOLD_CS (1 << 1)

void spi_init(void);
void spi_xfer(unsigned char *buf, size_t len, int flags);
