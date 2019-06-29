#include <vector>

#include "RiscVELF.h"
#include "RXVSim.h"

void SimulatorBase::load_elf(const RiscVELF &elf)
{
    for (auto &seg : elf.load_segments())
        for (size_t offs = 0; offs < seg.second.size(); ++offs)
            write_mem<uint8_t>(seg.first + offs, seg.second[offs]);

    write_pc(elf.entry_point());
}

std::string SimulatorBase::read_string(uint32_t addr) const
{
    std::string str;

    for (;;) {
        auto v = read_mem<char>(addr++);
        if (!v)
            break;
        str += v;
    }

    return str;
}
