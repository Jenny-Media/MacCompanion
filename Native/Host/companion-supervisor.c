/* Development process boundary for an authorized, finite streaming lease.
 * No discovery, pairing, grant or configuration semantics live here.
 */
#include <errno.h>
#include <mach/mach_time.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/event.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t stopping;
static void stop_requested(int signal_number) { stopping = signal_number; }

static uint64_t uptime_nanoseconds(void) {
    mach_timebase_info_data_t scale;
    if (mach_timebase_info(&scale) != KERN_SUCCESS || scale.denom == 0) { return 0; }
    return (uint64_t)(((__uint128_t)mach_absolute_time() * scale.numer) / scale.denom);
}

int main(int argc, char **argv) {
    if (argc < 3 || argv[2][0] != '/') { return 64; }
    char *end;
    if (argv[1][0] < '0' || argv[1][0] > '9') { return 64; }
    errno = 0;
    uint64_t deadline = strtoull(argv[1], &end, 10);
    if (*end || errno == ERANGE || deadline == 0) { return 64; }
    uint64_t now = uptime_nanoseconds();
    if (!now) { return 70; }
    if (deadline <= now) { return 124; }
    if (deadline - now > UINT64_C(14400000000000)) { return 64; }
    pid_t owner = getppid();
    if (owner <= 1) { return 70; }
    int events = kqueue();
    if (events < 0) { return 70; }
    struct kevent watch;
    EV_SET(&watch, owner, EVFILT_PROC, EV_ADD | EV_ENABLE | EV_ONESHOT, NOTE_EXIT, 0, NULL);
    if (kevent(events, &watch, 1, NULL, 0, NULL) < 0 || getppid() != owner) { close(events); return 70; }
    struct sigaction action = {0};
    action.sa_handler = stop_requested;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGHUP, &action, NULL);
    pid_t child = fork();
    if (child < 0) { close(events); return 70; }
    if (child == 0) {
        close(events);
        setpgid(0, 0);
        signal(SIGTERM, SIG_DFL);
        signal(SIGINT, SIG_DFL);
        signal(SIGHUP, SIG_DFL);
        umask(0077);
        execv(argv[2], &argv[2]);
        _exit(127);
    }
    setpgid(child, child);
    int reason = 0;
    int status = 0;
    for (;;) {
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child) { close(events); return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status); }
        if (result < 0 && errno != EINTR) { reason = 70; break; }
        now = uptime_nanoseconds();
        if (stopping) { reason = 128 + stopping; break; }
        if (!now) { reason = 70; break; }
        if (now >= deadline) { reason = 124; break; }
        struct timespec interval = {.tv_sec = 0, .tv_nsec = 50000000};
        struct kevent event;
        int count = kevent(events, NULL, 0, &event, 1, &interval);
        if (count == 1 && event.filter == EVFILT_PROC && (event.fflags & NOTE_EXIT)) { reason = 125; break; }
        if (count < 0 && errno != EINTR) { reason = 70; break; }
    }
    // The Desktop profile cannot spawn apps. Kill the child group as well as
    // its direct process to clean up any future helper descendants.
    kill(-child, SIGTERM);
    kill(child, SIGTERM);
    uint64_t stopped = uptime_nanoseconds();
    for (;;) {
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child) { break; }
        if (result < 0 && errno == ECHILD) { break; }
        now = uptime_nanoseconds();
        if (!now || !stopped || now - stopped > UINT64_C(1000000000)) {
            kill(-child, SIGKILL);
            kill(child, SIGKILL);
            while (waitpid(child, &status, 0) < 0 && errno == EINTR) { }
            break;
        }
        struct timespec pause = {.tv_sec = 0, .tv_nsec = 10000000};
        nanosleep(&pause, NULL);
    }
    close(events);
    return reason;
}
