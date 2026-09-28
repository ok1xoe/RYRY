// Kontext jádra – nahrazuje globální proměnné MMTTY. Aktivní po dobu volání C API.
// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
#pragma once
#include "MMTTYTypes.h"

struct CoreContext {
    CoreSys sys;
    double SampFreq = 11025.0, SampBase = 11025.0, DemSamp = 11025.0 * 0.5;
    int DemOver = 1, FFT_SIZE = 2048, SampType = 0, SampSize = 1024;
    int FSKCount = 0, FSKCount1 = 0, FSKCount2 = 0, FSKDeff = 0;
};

extern thread_local CoreContext* g_ctx;

// RAII: po dobu života nastaví aktivní kontext aktuálního vlákna (vnořitelné).
struct CoreScope {
    CoreContext* prev;
    explicit CoreScope(CoreContext* c) : prev(g_ctx) { g_ctx = c; }
    ~CoreScope() { g_ctx = prev; }
    CoreScope(const CoreScope&) = delete;
    CoreScope& operator=(const CoreScope&) = delete;
};
