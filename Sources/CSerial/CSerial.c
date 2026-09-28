// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
#include "CSerial.h"
#include <errno.h>
#include <fcntl.h>
#include <termios.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <IOKit/serial/ioss.h>

int cserial_open(const char* path, int* fd_out) {
    int fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd < 0) return errno;
    if (ioctl(fd, TIOCEXCL) < 0) { int e = errno; close(fd); return e; }
    /* macOS při otevření zvedne DTR/RTS – hned shodit, aby PTT neblikl (klidový stav nastaví PTTController) */
    int bits = TIOCM_DTR | TIOCM_RTS;
    ioctl(fd, TIOCMBIC, &bits);
    int flags = fcntl(fd, F_GETFL);
    fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);   /* zápis blokující */
    *fd_out = fd;
    return 0;
}

int cserial_close(int fd) { return close(fd) == 0 ? 0 : errno; }

int cserial_configure(int fd, int dataBits, int stopBits) {
    struct termios t;
    if (tcgetattr(fd, &t) < 0) return errno;
    cfmakeraw(&t);
    t.c_cflag &= ~(CSIZE | PARENB | CSTOPB | CRTSCTS);
    t.c_cflag |= CLOCAL | CREAD;
    switch (dataBits) { case 5: t.c_cflag |= CS5; break; case 6: t.c_cflag |= CS6; break;
                        case 7: t.c_cflag |= CS7; break; default: t.c_cflag |= CS8; break; }
    if (stopBits >= 2) t.c_cflag |= CSTOPB;
    t.c_cflag |= HUPCL;                       /* při zavření (i pádu procesu) shodit DTR/RTS → PTT off */
    if (tcsetattr(fd, TCSANOW, &t) < 0) return errno;
    return 0;
}

int cserial_set_speed(int fd, unsigned long baud) {
    speed_t s = (speed_t)baud;
    return ioctl(fd, IOSSIOSPEED, &s) < 0 ? errno : 0;
}

static int modem_bit(int fd, int bit, int on) {
    return ioctl(fd, on ? TIOCMBIS : TIOCMBIC, &bit) < 0 ? errno : 0;
}
int cserial_set_rts(int fd, int on) { return modem_bit(fd, TIOCM_RTS, on); }
int cserial_set_dtr(int fd, int on) { return modem_bit(fd, TIOCM_DTR, on); }
int cserial_set_break(int fd, int on) { return ioctl(fd, on ? TIOCSBRK : TIOCCBRK) < 0 ? errno : 0; }

int cserial_write(int fd, const unsigned char* buf, unsigned long n) {
    while (n > 0) {
        ssize_t w = write(fd, buf, n);
        if (w < 0) { if (errno == EINTR) continue; return errno; }
        buf += w; n -= (unsigned long)w;
    }
    return 0;
}

int cserial_drain(int fd) { return tcdrain(fd) < 0 ? errno : 0; }

int cserial_flush_output(int fd) { return tcflush(fd, TCOFLUSH) < 0 ? errno : 0; }
