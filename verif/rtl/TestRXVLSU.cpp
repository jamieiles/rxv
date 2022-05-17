#include "VerilogTestbench.h"
#include "VRXVLSUWrapper.h"
#include "VRXVLSUWrapper_RXVLSUWrapper.h"
#include "VRXVLSUWrapper_BusTransactor.h"
#include "VRXVLSUWrapper_RXVTypes.h"
#include "VRXVLSUWrapper_RXVCSR.h"
#include "MemoryDevice.h"

static const int nr_lines = 4;
static const int nr_ways = 4;
static const int line_size_bytes = 16;
static const int lsu_timeout = 128;

class LSUTestbench
    : public VerilogTestbench<VRXVLSUWrapper>
    , public ::testing::Test
{
public:
    LSUTestbench() : next_id(0)
    {
        this->dut.exec_valid = 0;
        reset();
        bus = std::make_shared<MemoryBus>(0x80000000, 64 * 1024 * 1024);
        this->dut.RXVLSUWrapper->BusTransactor->set_bus(bus);
        this->dut.current_privilege =
            VRXVLSUWrapper_RXVCSR::privilege_t::PRIV_M;

        periodic(ClockCapture, [&] {
            if (this->dut.dcache_valid) {
                uint32_t addr = this->dut.dcache_address;
                after_n_cycles(1, [&, addr] {
                    this->dut.tlb_valid = 1;
                    this->dut.tlb_accessed = 1;
                    this->dut.tlb_dirty = 1;
                    this->dut.tlb_exec = 1;
                    this->dut.tlb_read = 1;
                    this->dut.tlb_write = 1;
                    this->dut.tlb_exec = 1;
                    this->dut.tlb_user = 1;
                    this->dut.tlb_valid = 1;
                    this->dut.tlb_pa = addr >> 10;
                });
            }
        });
    }

    void dispatch_read(uint32_t addr, size_t size, bool is_signed = false)
    {
        VRXVLSUWrapper_RXVTypes::rxv_uop uop;

        switch (size) {
        case 1:
            uop = is_signed ? VRXVLSUWrapper_RXVTypes::rxv_uop::UOP_LB
                            : VRXVLSUWrapper_RXVTypes::rxv_uop::UOP_LBU;
            break;
        case 2:
            uop = is_signed ? VRXVLSUWrapper_RXVTypes::rxv_uop::UOP_LH
                            : VRXVLSUWrapper_RXVTypes::rxv_uop::UOP_LHU;
            break;
        case 4: uop = VRXVLSUWrapper_RXVTypes::rxv_uop::UOP_LW; break;
        default: abort();
        }

        after_n_cycles(0, [&] {
            this->dut.exec_valid = 1;
            this->dut.exec_have_writeback = 1;
            this->dut.exec_rd = 10;
            this->dut.exec_id = this->next_id++;
            this->dut.op1 = addr;
            this->dut.op2 = 0xdeadbeef;
            this->dut.exec_immed = 0;
            this->dut.exec_uop = uop;

            after_n_cycles(1, [&] { this->dut.exec_valid = 0; });
        });

        cycle();
    }

    void dispatch_write(uint32_t addr, uint32_t v, size_t size)
    {
        VRXVLSUWrapper_RXVTypes::rxv_uop uop;

        switch (size) {
        case 1: uop = VRXVLSUWrapper_RXVTypes::rxv_uop::UOP_SB; break;
        case 2: uop = VRXVLSUWrapper_RXVTypes::rxv_uop::UOP_SH; break;
        case 4: uop = VRXVLSUWrapper_RXVTypes::rxv_uop::UOP_SW; break;
        default: abort();
        }

        after_n_cycles(0, [&] {
            this->dut.exec_valid = 1;
            this->dut.exec_have_writeback = 0;
            this->dut.exec_rd = 0;
            this->dut.exec_id = this->next_id++;
            this->dut.op1 = addr;
            this->dut.op2 = v;
            this->dut.exec_immed = 0;
            this->dut.exec_uop = uop;

            after_n_cycles(1, [&] { this->dut.exec_valid = 0; });
        });

        cycle();
    }

    void wait_for_completion()
    {
        int i = 0;

        do {
            cycle();
            if (i++ == lsu_timeout)
                FAIL() << "uop did not complete";
        } while (!(this->dut.lsu_complete || is_excepted()));
    }

    bool is_excepted() const
    {
        return this->dut.RXVCSR->exception_valid(this->dut.lsu_exception);
    }

    uint32_t exception_pc() const
    {
        return this->dut.RXVCSR->exception_pc(this->dut.lsu_exception) << 2;
    }

    uint32_t exception_val() const
    {
        return this->dut.RXVCSR->exception_val(this->dut.lsu_exception);
    }

    VRXVLSUWrapper_RXVCSR::CAUSE_id exception_cause() const
    {
        return static_cast<VRXVLSUWrapper_RXVCSR::CAUSE_id>(
            this->dut.RXVCSR->exception_cause(this->dut.lsu_exception));
    }

    std::shared_ptr<MemoryBus> bus;
    int next_id;
};

