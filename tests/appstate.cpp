// Test helper: drives QGuiApplication's application state through the QPA
// window-system interface (what platform plugins do), so tests can exercise
// "app became active" without a real window manager.
#include <QtCore/QCoreApplication>
#include <QtGui/qpa/qwindowsysteminterface.h>

extern "C" void qtcamera_test_set_app_state(int active)
{
    QWindowSystemInterface::handleApplicationStateChanged(
        active ? Qt::ApplicationActive : Qt::ApplicationInactive, /*forcePropagate=*/true);
    QWindowSystemInterface::flushWindowSystemEvents();
    QCoreApplication::processEvents();
}
