// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
//
// Boot console on the VGA framebuffer: 80x30 characters of 8x16 in
// 640x480 RGB565, written through the uncached framebuffer window.  The
// text is kept in a shadow buffer so that scrolling only writes the
// framebuffer.  UTF-8 is decoded for the glyphs in font.c (ASCII and the
// block characters in the banner).
#include <stdint.h>

#include "common.h"
#include "console.h"
#include "board.h"

#define WIDTH 640
#define HEIGHT 480
#define GLYPH_WIDTH 8
#define GLYPH_HEIGHT 16
#define COLS (WIDTH / GLYPH_WIDTH)
#define ROWS (HEIGHT / GLYPH_HEIGHT)

#define FG 0xc618
#define BG 0x0000

extern const uint32_t font_codepoints[];
extern const uint8_t font_glyphs[][GLYPH_HEIGHT];
extern const unsigned font_num_glyphs;

static volatile uint32_t *const fb = (volatile uint32_t *)BOARD_FB_BASE;
static uint8_t text[ROWS][COLS];
static unsigned col, row;
static uint32_t utf8_cp;
static unsigned utf8_remaining;

static uint8_t glyph_index(uint32_t cp)
{
    if (cp >= 0x20 && cp <= 0x7e)
        return cp - 0x20;
    for (unsigned i = 0; i < font_num_glyphs; ++i)
        if (font_codepoints[i] == cp)
            return i;
    return '?' - 0x20;
}

static void draw(unsigned r, unsigned c, uint8_t glyph)
{
    const uint8_t *bits = font_glyphs[glyph];
    // Two pixels per word, pixel 2n in the low half.
    volatile uint32_t *p = fb + (r * GLYPH_HEIGHT * WIDTH + c * GLYPH_WIDTH) / 2;

    for (unsigned y = 0; y < GLYPH_HEIGHT; ++y, p += WIDTH / 2) {
        uint8_t b = bits[y];
        for (unsigned x = 0; x < GLYPH_WIDTH / 2; ++x, b <<= 2) {
            uint32_t lo = (b & 0x80) ? FG : BG;
            uint32_t hi = (b & 0x40) ? FG : BG;
            p[x] = lo | (hi << 16);
        }
    }
}

static void put_glyph(uint8_t glyph)
{
    text[row][col] = glyph;
    draw(row, col, glyph);
}

static void newline(void)
{
    col = 0;
    if (++row < ROWS)
        return;

    row = ROWS - 1;
    for (unsigned r = 0; r < ROWS; ++r)
        for (unsigned c = 0; c < COLS; ++c) {
            uint8_t g = r + 1 < ROWS ? text[r + 1][c] : 0;
            if (text[r][c] != g) {
                text[r][c] = g;
                draw(r, c, g);
            }
        }
}

void console_init(void)
{
    for (unsigned i = 0; i < WIDTH * HEIGHT / 2; ++i)
        fb[i] = (BG << 16) | BG;
    // The shadow is in .bss so is already spaces (glyph 0).
    col = row = 0;
    utf8_remaining = 0;
}

void console_putc(int c)
{
    uint8_t ch = c;

    if (utf8_remaining) {
        utf8_cp = (utf8_cp << 6) | (ch & 0x3f);
        if (--utf8_remaining)
            return;
    } else if ((ch & 0xe0) == 0xc0) {
        utf8_cp = ch & 0x1f;
        utf8_remaining = 1;
        return;
    } else if ((ch & 0xf0) == 0xe0) {
        utf8_cp = ch & 0x0f;
        utf8_remaining = 2;
        return;
    } else {
        utf8_cp = ch;
    }

    switch (utf8_cp) {
    case '\n':
        newline();
        return;
    case '\r':
        col = 0;
        return;
    case '\b':
        if (col)
            --col;
        return;
    default:
        break;
    }

    if (col == COLS)
        newline();
    put_glyph(glyph_index(utf8_cp));
    ++col;
}
