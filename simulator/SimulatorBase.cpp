// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include <vector>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

#include <fmt/core.h>

#include "RiscVELF.h"
#include "RXVSim.h"

void SimulatorBase::load_elf(const RiscVELF &elf)
{
    for (auto &seg : elf.load_segments())
        for (size_t offs = 0; offs < seg.second.size(); ++offs)
            write_phys_mem<uint8_t>(seg.first + offs, seg.second[offs]);

    write_pc(elf.entry_point());
    fencei();
}

void SimulatorBase::load_binary(const std::string &path, uint32_t base)
{
    int fd = open(path.c_str(), O_RDONLY);
    if (fd < 0)
        throw std::runtime_error("failed to open " + path);

    struct stat s;
    if (fstat(fd, &s) < 0)
        throw std::runtime_error("failed to stat binary file");

    fmt::print(stderr, "loading {0} at {1:08x}\r\n", path, base);

    std::unique_ptr<char[]> buf(new char[s.st_size]);
    if (read(fd, buf.get(), s.st_size) != s.st_size)
        throw std::runtime_error("failed to read file");

    for (ssize_t m = 0; m < s.st_size; ++m, ++base)
        write_phys_mem<uint8_t>(base, buf[m]);

    close(fd);
}

std::string SimulatorBase::read_phys_string(uint32_t addr)
{
    std::string str;

    for (;;) {
        auto v = read_phys_mem<char>(addr++);
        if (!v)
            break;
        str += v;
    }

    return str;
}