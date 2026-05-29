// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <gtest/gtest.h>

#include "VerilogDriver.h"
#include "TestUtils.h"

static inline std::string test_fst()
{
    auto filename = current_test_name() + ".fst";

    boost::replace_all(filename, "/", "_");

    return filename;
}

template <typename T, bool debug_enabled = verilator_debug_enabled>
class VerilogTestbench : public VerilogDriver<T, true>
{
public:
    VerilogTestbench() : VerilogDriver<T, true>(test_fst())
    {
    }
};
