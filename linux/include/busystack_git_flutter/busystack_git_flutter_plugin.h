#ifndef BUSYSTACK_GIT_FLUTTER_PLUGIN_H_
#define BUSYSTACK_GIT_FLUTTER_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

G_BEGIN_DECLS
#ifdef FLUTTER_PLUGIN_IMPL
#define BUSYSTACK_GIT_FLUTTER_EXPORT __attribute__((visibility("default")))
#else
#define BUSYSTACK_GIT_FLUTTER_EXPORT
#endif

G_DECLARE_FINAL_TYPE(BusystackGitFlutterPlugin, busystack_git_flutter_plugin,
                     BUSYSTACK, GIT_FLUTTER_PLUGIN, GObject)

BUSYSTACK_GIT_FLUTTER_EXPORT void
busystack_git_flutter_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

// The application supplies its content overlay before registering plugins.
// Neither this function nor the plugin owns a window or reparents the FlView.
// Both references are weak and die with the application's view/overlay.
BUSYSTACK_GIT_FLUTTER_EXPORT void
busystack_git_flutter_plugin_set_accessibility_host(FlView* view,
                                                    GtkOverlay* overlay);
G_END_DECLS
#endif
