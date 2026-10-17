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

#include <type_traits>

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
    connect(m_ComputerManager, &ComputerManager::pairingCompleted,
            this, &SwiftUIShell::handlePairingCompleted);
    connect(m_ComputerManager, &ComputerManager::computerAddCompleted,
            this, &SwiftUIShell::handleComputerAddCompleted);
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
            if (m_DeletingUuids.contains(computer->uuid)) {
                continue;
            }

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
        { "unlockBitrate", m_Prefs->unlockBitrate },
        { "windowMode", static_cast<int>(m_Prefs->windowMode) },
        { "vsync", m_Prefs->enableVsync },
        { "framePacing", m_Prefs->framePacing },
        { "hdr", m_Prefs->enableHdr },
        { "yuv444", m_Prefs->enableYUV444 },
        { "videoCodec", static_cast<int>(m_Prefs->videoCodecConfig) },
        { "videoDecoder", static_cast<int>(m_Prefs->videoDecoderSelection) },
        { "renderer", static_cast<int>(m_Prefs->rendererSelection) },
        { "audioConfig", static_cast<int>(m_Prefs->audioConfig) },
        { "muteHost", !m_Prefs->playAudioOnHost },
        { "muteOnFocusLoss", m_Prefs->muteOnFocusLoss },
        { "absoluteMouse", m_Prefs->absoluteMouseMode },
        { "swapMouseButtons", m_Prefs->swapMouseButtons },
        { "reverseScroll", m_Prefs->reverseScrollDirection },
        { "captureSysKeys", static_cast<int>(m_Prefs->captureSysKeysMode) },
        { "multiController", m_Prefs->multiController },
        { "backgroundGamepad", m_Prefs->backgroundGamepad },
        { "gamepadMouse", m_Prefs->gamepadMouse },
        { "swapFaceButtons", m_Prefs->swapFaceButtons },
        { "mdns", m_Prefs->enableMdns },
        { "detectNetworkBlocking", m_Prefs->detectNetworkBlocking },
        { "disableAwdl", m_Prefs->disableAwdl },
        { "quitAppAfter", m_Prefs->quitAppAfter },
        { "gameOptimizations", m_Prefs->gameOptimizations },
        { "keepAwake", m_Prefs->keepAwake },
        { "showStats", m_Prefs->showPerformanceOverlay },
        { "connectionWarnings", m_Prefs->connectionWarnings },
        { "configurationWarnings", m_Prefs->configurationWarnings },
        { "richPresence", m_Prefs->richPresence },
    };
    mv_ui_update_prefs(toJson(prefs).constData());
}

