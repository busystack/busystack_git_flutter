#ifndef BUSYSTACK_GIT_SIDEBAR_ICON_H_
#define BUSYSTACK_GIT_SIDEBAR_ICON_H_

#include <gtk/gtk.h>

namespace busystack_git_ui {
// The same themed symbolic artwork used by both applications' headerbars.
GdkPixbuf* LoadSidebarIcon(GtkIconTheme* theme, int scale,
                          GtkTextDirection direction, GError** error);
}
#endif
