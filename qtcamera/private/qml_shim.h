// QML-side C ABI helper, kept apart from shim.h so the core stays QML-free.
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

// engine: QQmlEngine*; qobject: the QObject* exposed as context property `name`.
void qtcamera_qml_install(void* engine, const char* importPath, const char* name, void* qobject);

#ifdef __cplusplus
}
#endif
