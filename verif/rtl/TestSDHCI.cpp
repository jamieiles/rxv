// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include <random>
#include <vector>

#include <gtest/gtest.h>
#include <VSDHCIWrapper.h>

#include "VerilogTestbench.h"
#include "fixtures/SDCardModel.h"

namespace
{

// SDHCI register offsets
const uint32_t REG_BLOCK_SIZE = 0x04;
const uint32_t REG_BLOCK_COUNT = 0x06;
const uint32_t REG_ARGUMENT = 0x08;
const uint32_t REG_TRANSFER_MODE = 0x0c;
const uint32_t REG_COMMAND = 0x0e;
const uint32_t REG_RESPONSE = 0x10;
const uint32_t REG_BUFFER = 0x20;
const uint32_t REG_PRESENT_STATE = 0x24;
const uint32_t REG_HOST_CONTROL = 0x28;
const uint32_t REG_POWER_CONTROL = 0x29;
const uint32_t REG_CLOCK_CONTROL = 0x2c;
const uint32_t REG_TIMEOUT_CONTROL = 0x2e;
const uint32_t REG_SOFTWARE_RESET = 0x2f;
const uint32_t REG_INT_STATUS = 0x30;
const uint32_t REG_INT_ENABLE = 0x34;
const uint32_t REG_SIGNAL_ENABLE = 0x38;
const uint32_t REG_ACMD12_ERR = 0x3c;
const uint32_t REG_CAPABILITIES = 0x40;
const uint32_t REG_MAX_CURRENT = 0x48;
const uint32_t REG_VENDOR = 0xf0;
const uint32_t REG_SLOT_INT = 0xfc;
const uint32_t REG_HOST_VERSION = 0xfe;

// Interrupt status
const uint32_t INT_CMD_COMPLETE = 1 << 0;
const uint32_t INT_XFER_COMPLETE = 1 << 1;
const uint32_t INT_BUF_WR_READY = 1 << 4;
const uint32_t INT_BUF_RD_READY = 1 << 5;
const uint32_t INT_CARD_INSERT = 1 << 6;
const uint32_t INT_CARD_REMOVE = 1 << 7;
const uint32_t INT_ERROR = 1 << 15;
const uint32_t INT_CMD_TIMEOUT = 1 << 16;
const uint32_t INT_CMD_CRC = 1 << 17;
const uint32_t INT_CMD_INDEX = 1 << 19;
const uint32_t INT_DAT_TIMEOUT = 1 << 20;
const uint32_t INT_DAT_CRC = 1 << 21;
const uint32_t INT_ACMD12 = 1 << 24;

// Present state
const uint32_t PS_CMD_INHIBIT = 1 << 0;
const uint32_t PS_BUF_WR_EN = 1 << 10;
const uint32_t PS_BUF_RD_EN = 1 << 11;
const uint32_t PS_DAT_INHIBIT = 1 << 1;
const uint32_t PS_CARD_INSERTED = 1 << 16;
const uint32_t PS_CARD_STABLE = 1 << 17;
const uint32_t PS_WRITE_ENABLED = 1 << 19;

// Command flags
const uint16_t RESP_NONE = 0x00;
const uint16_t RESP_136 = 0x01 | 0x08;
const uint16_t RESP_R1 = 0x02 | 0x08 | 0x10;
const uint16_t RESP_R1B = 0x03 | 0x08 | 0x10;
const uint16_t RESP_R3 = 0x02;
const uint16_t CMD_DATA = 0x20;

// Transfer mode
const uint16_t TM_BCE = 1 << 1;
const uint16_t TM_AUTO12 = 1 << 2;
const uint16_t TM_READ = 1 << 4;
const uint16_t TM_MULTI = 1 << 5;

const int max_wait = 4000000;

} // namespace

