// Kontext jádra (bývalé globály z ComLib.cpp).
// Copyright 2000-2013 Makoto Mori, Nobuyuki Oba; Modifications Copyright 2026 OK1XOE, LGPL v3
#include "MMTTYCompat.h"

static CoreContext g_defaultCtx;                 // pro volání mimo C API (statická inicializace)
thread_local CoreContext* g_ctx = &g_defaultCtx;

void InitSampType(void)
{
    if( SampFreq >= 11600.0 ){
        SampType = 3; SampBase = 12000.0; DemSamp = SampFreq * 0.5; DemOver = 1;
        FFT_SIZE = 2048; SampSize = (12000*1024)/11025;
    }
    else if( SampFreq >= 10000.0 ){
        SampType = 0; SampBase = 11025.0; DemSamp = SampFreq * 0.5; DemOver = 1;
        FFT_SIZE = 2048; SampSize = 1024;
    }
    else if( SampFreq >= 7000.0 ){
        SampType = 1; SampBase = 8000.0; DemSamp = SampFreq; DemOver = 0;
        FFT_SIZE = 1024; SampSize = (8000*1024)/11025;
    }
    else if( SampFreq >= 5000.0 ){
        SampType = 2; SampBase = 6000.0; DemSamp = SampFreq; DemOver = 0;
        FFT_SIZE = 1024; SampSize = (6000*1024)/11025;
    }
}
