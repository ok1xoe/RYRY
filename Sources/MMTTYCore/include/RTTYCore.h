// RTTYCore.h – the C API of the RTTY core from MMTTY.
// Copyright 2026 OK1XOE (RYRY), LGPL v3
#ifndef RTTYCORE_H
#define RTTYCORE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct RTTYCore RTTYCore;

#define RC_OK           0
#define RC_ERR_UNKNOWN  (-1)
#define RC_ERR_RANGE    (-2)

typedef struct {
    double sampleRate;   /* 11025 or 12000 (± 2 % for the ppm correction), otherwise create returns NULL */
    double txOffset;     /* TX sample rate correction in Hz */
    int    codeSet;      /* 0 = US (S-BELL), 1 = J-BELL */
    int    doubleShift;  /* 1 = send LTRS/FIGS twice */
    int    txUOS;        /* 1 = unshift on space when transmitting */
} RTTYCoreConfig;

typedef enum {
    RC_BAUD = 0,            /* 20 .. 300 */
    RC_MARK,                /* 100 .. 3000 Hz */
    RC_SPACE,               /* 100 .. 3000 Hz, |space-mark| 20 .. 2000 */
    RC_REVERSE,             /* 0/1 */
    RC_SQUELCH,             /* 0/1 */
    RC_SQUELCH_LEVEL,       /* 0 .. 32768 (MMTTY m_SQLevel, default 600) */
    RC_DEMOD_TYPE,          /* 0 IIR, 1 FIR, 2 PLL, 3 FFT */
    RC_IIR_BW,              /* 20 .. 500 Hz */
    RC_FIR_TAP,             /* 8 .. 512 */
    RC_SMOOTH_TYPE,         /* 0 moving avg, 1 IIR LPF */
    RC_SMOOTH_FREQ,         /* 10 .. 1000 Hz (MMTTY "Smooz", moving average) */
    RC_LPF_FREQ,            /* 10 .. 1000 Hz (MMTTY "SmoozIIR", IIR LPF cutoff) */
    RC_LPF_ORDER,           /* 1 .. 8 */
    RC_ATC,                 /* 0/1 */
    RC_MAJORITY,            /* 0/1 */
    RC_IGNORE_FRAMING,      /* 0/1 */
    RC_BIT_LENGTH,          /* 5 .. 8 */
    RC_STOP_BITS,           /* 0 .. 4 (MMTTY m_StopLen: 0=1, 1=1.5, 2=2, 3=1, 4=1.42) */
    RC_PARITY,              /* 0 .. 4 (none, even, odd, mark, space) */
    RC_LIMITER_AGC,         /* 0/1 */
    RC_LIMITER_OVERSAMPLE,  /* 0/1 */
    RC_UOS,                 /* 0/1 RX unshift on space */
    RC_DIDDLE,              /* 0 off, 1 BLK, 2 LTR */
    RC_ECHO,                /* 0/1/2 like sys.m_echo */
    RC_AFC,                 /* 0/1 */
    RC_AFC_MODE,            /* 0 Free, 1 Fixed, 2 HAM, 3 FSK (sys.m_FixShift) */
    RC_AFC_SQ,              /* 0 .. 1024 */
    RC_AFC_TIME,            /* 1 .. 64 */
    RC_AFC_SWEEP,           /* 0.1 .. 3.0 */
    RC_RX_BPF,              /* 0/1 input BPF */
    RC_RX_BPF_WIDTH,        /* 20 .. 500 Hz (TSound m_bpffw, default 100) */
    RC_RX_LMS,              /* 0/1 LMS/notch */
    RC_TX_OUTPUT_GAIN,      /* 0 .. 32768 (CFSKMOD m_OutputGain) */
    RC_NET,                 /* 0/1: on tx_begin the TX frequencies are taken from RX (after AFC), default 1 */
    /* Plan 7: filters and parameters from the MMTTY Setup dialog */
    RC_AA6YQ,               /* 0/1 AA6YQ filter (BPF mark..space + BEF in the centre), CFSKDEM::m_AA6YQ */
    RC_AA6YQ_BPF_TAPS,      /* 16 .. 1024 (default 512) */
    RC_AA6YQ_BPF_FW,        /* 5 .. 500 Hz BPF margin (default 35) */
    RC_AA6YQ_BEF_TAPS,      /* 16 .. 1024 (default 256) */
    RC_AA6YQ_BEF_FW,        /* 5 .. 100 Hz BEF half-width (default 15) */
    RC_LMS_TYPE,            /* 0 LMS, 1 notch (CLMS::m_Type, default 1) */
    RC_NOTCH_FREQ,          /* 0 .. 3000 Hz (0 or inside mark..space = the centre) */
    RC_NOTCH2_FREQ,         /* 0 .. 3000 Hz the second notch (only with RC_TWO_NOTCH) */
    RC_TWO_NOTCH,           /* 0/1 */
    RC_NOTCH_TAPS,          /* 8 .. 512 (default 72) */
    RC_LMS_TAPS,            /* 8 .. 512 (default 56) */
    RC_LMS_MU2,             /* 0 .. 1 (default 0.003) */
    RC_LMS_GAMMA,           /* 0 .. 1 (default 0.9999) */
    RC_LMS_DELAY,           /* 0 .. 512 */
    RC_LMS_AGC,             /* 0/1 */
    RC_LMS_INV,             /* 0/1 */
    RC_LMS_BPF,             /* 0/1 (default 1) */
    RC_PLL_VCO_GAIN,        /* (0, 100] (default 3) */
    RC_PLL_LOOP_ORDER,      /* 1 .. 31 (default 2) */
    RC_PLL_LOOP_FC,         /* 1 .. 2500 Hz (default 250) */
    RC_PLL_OUT_ORDER,       /* 1 .. 31 (default 4) */
    RC_PLL_OUT_FC,          /* 1 .. 2500 Hz (default 200) */
    RC_TX_BPF,              /* 0/1 TX BPF (default 1) */
    RC_TX_LPF,              /* 0/1 TX LPF (shaping) */
    RC_TX_LPF_FREQ,         /* 10 .. 1000 Hz (default 100) */
    RC_TX_CHAR_WAIT,        /* 0 .. 50 (MMTTY TXCharWait) */
    RC_TX_CHAR_WAIT_DIDDLE, /* 0/1 fill the wait with diddle */
    RC_TX_RANDOM_DIDDLE,    /* 0/1 random diddle */
    /* Plan 9 (an extension over MMTTY) */
    RC_AFC_MAX_DEV,         /* 0 .. 1000 Hz: AFC must not drift further from the manually set mark (0 = no limit) */
    RC_AFC_GATE,            /* 0/1: AFC only when the signal level is above the squelch threshold */
    RC_PARAM_COUNT
} RTTYCoreParam;