class SDHCITest
    : public VerilogTestbench<VSDHCIWrapper>
    , public ::testing::Test
{
public:
    SDHCITest() : card(256), sdclk_rises(0), last_sdclk(false)
    {
        dut.s_axi_bready = 1;
        dut.s_axi_rready = 1;
        dut.cd_n = 0;
        dut.cmd_i = 1;
        dut.dat_i = 0xf;

        periodic(ClockCapture, [this] {
            card.step(dut.sd_clk, dut.cmd_o, dut.cmd_t, dut.dat_o, dut.dat_t);
            dut.cmd_i = card.cmd_line();
            dut.dat_i = card.dat_lines();
            if (dut.sd_clk && !last_sdclk) {
                ++sdclk_rises;
                rise_cycles.push_back(cur_cycle());
            }
            last_sdclk = dut.sd_clk;
        });

        reset();
        // Let card detect debounce.
        cycle(64);

        std::mt19937 rng(1234);
        for (auto &b : card.disk)
            b = rng();
    }

    ~SDHCITest()
    {
        EXPECT_FALSE(card.contention);
    }

    // ------------------------------------------------------------------
    // AXI4-Lite manager
    // ------------------------------------------------------------------
    void axi_write(uint32_t addr, uint32_t data, uint8_t strb)
    {
        dut.s_axi_awaddr = addr & ~3u;
        dut.s_axi_wdata = data;
        dut.s_axi_wstrb = strb;
        dut.s_axi_awvalid = 1;
        dut.s_axi_wvalid = 1;
        for (;;) {
            dut.eval();
            bool fire = dut.s_axi_awready;
            cycle();
            if (fire)
                break;
        }
        dut.s_axi_awvalid = 0;
        dut.s_axi_wvalid = 0;
        EXPECT_TRUE(dut.s_axi_bvalid);
        EXPECT_EQ(dut.s_axi_bresp, 0);
        cycle();
    }

    uint32_t axi_read(uint32_t addr)
    {
        dut.s_axi_araddr = addr & ~3u;
        dut.s_axi_arvalid = 1;
        for (;;) {
            dut.eval();
            bool fire = dut.s_axi_arready;
            cycle();
            if (fire)
                break;
        }
        dut.s_axi_arvalid = 0;
        EXPECT_TRUE(dut.s_axi_rvalid);
        EXPECT_EQ(dut.s_axi_rresp, 0);
        uint32_t v = dut.s_axi_rdata;
        cycle();
        return v;
    }

    void write32(uint32_t addr, uint32_t v)
    {
        axi_write(addr, v, 0xf);
    }

    void write16(uint32_t addr, uint16_t v)
    {
        unsigned shift = (addr & 2) * 8;
        axi_write(addr, uint32_t(v) << shift, 0x3 << (addr & 2));
    }

    void write8(uint32_t addr, uint8_t v)
    {
        unsigned shift = (addr & 3) * 8;
        axi_write(addr, uint32_t(v) << shift, 0x1 << (addr & 3));
    }

    uint32_t read32(uint32_t addr)
    {
        return axi_read(addr);
    }

    uint16_t read16(uint32_t addr)
    {
        return axi_read(addr) >> ((addr & 2) * 8);
    }

    uint8_t read8(uint32_t addr)
    {
        return axi_read(addr) >> ((addr & 3) * 8);
    }

    // ------------------------------------------------------------------
    // Host driver helpers
    // ------------------------------------------------------------------
    void power_on(uint8_t div = 1, bool enable_ints = true)
    {
        write8(REG_POWER_CONTROL, 0x0f);
        write16(REG_CLOCK_CONTROL, (div << 8) | 0x1);
        EXPECT_TRUE(read16(REG_CLOCK_CONTROL) & 0x2);
        write16(REG_CLOCK_CONTROL, (div << 8) | 0x5);
        write8(REG_TIMEOUT_CONTROL, 0x0);
        if (enable_ints)
            write32(REG_INT_ENABLE, 0xffffffff);
        // Initialization clocks before the first command.
        cycle(200);
    }

    uint32_t wait_int(uint32_t mask, int timeout = max_wait)
    {
        uint32_t status = 0;
        for (int i = 0; i < timeout; i += 8) {
            status = read32(REG_INT_STATUS);
            if (status & (mask | INT_ERROR))
                return status;
        }
        ADD_FAILURE() << "timeout waiting for interrupt " << std::hex << mask;
        return status;
    }

    uint32_t send_cmd(unsigned index,
                      uint32_t arg,
                      uint16_t flags,
                      bool expect_ok = true)
    {
        write32(REG_ARGUMENT, arg);
        write16(REG_COMMAND, (index << 8) | flags);
        auto status = wait_int(INT_CMD_COMPLETE);
        write32(REG_INT_STATUS, status & (INT_CMD_COMPLETE | 0xffff0000));
        if (expect_ok) {
            EXPECT_EQ(status & (INT_ERROR | 0xffff0000), 0u)
                << "CMD" << index << " status " << std::hex << status;
        }
        return status;
    }

    void wait_xfer_complete()
    {
        auto status = wait_int(INT_XFER_COMPLETE);
        EXPECT_TRUE(status & INT_XFER_COMPLETE) << std::hex << status;
        write32(REG_INT_STATUS, INT_XFER_COMPLETE);
    }

    uint16_t init_card(bool wide)
    {
        send_cmd(0, 0, RESP_NONE);
        send_cmd(8, 0x1aa, RESP_R1);
        EXPECT_EQ(read32(REG_RESPONSE), 0x1aau);

        for (int i = 0; i < 10; ++i) {
            send_cmd(55, 0, RESP_R1);
            send_cmd(41, 0x40ff8000, RESP_R3);
            if (read32(REG_RESPONSE) & (1u << 31))
                break;
        }
        EXPECT_TRUE(read32(REG_RESPONSE) & (1u << 31));

        send_cmd(2, 0, RESP_136);
        send_cmd(3, 0, RESP_R1);
        uint16_t rca = read32(REG_RESPONSE) >> 16;
        send_cmd(7, uint32_t(rca) << 16, RESP_R1B);
        wait_xfer_complete();

        if (wide) {
            send_cmd(55, uint32_t(rca) << 16, RESP_R1);
            send_cmd(6, 2, RESP_R1);
            write8(REG_HOST_CONTROL, 0x02);
        }

        return rca;
    }

    void setup_xfer(unsigned blocks, uint16_t mode)
    {
        write16(REG_BLOCK_SIZE, 0x7000 | SDCardModel::block_size);
        write16(REG_BLOCK_COUNT, blocks);
        write16(REG_TRANSFER_MODE, mode);
    }

    std::vector<uint8_t> read_buffer_block(unsigned len = SDCardModel::block_size)
    {
        std::vector<uint8_t> data;
        for (unsigned i = 0; i < (len + 3) / 4; ++i) {
            uint32_t w = read32(REG_BUFFER);
            for (int b = 0; b < 4; ++b)
                data.push_back(w >> (b * 8));
        }
        data.resize(len);
        return data;
    }

    void write_buffer_block(const uint8_t *data)
    {
        for (unsigned i = 0; i < SDCardModel::block_size; i += 4)
            write32(REG_BUFFER, data[i] | (data[i + 1] << 8) |
                                    (data[i + 2] << 16) | (data[i + 3] << 24));
    }

    std::vector<uint8_t> read_blocks(uint32_t start,
                                     unsigned n,
                                     uint16_t mode,
                                     int drain_delay = 0)
    {
        std::vector<uint8_t> data;

        setup_xfer(n, mode | TM_READ);
        send_cmd(n > 1 ? 18 : 17, start, RESP_R1 | CMD_DATA);

        // As Linux does: one interrupt may cover several buffered blocks so
        // drain while Buffer Read Enable is set.
        unsigned b = 0;
        while (b < n) {
            auto status = wait_int(INT_BUF_RD_READY);
            EXPECT_TRUE(status & INT_BUF_RD_READY) << std::hex << status;
            if (!(status & INT_BUF_RD_READY))
                return data;
            write32(REG_INT_STATUS, INT_BUF_RD_READY);
            cycle(drain_delay);
            while (b < n && (read32(REG_PRESENT_STATE) & PS_BUF_RD_EN)) {
                auto blk = read_buffer_block();
                data.insert(data.end(), blk.begin(), blk.end());
                ++b;
            }
        }

        wait_xfer_complete();

        return data;
    }

    void write_blocks(uint32_t start, const std::vector<uint8_t> &data, uint16_t mode)
    {
        unsigned n = data.size() / SDCardModel::block_size;

        setup_xfer(n, mode);
        send_cmd(n > 1 ? 25 : 24, start, RESP_R1 | CMD_DATA);

        unsigned b = 0;
        while (b < n) {
            auto status = wait_int(INT_BUF_WR_READY);
            EXPECT_TRUE(status & INT_BUF_WR_READY) << std::hex << status;
            if (!(status & INT_BUF_WR_READY))
                return;
            write32(REG_INT_STATUS, INT_BUF_WR_READY);
            while (b < n && (read32(REG_PRESENT_STATE) & PS_BUF_WR_EN)) {
                write_buffer_block(&data[b * SDCardModel::block_size]);
                ++b;
            }
        }

        wait_xfer_complete();
    }

    std::vector<uint8_t> disk_blocks(uint32_t start, unsigned n)
    {
        auto first = card.disk.begin() + start * SDCardModel::block_size;
        return std::vector<uint8_t>(first, first + n * SDCardModel::block_size);
    }

    std::vector<uint8_t> random_blocks(unsigned n, unsigned seed)
    {
        std::mt19937 rng(seed);
        std::vector<uint8_t> data(n * SDCardModel::block_size);
        for (auto &b : data)
            b = rng();
        return data;
    }

    SDCardModel card;
    unsigned sdclk_rises;
    bool last_sdclk;
    std::vector<uint64_t> rise_cycles;
};

