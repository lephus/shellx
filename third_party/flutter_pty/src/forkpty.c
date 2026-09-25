#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include <fcntl.h>
#include <pthread.h>
#include <unistd.h>
#include <termios.h>
#include <sys/ioctl.h>

pid_t pty_forkpty(
    int *master,
    int *slave,
    const struct termios *termp,
    const struct winsize *winp)
{
    // ShellX: O_CLOEXEC on both ends, set atomically, so no process started
    // by another thread (or by a later session) inherits them.
    int ptm = open("/dev/ptmx", O_RDWR | O_NOCTTY | O_CLOEXEC);

    if (ptm < 0)
    {
        return -1;
    }

    if (grantpt(ptm) || unlockpt(ptm))
    {
        close(ptm);
        return -1;
    }

    char *devname;

    if ((devname = ptsname(ptm)) == NULL)
    {
        close(ptm);
        return -1;
    }

    int pts = open(devname, O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (pts < 0)
    {
        close(ptm);
        return -1;
    }

    if (termp)
    {
        tcsetattr(pts, TCSAFLUSH, termp);
    }

    if (winp)
    {
        ioctl(pts, TIOCSWINSZ, winp);
    }

    pid_t pid = fork();

    if (pid < 0)
    {
        close(pts);
        close(ptm);
        return -1;
    }

    if (pid == 0)
    {
        setsid();
        // ShellX: _exit, not exit: this is a fork of a multi-threaded process.
        if (ioctl(pts, TIOCSCTTY, (char *)NULL) == -1)
            _exit(1);

        dup2(pts, STDIN_FILENO);
        dup2(pts, STDOUT_FILENO);
        dup2(pts, STDERR_FILENO);

        if (pts > 2)
        {
            close(pts);
        }
    }
    else
    {
        *master = ptm;
        if (slave)
        {
            *slave = pts;
        }
    }

    return pid;
}
