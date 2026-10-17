#include "swiftuishell.h"
#include "moonvibeui.h"

#include "backend/computermanager.h"
#include "streaming/session.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>

SwiftUIShell* SwiftUIShell::s_Instance = nullptr;

SwiftUIShell::SwiftUIShell(ComputerManager* computerManager, QObject* parent)
    : QObject(parent),
      m_ComputerManager(computerManager),
      m_Session(nullptr)
{
    Q_ASSERT(s_Instance == nullptr);
    s_Instance = this;

    connect(m_ComputerManager, &ComputerManager::computerStateChanged,
            this, &SwiftUIShell::pushComputers, Qt::QueuedConnection);
}

void SwiftUIShell::show()
{
    mv_ui_show(&SwiftUIShell::handleLaunchRequest, &SwiftUIShell::handleQuitRequest);
    pushComputers();
    m_ComputerManager->startPolling();
}

void SwiftUIShell::pushComputers()
{
    QJsonArray computers;

    for (NvComputer* computer : m_ComputerManager->getComputers()) {
        QReadLocker lock(&computer->lock);

        QJsonArray apps;
        for (const NvApp& app : computer->appList) {
            if (!app.hidden) {
                apps.append(QJsonObject {
                    { "id", app.id },
                    { "name", app.name },
                });
            }
        }

        computers.append(QJsonObject {
            { "uuid", computer->uuid },
            { "name", computer->name },
            { "online", computer->state == NvComputer::CS_ONLINE },
            { "paired", computer->pairState == NvComputer::PS_PAIRED },
            { "runningAppId", computer->currentGameId },
            { "apps", apps },
        });
    }

    mv_ui_update_computers(QJsonDocument(computers).toJson(QJsonDocument::Compact).constData());
}

void SwiftUIShell::handleLaunchRequest(const char* computerUuid, int appId)
{
    // Leave the SwiftUI event handler before doing any heavy lifting
    QString uuid = QString::fromUtf8(computerUuid);
    QMetaObject::invokeMethod(s_Instance, [uuid, appId] {
        s_Instance->launch(uuid, appId);
    }, Qt::QueuedConnection);
}

void SwiftUIShell::handleQuitRequest()
{
    QMetaObject::invokeMethod(QCoreApplication::instance(), &QCoreApplication::quit, Qt::QueuedConnection);
}

void SwiftUIShell::setStatus(const QString& text, bool busy)
{
    mv_ui_set_status(text.toUtf8().constData(), busy);
}

void SwiftUIShell::launch(const QString& computerUuid, int appId)
{
    if (m_Session != nullptr) {
        return;
    }

    NvComputer* computer = nullptr;
    NvApp app;
    for (NvComputer* candidate : m_ComputerManager->getComputers()) {
        QReadLocker lock(&candidate->lock);
        if (candidate->uuid != computerUuid) {
            continue;
        }

        for (const NvApp& candidateApp : candidate->appList) {
            if (candidateApp.id == appId) {
                computer = candidate;
                app = candidateApp;
                break;
            }
        }
        break;
    }

    if (computer == nullptr) {
        setStatus(tr("This app is no longer available."), false);
        return;
    }

    m_LaunchError.clear();
    m_Session = new Session(computer, app);

    connect(m_Session, &Session::stageStarting, this, [this](QString stage) {
        setStatus(tr("Starting %1...").arg(stage), true);
    });
    connect(m_Session, &Session::stageFailed, this, [this](QString stage, int errorCode, QString failingPorts) {
        m_LaunchError = tr("Starting %1 failed: Error %2").arg(stage).arg(errorCode);
        if (!failingPorts.isEmpty()) {
            m_LaunchError += " " + tr("Check your firewall and port forwarding rules for port(s): %1").arg(failingPorts);
        }
    });
    connect(m_Session, &Session::displayLaunchError, this, [this](QString text) {
        m_LaunchError = text;
    });
    connect(m_Session, &Session::connectionStarted, this, [] {
        mv_ui_set_visible(false);
    });
    connect(m_Session, &Session::sessionFinished, this, [this](int) {
        mv_ui_set_visible(true);
        setStatus(m_LaunchError, false);
    });
    connect(m_Session, &Session::readyForDeletion, this, [this] {
        m_Session->deleteLater();
        m_Session = nullptr;
        pushComputers();
    });

    // The SwiftUI shell has no Qt window, so the session falls back to the main display
    if (!m_Session->initialize(nullptr)) {
        setStatus(m_LaunchError.isEmpty() ? tr("Unable to initialize the stream.") : m_LaunchError, false);
        m_Session->deleteLater();
        m_Session = nullptr;
        return;
    }

    QTimer::singleShot(0, m_Session, &Session::start);
}