TEST_F(SDHCITest, ResetValues)
{
    // 3.3V, high speed, TMCLK 1MHz, no DMA, base clock from the platform.
    EXPECT_EQ(read32(REG_CAPABILITIES), 0x01200081u);
    EXPECT_EQ(read32(REG_CAPABILITIES + 4), 0u);
    EXPECT_EQ(read32(REG_MAX_CURRENT), 50u);
    EXPECT_EQ(read16(REG_HOST_VERSION), 0x0001u);
    EXPECT_EQ(read16(REG_SLOT_INT), 0u);

    for (uint32_t r = 0; r < 0x20; r += 4)
        EXPECT_EQ(read32(r), 0u) << std::hex << r;
    EXPECT_EQ(read32(REG_HOST_CONTROL), 0u);
    EXPECT_EQ(read32(REG_CLOCK_CONTROL), 0u);
    EXPECT_EQ(read32(REG_INT_STATUS), 0u);
    EXPECT_EQ(read32(REG_INT_ENABLE), 0u);
    EXPECT_EQ(read32(REG_SIGNAL_ENABLE), 0u);
    EXPECT_EQ(read32(REG_ACMD12_ERR), 0u);
    EXPECT_FALSE(dut.irq);

    auto ps = read32(REG_PRESENT_STATE);
    EXPECT_EQ(ps & (PS_CMD_INHIBIT | PS_DAT_INHIBIT), 0u);
    EXPECT_TRUE(ps & PS_WRITE_ENABLED);
    // CMD and DAT[3:0] pulled up
    EXPECT_EQ((ps >> 20) & 0x1f, 0x1fu);
    // Card detect is debounced, the card is reported once stable.
    EXPECT_TRUE(ps & PS_CARD_INSERTED);
    EXPECT_TRUE(ps & PS_CARD_STABLE);
}

