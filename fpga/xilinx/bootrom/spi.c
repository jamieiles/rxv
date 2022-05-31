#include "spi.h"

#define SPI_SRR_OFFSET 0x40
#define SPI_SRR_RESET 0xa
#define SPI_SPICR_OFFSET 0x60
#define SPI_SPICR_SPE (1 << 1)
#define SPI_SPICR_MASTER (1 << 2)
#define SPI_SPICR_FIFO_RESET (3 << 5)
#define SPI_SPICR_MANUAL_SS (1 << 7)
#define SPI_SPICR_INHIBIT (1 << 8)
#define SPI_SPICR_LSB_FIRST (1 << 9)
#define SPI_SPISR_OFFSET 0x64
#define SPI_SPISR_RX_EMPTY (1 << 0)
#define SPI_SPISR_RX_FULL (1 << 1)
#define SPI_SPISR_TX_EMPTY (1 << 2)
#define SPI_SPISR_TX_FULL (1 << 3)
#define SPI_DTR_OFFSET 0x68
#define SPI_DRR_OFFSET 0x6c
#define SPI_SSR_OFFSET 0x70
#define SPI_TX_FIFO_OCC_OFFSET 0x74
#define SPI_RX_FIFO_OCC_OFFSET 0x78
#define SPI_DGIER_OFFSET 0x1c
#define SPI_IPISR_OFFSET 0x20
#define SPI_IPIER_OFFSET 0x28

unsigned char spi_cmd_buf[32 * 1024];

void spi_init(void)
{
    void *spi_mmio = (void *)0xfffe0000;

    writel(SPI_SRR_RESET, spi_mmio + SPI_SRR_OFFSET);
    writel(SPI_SPICR_SPE | SPI_SPICR_MASTER | SPI_SPICR_MANUAL_SS |
               SPI_SPICR_INHIBIT,
           spi_mmio + SPI_SPICR_OFFSET);
    writel(~0, spi_mmio + SPI_SSR_OFFSET);
}

void spi_xfer(unsigned char *buf, size_t len, int flags)
{
    size_t sent = 0;
    unsigned char *rx_pos = buf;
    void *spi_mmio = (void *)0xfffe0000;

    writel(readl(spi_mmio + SPI_SPICR_OFFSET) | SPI_SPICR_INHIBIT,
           spi_mmio + SPI_SPICR_OFFSET);

    if (!(flags & SPI_F_NO_CS))
        writel(~1, spi_mmio + SPI_SSR_OFFSET);
    else
        writel(~0, spi_mmio + SPI_SSR_OFFSET);

    while (sent < len) {
        int tx = 0, rx = 0;

        while (!(readl(spi_mmio + SPI_SPISR_OFFSET) & SPI_SPISR_TX_FULL) &&
               sent < len) {
            writel(buf[sent++], spi_mmio + SPI_DTR_OFFSET);
            ++tx;
        }

        writel(readl(spi_mmio + SPI_SPICR_OFFSET) & ~SPI_SPICR_INHIBIT,
               spi_mmio + SPI_SPICR_OFFSET);

        while (!(readl(spi_mmio + SPI_SPISR_OFFSET) & SPI_SPISR_TX_EMPTY))
            continue;

        while (rx != tx) {
            while (readl(spi_mmio + SPI_SPISR_OFFSET) & SPI_SPISR_RX_EMPTY)
                continue;
            *rx_pos++ = readl(spi_mmio + SPI_DRR_OFFSET);
            ++rx;
        }

        writel(readl(spi_mmio + SPI_SPICR_OFFSET) | SPI_SPICR_INHIBIT,
               spi_mmio + SPI_SPICR_OFFSET);
    }

    if (!(flags & SPI_F_HOLD_CS))
        writel(~0, spi_mmio + SPI_SSR_OFFSET);
}
