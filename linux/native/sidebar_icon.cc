#include "sidebar_icon.h"

namespace busystack_git_ui {
GdkPixbuf* LoadSidebarIcon(GtkIconTheme* theme, int scale,
                          GtkTextDirection direction, GError** error) {
  const auto flags = static_cast<GtkIconLookupFlags>(
      GTK_ICON_LOOKUP_FORCE_SYMBOLIC |
      (direction == GTK_TEXT_DIR_RTL ? GTK_ICON_LOOKUP_DIR_RTL
                                     : GTK_ICON_LOOKUP_DIR_LTR));
  g_autoptr(GtkIconInfo) info = gtk_icon_theme_lookup_icon_for_scale(
      theme, "sidebar-show-symbolic", 16, scale, flags);
  if (!info) {
    g_set_error_literal(error, GTK_ICON_THEME_ERROR,
                        GTK_ICON_THEME_NOT_FOUND,
                        "The headerbar sidebar icon is unavailable");
    return nullptr;
  }
  const GdkRGBA white = {1, 1, 1, 1};
  return gtk_icon_info_load_symbolic(info, &white, &white, &white, &white,
                                     nullptr, error);
}
}
