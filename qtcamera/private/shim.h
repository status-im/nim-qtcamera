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

/* How a QVideoFrame is displayed, composed as Qt's private
   qNormalizedFrameTransformation without the VideoOutput part: the surface
   format's (BottomToTop scan lines, rotation, mirror) when `include_surface`,
   then the frame's own rotation and mirror. Rotation: clockwise degrees. */
void qtcamera_frame_transform(const void* frame, int include_surface,
                              int* rotation, int* mirrored);

// 1 when this platform can open the OS page where camera access is granted
// (macOS, Windows, iOS, Android); 0 otherwise (Linux).
int qtcamera_can_open_camera_settings(void);
// Opens that page. GUI thread only; returns 1 if the OS accepted the request.
int qtcamera_open_camera_settings(void);

typedef void (*qtcamera_app_activated_cb)(void* ctx);
// Calls cb(ctx) on the GUI thread whenever the application becomes active
// (e.g. back from the OS settings). Needs a QGuiApplication; returns NULL
// otherwise. Release with qtcamera_disconnect_app_activated.
void* qtcamera_on_app_activated(void* ctx, qtcamera_app_activated_cb cb);
void qtcamera_disconnect_app_activated(void* handle);

#ifdef __cplusplus
}
#endif
