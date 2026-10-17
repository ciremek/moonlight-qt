// The SwiftUI shell is French-only for now, so its messages are not run through tr()
#include "swiftuishell.h"
#include "moonvibeui.h"

#include "backend/computermanager.h"
#include "settings/streamingpreferences.h"
#include "streaming/awdl.h"
#include "streaming/session.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QTimer>

SwiftUIShell* SwiftUIShell::s_Instance = nullptr;

static QByteArray toJson(const QJsonObject& object)
{
    return QJsonDocument(object).toJson(QJsonDocument::Compact);
}

SwiftUIShell::SwiftUIShell(ComputerManager* computerManager, QObject* parent)
    : QObject(parent),
      m_ComputerManager(computerManager),
      m_Prefs(StreamingPreferences::get()),
      m_Session(nullptr)
{
    Q_ASSERT(s_Instance == nullptr);
    s_Instance = this;

    connect(m_ComputerManager, &ComputerManager::computerStateChanged,
            this, &SwiftUIShell::pushComputers, Qt::QueuedConnection);
    connect(&m_BoxArtManager, &BoxArtManager::boxArtLoadComplete,
            this, &SwiftUIShell::handleBoxArtLoaded);
}

void SwiftUIShell::show()
{
    mv_ui_show(&SwiftUIShell::handleAction);
    pushPrefs();
    pushComputers();
    m_ComputerManager->startPolling();
}

QString SwiftUIShell::boxArtPath(NvComputer* computer, NvApp& app)
{
    QString key = computer->uuid + ":" + QString::number(app.id);
    auto cached = m_BoxArtPaths.constFind(key);
    if (cached != m_BoxArtPaths.constEnd()) {
        return *cached;
    }

    // Only ask once per app: the manager fetches missing art in the background
    // and reports back through boxArtLoadComplete()
    if (!m_BoxArtRequested.contains(key)) {
        m_BoxArtRequested.insert(key);
        QUrl url = m_BoxArtManager.loadBoxArt(computer, app);
        if (url.isLocalFile()) {
            m_BoxArtPaths.insert(key, url.toLocalFile());
            return url.toLocalFile();
        }
    }

    return QString();
}

void SwiftUIShell::handleBoxArtLoaded(NvComputer* computer, NvApp app, QUrl image)
{
    if (image.isLocalFile()) {
        m_BoxArtPaths.insert(computer->uuid + ":" + QString::number(app.id), image.toLocalFile());
        pushComputers();
    }
}

void SwiftUIShell::pushComputers()
{
    QJsonArray computers;

    for (NvComputer* computer : m_ComputerManager->getComputers()) {
        QVector<NvApp> appList;
        QJsonObject entry;
        {
            QReadLocker lock(&computer->lock);
            appList = computer->appList;
            entry = QJsonObject {
                { "uuid", computer->uuid },
                { "name", computer->name },
                { "online", computer->state == NvComputer::CS_ONLINE },
                { "paired", computer->pairState == NvComputer::PS_PAIRED },
                { "canWake", !computer->macAddress.isEmpty() },
                { "runningAppId", computer->currentGameId },
            };
        }

        QJsonArray apps;
        for (NvApp& app : appList) {
            if (!app.hidden) {
                apps.append(QJsonObject {
                    { "id", app.id },
                    { "name", app.name },
                    { "boxArt", boxArtPath(computer, app) },
                });
            }
        }
        entry.insert("apps", apps);
        computers.append(entry);
    }

    mv_ui_update_computers(QJsonDocument(computers).toJson(QJsonDocument::Compact).constData());
}

void SwiftUIShell::pushPrefs()
{
    QJsonObject prefs {
        { "resolutionMode", static_cast<int>(m_Prefs->resolutionMode) },
        { "width", m_Prefs->width },
        { "height", m_Prefs->height },
        { "fps", m_Prefs->fps },
        { "bitrateKbps", m_Prefs->bitrateKbps },
        { "windowMode", static_cast<int>(m_Prefs->windowMode) },
        { "vsync", m_Prefs->enableVsync },
        { "framePacing", m_Prefs->framePacing },
        { "hdr", m_Prefs->enableHdr },
        { "muteHost", !m_Prefs->playAudioOnHost },
        { "disableAwdl", m_Prefs->disableAwdl },
    };
    mv_ui_update_prefs(toJson(prefs).constData());
}

