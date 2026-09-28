// RTTYCore.cpp – C++ obal jádra MMTTY za C API.
// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
#include "include/RTTYCore.h"
#include "MMTTYCompat.h"
#include "mmtty/Rtty.h"
#include "mmtty/Fft.h"
#include "AFC.h"
#include <cmath>
#include <memory>
#include <vector>

struct RTTYCore {
    RTTYCoreConfig cfg;
    std::unique_ptr<CFSKDEM> dem;
    std::unique_ptr<CFSKMOD> mod;
    std::unique_ptr<CFFT> fft;
    int    fftWindow = 0;     // TSound::m_FFTWINDOW
    int    bpfafc = 1;        // TSound::m_bpfafc
    int    net = 1;
    CRTTY rtty;
    CLMS  lms;
    double HBPF[TAPMAX + 1];
    double ZBPF[TAPMAX + 1];
    int    bpf = 0, lmsOn = 0, bpftap = 56;
    double bpffw = 100.0;
    int    echo = 1;
    int    afc = 1, afcMode = 1;
    double afcSQ = 32, afcTime = 8.0, afcSweep = 1.0;
    int    txActive = 0;
    int    txStopping = 0;
    static constexpr int kBufSize = 1024;   // MMTTY m_BuffSize při 11025 Hz
    int    overflowLatched = 0;
    std::vector<double> block;

    void calcBPF() {
        MakeFilter(HBPF, bpftap, ffBPF, SampFreq,
                   dem->GetMarkFreq() - bpffw, dem->GetSpaceFreq() + bpffw, 60, 1.0);
        lms.SetWindow(dem->GetMarkFreq(), dem->GetSpaceFreq());
    }
};

static bool validRate(double r) {
    if (!std::isfinite(r)) return false;
    return (r >= 11025 * 0.98 && r <= 11025 * 1.02) || (r >= 12000 * 0.98 && r <= 12000 * 1.02);
}

extern "C" RTTYCoreConfig rttycore_default_config(void) {
    RTTYCoreConfig c;
    c.sampleRate = 11025; c.txOffset = 0; c.codeSet = 0; c.doubleShift = 0; c.txUOS = 1;
    return c;
}

extern "C" const char* rttycore_version(void) { return "MMTTYCore 0.1 (MMTTY 1.70H)"; }

extern "C" RTTYCore* rttycore_create(const RTTYCoreConfig* cfg) {
    if (!cfg || !validRate(cfg->sampleRate)) return nullptr;
    // Globály MUSÍ být nastavené PŘED konstrukcí CFSKDEM/CFSKMOD (konstruktory je čtou).
    SampFreq = cfg->sampleRate;
    InitSampType();
    sys.m_SampFreq = SampFreq;
    sys.m_TxOffset = cfg->txOffset;
    sys.m_CodeSet  = cfg->codeSet;
    sys.m_dblsft   = cfg->doubleShift;
    sys.m_txuos    = cfg->txUOS;
    sys.m_TxPort   = txSound;

    auto* c = new RTTYCore();
    c->cfg = *cfg;
    c->dem = std::make_unique<CFSKDEM>();
    c->mod = std::make_unique<CFSKMOD>();
    c->fft = std::make_unique<CFFT>();
    c->fftWindow = (SampType == 2) ? int(3000 * FFT_SIZE / SampFreq) : int(4000 * FFT_SIZE / SampFreq);
    c->mod->SetDem(c->dem.get());
    c->mod->SetSampFreq(SampFreq + sys.m_TxOffset);
    c->rtty.SetCodeSet();
    memset(c->HBPF, 0, sizeof(c->HBPF));
    memset(c->ZBPF, 0, sizeof(c->ZBPF));
    c->calcBPF();
    return c;
}

extern "C" void rttycore_destroy(RTTYCore* c) { delete c; }

