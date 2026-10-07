// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

// A disk image with an MBR and a single active FAT16 partition holding
// files in the root directory, enough for the boot ROM to load from.  Files
// are stored in contiguous clusters with 8.3 names ("OPENSBI.BIN").
class FatImage
{
public:
    static const unsigned sector_size = 512;
    static const unsigned partition_lba = 64;
    // One sector per cluster, enough clusters to be FAT16.
    static const unsigned partition_sectors = 8192;
    static const unsigned reserved_sectors = 1;
    static const unsigned nr_fats = 2;
    static const unsigned root_entries = 512;
    static const unsigned sectors_per_fat = partition_sectors * 2 / sector_size;

    void add_file(const std::string &name, std::vector<uint8_t> data)
    {
        files.emplace_back(name, std::move(data));
    }

    std::vector<uint8_t> build() const
    {
        std::vector<uint8_t> disk((partition_lba + partition_sectors) *
                                  sector_size);

        // MBR, one active FAT16 partition
        uint8_t *pe = &disk[0x1be];
        pe[0] = 0x80;
        pe[4] = 0x06;
        put32(pe + 8, partition_lba);
        put32(pe + 12, partition_sectors);
        disk[0x1fe] = 0x55;
        disk[0x1ff] = 0xaa;

        uint8_t *part = &disk[partition_lba * sector_size];
        uint8_t *bs = part;
        bs[0] = 0xeb;
        bs[1] = 0x3c;
        bs[2] = 0x90;
        std::memcpy(bs + 3, "RXVTEST ", 8);
        put16(bs + 0x0b, sector_size);
        bs[0x0d] = 1;
        put16(bs + 0x0e, reserved_sectors);
        bs[0x10] = nr_fats;
        put16(bs + 0x11, root_entries);
        put16(bs + 0x13, partition_sectors);
        bs[0x15] = 0xf8;
        put16(bs + 0x16, sectors_per_fat);
        bs[0x1fe] = 0x55;
        bs[0x1ff] = 0xaa;

        std::vector<uint16_t> fat(partition_sectors, 0);
        fat[0] = 0xfff8;
        fat[1] = 0xffff;

        uint8_t *root = part + (reserved_sectors + nr_fats * sectors_per_fat) *
                                   sector_size;
        unsigned data_sector = reserved_sectors + nr_fats * sectors_per_fat +
                               root_entries * 32 / sector_size;
        unsigned next_cluster = 2;

        for (size_t f = 0; f < files.size(); ++f) {
            const auto &[name, data] = files[f];
            uint8_t *de = root + f * 32;
            std::memset(de, ' ', 11);
            auto dot = name.find('.');
            std::memcpy(de, name.data(), std::min<size_t>(dot, 8));
            if (dot != std::string::npos)
                std::memcpy(de + 8, name.data() + dot + 1,
                            std::min<size_t>(name.size() - dot - 1, 3));
            de[0x0b] = 0x20;

            unsigned clusters = (data.size() + sector_size - 1) / sector_size;
            if (clusters == 0)
                clusters = 1;
            if (next_cluster + clusters >= partition_sectors)
                throw std::runtime_error("FatImage: disk full");

            put16(de + 0x1a, next_cluster);
            put32(de + 0x1c, data.size());
            for (unsigned c = 0; c < clusters; ++c)
                fat[next_cluster + c] =
                    c + 1 == clusters ? 0xffff : next_cluster + c + 1;
            std::memcpy(part + (data_sector + next_cluster - 2) * sector_size,
                        data.data(), data.size());
            next_cluster += clusters;
        }

        for (unsigned n = 0; n < nr_fats; ++n) {
            uint8_t *fatp = part + (reserved_sectors + n * sectors_per_fat) *
                                       sector_size;
            for (size_t e = 0; e < fat.size(); ++e)
                put16(fatp + e * 2, fat[e]);
        }

        return disk;
    }

private:
    static void put16(uint8_t *p, uint16_t v)
    {
        p[0] = v;
        p[1] = v >> 8;
    }

    static void put32(uint8_t *p, uint32_t v)
    {
        put16(p, v);
        put16(p + 2, v >> 16);
    }

    std::vector<std::pair<std::string, std::vector<uint8_t>>> files;
};
