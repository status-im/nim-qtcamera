#include "shim.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QPermissions>
#include <QtCore/QThread>
#include <QtCore/QUrl>
#include <QtCore/QVariant>
#include <QtGui/QDesktopServices>
#include <QtMultimedia/QVideoFrame>
#include <QtMultimedia/QVideoSink>

#if defined(Q_OS_ANDROID)
#include <QtCore/QJniEnvironment>
#include <QtCore/QJniObject>
#endif

#include <atomic>
#include <memory>

namespace {
// Shared between the connection's lambda and the handle returned to Nim.
// Disconnecting does not cancel frame events already queued (frames emitted
// off the sink's thread), so the lambda checks `ctx`, which qtcamera_disconnect
// clears first, before calling back into Nim.
struct FrameTapLink {
    std::atomic<void*> ctx;
    qtcamera_frame_cb cb;
    QMetaObject::Connection connection;
};
} // namespace

extern "C" void* qtcamera_connect_frames(void* sink, void* ctx, qtcamera_frame_cb cb)
{
    auto* s = qobject_cast<QVideoSink*>(static_cast<QObject*>(sink));
    if (!s) {
        qWarning("qtcamera: frame tap target is not a QVideoSink");
        return nullptr;
    }
    auto link = std::make_shared<FrameTapLink>();
    link->ctx.store(ctx);
    link->cb = cb;
    // Context = sink: the lambda runs on the sink's thread (queued when the
    // signal is emitted elsewhere) and the connection dies with the sink.
    link->connection = QObject::connect(s, &QVideoSink::videoFrameChanged, s,
                                        [link](const QVideoFrame& f) {
                                            if (void* c = link->ctx.load())
                                                link->cb(c, &f);
                                        });
    if (!link->connection) {
        return nullptr;
    }
    return new std::shared_ptr<FrameTapLink>(std::move(link));
}

extern "C" void qtcamera_disconnect(void* handle)
{
    auto* link = static_cast<std::shared_ptr<FrameTapLink>*>(handle);
    if (!link)
        return;
    (*link)->ctx.store(nullptr);              // queued events become no-ops
    QObject::disconnect((*link)->connection); // no-op when the sink is gone
    delete link;
}

extern "C" int qtcamera_camera_permission_status(void)
{
#if QT_CONFIG(permissions)
    return static_cast<int>(qApp->checkPermission(QCameraPermission{}));
#else
    return static_cast<int>(Qt::PermissionStatus::Granted);
#endif
}

extern "C" void qtcamera_request_camera_permission(void* ctx, qtcamera_permission_cb cb)
{
#if QT_CONFIG(permissions)
    qApp->requestPermission(QCameraPermission{}, qApp,
                            [ctx, cb](const QPermission& p) { cb(ctx, static_cast<int>(p.status())); });
#else
    cb(ctx, static_cast<int>(Qt::PermissionStatus::Granted));
#endif
}

extern "C" void* qtcamera_qobject_from_variant(const void* v)
{
    if (!v)
        return nullptr;
    QVariant var = *static_cast<const QVariant*>(v);
    // nimqml boxes slot arguments, so the object may sit in a nested QVariant.
    while (var.metaType() == QMetaType::fromType<QVariant>())
        var = var.value<QVariant>();
    return var.value<QObject*>();
}

namespace {
const char* cameraSettingsUrl()
{
#if defined(Q_OS_MACOS)
    return "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera";
#elif defined(Q_OS_WIN)
    return "ms-settings:privacy-webcam";
#elif defined(Q_OS_IOS)
    return "app-settings:";
#else
    return nullptr;
#endif
}
} // namespace

extern "C" int qtcamera_can_open_camera_settings(void)
{
#if defined(Q_OS_ANDROID)
    return 1;
#else
    return cameraSettingsUrl() ? 1 : 0;
#endif
}

extern "C" int qtcamera_open_camera_settings(void)
{
    auto* app = QCoreApplication::instance();
    if (!app || QThread::currentThread() != app->thread())
        return 0;
#if defined(Q_OS_ANDROID)
    // Self-contained (no app-specific Activity): open this app's details page,
    // where Android lists its permissions.
    QJniObject ctx(QNativeInterface::QAndroidApplication::context().object());
    if (!ctx.isValid())
        return 0;
    QJniEnvironment env;
    QJniObject pkg = ctx.callObjectMethod("getPackageName", "()Ljava/lang/String;");
    QJniObject uri = QJniObject::callStaticObjectMethod(
        "android/net/Uri", "fromParts",
        "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Landroid/net/Uri;",
        QJniObject::fromString(QStringLiteral("package")).object<jstring>(),
        pkg.object<jstring>(), static_cast<jstring>(nullptr));
    QJniObject intent("android/content/Intent", "(Ljava/lang/String;Landroid/net/Uri;)V",
        QJniObject::fromString(QStringLiteral("android.settings.APPLICATION_DETAILS_SETTINGS"))
            .object<jstring>(),
        uri.object());
    intent.callObjectMethod("addFlags", "(I)Landroid/content/Intent;", jint(0x10000000));
    ctx.callMethod<void>("startActivity", "(Landroid/content/Intent;)V", intent.object());
    if (env.checkAndClearExceptions()) {
        qWarning("qtcamera: could not open the app settings");
        return 0;
    }
    return 1;
#else
    const char* url = cameraSettingsUrl();
    if (!url)
        return 0;
    if (!QDesktopServices::openUrl(QUrl(QString::fromLatin1(url)))) {
        qWarning("qtcamera: could not open %s", url);
        return 0;
    }
    return 1;
#endif
}
