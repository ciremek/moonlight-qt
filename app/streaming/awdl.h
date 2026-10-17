#pragma once

#include <atomic>
#include <functional>
#include <condition_variable>
#include <mutex>
#include <thread>

class QObject;

// Keeps the macOS AWDL interface (awdl0) down while alive, which avoids the
// periodic Wi-Fi latency spikes AWDL causes during streaming. macOS brings
// awdl0 back up on its own, so a watchdog thread takes it down again.
//
// Toggling awdl0 requires root, which is granted through a scoped sudoers
// rule (see installSudoersRule()). Without that rule, this class does nothing.
class AwdlBlocker
{
public:
    explicit AwdlBlocker(bool enabled);
    ~AwdlBlocker();

    // True if awdl0 can be toggled without a password prompt
    static bool isControlReady();

    // Installs the sudoers rule through the standard macOS admin prompt.
    // Returns true if AWDL control is ready afterwards.
    static bool installSudoersRule();

    // Same without blocking: done(ready) runs on context's thread once the prompt is answered
    static void installSudoersRuleAsync(QObject* context, std::function<void(bool)> done);

private:
    static bool isInterfaceUp();
    static bool setInterfaceUp(bool up);
    void watchdogLoop();

    std::thread m_Watchdog;
    std::mutex m_Mutex;
    std::condition_variable m_Cond;
    bool m_Stopping;
    bool m_WasUp;
    std::atomic<int> m_KillCount;
};
