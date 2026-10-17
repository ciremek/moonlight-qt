#include "awdl.h"

#include <QtGlobal>

#include "SDL_compat.h"

#ifdef Q_OS_DARWIN
#include <fcntl.h>
#include <ifaddrs.h>
#include <pwd.h>
#include <net/if.h>
#include <spawn.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include <QProcess>
#include <QStringList>

extern char** environ;

#define AWDL_INTERFACE "awdl0"
#define IFCONFIG_PATH "/sbin/ifconfig"
#define SUDO_PATH "/usr/bin/sudo"
// Shared with the standalone AWDL Toggle app, so either one can install it
#define SUDOERS_PATH "/etc/sudoers.d/awdl"

static int runCommand(const char* const argv[])
{
    pid_t pid;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);

    int err = posix_spawn(&pid, argv[0], &actions, nullptr, const_cast<char* const*>(argv), environ);
    posix_spawn_file_actions_destroy(&actions);
    if (err != 0) {
        return -1;
    }

    int status;
    if (waitpid(pid, &status, 0) < 0 || !WIFEXITED(status)) {
        return -1;
    }

    return WEXITSTATUS(status);
}
#endif

AwdlBlocker::AwdlBlocker(bool enabled)
    : m_Stopping(false),
      m_WasUp(false),
      m_KillCount(0)
{
#ifdef Q_OS_DARWIN
    if (!enabled) {
        return;
    }

    if (!isControlReady()) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "AWDL control is not set up; leaving AWDL untouched");
        return;
    }

    m_WasUp = isInterfaceUp();
    if (m_WasUp) {
        setInterfaceUp(false);
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "AWDL disabled for streaming");
    m_Watchdog = std::thread(&AwdlBlocker::watchdogLoop, this);
#else
    Q_UNUSED(enabled);
#endif
}

AwdlBlocker::~AwdlBlocker()
{
    if (!m_Watchdog.joinable()) {
        return;
    }

    {
        std::lock_guard<std::mutex> lock(m_Mutex);
        m_Stopping = true;
    }
    m_Cond.notify_all();
    m_Watchdog.join();

    // Only hand AWDL back if it was up before the stream started
    if (m_WasUp) {
        setInterfaceUp(true);
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "AWDL restored (watchdog took it down %d times during the stream)",
                m_KillCount.load());
}

void AwdlBlocker::watchdogLoop()
{
    std::unique_lock<std::mutex> lock(m_Mutex);
    while (!m_Cond.wait_for(lock, std::chrono::seconds(1), [this] { return m_Stopping; })) {
        if (isInterfaceUp() && setInterfaceUp(false)) {
            m_KillCount++;
        }
    }
}

bool AwdlBlocker::isInterfaceUp()
{
#ifdef Q_OS_DARWIN
    struct ifaddrs* head;
    if (getifaddrs(&head) != 0) {
        return false;
    }

    bool up = false;
    for (struct ifaddrs* entry = head; entry != nullptr; entry = entry->ifa_next) {
        if (strcmp(entry->ifa_name, AWDL_INTERFACE) == 0) {
            up = (entry->ifa_flags & IFF_UP) != 0;
            break;
        }
    }

    freeifaddrs(head);
    return up;
#else
    return false;
#endif
}

bool AwdlBlocker::setInterfaceUp(bool up)
{
#ifdef Q_OS_DARWIN
    const char* const argv[] = { SUDO_PATH, "-n", IFCONFIG_PATH, AWDL_INTERFACE, up ? "up" : "down", nullptr };
    return runCommand(argv) == 0;
#else
    Q_UNUSED(up);
    return false;
#endif
}

bool AwdlBlocker::isControlReady()
{
#ifdef Q_OS_DARWIN
    // sudo -l only says a command is permitted, not that it runs without a password,
    // so re-apply the current state (a no-op) non-interactively instead.
    const char* const argv[] = { SUDO_PATH, "-n", "-k", IFCONFIG_PATH, AWDL_INTERFACE,
                                 isInterfaceUp() ? "up" : "down", nullptr };
    return runCommand(argv) == 0;
#else
    return false;
#endif
}

bool AwdlBlocker::installSudoersRule()
{
#ifdef Q_OS_DARWIN
    struct passwd* pw = getpwuid(getuid());
    if (pw == nullptr) {
        return false;
    }

    QString user = QString::fromLocal8Bit(pw->pw_name);

    QString rule = QString("%1 ALL=(root) NOPASSWD: %2 %3 up, %2 %3 down")
            .arg(user, IFCONFIG_PATH, AWDL_INTERFACE);
    QString tmpPath = QString("/tmp/moonvibe.sudoers.%1").arg(getpid());
    QString script = QStringList {
        QString("printf '%s\\n' '%1' > %2").arg(rule, tmpPath),
        QString("/usr/sbin/visudo -cf %1").arg(tmpPath),
        QString("/usr/bin/install -m 0440 -o root -g wheel %1 %2").arg(tmpPath, SUDOERS_PATH),
        QString("rm -f %1").arg(tmpPath),
    }.join(" && ");

    QString escaped = script;
    escaped.replace("\\", "\\\\").replace("\"", "\\\"");

    QProcess::execute("/usr/bin/osascript",
                      { "-e", QString("do shell script \"%1\" with administrator privileges").arg(escaped) });

    return isControlReady();
#else
    return false;
#endif
}