void SwiftUIShell::applyPrefs(const QJsonObject& prefs)
{
    auto readBool = [&prefs](const char* key, bool& value) { value = prefs[key].toBool(value); };
    auto readInt = [&prefs](const char* key, int& value) { value = prefs[key].toInt(value); };
    auto readEnum = [&prefs](const char* key, auto& value) {
        value = static_cast<std::remove_reference_t<decltype(value)>>(prefs[key].toInt(static_cast<int>(value)));
    };

    readEnum("resolutionMode", m_Prefs->resolutionMode);
    readInt("width", m_Prefs->width);
    readInt("height", m_Prefs->height);
    readInt("fps", m_Prefs->fps);
    readInt("bitrateKbps", m_Prefs->bitrateKbps);
    readBool("unlockBitrate", m_Prefs->unlockBitrate);
    readEnum("windowMode", m_Prefs->windowMode);
    readBool("vsync", m_Prefs->enableVsync);
    readBool("framePacing", m_Prefs->framePacing);
    m_Prefs->framePacing = m_Prefs->framePacing && m_Prefs->enableVsync;
    readBool("hdr", m_Prefs->enableHdr);
    readBool("yuv444", m_Prefs->enableYUV444);
    readEnum("videoCodec", m_Prefs->videoCodecConfig);
    readEnum("videoDecoder", m_Prefs->videoDecoderSelection);
    readEnum("renderer", m_Prefs->rendererSelection);
    readEnum("audioConfig", m_Prefs->audioConfig);
    m_Prefs->playAudioOnHost = !prefs["muteHost"].toBool(!m_Prefs->playAudioOnHost);
    readBool("muteOnFocusLoss", m_Prefs->muteOnFocusLoss);
    readBool("absoluteMouse", m_Prefs->absoluteMouseMode);
    readBool("swapMouseButtons", m_Prefs->swapMouseButtons);
    readBool("reverseScroll", m_Prefs->reverseScrollDirection);
    readEnum("captureSysKeys", m_Prefs->captureSysKeysMode);
    readBool("multiController", m_Prefs->multiController);
    readBool("backgroundGamepad", m_Prefs->backgroundGamepad);
    readBool("gamepadMouse", m_Prefs->gamepadMouse);
    readBool("swapFaceButtons", m_Prefs->swapFaceButtons);
    readBool("mdns", m_Prefs->enableMdns);
    readBool("detectNetworkBlocking", m_Prefs->detectNetworkBlocking);
    readBool("quitAppAfter", m_Prefs->quitAppAfter);
    readBool("gameOptimizations", m_Prefs->gameOptimizations);
    readBool("keepAwake", m_Prefs->keepAwake);
    readBool("showStats", m_Prefs->showPerformanceOverlay);
    readBool("connectionWarnings", m_Prefs->connectionWarnings);
    readBool("configurationWarnings", m_Prefs->configurationWarnings);
    readBool("richPresence", m_Prefs->richPresence);

    // Without an unlocked bitrate, keep it within the standard range
    if (!m_Prefs->unlockBitrate && m_Prefs->bitrateKbps > 150000) {
        m_Prefs->bitrateKbps = 150000;
    }

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

int SwiftUIShell::streamState()
{
    Session* session = s_Instance->m_Session;
    if (session == nullptr) {
        return 0;
    }

    return (session->isCaptureActive() ? MV_STREAM_CAPTURED : 0) |
           (session->isExternalStatsVisible() ? MV_STREAM_STATS : 0) |
           (session->isStreamFullScreen() ? MV_STREAM_FULLSCREEN : 0);
}

void SwiftUIShell::handleAction(const char* json)
{
    QJsonObject action = QJsonDocument::fromJson(QByteArray(json)).object();

    // Stream overlay actions arrive while Qt's event loop is suspended by the stream,
    // so they can't be queued: hand them straight to the session's event loop
    if (action["action"].toString() == "streamAction") {
        if (s_Instance->m_Session != nullptr) {
            s_Instance->m_Session->requestStreamAction(action["value"].toInt());
        }
        return;
    }

    // Leave the SwiftUI event handler before doing any heavy lifting
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
    else if (type == "pair") {
        pair(action["uuid"].toString());
    }
    else if (type == "deleteHost") {
        deleteHost(action["uuid"].toString());
    }
    else if (type == "addHost") {
        m_ComputerManager->addNewHostManually(action["address"].toString().trimmed());
    }
    else if (type == "setPrefs") {
        applyPrefs(action["prefs"].toObject());
    }
    else if (type == "quit") {
        QCoreApplication::quit();
    }
}

void SwiftUIShell::pair(const QString& computerUuid)
{
    NvComputer* computer = findComputer(computerUuid);
    if (computer == nullptr) {
        return;
    }

    // The PC shows nothing: the user types this PIN into Sunshine
    QString pin = m_ComputerManager->generatePinString();
    mv_ui_update_pairing(toJson(QJsonObject {
        { "uuid", computerUuid },
        { "stage", "waiting" },
        { "pin", pin },
    }).constData());
    m_ComputerManager->pairHost(computer, pin);
}

void SwiftUIShell::deleteHost(const QString& computerUuid)
{
    NvComputer* computer = findComputer(computerUuid);
    if (computer == nullptr) {
        return;
    }

    // Deletion finishes on a worker thread: hide the host meanwhile, then let
    // discovery bring it back as a new, unpaired PC if it is still on the network
    m_DeletingUuids.insert(computerUuid);
    for (auto it = m_BoxArtPaths.begin(); it != m_BoxArtPaths.end();) {
        it = it.key().startsWith(computerUuid + ":") ? m_BoxArtPaths.erase(it) : std::next(it);
    }
    m_BoxArtRequested.clear();
    m_ComputerManager->deleteHost(computer);
    pushComputers();

    QTimer::singleShot(1500, this, [this, computerUuid] {
        m_DeletingUuids.remove(computerUuid);
        pushComputers();
    });
}

void SwiftUIShell::handlePairingCompleted(NvComputer* computer, QString error)
{
    QString uuid;
    {
        QReadLocker lock(&computer->lock);
        uuid = computer->uuid;
    }

    mv_ui_update_pairing(toJson(QJsonObject {
        { "uuid", uuid },
        { "stage", error.isEmpty() ? "paired" : "failed" },
        { "error", error },
    }).constData());
    pushComputers();
}

void SwiftUIShell::handleComputerAddCompleted(QVariant success, QVariant detectedPortBlocking)
{
    mv_ui_add_host_result(toJson(QJsonObject {
        { "success", success.toBool() },
        { "portBlocking", detectedPortBlocking.toBool() },
    }).constData());
    pushComputers();
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
    m_Session->setExternalOverlayUi(true);

    // Stream overlays: these signals fire on the streaming and decoder threads
    // while Qt's event loop is suspended, hence the direct connections
    QByteArray overlayInfo = toJson(QJsonObject {
        { "computer", computer->name },
        { "app", app.name },
        { "targetMbps", m_Prefs->bitrateKbps / 1000.0 },
    });
    connect(m_Session, &Session::streamWindowReady, this, [overlayInfo](void* nativeWindow) {
        mv_overlay_begin(nativeWindow, overlayInfo.constData(), &SwiftUIShell::streamState);
    }, Qt::DirectConnection);
    connect(m_Session, &Session::statsUpdated, this, [](Session::StreamStats stats) {
        mv_overlay_stats(toJson(QJsonObject {
            { "fps", stats.fps },
            { "width", stats.width },
            { "height", stats.height },
            { "bitrateMbps", stats.bitrateMbps },
            { "rttMs", static_cast<int>(stats.rttMs) },
            { "decodeMs", stats.decodeMs },
            { "dropPercent", stats.dropPercent },
        }).constData());
    }, Qt::DirectConnection);
    connect(m_Session, &Session::streamWindowClosing, this, [] {
        mv_overlay_end();
    }, Qt::DirectConnection);

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
