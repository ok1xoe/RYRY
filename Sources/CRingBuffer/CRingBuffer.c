// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
#include "CRingBuffer.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct CRingBuffer {
    size_t cap;              /* number of slots = capacity + 1 */
    float* buf;
    _Atomic size_t head;     /* write (producer) */
    _Atomic size_t tail;     /* read (consumer) */
    _Atomic int clear_req;   /* the producer requests a flush */
};

CRingBuffer* cring_create(size_t capacity) {
    CRingBuffer* r = calloc(1, sizeof(CRingBuffer));
    if (!r) return NULL;
    r->cap = capacity + 1;
    r->buf = calloc(r->cap, sizeof(float));
    if (!r->buf) { free(r); return NULL; }
    atomic_init(&r->head, 0);
    atomic_init(&r->tail, 0);
    atomic_init(&r->clear_req, 0);
    return r;
}

void cring_destroy(CRingBuffer* r) { if (r) { free(r->buf); free(r); } }

size_t cring_capacity(const CRingBuffer* r) { return r->cap - 1; }

size_t cring_available(const CRingBuffer* r) {
    size_t h = atomic_load_explicit(&((CRingBuffer*)r)->head, memory_order_acquire);
    size_t t = atomic_load_explicit(&((CRingBuffer*)r)->tail, memory_order_acquire);
    return (h + r->cap - t) % r->cap;
}

size_t cring_write(CRingBuffer* r, const float* src, size_t n) {
    size_t h = atomic_load_explicit(&r->head, memory_order_relaxed);
    size_t t = atomic_load_explicit(&r->tail, memory_order_acquire);
    size_t free_ = (t + r->cap - h - 1) % r->cap;
    if (n > free_) n = free_;
    size_t first = r->cap - h; if (first > n) first = n;
    memcpy(r->buf + h, src, first * sizeof(float));
    memcpy(r->buf, src + first, (n - first) * sizeof(float));
    atomic_store_explicit(&r->head, (h + n) % r->cap, memory_order_release);
    return n;
}

void cring_request_clear(CRingBuffer* r) { atomic_store_explicit(&r->clear_req, 1, memory_order_release); }

size_t cring_read(CRingBuffer* r, float* dst, size_t n) {
    if (atomic_exchange_explicit(&r->clear_req, 0, memory_order_acq_rel)) {
        size_t h = atomic_load_explicit(&r->head, memory_order_acquire);
        atomic_store_explicit(&r->tail, h, memory_order_release);
    }
    size_t t = atomic_load_explicit(&r->tail, memory_order_relaxed);
    size_t h = atomic_load_explicit(&r->head, memory_order_acquire);
    size_t avail = (h + r->cap - t) % r->cap;
    if (n > avail) n = avail;
    size_t first = r->cap - t; if (first > n) first = n;
    memcpy(dst, r->buf + t, first * sizeof(float));
    memcpy(dst + first, r->buf, (n - first) * sizeof(float));
    atomic_store_explicit(&r->tail, (t + n) % r->cap, memory_order_release);
    return n;
}

void cring_clear(CRingBuffer* r) {
    size_t h = atomic_load_explicit(&r->head, memory_order_acquire);
    atomic_store_explicit(&r->tail, h, memory_order_release);
}
