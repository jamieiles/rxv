// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "MemoryDevice.h"

#include <iostream>
#include <fstream>
#include <termios.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>

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
        : IOPeripheral(base, len)
        , log_file(log_file)
        , log_open(false)
        , dlab_enabled(false)
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
        (void)len;

        uint8_t data = *v;

        switch (static_cast<RegMap>(offset)) {
        case THR:
            if (!dlab_enabled) {
                if (::write(STDIN_FILENO, v, 1) != 1)
                    throw std::runtime_error("failed to write stdout");
                open_log();
                log.write(v, 1);
                log.flush();
            }
            break;
        case LCR: dlab_enabled = !!(data & (1 << 7)); break;
        default: break;
        }
    }

    void read(uint32_t offset, char *v, size_t len)
    {
        (void)offset;
        (void)len;

        uint32_t val = 0;

        switch (static_cast<RegMap>(offset)) {
        case RHR:
            if (!dlab_enabled) {
                char c;

                if (::read(STDIN_FILENO, &c, 1) == 1)
                    val = c;
            }
            break;
        case LCR: val = dlab_enabled << 7; break;
        case LSR:
            // Transmitter always empty
            val = 3 << 5;
            if (data_ready())
                val |= (1 << 0);
            break;
        default: break;
        }

        if (len == sizeof(uint32_t))
            memcpy(v, &val, len);
    }

private:
    enum RegMap {
        RHR = 0,
        THR = 0,
        IER = 4,
        ISR = 8,
        FCR = 12,
        LCR = 12,
        MCR = 16,
        LSR = 20,
        MSR = 24,
        SCRATCH = 28,
        DLL = 0,
        DLM = 4,
        PD = 20
    };

    bool data_ready()
    {
        struct pollfd pfd;

        pfd.fd = STDIN_FILENO;
        pfd.events = POLLIN;

        if (poll(&pfd, 1, 0) < 0)
            throw std::runtime_error("failed to poll stdin");

        return pfd.revents & POLLIN;
    }

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
    bool dlab_enabled;
};