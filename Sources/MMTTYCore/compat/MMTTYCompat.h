// MMTTYCompat.h – náhrady typů a maker z Windows/VCL/ComLib.h pro jádro MMTTY.
// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
#pragma once
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <cmath>
#include <cstdio>
#include <cfloat>
#define MAXDOUBLE DBL_MAX

#define __fastcall
typedef int BOOL;
typedef uint8_t BYTE;
typedef uint16_t WORD;
typedef uint32_t DWORD;
typedef const char* LPCSTR;
typedef char* LPSTR;
#ifndef TRUE
#define TRUE 1
#define FALSE 0
#endif
#define ABS(c) (((c) < 0) ? (-(c)) : (c))

// z ComLib.h
enum { txSound, txTXD, txTXDOnly };

// Podmnožina SYSSET z ComLib.h, kterou jádro skutečně čte (výchozí hodnoty z Main.cpp).
struct CoreSys {
    double m_SampFreq = 11025.0;
    double m_TxOffset = 0.0;
    int    m_TxPort   = txSound;
    int    m_LWait    = 0;
    int    m_CodeSet  = 0;   // 0 = S-BELL (US), 1 = J-BELL
    int    m_txuos    = 1;
    int    m_dblsft   = 0;
    int    m_FFTGain  = 1;
    int    m_FFTResp  = 2;
};

extern CoreSys sys;
extern double SampFreq, SampBase, DemSamp;
extern int DemOver, FFT_SIZE, SampType, SampSize;
extern int FSKCount, FSKCount1, FSKCount2, FSKDeff;
void InitSampType(void);
