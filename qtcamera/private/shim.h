// C ABI gap-fillers for seaqt. seaqt does not bind QCameraPermission /
// QCoreApplication::requestPermission, its signal helpers return no handle to
// disconnect, and it cannot extract a QObject* from a QVariant.
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

typedef void (*qtcamera_frame_cb)(void* ctx, const void* qvideoframe);
typedef void (*qtcamera_permission_cb)(void* ctx, int status);

// Connects QVideoSink::videoFrameChanged. The callback runs on the sink's
// thread and never after qtcamera_disconnect (even for already-queued frames).
// Returns nullptr when `qvideosink` is not a QVideoSink. Release the handle
// with qtcamera_disconnect (safe after the sink is gone).
void* qtcamera_connect_frames(void* qvideosink, void* ctx, qtcamera_frame_cb cb);
void qtcamera_disconnect(void* connection);

// Qt::PermissionStatus: 0 Undetermined, 1 Granted, 2 Denied.
int qtcamera_camera_permission_status(void);
void qtcamera_request_camera_permission(void* ctx, qtcamera_permission_cb cb);

void* qtcamera_qobject_from_variant(const void* qvariant);

#ifdef __cplusplus
}
#endif