extern "C" void rttycore_process_rx(RTTYCore* c, const float* s, size_t n) {
    if (!c || !s || n == 0) return;
    c->block.resize(n);
    for (size_t i = 0; i < n; i++) c->block[i] = std::isfinite(s[i]) ? double(s[i]) * 32768.0 : 0.0;
    double* lp = c->block.data();
    if (c->bpf || c->lmsOn) {
        for (size_t i = 0; i < n; i++) {
            if (c->bpf)   lp[i] = DoFIR(c->HBPF, c->ZBPF, lp[i], c->bpftap);
            if (c->lmsOn) lp[i] = c->lms.Do(lp[i]);
        }
    }
    c->fft->CollectFFT(lp, int(n));
    if (!c->txActive || c->echo) {
        for (size_t i = 0; i < n; i++) c->dem->Do(lp[i]);
    }
    if (c->dem->m_OverFlow) { c->overflowLatched = 1; c->dem->m_OverFlow = 0; }
}

extern "C" size_t rttycore_read_chars(RTTYCore* c, RTTYCoreChar* out, size_t max) {
    if (!c || !out) return 0;
    size_t k = 0;
    while (k < max) {
        int d = c->dem->GetData();
        if (d < 0) break;
        char ch = 0;
        switch (c->dem->m_BitLen) {
            case 7: d &= 0x7f; /* fallthrough */
            case 8: ch = char(d); break;
            default: ch = c->rtty.ConvAscii(d); break;
        }
        if (ch) { out[k].ch = ch; out[k].echo = uint8_t(c->txActive ? 1 : 0); k++; }
    }
    return k;
}

extern "C" RTTYCoreSignal rttycore_signal(RTTYCore* c) {
    RTTYCoreSignal r{};
    if (!c) return r;
    r.level = c->dem->m_avgdeff;
    // Stejný práh jako CFSKDEM::DoFSK: při příjmu (m_Limit) SQLevel × 10.
    double thr = c->dem->m_Limit ? c->dem->GetSQLevel() * 10.0 : c->dem->GetSQLevel();
    r.squelchOpen = (!c->dem->GetSQ() || c->dem->m_avgdeff >= thr) ? 1 : 0;
    r.overflow = c->overflowLatched; c->overflowLatched = 0;
    r.mark = c->dem->GetMarkFreq();
    r.space = c->dem->GetSpaceFreq();
    r.fig = c->rtty.m_fig;
    return r;
}

static bool inRange(double v, double lo, double hi) { return std::isfinite(v) && v >= lo && v <= hi; }
static bool isBool(double v) { return v == 0.0 || v == 1.0; }
static bool isInt(double v, int lo, int hi) { return inRange(v, lo, hi) && v == std::floor(v); }

