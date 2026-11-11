#include "sidebar_icon.h"

#include <initializer_list>

using busystack_git_ui::LoadSidebarIcon;

static void matches_headerbar() {
  for (auto direction : {GTK_TEXT_DIR_LTR, GTK_TEXT_DIR_RTL}) {
    auto* window = gtk_offscreen_window_new();
    auto* image = gtk_image_new_from_icon_name("sidebar-show-symbolic",
                                               GTK_ICON_SIZE_BUTTON);
    gtk_widget_set_direction(image, direction);
    g_autoptr(GtkCssProvider) css = gtk_css_provider_new();
    gtk_css_provider_load_from_data(css, "image { color: white; }", -1, nullptr);
    gtk_style_context_add_provider(gtk_widget_get_style_context(image),
                                   GTK_STYLE_PROVIDER(css),
                                   GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    gtk_container_add(GTK_CONTAINER(window), image);
    gtk_widget_show_all(window);
    while (gtk_events_pending()) gtk_main_iteration();
    cairo_surface_t* surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32,
                                                          16, 16);
    cairo_t* cr = cairo_create(surface);
    gtk_widget_draw(image, cr);
    cairo_destroy(cr);
    g_autoptr(GdkPixbuf) expected = gdk_pixbuf_get_from_surface(surface, 0, 0, 16, 16);
    cairo_surface_destroy(surface);
    g_autoptr(GError) error = nullptr;
    g_autoptr(GdkPixbuf) actual = LoadSidebarIcon(
        gtk_icon_theme_get_default(), 1, direction, &error);
    g_assert_no_error(error);
    g_assert_nonnull(actual);
    g_assert_cmpint(gdk_pixbuf_get_width(actual), ==, 16);
    g_assert_cmpint(gdk_pixbuf_get_height(actual), ==, 16);
    for (int y = 0; y < 16; ++y) {
      const auto* a = gdk_pixbuf_get_pixels(actual) + y * gdk_pixbuf_get_rowstride(actual);
      const auto* e = gdk_pixbuf_get_pixels(expected) + y * gdk_pixbuf_get_rowstride(expected);
      g_assert_cmpmem(a, 16 * 4, e, 16 * 4);
    }
    gtk_widget_destroy(window);
  }
}

static void hidpi() {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkPixbuf) icon = LoadSidebarIcon(
      gtk_icon_theme_get_default(), 2, GTK_TEXT_DIR_LTR, &error);
  g_assert_no_error(error);
  g_assert_nonnull(icon);
  g_assert_cmpint(gdk_pixbuf_get_width(icon), ==, 32);
  g_assert_cmpint(gdk_pixbuf_get_height(icon), ==, 32);
}

int main(int argc, char** argv) {
  gtk_test_init(&argc, &argv, nullptr);
  g_test_add_func("/git/sidebar-icon/headerbar-pixels", matches_headerbar);
  g_test_add_func("/git/sidebar-icon/hidpi", hidpi);
  return g_test_run();
}
