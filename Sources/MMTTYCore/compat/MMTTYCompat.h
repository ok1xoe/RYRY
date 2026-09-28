// MMTTYCompat.h – typy z Windows/VCL + přesměrování bývalých globálů MMTTY na CoreContext.
// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
#pragma once
#include "MMTTYTypes.h"
#include "CoreContext.h"

#define sys        (g_ctx->sys)
#define SampFreq   (g_ctx->SampFreq)
#define SampBase   (g_ctx->SampBase)
#define DemSamp    (g_ctx->DemSamp)
#define DemOver    (g_ctx->DemOver)
#define FFT_SIZE   (g_ctx->FFT_SIZE)
#define SampType   (g_ctx->SampType)
#define SampSize   (g_ctx->SampSize)
#define FSKCount   (g_ctx->FSKCount)
#define FSKCount1  (g_ctx->FSKCount1)
#define FSKCount2  (g_ctx->FSKCount2)
#define FSKDeff    (g_ctx->FSKDeff)

void InitSampType(void);