extern "C" int rttycore_set_param(RTTYCore* c, RTTYCoreParam p, double v) {
    if (!c) return RC_ERR_UNKNOWN;
    CFSKDEM& dem = *c->dem;
    CFSKMOD& mod = *c->mod;
    switch (p) {
    case RC_BAUD:
        if (!inRange(v, 20, 300)) return RC_ERR_RANGE;
        dem.SetBaudRate(v); mod.SetBaudRate(v); break;
    case RC_MARK:
        if (!inRange(v, 100, 3000)) return RC_ERR_RANGE;
        if (!inRange(std::fabs(dem.GetSpaceFreq() - v), 20, 2000)) return RC_ERR_RANGE;
        dem.SetMarkFreq(v); mod.SetMarkFreq(v); c->calcBPF(); break;
    case RC_SPACE:
        if (!inRange(v, 100, 3000)) return RC_ERR_RANGE;
        if (!inRange(std::fabs(v - dem.GetMarkFreq()), 20, 2000)) return RC_ERR_RANGE;
        dem.SetSpaceFreq(v); mod.SetSpaceFreq(v); c->calcBPF(); break;
    case RC_REVERSE:
        if (!isBool(v)) return RC_ERR_RANGE;
        dem.SetRev(int(v)); mod.SetRev(int(v)); break;
    case RC_SQUELCH:
        if (!isBool(v)) return RC_ERR_RANGE;
        dem.SetSQ(int(v)); break;
    case RC_SQUELCH_LEVEL:
        if (!inRange(v, 0, 32768)) return RC_ERR_RANGE;
        dem.SetSQLevel(v); break;
    case RC_DEMOD_TYPE:
        if (!isInt(v, 0, 3)) return RC_ERR_RANGE;
        dem.m_type = int(v); break;
    case RC_IIR_BW:
        if (!inRange(v, 20, 500)) return RC_ERR_RANGE;
        dem.SetIIR(v); break;
    case RC_FIR_TAP:
        if (!isInt(v, 8, TAPMAX)) return RC_ERR_RANGE;
        dem.SetFilterTap(int(v)); break;
    case RC_SMOOTH_TYPE:
        if (!isBool(v)) return RC_ERR_RANGE;
        dem.m_lpf = int(v); break;
    case RC_SMOOTH_FREQ:
        if (!inRange(v, 10, 1000)) return RC_ERR_RANGE;
        dem.SetSmoozFreq(v); break;
    case RC_LPF_FREQ:
        if (!inRange(v, 10, 1000)) return RC_ERR_RANGE;
        dem.SetLPFFreq(v); break;
    case RC_LPF_ORDER:
        if (!isInt(v, 1, 8)) return RC_ERR_RANGE;
        dem.m_lpfOrder = int(v); dem.SetLPFFreq(dem.m_lpffreq); break;
    case RC_ATC:
        if (!isBool(v)) return RC_ERR_RANGE;
        dem.m_atc = int(v); break;
    case RC_MAJORITY:
        if (!isBool(v)) return RC_ERR_RANGE;
        dem.m_majority = int(v); break;
    case RC_IGNORE_FRAMING:
        if (!isBool(v)) return RC_ERR_RANGE;
        dem.m_ignoreFream = int(v); break;
    case RC_BIT_LENGTH:
        if (!isInt(v, 5, 8)) return RC_ERR_RANGE;
        dem.m_BitLen = mod.m_BitLen = int(v); break;
    case RC_STOP_BITS:
        if (!isInt(v, 0, 4)) return RC_ERR_RANGE;
        dem.m_StopLen = mod.m_StopLen = int(v); break;
    case RC_PARITY:
        if (!isInt(v, 0, 4)) return RC_ERR_RANGE;
        dem.m_Parity = mod.m_Parity = int(v); break;
    case RC_LIMITER_AGC:
        if (!isBool(v)) return RC_ERR_RANGE;
        dem.m_LimitAGC = int(v); break;
    case RC_LIMITER_OVERSAMPLE:
        if (!isBool(v)) return RC_ERR_RANGE;
        dem.m_LimitOverSampling = int(v); break;
    case RC_UOS:
        if (!isBool(v)) return RC_ERR_RANGE;
        c->rtty.m_uos = int(v); break;
    case RC_DIDDLE:
        if (!isInt(v, 0, 2)) return RC_ERR_RANGE;
        mod.m_diddle = int(v); break;
    case RC_ECHO:
        if (!isInt(v, 0, 2)) return RC_ERR_RANGE;
        c->echo = int(v); break;
    case RC_AFC:
        if (!isBool(v)) return RC_ERR_RANGE;
        c->afc = int(v); break;
    case RC_AFC_MODE:
        if (!isInt(v, 0, 3)) return RC_ERR_RANGE;
        c->afcMode = int(v); break;
    case RC_AFC_SQ:
        if (!inRange(v, 0, 1024)) return RC_ERR_RANGE;
        c->afcSQ = v; break;
    case RC_AFC_TIME:
        if (!inRange(v, 1, 64)) return RC_ERR_RANGE;
        c->afcTime = v; break;
    case RC_AFC_SWEEP:
        if (!inRange(v, 0.1, 3.0)) return RC_ERR_RANGE;
        c->afcSweep = v; break;
    case RC_RX_BPF:
        if (!isBool(v)) return RC_ERR_RANGE;
        c->bpf = int(v); break;
    case RC_RX_BPF_WIDTH:
        if (!inRange(v, 20, 500)) return RC_ERR_RANGE;
        c->bpffw = v; c->calcBPF(); break;
    case RC_RX_LMS:
        if (!isBool(v)) return RC_ERR_RANGE;
        c->lmsOn = int(v); break;
    case RC_TX_OUTPUT_GAIN:
        if (!inRange(v, 0, 32768)) return RC_ERR_RANGE;
        mod.SetOutputGain(v); break;
    case RC_NET:
        if (!isBool(v)) return RC_ERR_RANGE;
        c->net = int(v); break;
    default:
        return RC_ERR_UNKNOWN;
    }
    return RC_OK;
}