TEST_F(LSUTestbench, ReadWord)
{
    this->bus->write(0x80001004, 0xaa55a5a5, 0xf);

    dispatch_read(0x80001004, 4);
    wait_for_completion();
    EXPECT_TRUE(this->dut.lsu_reg_wr_en);
    EXPECT_EQ(this->dut.lsu_reg_addr, 10);
    EXPECT_EQ(this->dut.lsu_reg_wr_data, 0xaa55a5a5);
}

TEST_F(LSUTestbench, ReadWordUnaligned)
{
    this->bus->write(0x80001004, 0xaa55a5a5, 0xf);

    dispatch_read(0x80001005, 4);
    wait_for_completion();
    EXPECT_TRUE(is_excepted());
    EXPECT_EQ(exception_cause(), VRXVLSUWrapper_RXVCSR::CAUSE_LOAD_MISALIGN);
    EXPECT_EQ(this->dut.lsu_except_id, 0);
}

TEST_F(LSUTestbench, PipelinedReadWord)
{
    this->bus->write(0x80001004, 0xaa55a5a5, 0xf);
    this->bus->write(0x80001008, 0xdefaced0, 0xf);

    dispatch_read(0x80001004, 4);
    wait_for_completion();
    EXPECT_TRUE(this->dut.lsu_reg_wr_en);
    EXPECT_EQ(this->dut.lsu_reg_addr, 10);
    EXPECT_EQ(this->dut.lsu_reg_wr_data, 0xaa55a5a5);

    // Cache is now warmed, can perform pipelined reads without a hazard
    dispatch_read(0x80001004, 4);
    dispatch_read(0x80001008, 4);

    cycle(32);
}

TEST_F(LSUTestbench, ReadUnsignedByte)
{
    this->bus->write(0x80001004, 0xaa55a5a5, 0xf);

    dispatch_read(0x80001007, 1);
    wait_for_completion();
    EXPECT_TRUE(this->dut.lsu_reg_wr_en);
    EXPECT_EQ(this->dut.lsu_reg_addr, 10);
    EXPECT_EQ(this->dut.lsu_reg_wr_data, 0xaa);

    dispatch_read(0x80001006, 1);
    wait_for_completion();
    EXPECT_TRUE(this->dut.lsu_reg_wr_en);
    EXPECT_EQ(this->dut.lsu_reg_addr, 10);
    EXPECT_EQ(this->dut.lsu_reg_wr_data, 0x55);
}

TEST_F(LSUTestbench, StoreToLoad)
{
    this->bus->write(0x80001004, 0xaa55a5a5, 0xf);
    this->bus->write(0x80001008, 0xdefaced0, 0xf);

    dispatch_read(0x80001004, 4);
    wait_for_completion();
    EXPECT_TRUE(this->dut.lsu_reg_wr_en);
    EXPECT_EQ(this->dut.lsu_reg_addr, 10);
    EXPECT_EQ(this->dut.lsu_reg_wr_data, 0xaa55a5a5);

    // Cache is now warmed, can perform pipelined accesses without a hazard
    dispatch_write(0x80001004, 0x12345678, 4);
    dispatch_read(0x80001004, 4);
    wait_for_completion();
    EXPECT_EQ(this->dut.lsu_complete_id, 1);
    wait_for_completion();
    EXPECT_EQ(this->dut.lsu_complete_id, 2);
    EXPECT_TRUE(this->dut.lsu_reg_wr_en);
    EXPECT_EQ(this->dut.lsu_reg_addr, 10);
    EXPECT_EQ(this->dut.lsu_reg_wr_data, 0x12345678);
}

TEST_F(LSUTestbench, HazardKill)
{
    this->bus->write(0x80001004, 0xaa55a5a5, 0xf);
    this->bus->write(0x80001008, 0xdefaced0, 0xf);

    dispatch_read(0x80001004, 4);
    dispatch_read(0x80001008, 4);

    cycle(32);
}
