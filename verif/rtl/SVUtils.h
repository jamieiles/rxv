// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <svdpi.h>

static inline void sv_set_scope_name(const std::string &name)
{
    auto scope = svGetScopeFromName(name.c_str());
    assert(scope);
    svSetScope(scope);
}