TEST_F(SDHCITest, ByteLaneWrites)
{
    write32(REG_ARGUMENT, 0x11223344);
    write8(REG_ARGUMENT + 1, 0xaa);
    EXPECT_EQ(read32(REG_ARGUMENT), 0x1122aa44u);
    write16(REG_ARGUMENT + 2, 0xbbcc);
    EXPECT_EQ(read32(REG_ARGUMENT), 0xbbccaa44u);
    EXPECT_EQ(read8(REG_ARGUMENT + 3), 0xbbu);

    write16(REG_BLOCK_SIZE, 0x7200);
    write16(REG_BLOCK_COUNT, 0x1234);
    EXPECT_EQ(read32(REG_BLOCK_SIZE), 0x12347200u);
    write8(REG_BLOCK_COUNT, 0x55);
    EXPECT_EQ(read16(REG_BLOCK_COUNT), 0x1255u);

    // Writing only the transfer mode doesn't issue a command.
    write16(REG_TRANSFER_MODE, TM_READ | TM_BCE);
    EXPECT_EQ(read32(REG_TRANSFER_MODE), uint32_t(TM_READ | TM_BCE));
    cycle(100);
    EXPECT_TRUE(card.commands.empty());

    write8(REG_HOST_CONTROL, 0x06);
    write8(REG_POWER_CONTROL, 0x0f);
    EXPECT_EQ(read32(REG_HOST_CONTROL), 0x0f06u);

    write8(REG_TIMEOUT_CONTROL, 0x0e);
    write8(REG_CLOCK_CONTROL + 1, 0x80);
    EXPECT_EQ(read32(REG_CLOCK_CONTROL), 0x000e8000u);

    write32(REG_INT_ENABLE, 0xffffffff);
    EXPECT_EQ(read32(REG_INT_ENABLE), 0x017f00f3u);
    write16(REG_SIGNAL_ENABLE + 2, 0xffff);
    EXPECT_EQ(read32(REG_SIGNAL_ENABLE), 0x017f0000u);

    write8(REG_VENDOR, 0x3);
    EXPECT_EQ(read32(REG_VENDOR), 0x3u);
}

TEST_F(SDHCITest, InterruptsWriteOneToClear)
{
    power_on(1, false);

    // Disabled status is never latched.
    write32(REG_ARGUMENT, 0);
    write16(REG_COMMAND, RESP_NONE);
    cycle(200);
    EXPECT_EQ(read32(REG_INT_STATUS), 0u);

    write16(REG_INT_ENABLE, INT_CMD_COMPLETE);
    send_cmd(0, 0, RESP_NONE);
    // send_cmd cleared the status
    EXPECT_EQ(read32(REG_INT_STATUS), 0u);

    write32(REG_ARGUMENT, 0);
    write16(REG_COMMAND, RESP_NONE);
    wait_int(INT_CMD_COMPLETE);
    EXPECT_EQ(read32(REG_INT_STATUS), INT_CMD_COMPLETE);
    EXPECT_FALSE(dut.irq);

    write16(REG_SIGNAL_ENABLE, INT_CMD_COMPLETE);
    cycle();
    EXPECT_TRUE(dut.irq);
    EXPECT_EQ(read32(REG_SLOT_INT) & 1, 1u);

    // Writing zero has no effect.
    write32(REG_INT_STATUS, 0);
    EXPECT_EQ(read32(REG_INT_STATUS), INT_CMD_COMPLETE);
    EXPECT_TRUE(dut.irq);

    write8(REG_INT_STATUS, INT_CMD_COMPLETE);
    EXPECT_EQ(read32(REG_INT_STATUS), 0u);
    cycle();
    EXPECT_FALSE(dut.irq);

    // Error status signals through the error signal enable.
    write32(REG_INT_ENABLE, 0xffffffff);
    write32(REG_SIGNAL_ENABLE, INT_CMD_TIMEOUT);
    card.no_response.insert(13);
    write32(REG_ARGUMENT, 0);
    write16(REG_COMMAND, (13 << 8) | RESP_R1);
    auto status = wait_int(INT_CMD_TIMEOUT);
    EXPECT_EQ(status, INT_ERROR | INT_CMD_TIMEOUT);
    cycle();
    EXPECT_TRUE(dut.irq);
    write16(REG_INT_STATUS + 2, INT_CMD_TIMEOUT >> 16);
    EXPECT_EQ(read32(REG_INT_STATUS), 0u);
    cycle();
    EXPECT_FALSE(dut.irq);
}

