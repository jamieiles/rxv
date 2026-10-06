// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include "SDCardModel.h"

#include <algorithm>

namespace
{

const uint32_t ocr_voltage_window = 0x00ff8000;

std::vector<uint8_t> make_register(const std::vector<uint8_t> &prefix)
{
    std::vector<uint8_t> reg(prefix);
    reg.resize(16);

    std::vector<int> bits;
    for (unsigned i = 0; i < 15; ++i)
        for (int b = 7; b >= 0; --b)
            bits.push_back((reg[i] >> b) & 1);
    reg[15] = (SDCardModel::crc7(bits, 0, bits.size()) << 1) | 1;

    return reg;
}

void push_bits(std::vector<int> &bits, uint64_t v, unsigned n)
{
    for (int i = n - 1; i >= 0; --i)
        bits.push_back((v >> i) & 1);
}

} // namespace

SDCardModel::SDCardModel(unsigned num_blocks)
    : disk(num_blocks * block_size),
      high_capacity(true),
      hs_output_timing(false),
      acmd41_busy_polls(2),
      ncr(2),
      nac(4),
      busy_clocks(16),
      corrupt_next_response_crc(false),
      corrupt_next_read_crc(false),
      drop_next_read(false),
      reject_next_write(false),
      bus_width(1),
      high_speed(false),
      contention(false),
      blocks_read(0),
      blocks_written(0),
      bad_commands(0),
      state(State::Idle),
      last_clk(false),
      host_cmd_drive(false),
      host_cmd_val(true),
      host_dat_mask(0),
      host_dat_val(0xf),
      card_cmd_drive(false),
      card_cmd_val(true),
      pending_busy(0),
      card_dat_mask(0),
      card_dat_val(0xf),
      cmd_receiving(false),
      app_cmd(false),
      acmd41_polls(0),
      rca(0),
      blocklen(block_size),
      multi_read(false),
      read_addr(0),
      write_active(false),
      write_multi(false),
      write_addr(0),
      wr_in_block(false),
      wr_bits(0),
      wr_crc{},
      wr_crc_bits(0),
      wr_crc_ok(false)
{
    cid = make_register({0x03, 'R', 'X', 'R', 'X', 'V', 'S', 'D', 0x10,
                         0x12, 0x34, 0x56, 0x78, 0x01, 0x9a});
    csd = make_register({0x40, 0x0e, 0x00, 0x32, 0x5b, 0x59, 0x00, 0x00,
                         0x1d, 0x8a, 0x7f, 0x80, 0x0a, 0x40, 0x00});
}

uint8_t SDCardModel::crc7(const std::vector<int> &bits, size_t start, size_t len)
{
    uint8_t crc = 0;

    for (size_t i = start; i < start + len; ++i) {
        int fb = ((crc >> 6) & 1) ^ bits[i];
        crc = (crc << 1) & 0x7f;
        if (fb)
            crc ^= 0x09;
    }

    return crc;
}

uint16_t SDCardModel::crc16_step(uint16_t crc, int bit)
{
    int fb = ((crc >> 15) & 1) ^ bit;
    crc <<= 1;
    if (fb)
        crc ^= 0x1021;
    return crc;
}

bool SDCardModel::cmd_line() const
{
    if (host_cmd_drive)
        return host_cmd_val;
    if (card_cmd_drive)
        return card_cmd_val;
    return true;
}

uint8_t SDCardModel::dat_lines() const
{
    uint8_t v = 0;

    for (int i = 0; i < 4; ++i) {
        int bit = 1;
        if (host_dat_mask & (1 << i))
            bit = (host_dat_val >> i) & 1;
        else if (card_dat_mask & (1 << i))
            bit = (card_dat_val >> i) & 1;
        v |= bit << i;
    }

    return v;
}