typedef struct { char ch; uint8_t echo; } RTTYCoreChar;

typedef struct {
    double level;        /* CFSKDEM m_avgdeff */
    int    squelchOpen;  /* 1 when the squelch is off or level >= the squelch level */
    int    overflow;     /* 1 = overdrive since the last rttycore_signal call */
    double mark;         /* the current mark (after AFC) */
    double space;
    int    fig;          /* 1 = RX in FIGS */
} RTTYCoreSignal;

RTTYCoreConfig rttycore_default_config(void);
const char* rttycore_version(void);

RTTYCore* rttycore_create(const RTTYCoreConfig* cfg);
void      rttycore_destroy(RTTYCore* core);

void      rttycore_process_rx(RTTYCore* core, const float* samples, size_t n);
size_t    rttycore_read_chars(RTTYCore* core, RTTYCoreChar* out, size_t max);
RTTYCoreSignal rttycore_signal(RTTYCore* core);

int       rttycore_set_param(RTTYCore* core, RTTYCoreParam p, double value);
double    rttycore_get_param(const RTTYCore* core, RTTYCoreParam p);

/* Transmitting. tune=1 sends only the mark carrier (no diddle, no text).
   Echo (RC_ECHO): 0 = codes straight into RX, 1 = RX decodes our own TX audio, 2 = RX listens to the input. */
