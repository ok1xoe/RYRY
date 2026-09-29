// CRingBuffer.h – lock-free SPSC ring buffer pro float vzorky (C11 atomics).
// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
#pragma once
#include <stddef.h>

typedef struct CRingBuffer CRingBuffer;

CRingBuffer* cring_create(size_t capacity);
void   cring_destroy(CRingBuffer* r);
/* Producent (jedno vlákno). Vrací počet zapsaných vzorků. */
size_t cring_write(CRingBuffer* r, const float* src, size_t n);
/* Konzument (jedno vlákno). Vrací počet přečtených vzorků. */
size_t cring_read(CRingBuffer* r, float* dst, size_t n);
size_t cring_available(const CRingBuffer* r);
size_t cring_capacity(const CRingBuffer* r);
/* Zahodí obsah (volat z konzumenta). */
void   cring_clear(CRingBuffer* r);
/* Požádá konzumenta o zahození obsahu (volá producent); provede se při příštím cring_read. */
void   cring_request_clear(CRingBuffer* r);
