#include "qml_shim.h"

#include <QtQml/QQmlContext>
#include <QtQml/QQmlEngine>

extern "C" void qtcamera_qml_install(void* engine, const char* importPath, const char* name, void* qobject)
{
    auto* e = static_cast<QQmlEngine*>(engine);
    if (!e)
        return;
    e->addImportPath(QString::fromUtf8(importPath));
    e->rootContext()->setContextProperty(QString::fromUtf8(name), static_cast<QObject*>(qobject));
}