TEST_F(SDHCITest, CommandResponses)
{
    power_on();

    send_cmd(0, 0, RESP_NONE);
    EXPECT_EQ(card.commands.back(), 0u);

    // R7
    send_cmd(8, 0x1aa, RESP_R1);
    EXPECT_EQ(read32(REG_RESPONSE), 0x1aau);
    EXPECT_EQ(card.args.back(), 0x1aau);

    // R1 with APP_CMD then R3, without CRC or index checks
    send_cmd(55, 0, RESP_R1);
    EXPECT_TRUE(read32(REG_RESPONSE) & (1 << 5));
    send_cmd(41, 0x40ff8000, RESP_R3);
    EXPECT_EQ(read32(REG_RESPONSE), 0x00ff8000u);
    card.acmd41_busy_polls = 0;
    send_cmd(55, 0, RESP_R1);
    send_cmd(41, 0x40ff8000, RESP_R3);
    EXPECT_EQ(read32(REG_RESPONSE), 0xc0ff8000u);

    // R2: RESPONSE[119:0] holds CID[127:8]
    send_cmd(2, 0, RESP_136);
    uint8_t resp[16];
    for (int i = 0; i < 4; ++i) {
        uint32_t w = read32(REG_RESPONSE + 4 * i);
        for (int b = 0; b < 4; ++b)
            resp[i * 4 + b] = w >> (8 * b);
    }
    for (int i = 0; i < 15; ++i)
        EXPECT_EQ(resp[i], card.cid[14 - i]) << i;
    EXPECT_EQ(resp[15], 0u);

    // R6
    send_cmd(3, 0, RESP_R1);
    uint16_t rca = read32(REG_RESPONSE) >> 16;
    EXPECT_EQ(rca, 0x1234u);

    // R2 CSD
    send_cmd(9, uint32_t(rca) << 16, RESP_136);
    EXPECT_EQ((read32(REG_RESPONSE + 12) >> 8) & 0xffff,
              uint32_t((card.csd[0] << 8) | card.csd[1]));

    // R1b: command complete with the response, transfer complete once busy
    // has been released, with the DAT lines inhibited until then.
    card.busy_clocks = 200;
    send_cmd(7, uint32_t(rca) << 16, RESP_R1B);
    EXPECT_TRUE(read32(REG_PRESENT_STATE) & PS_DAT_INHIBIT);
    EXPECT_FALSE(read32(REG_INT_STATUS) & INT_XFER_COMPLETE);
    wait_xfer_complete();
    EXPECT_FALSE(read32(REG_PRESENT_STATE) & PS_DAT_INHIBIT);
    EXPECT_EQ(card.state, SDCardModel::State::Transfer);

    EXPECT_EQ(card.bad_commands, 0u);
}

TEST_F(SDHCITest, InhibitWhileBusy)
{
    power_on(0x80);

    write32(REG_ARGUMENT, 0x1aa);
    write16(REG_COMMAND, (8 << 8) | RESP_R1);
    EXPECT_TRUE(read32(REG_PRESENT_STATE) & PS_CMD_INHIBIT);
    // Another command while inhibited is dropped.
    write16(REG_COMMAND, (13 << 8) | RESP_R1);
    wait_int(INT_CMD_COMPLETE);
    write32(REG_INT_STATUS, INT_CMD_COMPLETE);
    EXPECT_FALSE(read32(REG_PRESENT_STATE) & PS_CMD_INHIBIT);
    cycle(10000);
    EXPECT_EQ(card.commands, std::vector<unsigned>{8});
}

TEST_F(SDHCITest, ClockDivider)
{
    for (unsigned div : {0x01, 0x02, 0x04, 0x80}) {
        power_on(div);
        rise_cycles.clear();
        cycle(div * 2 * 10 + 4);
        ASSERT_GE(rise_cycles.size(), 9u);
        for (size_t i = 1; i < rise_cycles.size(); ++i)
            EXPECT_EQ(rise_cycles[i] - rise_cycles[i - 1], div * 2) << div;
    }

    // SD clock enable gates the clock.
    write16(REG_CLOCK_CONTROL, 0x0101);
    cycle(10);
    rise_cycles.clear();
    cycle(1000);
    EXPECT_TRUE(rise_cycles.empty());
    EXPECT_FALSE(dut.sd_clk);
}

TEST_F(SDHCITest, IdentificationAtSlowClock)
{
    power_on(0x80);
    send_cmd(0, 0, RESP_NONE);
    send_cmd(8, 0x1aa, RESP_R1);
    EXPECT_EQ(read32(REG_RESPONSE), 0x1aau);
}

