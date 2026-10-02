// Core context – replaces the MMTTY global variables. Active for the duration of a C API call.
// Copyright 2026 OK1XOE (RYRY), LGPL v3
#pragma once
#include "MMTTYTypes.h"

struct CoreContext {
    CoreSys sys;
    double SampFreq = 11025.0, SampBase = 11025.0, DemSamp = 11025.0 * 0.5;
    int DemOver = 1, FFT_SIZE = 2048, SampType = 0, SampSize = 1024;
    int FSKCount = 0, FSKCount1 = 0, FSKCount2 = 0, FSKDeff = 0;
};

extern thread_local CoreContext* g_ctx;

// RAII: sets the active context of the current thread for its lifetime (nestable).
struct CoreScope {
    CoreContext* prev;
    explicit CoreScope(CoreContext* c) : prev(g_ctx) { g_ctx = c; }
    ~CoreScope() { g_ctx = prev; }
    CoreScope(const CoreScope&) = delete;
    CoreScope& operator=(const CoreScope&) = delete;
};