void SDCardModel::step(bool sdclk,
                       bool cmd_o,
                       bool cmd_t,
                       uint8_t dat_o,
                       uint8_t dat_t)
{
    host_cmd_drive = !cmd_t;
    host_cmd_val = cmd_o;
    host_dat_mask = ~dat_t & 0xf;
    host_dat_val = dat_o & 0xf;

    if (sdclk && !last_clk) {
        rising_edge();
        if (hs_output_timing)
            advance_outputs();
    } else if (!sdclk && last_clk && !hs_output_timing) {
        advance_outputs();
    }

    last_clk = sdclk;
}

void SDCardModel::rising_edge()
{
    if (host_cmd_drive && card_cmd_drive)
        contention = true;
    if (host_dat_mask & card_dat_mask)
        contention = true;

    if (!card_cmd_drive)
        receive_cmd_bit(cmd_line());
    if (write_active && dat_q.empty() && !card_dat_mask)
        receive_dat(dat_lines());
}

void SDCardModel::advance_outputs()
{
    if (!cmd_q.empty()) {
        int v = cmd_q.front();
        cmd_q.pop_front();

        if (v < 0) {
            card_cmd_drive = false;
            if (cmd_q.empty() && pending_busy) {
                for (unsigned i = 0; i < pending_busy; ++i)
                    dat_q.push_back({0x1, 0x0});
                dat_q.push_back({0x0, 0xf});
                pending_busy = 0;
            }
        } else {
            card_cmd_drive = true;
            card_cmd_val = v;
        }
    }

    if (dat_q.empty() && multi_read) {
        dat_q.push_back({0x0, 0xf});
        dat_q.push_back({0x0, 0xf});
        queue_block(&disk[read_addr % disk.size()], block_size);
        read_addr += block_size;
        ++blocks_read;
    }

    if (!dat_q.empty()) {
        auto e = dat_q.front();
        dat_q.pop_front();
        card_dat_mask = e.mask;
        card_dat_val = e.val;
    } else {
        card_dat_mask = 0;
        card_dat_val = 0xf;
    }
}

void SDCardModel::receive_cmd_bit(int bit)
{
    if (!cmd_receiving) {
        if (!bit) {
            cmd_receiving = true;
            cmd_bits.assign(1, 0);
        }
        return;
    }

    cmd_bits.push_back(bit);
    if (cmd_bits.size() != 48)
        return;

    cmd_receiving = false;

    uint8_t rx_crc = 0;
    for (int i = 40; i < 47; ++i)
        rx_crc = (rx_crc << 1) | cmd_bits[i];

    if (cmd_bits[1] != 1 || cmd_bits[47] != 1 ||
        crc7(cmd_bits, 0, 40) != rx_crc) {
        ++bad_commands;
        return;
    }

    unsigned index = 0;
    uint32_t arg = 0;
    for (int i = 2; i < 8; ++i)
        index = (index << 1) | cmd_bits[i];
    for (int i = 8; i < 40; ++i)
        arg = (arg << 1) | cmd_bits[i];

    handle_command(index, arg);
}

void SDCardModel::receive_dat(uint8_t lines)
{
    uint8_t mask = bus_width == 4 ? 0xf : 0x1;

    if (!wr_in_block) {
        if (!(lines & 1)) {
            wr_in_block = true;
            wr_bits = 0;
            wr_crc_bits = 0;
            wr_data.assign(block_size, 0);
            std::fill(std::begin(wr_crc), std::end(wr_crc), 0);
        }
        return;
    }

    if (wr_bits < block_size * 8) {
        unsigned idx = wr_bits / 8;
        if (bus_width == 4) {
            uint8_t nib = lines & 0xf;
            for (int i = 0; i < 4; ++i)
                wr_crc[i] = crc16_step(wr_crc[i], (nib >> i) & 1);
            wr_data[idx] |= nib << (wr_bits % 8 == 0 ? 4 : 0);
            wr_bits += 4;
        } else {
            int b = lines & 1;
            wr_crc[0] = crc16_step(wr_crc[0], b);
            wr_data[idx] |= b << (7 - wr_bits % 8);
            ++wr_bits;
        }
    } else if (wr_crc_bits < 16) {
        for (int i = 0; i < 4; ++i)
            if (mask & (1 << i))
                wr_crc[i] = crc16_step(wr_crc[i], (lines >> i) & 1);
        ++wr_crc_bits;
    } else {
        wr_crc_ok = (lines & mask) == mask;
        for (int i = 0; i < 4; ++i)
            if (wr_crc[i])
                wr_crc_ok = false;
        wr_in_block = false;
        end_write_block();
    }
}

