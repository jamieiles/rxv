#pragma once
#include <err.h>
#include <stdint.h>
#include <iostream>
#include <fstream>
#include <cstring>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "Trace_generated.h"

struct TraceRange {
    std::unique_ptr<char[]> buf;
    const RXV::Trace::ProcessorTrace *trace;
    unsigned long event_offset;
};

class TraceFile
{
public:
    TraceFile(const std::string &filename) : event_offset(0)
    {
        fd = open(filename.c_str(), O_RDONLY);
        if (fd < 0)
            throw std::runtime_error("failed to open trace file");
    }

    bool end_of_trace() const
    {
        struct stat statbuf = {};
        if (fstat(fd, &statbuf))
            err(1, "failed to stat %s", filename.c_str());

        loff_t fileoff = lseek(fd, 0, SEEK_CUR);

        return fileoff == statbuf.st_size;
    }

    TraceRange range_containing_event(unsigned long event_idx)
    {
        auto range = next_range();

        while (
            !(event_idx >= range.event_offset &&
              event_idx < range.event_offset + range.trace->events()->size())) {
            range = next_range();
        }

        return range;
    }

    TraceRange next_range()
    {
        uint64_t size;

        if (read(fd, &size, sizeof(size)) != sizeof(size))
            throw std::runtime_error("failed to read trace segment size");

        TraceRange range;

        range.buf = std::make_unique<char[]>(size);
        if (read(fd, reinterpret_cast<char *>(range.buf.get()), size) != size)
            throw std::runtime_error("failed to read trace contents");

        range.trace = RXV::Trace::GetProcessorTrace(range.buf.get());
        range.event_offset = event_offset;

        event_offset += range.trace->events()->size();

        return range;
    }

    size_t num_events()
    {
        size_t count = 0;

        while (!end_of_trace()) {
            auto t = next_range();
            count += t.trace->events()->size();
        }

        lseek(fd, 0, SEEK_SET);
        event_offset = 0;

        return count;
    }

private:
    std::string filename;
    unsigned long event_offset;
    int fd;
};