extern "C" double rttycore_get_param(const RTTYCore* c, RTTYCoreParam p) {
    if (!c) return NAN;
    CFSKDEM& dem = *c->dem;
    CFSKMOD& mod = *c->mod;
    switch (p) {
    case RC_BAUD: return dem.GetBaudRate();
    case RC_MARK: return dem.GetMarkFreq();
    case RC_SPACE: return dem.GetSpaceFreq();
    case RC_REVERSE: return dem.GetRev();
    case RC_SQUELCH: return dem.GetSQ();
    case RC_SQUELCH_LEVEL: return dem.GetSQLevel();
    case RC_DEMOD_TYPE: return dem.m_type;
    case RC_IIR_BW: return dem.m_iirfw;
    case RC_FIR_TAP: return dem.GetFilterTap();
    case RC_SMOOTH_TYPE: return dem.m_lpf;
    case RC_SMOOTH_FREQ: return dem.GetSmoozFreq();
    case RC_LPF_FREQ: return dem.m_lpffreq;
    case RC_LPF_ORDER: return dem.m_lpfOrder;
    case RC_ATC: return dem.m_atc;
    case RC_MAJORITY: return dem.m_majority;
    case RC_IGNORE_FRAMING: return dem.m_ignoreFream;
    case RC_BIT_LENGTH: return dem.m_BitLen;
    case RC_STOP_BITS: return dem.m_StopLen;
    case RC_PARITY: return dem.m_Parity;
    case RC_LIMITER_AGC: return dem.m_LimitAGC;
    case RC_LIMITER_OVERSAMPLE: return dem.m_LimitOverSampling;
    case RC_UOS: return c->rtty.m_uos;
    case RC_DIDDLE: return mod.m_diddle;
    case RC_ECHO: return c->echo;
    case RC_AFC: return c->afc;
    case RC_AFC_MODE: return c->afcMode;
    case RC_AFC_SQ: return c->afcSQ;
    case RC_AFC_TIME: return c->afcTime;
    case RC_AFC_SWEEP: return c->afcSweep;
    case RC_RX_BPF: return c->bpf;
    case RC_RX_BPF_WIDTH: return c->bpffw;
    case RC_RX_LMS: return c->lmsOn;
    case RC_TX_OUTPUT_GAIN: return mod.GetOutputGain();
    case RC_NET: return c->net;
    default: return NAN;
    }
}

// --- Vysílání (podle TMmttyWd::XMIT, ToRX a TX větve TSound::Execute) ---

extern "C" void rttycore_tx_begin(RTTYCore* c, int tune) {
    if (!c) return;
    if (c->net) {   // UpdateNet(): TX na kmitočtu RX (po AFC)
        c->mod->SetMarkFreq(c->dem->GetMarkFreq());
        c->mod->SetSpaceFreq(c->dem->GetSpaceFreq());
    }
    c->mod->ClearTXBuf();
    c->rtty.ClearTX();
    c->mod->SetBaudRate(c->dem->GetBaudRate());
    c->mod->m_Amp.Reset();
    c->mod->m_AmpVal = 1;
    c->mod->OutTone(tune ? 1 : 0, RTTYCore::kBufSize);
    if (c->echo != 2) c->dem->ClearRXBuf();
    c->mod->InitPhase();
    c->mod->SetCount(RTTYCore::kBufSize * 3);
    c->mod->SetDiddleTimer(int(SampFreq / 4));     // 0,25 s jako XMIT
    c->txActive = 1;
    c->txStopping = 0;
}

