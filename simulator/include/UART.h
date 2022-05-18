#pragma once

#include "MemoryDevice.h"

#include <iostream>
#include <fstream>
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
    UART(uint32_t base, size_t len, const std::string &log_file)
        : IOPeripheral(base, len), log_file(log_file), log_open(false)
    {
    }

    virtual ~UART()
    {
        if (log_open) {
            log.close();
            log_open = false;
        }
    }

    void write(uint32_t offset, const char *v, size_t len)
    {
        (void)offset;
        (void)len;

        if (::write(STDIN_FILENO, v, 1) != 1)
            throw std::runtime_error("failed to write stdout");

        open_log();
        log.write(v, 1);
        log.flush();
    }

    void read(uint32_t offset, char *v, size_t len)
    {
        (void)offset;
        (void)len;

        char c;
        uint32_t val = 0;
        if (::read(STDIN_FILENO, &c, 1) == 1)
            val = 0x100 | c;

        if (len == sizeof(uint32_t))
            memcpy(v, &val, len);
    }

private:
    void open_log()
    {
        if (log_open)
            return;

        log.open(log_file, std::ios::out | std::ios::binary);

        log_open = true;
    }

    RawTTY raw_tty;
    std::string log_file;
    std::ofstream log;
    bool log_open;
};