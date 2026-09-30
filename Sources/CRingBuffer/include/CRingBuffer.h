// CRingBuffer.h – lock-free SPSC ring buffer for float samples (C11 atomics).
// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
#pragma once
#include <stddef.h>

typedef struct CRingBuffer CRingBuffer;

CRingBuffer* cring_create(size_t capacity);
void   cring_destroy(CRingBuffer* r);
/* Producer (single thread). Returns the number of samples written. */
size_t cring_write(CRingBuffer* r, const float* src, size_t n);
/* Consumer (single thread). Returns the number of samples read. */
size_t cring_read(CRingBuffer* r, float* dst, size_t n);
size_t cring_available(const CRingBuffer* r);
size_t cring_capacity(const CRingBuffer* r);
/* Discards the contents (call from the consumer). */
void   cring_clear(CRingBuffer* r);
/* Asks the consumer to discard the contents (called by the producer); done on the next cring_read. */
void   cring_request_clear(CRingBuffer* r);
