#pragma once

#define BLOCK_SIZE 512

void sd_init(void);
int read_sector(unsigned long address, unsigned char *dst);