void   rttycore_tx_begin(RTTYCore* core, int tune);
/* Returns the number of input BYTES processed (both accepted and skipped); it stops
   when there is no room for at least 3 codes in the buffer. Lower case → upper case. Skipped: bytes outside
   ASCII 0x20..0x7E (except CR/LF and FIGS 0x1B / LTRS 0x1F, which force a shift), characters with no Baudot code (@ # % * + < = > \ ^ ` { | })
   and the MMTTY control characters (_ ~ [ ]). During tune (tx_begin(core,1)) nothing is accepted. */
size_t rttycore_queue_tx(RTTYCore* core, const char* text);
/* Raw codes into the TX buffer (MMTTY bit order) including the control ones: 0xFF mark for 3 bits,
   0xFE carrier off, 0xFD diddle off, 0xFC diddle on. Returns the number accepted. */
size_t rttycore_queue_tx_raw(RTTYCore* core, const uint8_t* codes, size_t n);
size_t rttycore_tx_space(const RTTYCore* core);    /* free room in the buffer (codes) */
size_t rttycore_tx_pending(const RTTYCore* core);  /* codes waiting to be transmitted */
/* Returns the number of samples; < n when the transmission ended (the rest is filled with zeros). */
size_t rttycore_generate_tx(RTTYCore* core, float* out, size_t n);
void   rttycore_tx_stop(RTTYCore* core);   /* finishes the character in progress, discards the rest */
void   rttycore_tx_abort(RTTYCore* core);  /* immediate end */
int    rttycore_is_tx(const RTTYCore* core);
/* The codes (5-bit, MMTTY bit order) that the modulator has started transmitting since the last call,
   including diddle and LTRS/FIGS; the control codes 0xFC–0xFF are not returned. For the FSK keyer. */
size_t rttycore_read_fsk_codes(RTTYCore* core, uint8_t* out, size_t max);

/* Call after every ~100 ms of processed samples: it computes the FFT and runs AFC.
   Returns 1 when AFC changed mark/space. */
int    rttycore_tick(RTTYCore* core);
/* XY scope (MMTTY): enable/disable collection; read a batch of points (mark, space) – 0 until the batch is full.
   After it is read, collection of the next batch starts again. */
void   rttycore_set_xy(RTTYCore* core, int on);
size_t rttycore_read_xy(RTTYCore* core, float* x, float* y, size_t max);
/* Right button in the MMTTY spectrum: with the notch type it sets the notch at hz (and switches LMS/notch on),
   when it is already on, it moves the previous notch into the second one. With the LMS type it does nothing. */
void   rttycore_notch_click(RTTYCore* core, double hz);
/* Demodulator scope (MMTTY TTScope): enable/disable collection of batches of 8192 samples.
   Source 0 = the filter output, 1 = the detector, 2 = LPF (the integrator), 3 = ATC (only with ATC on).
   ready = 1 when the batch (bit + sync) is full. read returns 0 until the source is full; it does not clear the batch
   (so all the sources of the same instant can be read). mark/space are the levels / 32768, bit 0/1,
   sync: 1 = bit sampling, −1 = start bit, −0.5 = stop bit. rearm starts collecting the next batch. */
void   rttycore_set_scope(RTTYCore* core, int on);
int    rttycore_scope_ready(RTTYCore* core);
size_t rttycore_read_scope(RTTYCore* core, int source, float* mark, float* space, float* bit, float* sync, size_t max);
void   rttycore_scope_rearm(RTTYCore* core);
/* The latest spectrum (CFFT::m_fft), returns the number of bins; *binHz = the bin width. */
size_t rttycore_spectrum(RTTYCore* core, float* out, size_t max, double* binHz);

#ifdef __cplusplus
}
#endif
#endif
