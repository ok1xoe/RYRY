// CSerial.h – thin ioctl wrappers for macOS serial ports (the ioctl macros are not visible to Swift).
// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
#pragma once
/* All return 0 = OK, otherwise errno. */
int cserial_open(const char* path, int* fd_out);
int cserial_close(int fd);
/* raw 8N1 → sets dataBits (5–8), stopBits (1/2), no parity, no flow control. */
int cserial_configure(int fd, int dataBits, int stopBits);
/* Non-standard speed via IOSSIOSPEED (integers, e.g. 45). */
int cserial_set_speed(int fd, unsigned long baud);
int cserial_set_rts(int fd, int on);
int cserial_set_dtr(int fd, int on);
int cserial_set_break(int fd, int on);
int cserial_write(int fd, const unsigned char* buf, unsigned long n);
int cserial_drain(int fd);
int cserial_flush_output(int fd);
/* Reads up to n bytes, waits at most timeout_ms; *got = the count (0 = nothing arrived). */
int cserial_read(int fd, unsigned char* buf, unsigned long n, int timeout_ms, long* got);
int cserial_flush_input(int fd);
/* Write with an overall timeout_ms limit; ETIMEDOUT when the port is stuck. */
int cserial_write_timeout(int fd, const unsigned char* buf, unsigned long n, int timeout_ms);
