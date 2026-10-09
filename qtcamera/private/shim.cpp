#include "shim.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QPermissions>
#include <QtCore/QVariant>
#include <QtMultimedia/QVideoFrame>
#include <QtMultimedia/QVideoSink>

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
