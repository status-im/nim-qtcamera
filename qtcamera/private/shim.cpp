#include "shim.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QPermissions>
#include <QtCore/QVariant>
#include <QtMultimedia/QVideoFrame>
#include <QtMultimedia/QVideoSink>

extern "C" void* qtcamera_connect_frames(void* sink, void* ctx, qtcamera_frame_cb cb)
{
    auto* s = static_cast<QVideoSink*>(sink);
    // Context = sink: the lambda runs on the sink's thread (queued when the
    // signal is emitted elsewhere) and the connection dies with the sink.
    auto conn = QObject::connect(s, &QVideoSink::videoFrameChanged, s,
                                 [ctx, cb](const QVideoFrame& f) { cb(ctx, &f); });
    return new QMetaObject::Connection(conn);
}

extern "C" void qtcamera_disconnect(void* connection)
{
    auto* c = static_cast<QMetaObject::Connection*>(connection);
    if (!c)
        return;
    QObject::disconnect(*c); // no-op when the sink is already gone
    delete c;
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
    auto* var = static_cast<const QVariant*>(v);
    return var ? var->value<QObject*>() : nullptr;
}
