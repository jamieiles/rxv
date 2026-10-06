// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <deque>
#include <set>
#include <vector>

// Behavioural model of an SD memory card in SD (not SPI) bus mode, backed
// by an in-memory disk image.
//
// The model is stepped once per host clock cycle with the host's SD bus
// outputs and acts on SDCLK edges: on a rising edge it samples CMD and DAT,
// on a falling edge (or the rising edge with high-speed output timing) it
// moves its own outputs on.  The resolved line levels, including the bus
// pull-ups, are returned through cmd_line() and dat_lines() to be fed back
// into the host.
class SDCardModel
{
public:
    static const unsigned block_size = 512;

    enum class State {
        Idle,
        Ready,
        Ident,
        Standby,
        Transfer,
        Data,
        Receive,
    };

    explicit SDCardModel(unsigned num_blocks = 1024);

    void step(bool sdclk,
              bool cmd_o,
              bool cmd_t,
              uint8_t dat_o,
              uint8_t dat_t);
    bool cmd_line() const;
    uint8_t dat_lines() const;

    std::vector<uint8_t> disk;
    std::vector<uint8_t> cid;
    std::vector<uint8_t> csd;

    // Configuration
    bool high_capacity;
    bool hs_output_timing;
    unsigned acmd41_busy_polls;
    unsigned ncr;
    unsigned nac;
    unsigned busy_clocks;

    // Error injection
    std::set<unsigned> no_response;
    bool corrupt_next_response_crc;
    bool corrupt_next_read_crc;
    bool drop_next_read;
    bool reject_next_write;

    // Observation
    std::vector<unsigned> commands;
    std::vector<uint32_t> args;
    unsigned bus_width;
    bool high_speed;
    bool contention;
    unsigned blocks_read;
    unsigned blocks_written;
    unsigned bad_commands;
    State state;

    static uint8_t crc7(const std::vector<int> &bits, size_t start, size_t len);
    static uint16_t crc16_step(uint16_t crc, int bit);

private:
    struct DatEntry {
        uint8_t mask;
        uint8_t val;
    };

    void rising_edge();
    void advance_outputs();
    void receive_cmd_bit(int bit);
    void receive_dat(uint8_t lines);
    void handle_command(unsigned index, uint32_t arg);
    void respond_r1(unsigned index, bool busy = false);
    void respond_bits(const std::vector<int> &bits);
    void respond_r2(const std::vector<uint8_t> &reg);
    void queue_block(const uint8_t *data, unsigned len);
    uint32_t card_status() const;
    void end_write_block();

    bool last_clk;
    bool host_cmd_drive;
    bool host_cmd_val;
    uint8_t host_dat_mask;
    uint8_t host_dat_val;

    // CMD output
    std::deque<int> cmd_q;
    bool card_cmd_drive;
    bool card_cmd_val;
    unsigned pending_busy;

    // DAT output
    std::deque<DatEntry> dat_q;
    uint8_t card_dat_mask;
    uint8_t card_dat_val;

    // CMD input
    bool cmd_receiving;
    std::vector<int> cmd_bits;

    // Card state
    bool app_cmd;
    unsigned acmd41_polls;
    uint16_t rca;
    unsigned blocklen;

    // Multi-block read
    bool multi_read;
    uint32_t read_addr;

    // Write receive
    bool write_active;
    bool write_multi;
    uint32_t write_addr;
    bool wr_in_block;
    unsigned wr_bits;
    std::vector<uint8_t> wr_data;
    uint16_t wr_crc[4];
    unsigned wr_crc_bits;
    bool wr_crc_ok;
};