void SDCardModel::end_write_block()
{
    bool ok = wr_crc_ok && !reject_next_write;
    reject_next_write = false;

    if (ok) {
        std::copy(wr_data.begin(), wr_data.end(),
                  disk.begin() + (write_addr % disk.size()));
        write_addr += block_size;
        ++blocks_written;
    }

    // CRC status token two clocks after the end bit followed by busy.
    dat_q.push_back({0x0, 0xf});
    dat_q.push_back({0x1, 0x0});
    uint8_t status = ok ? 0x2 : 0x5;
    for (int i = 2; i >= 0; --i)
        dat_q.push_back({0x1, uint8_t((status >> i) & 1)});
    dat_q.push_back({0x1, 0x1});
    for (unsigned i = 0; i < busy_clocks; ++i)
        dat_q.push_back({0x1, 0x0});
    dat_q.push_back({0x0, 0xf});

    if (!write_multi || !ok) {
        write_active = false;
        state = State::Transfer;
    }
}

uint32_t SDCardModel::card_status() const
{
    return (uint32_t(state) << 9) | (1 << 8) | (app_cmd ? (1 << 5) : 0);
}

void SDCardModel::respond_bits(const std::vector<int> &bits)
{
    std::vector<int> b(bits);

    if (corrupt_next_response_crc) {
        b[b.size() - 3] ^= 1;
        corrupt_next_response_crc = false;
    }

    for (unsigned i = 0; i < ncr; ++i)
        cmd_q.push_back(-1);
    for (auto v : b)
        cmd_q.push_back(v);
    cmd_q.push_back(-1);
}

void SDCardModel::respond_r1(unsigned index, bool busy)
{
    std::vector<int> bits;

    push_bits(bits, 0, 2);
    push_bits(bits, index, 6);
    push_bits(bits, card_status(), 32);
    push_bits(bits, crc7(bits, 0, 40), 7);
    bits.push_back(1);
    respond_bits(bits);

    if (busy)
        pending_busy = busy_clocks;
}

void SDCardModel::respond_r2(const std::vector<uint8_t> &reg)
{
    std::vector<int> bits;

    push_bits(bits, 0, 2);
    push_bits(bits, 0x3f, 6);
    for (unsigned i = 0; i < 16; ++i)
        push_bits(bits, reg[i], 8);
    respond_bits(bits);
}

void SDCardModel::queue_block(const uint8_t *data, unsigned len)
{
    uint8_t mask = bus_width == 4 ? 0xf : 0x1;
    uint16_t crc[4] = {};

    dat_q.push_back({mask, 0x0});

    for (unsigned i = 0; i < len; ++i) {
        if (bus_width == 4) {
            for (int n = 1; n >= 0; --n) {
                uint8_t nib = (data[i] >> (n * 4)) & 0xf;
                for (int l = 0; l < 4; ++l)
                    crc[l] = crc16_step(crc[l], (nib >> l) & 1);
                dat_q.push_back({mask, nib});
            }
        } else {
            for (int b = 7; b >= 0; --b) {
                int bit = (data[i] >> b) & 1;
                crc[0] = crc16_step(crc[0], bit);
                dat_q.push_back({mask, uint8_t(bit)});
            }
        }
    }

    if (corrupt_next_read_crc) {
        crc[0] ^= 0x0100;
        corrupt_next_read_crc = false;
    }

    for (int b = 15; b >= 0; --b) {
        uint8_t v = 0;
        for (int l = 0; l < 4; ++l)
            v |= ((crc[l] >> b) & 1) << l;
        dat_q.push_back({mask, v});
    }

    dat_q.push_back({mask, 0xf});
    dat_q.push_back({0x0, 0xf});
}

