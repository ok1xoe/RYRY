// RTTYCore.h – C API jádra RTTY z MMTTY.
// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
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
    double sampleRate;   /* 11025 nebo 12000 (± 2 % kvůli korekci ppm), jinak create vrátí NULL */
    double txOffset;     /* korekce vzorkovací frekvence TX v Hz */
    int    codeSet;      /* 0 = US (S-BELL), 1 = J-BELL */
    int    doubleShift;  /* 1 = LTRS/FIGS posílat 2× */
    int    txUOS;        /* 1 = unshift on space při vysílání */
} RTTYCoreConfig;

typedef enum {
    RC_BAUD = 0,            /* 20 .. 300 */
    RC_MARK,                /* 100 .. 3000 Hz */
    RC_SPACE,               /* 100 .. 3000 Hz, |space-mark| 20 .. 2000 */
    RC_REVERSE,             /* 0/1 */
    RC_SQUELCH,             /* 0/1 */
    RC_SQUELCH_LEVEL,       /* 0 .. 32768 (MMTTY m_SQLevel, výchozí 600) */
    RC_DEMOD_TYPE,          /* 0 IIR, 1 FIR, 2 PLL, 3 FFT */
    RC_IIR_BW,              /* 20 .. 500 Hz */
    RC_FIR_TAP,             /* 8 .. 512 */
    RC_SMOOTH_TYPE,         /* 0 moving avg, 1 IIR LPF */
    RC_SMOOTH_FREQ,         /* 10 .. 1000 Hz (MMTTY "Smooz", klouzavý průměr) */
    RC_LPF_FREQ,            /* 10 .. 1000 Hz (MMTTY "SmoozIIR", mez IIR LPF) */
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
    RC_ECHO,                /* 0/1/2 jako sys.m_echo */
    RC_AFC,                 /* 0/1 */
    RC_AFC_MODE,            /* 0 Free, 1 Fixed, 2 HAM, 3 FSK (sys.m_FixShift) */
    RC_AFC_SQ,              /* 0 .. 1024 */
    RC_AFC_TIME,            /* 1 .. 64 */
    RC_AFC_SWEEP,           /* 0.1 .. 3.0 */
    RC_RX_BPF,              /* 0/1 vstupní BPF */
    RC_RX_BPF_WIDTH,        /* 20 .. 500 Hz (TSound m_bpffw, výchozí 100) */
    RC_RX_LMS,              /* 0/1 LMS/notch */
    RC_TX_OUTPUT_GAIN,      /* 0 .. 32768 (CFSKMOD m_OutputGain) */
    RC_PARAM_COUNT
} RTTYCoreParam;

typedef struct { char ch; uint8_t echo; } RTTYCoreChar;

typedef struct {
    double level;        /* CFSKDEM m_avgdeff */
    int    squelchOpen;  /* 1 když squelch vypnutý nebo level >= squelch level */
    int    overflow;     /* 1 = přebuzení od posledního volání rttycore_signal */
    double mark;         /* aktuální mark (po AFC) */
    double space;
    int    fig;          /* 1 = RX ve FIGS */
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

/* Vysílání. tune=1 vysílá jen nosnou mark. */
void   rttycore_tx_begin(RTTYCore* core, int tune);
/* Vrací počet zpracovaných BAJTŮ vstupu (přijatých i vynechaných); zastaví se,
   když v bufferu není místo aspoň na 3 kódy. Malá písmena → velká, bajty mimo
   ASCII 0x20..0x7E (kromě CR/LF) se vynechají. */
size_t rttycore_queue_tx(RTTYCore* core, const char* text);
size_t rttycore_tx_space(const RTTYCore* core);    /* volné místo v bufferu (kódy) */
size_t rttycore_tx_pending(const RTTYCore* core);  /* kódy čekající na odvysílání */
/* Vrací počet vzorků; < n, když vysílání skončilo (zbytek vyplní nulami). */
size_t rttycore_generate_tx(RTTYCore* core, float* out, size_t n);
void   rttycore_tx_stop(RTTYCore* core);   /* dovysílá rozpracovaný znak, zbytek zahodí */
void   rttycore_tx_abort(RTTYCore* core);  /* okamžitý konec */
int    rttycore_is_tx(const RTTYCore* core);

#ifdef __cplusplus
}
#endif
#endif