void SwiftUIShell::applyPrefs(const QJsonObject& prefs)
{
    m_Prefs->resolutionMode = static_cast<StreamingPreferences::ResolutionMode>(prefs["resolutionMode"].toInt(m_Prefs->resolutionMode));
    m_Prefs->width = prefs["width"].toInt(m_Prefs->width);
    m_Prefs->height = prefs["height"].toInt(m_Prefs->height);
    m_Prefs->fps = prefs["fps"].toInt(m_Prefs->fps);
    m_Prefs->bitrateKbps = prefs["bitrateKbps"].toInt(m_Prefs->bitrateKbps);
    m_Prefs->windowMode = static_cast<StreamingPreferences::WindowMode>(prefs["windowMode"].toInt(m_Prefs->windowMode));
    m_Prefs->enableVsync = prefs["vsync"].toBool(m_Prefs->enableVsync);
    m_Prefs->framePacing = m_Prefs->enableVsync && prefs["framePacing"].toBool(m_Prefs->framePacing);
    m_Prefs->enableHdr = prefs["hdr"].toBool(m_Prefs->enableHdr);
    m_Prefs->playAudioOnHost = !prefs["muteHost"].toBool(!m_Prefs->playAudioOnHost);

    // The shell always picks the bitrate explicitly (presets or slider)
    m_Prefs->autoAdjustBitrate = false;

    bool disableAwdl = prefs["disableAwdl"].toBool(m_Prefs->disableAwdl);
    if (disableAwdl && !m_Prefs->disableAwdl && !AwdlBlocker::isControlReady()) {
        // Toggling AWDL needs a one-time admin approval
        disableAwdl = AwdlBlocker::installSudoersRule();
    }
    m_Prefs->disableAwdl = disableAwdl;

    m_Prefs->save();
    pushPrefs();
}

void SwiftUIShell::handleAction(const char* json)
{
    // Leave the SwiftUI event handler before doing any heavy lifting
    QJsonObject action = QJsonDocument::fromJson(QByteArray(json)).object();
    QMetaObject::invokeMethod(s_Instance, [action] {
        s_Instance->dispatch(action);
    }, Qt::QueuedConnection);
}

NvComputer* SwiftUIShell::findComputer(const QString& uuid)
{
    for (NvComputer* computer : m_ComputerManager->getComputers()) {
        QReadLocker lock(&computer->lock);
        if (computer->uuid == uuid) {
            return computer;
        }
    }
    return nullptr;
}

void SwiftUIShell::dispatch(const QJsonObject& action)
{
    QString type = action["action"].toString();

    if (type == "launch") {
        launch(action["uuid"].toString(), action["appId"].toInt(),
               QPoint(action["displayX"].toInt(), action["displayY"].toInt()));
    }
    else if (type == "cancel") {
        if (m_Session != nullptr) {
            m_Session->interrupt();
        }
    }
    else if (type == "wake") {
        NvComputer* computer = findComputer(action["uuid"].toString());
        if (computer != nullptr) {
            bool sent = computer->wake();
            setStatus(sent ? QStringLiteral("Demande de réveil envoyée. Le PC peut mettre une minute à apparaître en ligne.")
                           : QStringLiteral("Impossible d'envoyer la demande de réveil."), false, !sent);
        }
    }
    else if (type == "quitApp") {
        NvComputer* computer = findComputer(action["uuid"].toString());
        if (computer != nullptr) {
            m_ComputerManager->quitRunningApp(computer);
        }
    }
    else if (type == "setPrefs") {
        applyPrefs(action["prefs"].toObject());
    }
    else if (type == "quit") {
        QCoreApplication::quit();
    }
}

void SwiftUIShell::setStatus(const QString& text, bool busy, bool error)
{
    QJsonObject status {
        { "text", text },
        { "busy", busy },
        { "error", error },
    };
    mv_ui_set_status(toJson(status).constData());
}

void SwiftUIShell::launch(const QString& computerUuid, int appId, const QPoint& displayOrigin)
{
    if (m_Session != nullptr) {
        return;
    }

    NvComputer* computer = findComputer(computerUuid);
    NvApp app;
    if (computer != nullptr) {
        QReadLocker lock(&computer->lock);
        for (const NvApp& candidate : computer->appList) {
            if (candidate.id == appId) {
                app = candidate;
                break;
            }
        }
    }

    if (computer == nullptr || !app.isInitialized()) {
        setStatus(QStringLiteral("Cette app n'est plus disponible."), false, true);
        return;
    }

    m_LaunchError.clear();
    m_Session = new Session(computer, app);
    m_Session->setDisplayOrigin(displayOrigin);

    connect(m_Session, &Session::stageStarting, this, [this](QString stage) {
        setStatus(QStringLiteral("Démarrage : %1…").arg(stage), true);
    });
    connect(m_Session, &Session::stageFailed, this, [this](QString stage, int errorCode, QString failingPorts) {
        m_LaunchError = QStringLiteral("Échec au démarrage de %1 (erreur %2).").arg(stage).arg(errorCode);
        if (!failingPorts.isEmpty()) {
            m_LaunchError += "\n\n" + QStringLiteral("Vérifie ton pare-feu et la redirection des ports : %1").arg(failingPorts);
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
        setStatus(m_LaunchError, false, !m_LaunchError.isEmpty());
    });
    connect(m_Session, &Session::readyForDeletion, this, [this] {
        m_Session->deleteLater();
        m_Session = nullptr;
        pushComputers();
    });

    setStatus(QStringLiteral("Démarrage : %1…").arg(app.name), true);

    if (!m_Session->initialize(nullptr)) {
        setStatus(m_LaunchError.isEmpty() ? QStringLiteral("Impossible de préparer le stream.") : m_LaunchError, false, true);
        m_Session->deleteLater();
        m_Session = nullptr;
        return;
    }

    QTimer::singleShot(0, m_Session, &Session::start);
}
