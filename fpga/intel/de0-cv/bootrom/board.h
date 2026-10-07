#pragma once

/* DE0-CV bootrom configuration. */

#define BOARD_DTB_NAME u"DE0CV.DTB"

/* The mtime reference is 10MHz from the PLL. */
#define BOARD_TIMER_HZ 10000000
#define BOARD_US_TO_TICKS(us) ((uint64_t)(us) * 10)

/* The uncached window onto the framebuffer at the top of the SDRAM. */
#define BOARD_FB_BASE 0xf8000000

/* The SD host controller's base clock, the system clock. */
#define BOARD_SDHCI_BASE_KHZ 60000

/* The console UART, read out over JTAG. */
#define BOARD_CONSOLE_UART 0xffff1000