extern "C" size_t rttycore_tx_space(const RTTYCore* c) {
    return c ? size_t(MODBUFMAX - c->mod->GetBufCount()) : 0;
}

extern "C" size_t rttycore_tx_pending(const RTTYCore* c) {
    return c ? size_t(c->mod->GetBufCount()) : 0;
}

extern "C" size_t rttycore_queue_tx(RTTYCore* c, const char* text) {
    if (!c || !text || !c->txActive || c->txStopping) return 0;
    size_t used = 0;
    BYTE codes[8];
    for (const char* p = text; *p; p++) {
        if (rttycore_tx_space(c) < 3) break;
        unsigned char u = (unsigned char)*p;
        used++;
        if (u >= 'a' && u <= 'z') u = u - 'a' + 'A';
        if (!(u == '\r' || u == '\n' || (u >= 0x20 && u < 0x7F))) continue;
        char one[2] = { char(u), 0 };
        int n = c->rtty.ConvRTTY(codes, one);
        for (int i = 0; i < n; i++) c->mod->PutData(codes[i]);
    }
    return used;
}

extern "C" size_t rttycore_generate_tx(RTTYCore* c, float* out, size_t n) {
    if (!c || !out) return 0;
    size_t i = 0;
    if (c->txActive) {
        for (; i < n; i++) {
            if (c->txStopping && !c->mod->GetMode()) { c->txActive = 0; c->txStopping = 0; break; }
            double d = c->mod->Do(c->echo);
            double f = d / 32768.0;
            out[i] = float(f > 1.0 ? 1.0 : (f < -1.0 ? -1.0 : f));
        }
    }
    for (size_t k = i; k < n; k++) out[k] = 0.0f;
    return i;
}

extern "C" void rttycore_tx_stop(RTTYCore* c) {
    if (!c || !c->txActive) return;
    c->mod->SetDiddleTimer(-1);
    c->mod->DeleteTXBuf();
    c->txStopping = 1;
}

extern "C" void rttycore_tx_abort(RTTYCore* c) {
    if (!c) return;
    c->mod->DeleteTXBuf();
    c->txActive = 0; c->txStopping = 0;
}

extern "C" int rttycore_is_tx(const RTTYCore* c) { return c && c->txActive ? 1 : 0; }

// --- Spektrum a AFC (podle TSound::DrawFFT a volání DoAFC z TMmttyWd::TimerTimer) ---

extern "C" int rttycore_tick(RTTYCore* c) {
    if (!c) return 0;
    if (c->fft->m_CollectFFT) {
        double gain;
        switch (sys.m_FFTGain) {
            case 0: gain = 30.0; break;
            case 1: gain = 34.0; break;
            case 2: gain = 42.0; break;
            case 3: gain = 54.0; break;
            default: gain = (c->echo != 2 && c->txActive) ? 0.02 : 0.1; break;
        }
        c->fft->CalcFFT(c->fftWindow, gain, sys.m_FFTResp);
        c->fft->TrigFFT();
    }
    if (!c->afc) return 0;
    if (c->txActive && c->echo != 2) return 0;        // během vysílání AFC neběží
    AFCParams p{ c->afcMode, c->afcSQ, c->afcTime, c->afcSweep, sys.m_FFTGain };
    int r = DoAFC(c->fft->m_fft, c->fftWindow, c->bpfafc, *c->dem, p);
    if (r == AFC_CHANGED_RECALC_BPF) c->calcBPF();
    return r != AFC_NOCHANGE ? 1 : 0;
}

extern "C" size_t rttycore_spectrum(RTTYCore* c, float* out, size_t max, double* binHz) {
    if (!c || !out) return 0;
    size_t n = size_t(c->fftWindow);
    if (n > max) n = max;
    for (size_t i = 0; i < n; i++) out[i] = float(c->fft->m_fft[i]);
    if (binHz) *binHz = SampFreq / FFT_SIZE;
    return n;
}
