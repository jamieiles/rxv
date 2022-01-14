#pragma once

#include "MemoryDevice.h"

#include <termios.h>
#include <unistd.h>
#include <fcntl.h>

class RawTTY
{
public:
    RawTTY()
    {
        if (!isatty(STDOUT_FILENO))
            return;

        if (tcgetattr(STDIN_FILENO, &old_termios))
            throw std::runtime_error("Failed to get termios");

        auto termios = old_termios;
        cfmakeraw(&termios);
        termios.c_cc[VMIN] = 0;
        termios.c_cc[VTIME] = 0;
        termios.c_lflag |= ISIG;
        termios.c_cc[VINTR] = 0;
        if (tcsetattr(STDIN_FILENO, TCSANOW, &termios))
            throw std::runtime_error("Failed to set new termios");
    }

    virtual ~RawTTY()
    {
        if (!isatty(STDOUT_FILENO))
            return;
        tcsetattr(STDIN_FILENO, TCSANOW, &old_termios);
    }

private:
    struct termios old_termios;
};

class UART : public IOPeripheral
{
public:
    UART(uint32_t base, size_t len) : IOPeripheral(base, len)
    {
    }

    void write(uint32_t offset, const char *v, size_t len)
    {
        if (::write(STDIN_FILENO, v, 1) != 1)
            throw std::runtime_error("failed to write stdout");
    }

    void read(uint32_t offset, char *v, size_t len)
    {
        char c;
        uint32_t val = 0;
        if (::read(STDIN_FILENO, &c, 1) == 1)
            val = 0x100 | c;

        if (len == sizeof(uint32_t))
            memcpy(v, &val, len);
    }

private:
    RawTTY raw_tty;
};