class SDHCIWidthTest
    : public SDHCITest
    , public ::testing::WithParamInterface<bool>
{
};

TEST_P(SDHCIWidthTest, SingleBlockRead)
{
    power_on();
    init_card(GetParam());
    send_cmd(16, 512, RESP_R1);

    auto data = read_blocks(5, 1, 0);
    EXPECT_EQ(data, disk_blocks(5, 1));
    EXPECT_EQ(card.blocks_read, 1u);
    EXPECT_EQ(card.bus_width, GetParam() ? 4u : 1u);
    EXPECT_FALSE(read32(REG_PRESENT_STATE) & PS_DAT_INHIBIT);
}

TEST_P(SDHCIWidthTest, SingleBlockWrite)
{
    power_on();
    init_card(GetParam());

    auto data = random_blocks(1, 99);
    write_blocks(9, data, 0);
    EXPECT_EQ(disk_blocks(9, 1), data);
    EXPECT_EQ(card.blocks_written, 1u);
    EXPECT_FALSE(read32(REG_PRESENT_STATE) & PS_DAT_INHIBIT);
}

TEST_P(SDHCIWidthTest, MultiBlockReadAutoCMD12)
{
    power_on();
    init_card(GetParam());

    auto data = read_blocks(20, 4, TM_MULTI | TM_BCE | TM_AUTO12);
    EXPECT_EQ(data, disk_blocks(20, 4));
    EXPECT_EQ(card.commands.back(), 12u);
    EXPECT_EQ(read16(REG_BLOCK_COUNT), 0u);
    // Auto-CMD12 response in RESPONSE[127:96], the CMD18 response is kept.
    EXPECT_EQ((read32(REG_RESPONSE + 12) >> 9) & 0xf, 4u);
    EXPECT_EQ((read32(REG_RESPONSE) >> 9) & 0xf, 4u);
    EXPECT_EQ(read32(REG_ACMD12_ERR), 0u);
    EXPECT_FALSE(read32(REG_PRESENT_STATE) & PS_DAT_INHIBIT);
}

TEST_P(SDHCIWidthTest, MultiBlockWriteAutoCMD12)
{
    power_on();
    init_card(GetParam());

    auto data = random_blocks(3, 7);
    write_blocks(30, data, TM_MULTI | TM_BCE | TM_AUTO12);
    EXPECT_EQ(disk_blocks(30, 3), data);
    EXPECT_EQ(card.blocks_written, 3u);
    EXPECT_EQ(card.commands.back(), 12u);
    EXPECT_EQ(read32(REG_ACMD12_ERR), 0u);
}

INSTANTIATE_TEST_SUITE_P(Width,
                         SDHCIWidthTest,
                         ::testing::Values(false, true),
                         [](const auto &info) {
                             return info.param ? "4Bit" : "1Bit";
                         });

TEST_F(SDHCITest, MultiBlockReadStopsClockUntilDrained)
{
    power_on();
    init_card(true);

    // Nothing drains the buffer: the card must be stopped once the eight
    // block buffer is full rather than overrunning it.
    setup_xfer(12, TM_READ | TM_MULTI | TM_BCE | TM_AUTO12);
    send_cmd(18, 40, RESP_R1 | CMD_DATA);
    cycle(100000);
    auto rises = sdclk_rises;
    cycle(20000);
    EXPECT_EQ(sdclk_rises, rises);
    EXPECT_TRUE(read32(REG_PRESENT_STATE) & PS_BUF_RD_EN);

    // Draining restarts the clock and every block arrives intact.
    std::vector<uint8_t> data;
    while (data.size() < 12 * SDCardModel::block_size) {
        auto status = wait_int(INT_BUF_RD_READY);
        ASSERT_TRUE(status & INT_BUF_RD_READY) << std::hex << status;
        write32(REG_INT_STATUS, INT_BUF_RD_READY);
        while (data.size() < 12 * SDCardModel::block_size &&
               (read32(REG_PRESENT_STATE) & PS_BUF_RD_EN)) {
            auto blk = read_buffer_block();
            data.insert(data.end(), blk.begin(), blk.end());
        }
    }
    wait_xfer_complete();
    EXPECT_EQ(data, disk_blocks(40, 12));
}

