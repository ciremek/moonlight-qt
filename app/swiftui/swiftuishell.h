#pragma once

#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QPoint>
#include <QSet>
#include <QString>

#include "backend/boxartmanager.h"

class ComputerManager;
class NvComputer;
class Session;
class StreamingPreferences;

// Hosts the SwiftUI shell on top of the existing Qt backend: it feeds the
// shell with computers, apps and preferences, and runs the actions it requests.
class SwiftUIShell : public QObject
{
    Q_OBJECT

public:
    explicit SwiftUIShell(ComputerManager* computerManager, QObject* parent = nullptr);

    void show();

private slots:
    void pushComputers();
    void handleBoxArtLoaded(NvComputer* computer, NvApp app, QUrl image);
    void handlePairingCompleted(NvComputer* computer, QString error);
    void handleComputerAddCompleted(QVariant success, QVariant detectedPortBlocking);

private:
    static void handleAction(const char* json);

    void dispatch(const QJsonObject& action);
    void launch(const QString& computerUuid, int appId, const QPoint& displayOrigin);
    void pair(const QString& computerUuid);
    void deleteHost(const QString& computerUuid);
    void applyPrefs(const QJsonObject& prefs);
    void pushPrefs();
    void setStatus(const QString& text, bool busy, bool error = false);
    NvComputer* findComputer(const QString& uuid);
    QString boxArtPath(NvComputer* computer, NvApp& app);

    static SwiftUIShell* s_Instance;

    ComputerManager* m_ComputerManager;
    StreamingPreferences* m_Prefs;
    BoxArtManager m_BoxArtManager;
    QHash<QString, QString> m_BoxArtPaths;
    QSet<QString> m_BoxArtRequested;
    QSet<QString> m_DeletingUuids;
    Session* m_Session;
    QString m_LaunchError;
};
