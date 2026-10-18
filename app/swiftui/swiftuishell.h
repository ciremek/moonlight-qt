#pragma once

#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QPoint>
#include <QSet>
#include <QString>
#include <QTimer>

#include "backend/nvapp.h"

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
    void handlePairingCompleted(NvComputer* computer, QString error);
    void handleComputerAddCompleted(QVariant success, QVariant detectedPortBlocking);

private:
    static void handleAction(const char* json);
    static int streamState();

    void dispatch(const QJsonObject& action);
    void launch(const QString& computerUuid, int appId, const QPoint& displayOrigin);
    void pair(const QString& computerUuid);
    void wake(const QJsonObject& action);
    void deleteHost(const QString& computerUuid);
    void applyPrefs(const QJsonObject& prefs);
    void pushPrefs();
    void setStatus(const QString& text, bool busy, bool error = false);
    void setPolling(bool enabled);
    void handleApplicationStateChanged(Qt::ApplicationState state);
    NvComputer* findComputer(const QString& uuid);

    static SwiftUIShell* s_Instance;

    ComputerManager* m_ComputerManager;
    StreamingPreferences* m_Prefs;
    QSet<QString> m_DeletingUuids;
    Session* m_Session;
    bool m_Polling;
    QTimer m_InactivityTimer;
    QString m_LaunchError;
};