TEST_F(SDHCITest, MultiBlockBuffering)
{
    power_on();
    init_card(true);

    // Reads run ahead of the CPU: several blocks are ready at once.
    setup_xfer(4, TM_READ | TM_MULTI | TM_BCE | TM_AUTO12);
    send_cmd(18, 90, RESP_R1 | CMD_DATA);
    cycle(100000);
    // Transfer complete waits for the buffer to be drained.
    EXPECT_FALSE(read32(REG_INT_STATUS) & INT_XFER_COMPLETE);
    std::vector<uint8_t> data;
    for (int b = 0; b < 4; ++b) {
        EXPECT_TRUE(read32(REG_PRESENT_STATE) & PS_BUF_RD_EN) << b;
        auto blk = read_buffer_block();
        data.insert(data.end(), blk.begin(), blk.end());
    }
    EXPECT_FALSE(read32(REG_PRESENT_STATE) & PS_BUF_RD_EN);
    wait_xfer_complete();
    EXPECT_EQ(data, disk_blocks(90, 4));

    // Writes: the CPU can fill eight blocks before space runs out.
    auto wdata = random_blocks(10, 11);
    setup_xfer(10, TM_MULTI | TM_BCE | TM_AUTO12);
    send_cmd(25, 100, RESP_R1 | CMD_DATA);
    unsigned b = 0;
    while (read32(REG_PRESENT_STATE) & PS_BUF_WR_EN)
        write_buffer_block(&wdata[b++ * SDCardModel::block_size]);
    EXPECT_GE(b, 8u);
    while (b < 10) {
        wait_int(INT_BUF_WR_READY);
        write32(REG_INT_STATUS, INT_BUF_WR_READY);
        while (b < 10 && (read32(REG_PRESENT_STATE) & PS_BUF_WR_EN))
            write_buffer_block(&wdata[b++ * SDCardModel::block_size]);
    }
    wait_xfer_complete();
    EXPECT_EQ(disk_blocks(100, 10), wdata);
}

TEST_F(SDHCITest, MultiBlockReadManualStop)
{
    power_on();
    init_card(true);

    // As Linux does: block count enabled, CMD12 sent by the driver.
    auto data = read_blocks(50, 2, TM_MULTI | TM_BCE);
    EXPECT_EQ(data, disk_blocks(50, 2));
    send_cmd(12, 0, RESP_R1B | 0xc0);
    wait_xfer_complete();
    EXPECT_EQ(card.state, SDCardModel::State::Transfer);
}

TEST_F(SDHCITest, SwitchFunctionHighSpeed)
{
    power_on();
    init_card(true);

    write16(REG_BLOCK_SIZE, 64);
    write16(REG_BLOCK_COUNT, 1);
    write16(REG_TRANSFER_MODE, TM_READ);
    send_cmd(6, 0x80fffff1, RESP_R1 | CMD_DATA);
    wait_int(INT_BUF_RD_READY);
    write32(REG_INT_STATUS, INT_BUF_RD_READY);
    auto status = read_buffer_block(64);
    wait_xfer_complete();
    EXPECT_EQ(status[16] & 0xf, 1u);
    EXPECT_TRUE(card.high_speed);

    // High speed timing: the card drives following the rising edge.
    card.hs_output_timing = true;
    write8(REG_HOST_CONTROL, 0x06);
    auto data = read_blocks(3, 2, TM_MULTI | TM_BCE | TM_AUTO12);
    EXPECT_EQ(data, disk_blocks(3, 2));
    auto wdata = random_blocks(2, 3);
    write_blocks(60, wdata, TM_MULTI | TM_BCE | TM_AUTO12);
    EXPECT_EQ(disk_blocks(60, 2), wdata);
}

TEST_F(SDHCITest, SampleDelay)
{
    // Default speed timing at SDCLK / 8: the card drives following the
    // falling edge so the value is stable throughout the high phase.
    power_on(4);
    init_card(true);
    for (uint8_t delay = 0; delay < 4; ++delay) {
        write8(REG_VENDOR, delay);
        auto data = read_blocks(70 + delay, 2, TM_MULTI | TM_BCE | TM_AUTO12);
        EXPECT_EQ(data, disk_blocks(70 + delay, 2)) << unsigned(delay);
        auto wdata = random_blocks(1, delay);
        write_blocks(80 + delay, wdata, 0);
        EXPECT_EQ(disk_blocks(80 + delay, 1), wdata) << unsigned(delay);
    }
}

TEST_F(SDHCITest, CommandTimeout)
{
    power_on();
    card.no_response.insert(8);
    auto status = send_cmd(8, 0x1aa, RESP_R1, false);
    EXPECT_EQ(status & ~INT_ERROR, INT_CMD_TIMEOUT);
    EXPECT_FALSE(read32(REG_PRESENT_STATE) & PS_CMD_INHIBIT);

    // The next command completes normally.
    card.no_response.clear();
    send_cmd(8, 0x1aa, RESP_R1);
}

TEST_F(SDHCITest, CommandCRCError)
{
    power_on();
    card.corrupt_next_response_crc = true;
    auto status = send_cmd(8, 0x1aa, RESP_R1, false);
    EXPECT_EQ(status & ~INT_ERROR, INT_CMD_CRC);

    // Without CRC checking the corrupt response is accepted.
    card.corrupt_next_response_crc = true;
    send_cmd(8, 0x1aa, RESP_R1 & ~0x08);
}

TEST_F(SDHCITest, CommandIndexError)
{
    power_on();
    // ACMD41's R3 carries 111111 in the index field so fails an index check.
    send_cmd(55, 0, RESP_R1);
    auto status = send_cmd(41, 0x40ff8000, RESP_R3 | 0x10, false);
    EXPECT_EQ(status & ~INT_ERROR, INT_CMD_INDEX);
}

