// AFC.h – automatic frequency control (AFC) extracted from TSound::DoAFC (MMTTY Sound.cpp).
// Copyright 2000-2013 Makoto Mori, Nobuyuki Oba; Modifications Copyright 2026 OK1XOE, LGPL v3
#pragma once
#include "MMTTYCompat.h"
#include "mmtty/Rtty.h"

struct AFCParams {
    int    fixShift;   // sys.m_FixShift: 0 Free, 1 Fixed, 2 HAM, 3 FSK
    double sq;         // sys.m_AFCSQ
    double time;       // sys.m_AFCTime
    double sweep;      // sys.m_AFCSweep
    int    fftGain;    // sys.m_FFTGain
};

enum { AFC_NOCHANGE = 0, AFC_CHANGED = 1, AFC_CHANGED_RECALC_BPF = 2 };

// fft = CFFT::m_fft, fftWindow = TSound::m_FFTWINDOW, bpfafc = TSound::m_bpfafc.
// Returns AFC_NOCHANGE, AFC_CHANGED or AFC_CHANGED_RECALC_BPF (the caller recomputes the input BPF).
int DoAFC(const int* fft, int fftWindow, int bpfafc, CFSKDEM& dem, const AFCParams& p);