void SDCardModel::handle_command(unsigned index, uint32_t arg)
{
    bool is_app = app_cmd;

    commands.push_back(is_app ? (0x80 | index) : index);
    args.push_back(arg);
    app_cmd = false;

    if (no_response.count(index))
        return;

    uint32_t addr = high_capacity ? arg * block_size : arg;

    if (is_app) {
        switch (index) {
        case 41: {
            ++acmd41_polls;
            bool ready = acmd41_polls > acmd41_busy_polls;
            uint32_t ocr = ocr_voltage_window;
            if (ready) {
                ocr |= 1u << 31;
                if (high_capacity)
                    ocr |= 1u << 30;
                state = State::Ready;
            }
            std::vector<int> bits;
            push_bits(bits, 0, 2);
            push_bits(bits, 0x3f, 6);
            push_bits(bits, ocr, 32);
            push_bits(bits, 0x7f, 7);
            bits.push_back(1);
            respond_bits(bits);
            return;
        }
        case 6:
            bus_width = (arg & 3) == 2 ? 4 : 1;
            respond_r1(index);
            return;
        default:
            break;
        }
    }

    switch (index) {
    case 0:
        state = State::Idle;
        rca = 0;
        bus_width = 1;
        high_speed = false;
        acmd41_polls = 0;
        multi_read = false;
        write_active = false;
        break;
    case 2:
        state = State::Ident;
        respond_r2(cid);
        break;
    case 3: {
        rca = 0x1234;
        state = State::Standby;
        std::vector<int> bits;
        push_bits(bits, 0, 2);
        push_bits(bits, 3, 6);
        push_bits(bits, (uint32_t(rca) << 16) | (card_status() & 0x1fff), 32);
        push_bits(bits, crc7(bits, 0, 40), 7);
        bits.push_back(1);
        respond_bits(bits);
        break;
    }
    case 6: {
        std::vector<uint8_t> status(64, 0);
        status[0] = 0x00;
        status[1] = 0x64;
        status[12] = 0x80;
        status[13] = 0x03;
        unsigned fn = arg & 0xf;
        status[16] = fn == 0xf ? 0 : fn;
        if ((arg >> 31) && fn == 1)
            high_speed = true;
        respond_r1(index);
        for (unsigned i = 0; i < nac; ++i)
            dat_q.push_back({0x0, 0xf});
        queue_block(status.data(), status.size());
        break;
    }
    case 7:
        if ((arg >> 16) == rca) {
            state = State::Transfer;
            respond_r1(index, true);
        } else {
            state = State::Standby;
        }
        break;
    case 8: {
        std::vector<int> bits;
        push_bits(bits, 0, 2);
        push_bits(bits, 8, 6);
        push_bits(bits, arg & 0xfff, 32);
        push_bits(bits, crc7(bits, 0, 40), 7);
        bits.push_back(1);
        respond_bits(bits);
        break;
    }
    case 9:
        respond_r2(csd);
        break;
    case 12:
        multi_read = false;
        write_active = false;
        dat_q.clear();
        card_dat_mask = 0;
        state = State::Transfer;
        respond_r1(index, true);
        break;
    case 13:
        respond_r1(index);
        break;
    case 16:
        blocklen = arg;
        respond_r1(index);
        break;
    case 17:
    case 18:
        respond_r1(index);
        if (drop_next_read) {
            drop_next_read = false;
            break;
        }
        state = State::Data;
        for (unsigned i = 0; i < nac; ++i)
            dat_q.push_back({0x0, 0xf});
        queue_block(&disk[addr % disk.size()], block_size);
        ++blocks_read;
        read_addr = addr + block_size;
        multi_read = index == 18;
        if (index == 17)
            state = State::Transfer;
        break;
    case 24:
    case 25:
        respond_r1(index);
        state = State::Receive;
        write_active = true;
        write_multi = index == 25;
        write_addr = addr;
        wr_in_block = false;
        break;
    case 55:
        app_cmd = true;
        respond_r1(index);
        break;
    default:
        // Illegal command: no response.
        break;
    }
}