TEST_F(SDHCITest, ReadDataTimeout)
{
    power_on();
    init_card(true);

    card.drop_next_read = true;
    setup_xfer(1, TM_READ);
    send_cmd(17, 0, RESP_R1 | CMD_DATA);
    auto status = wait_int(INT_DAT_TIMEOUT);
    EXPECT_EQ(status & ~INT_ERROR, INT_DAT_TIMEOUT);
    EXPECT_FALSE(read32(REG_PRESENT_STATE) & PS_DAT_INHIBIT);
}

TEST_F(SDHCITest, ReadDataCRCError)
{
    power_on();
    init_card(true);

    card.corrupt_next_read_crc = true;
    setup_xfer(1, TM_READ);
    send_cmd(17, 0, RESP_R1 | CMD_DATA);
    auto status = wait_int(INT_DAT_CRC);
    EXPECT_EQ(status & ~INT_ERROR, INT_DAT_CRC);

    // Recover with a DAT reset and read again.
    write8(REG_SOFTWARE_RESET, 0x04);
    EXPECT_EQ(read8(REG_SOFTWARE_RESET), 0u);
    write32(REG_INT_STATUS, 0xffffffff);
    auto data = read_blocks(0, 1, 0);
    EXPECT_EQ(data, disk_blocks(0, 1));
}

TEST_F(SDHCITest, WriteCRCStatusError)
{
    power_on();
    init_card(true);

    card.reject_next_write = true;
    setup_xfer(1, 0);
    send_cmd(24, 4, RESP_R1 | CMD_DATA);
    wait_int(INT_BUF_WR_READY);
    write32(REG_INT_STATUS, INT_BUF_WR_READY);
    auto data = random_blocks(1, 5);
    write_buffer_block(data.data());
    auto status = wait_int(INT_DAT_CRC);
    EXPECT_EQ(status & ~(INT_ERROR | INT_BUF_WR_READY), INT_DAT_CRC);
    EXPECT_EQ(card.blocks_written, 0u);
}

TEST_F(SDHCITest, AutoCMD12Error)
{
    power_on();
    init_card(true);

    card.no_response.insert(12);
    setup_xfer(2, TM_READ | TM_MULTI | TM_BCE | TM_AUTO12);
    send_cmd(18, 0, RESP_R1 | CMD_DATA);
    for (int b = 0; b < 2;) {
        wait_int(INT_BUF_RD_READY);
        write32(REG_INT_STATUS, INT_BUF_RD_READY);
        while (b < 2 && (read32(REG_PRESENT_STATE) & PS_BUF_RD_EN)) {
            read_buffer_block();
            ++b;
        }
    }
    auto status = wait_int(INT_ACMD12);
    EXPECT_TRUE(status & INT_ACMD12) << std::hex << status;
    EXPECT_EQ(read32(REG_ACMD12_ERR), 0x2u);
}

TEST_F(SDHCITest, SoftwareResetAll)
{
    power_on();
    write32(REG_ARGUMENT, 0x12345678);
    write8(REG_HOST_CONTROL, 0x2);
    send_cmd(0, 0, RESP_NONE);
    write32(REG_SIGNAL_ENABLE, 0xffffffff);

    write8(REG_SOFTWARE_RESET, 0x01);
    EXPECT_EQ(read8(REG_SOFTWARE_RESET), 0u);
    EXPECT_EQ(read32(REG_ARGUMENT), 0u);
    EXPECT_EQ(read32(REG_HOST_CONTROL), 0u);
    EXPECT_EQ(read32(REG_CLOCK_CONTROL), 0u);
    EXPECT_EQ(read32(REG_INT_ENABLE), 0u);
    EXPECT_EQ(read32(REG_SIGNAL_ENABLE), 0u);
    cycle(10);
    EXPECT_FALSE(dut.sd_clk);
}

TEST_F(SDHCITest, CardDetect)
{
    write32(REG_INT_ENABLE, INT_CARD_INSERT | INT_CARD_REMOVE);

    dut.cd_n = 1;
    cycle(100);
    auto ps = read32(REG_PRESENT_STATE);
    EXPECT_FALSE(ps & PS_CARD_INSERTED);
    EXPECT_TRUE(ps & PS_CARD_STABLE);
    EXPECT_EQ(read32(REG_INT_STATUS), INT_CARD_REMOVE);
    write32(REG_INT_STATUS, INT_CARD_REMOVE);

    // Glitches shorter than the debounce are ignored.
    dut.cd_n = 0;
    cycle(4);
    dut.cd_n = 1;
    cycle(100);
    EXPECT_EQ(read32(REG_INT_STATUS), 0u);

    dut.cd_n = 0;
    cycle(100);
    EXPECT_TRUE(read32(REG_PRESENT_STATE) & PS_CARD_INSERTED);
    EXPECT_EQ(read32(REG_INT_STATUS), INT_CARD_INSERT);
}

