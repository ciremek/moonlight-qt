#pragma once

#include <QObject>
#include <QString>

class ComputerManager;
class Session;

// Hosts the SwiftUI shell on top of the existing Qt backend: it feeds the
// shell with computers and apps, and runs streaming sessions it requests.
class SwiftUIShell : public QObject
{
    Q_OBJECT

public:
    explicit SwiftUIShell(ComputerManager* computerManager, QObject* parent = nullptr);

    void show();

private slots:
    void pushComputers();

private:
    static void handleLaunchRequest(const char* computerUuid, int appId);
    static void handleQuitRequest();

    void launch(const QString& computerUuid, int appId);
    void setStatus(const QString& text, bool busy);

    static SwiftUIShell* s_Instance;

    ComputerManager* m_ComputerManager;
    Session* m_Session;
    QString m_LaunchError;
};
