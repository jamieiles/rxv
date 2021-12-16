#include "VerilogTestbench.h"
#include "VRXVRegisterFile.h"

class RegFileTestbench
    : public VerilogTestbench<VRXVRegisterFile>
    , public ::testing::Test
{
public:
    RegFileTestbench()
    {
        periodic(ClockCapture, [&] {
            this->port_a_data = this->dut.rd_data_a;
            this->port_b_data = this->dut.rd_data_b;
        });
    }

    void write(uint8_t addr, uint32_t v)
    {
        after_n_cycles(0, [&] {
            this->dut.wr_en = 1;
            this->dut.wr_addr = addr;
            this->dut.wr_data = v;
            after_n_cycles(0, [&] { this->dut.wr_en = 0; });
        });
        cycle();
    }

    enum port { PORT_A, PORT_B };

    uint32_t read(uint8_t addr, enum port port)
    {
        after_n_cycles(0, [&] {
            if (port == PORT_A)
                this->dut.rd_addr_a = addr;
            else
                this->dut.rd_addr_b = addr;
        });
        cycle(2);

        return port == PORT_A ? port_a_data : port_b_data;
    }

private:
    uint32_t port_a_data;
    uint32_t port_b_data;
};

TEST_F(RegFileTestbench, RegX1ToX31Writable)
{
    for (uint8_t r = 1; r <= 31; ++r)
        write(r, r << 8);

    for (uint8_t r = 1; r <= 31; ++r)
        EXPECT_EQ(r << 8, read(r, PORT_A));
    for (uint8_t r = 1; r <= 31; ++r)
        EXPECT_EQ(r << 8, read(r, PORT_B));
}

TEST_F(RegFileTestbench, RegX0WritesIgnored)
{
    write(0, ~0);
    EXPECT_EQ(0, read(0, PORT_A));
    EXPECT_EQ(0, read(0, PORT_B));
}

TEST_F(RegFileTestbench, NoWriteIdle)
{
    this->dut.wr_addr = 1;
    this->dut.wr_data = 0xffffffff;
    cycle(8);

    EXPECT_EQ(0, read(1, PORT_A));
}