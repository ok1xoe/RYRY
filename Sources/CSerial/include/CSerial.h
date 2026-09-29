// CSerial.h – tenké obaly ioctl pro sériové porty macOS (makra ioctl nejdou do Swiftu).
// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
#pragma once
/* Všechny vrací 0 = OK, jinak errno. */
int cserial_open(const char* path, int* fd_out);
int cserial_close(int fd);
/* raw 8N1 → nastaví dataBits (5–8), stopBits (1/2), bez parity, bez řízení toku. */
int cserial_configure(int fd, int dataBits, int stopBits);
/* Nestandardní rychlost přes IOSSIOSPEED (celá čísla, např. 45). */
int cserial_set_speed(int fd, unsigned long baud);
int cserial_set_rts(int fd, int on);
int cserial_set_dtr(int fd, int on);
int cserial_set_break(int fd, int on);
int cserial_write(int fd, const unsigned char* buf, unsigned long n);
int cserial_drain(int fd);
int cserial_flush_output(int fd);
/* Přečte až n bajtů, čeká nejvýše timeout_ms; *got = počet (0 = nic nepřišlo). */
int cserial_read(int fd, unsigned char* buf, unsigned long n, int timeout_ms, long* got);
int cserial_flush_input(int fd);
