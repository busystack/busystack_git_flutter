#include "git_table.h"

#include <atk/atk.h>

#include <algorithm>
#include <string>
#include <vector>

using namespace busystack_git_ui;

namespace {
struct Fixture {
  GtkWidget* window;
  GtkWidget* table;
  AtkObject* accessible;
  TableFrame frame;
  std::vector<TableRow> rows;
  std::vector<TableRequest> requests;

  Fixture() {
    window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    table = CreateGitTable(
        [this](const TableRequest& request) { requests.push_back(request); });
    gtk_widget_set_size_request(table, 480, 300);
    gtk_container_add(GTK_CONTAINER(window), table);
    frame.generation = 1;
    frame.name = "Git commits";
    frame.description = "Two reviewed commits";
    frame.row_count = 2;
    frame.columns = {"Subject", "Author"};
    frame.widths = {300, 180};
    frame.width = 480;
    frame.height = 300;
    frame.row_height = 30;
    rows = {
        {0,
         "first",
         {"First café 😀", "Author one"},
         "2 parents",
         -1,
         0,
         -1,
         {}},
        {1, "second", {"Second", "Author two"}, "1 parent", -1, 0, -1, {}},
    };
    g_assert_true(UpdateGitTable(table, frame, rows));
    gtk_widget_show_all(window);
    while (g_main_context_pending(nullptr))
      g_main_context_iteration(nullptr, FALSE);
    accessible = gtk_widget_get_accessible(table);
  }
  ~Fixture() {
    gtk_widget_destroy(window);
    while (g_main_context_pending(nullptr))
      g_main_context_iteration(nullptr, FALSE);
  }
};

void interfaces_and_headers() {
  Fixture f;
  g_assert_true(ATK_IS_TABLE(f.accessible));
  g_assert_true(ATK_IS_SELECTION(f.accessible));
  g_assert_cmpint(atk_object_get_role(f.accessible), ==, ATK_ROLE_TABLE);
  g_assert_cmpint(atk_table_get_n_rows(ATK_TABLE(f.accessible)), ==, 2);
  g_assert_cmpint(atk_table_get_n_columns(ATK_TABLE(f.accessible)), ==, 2);
  AtkObject* header = atk_table_get_column_header(ATK_TABLE(f.accessible), 1);
  g_assert_cmpint(atk_object_get_role(header), ==, ATK_ROLE_COLUMN_HEADER);
  g_assert_cmpstr(atk_object_get_name(header), ==, "Author");
  g_autoptr(AtkObject) cell = atk_table_ref_at(ATK_TABLE(f.accessible), 1, 1);
  g_assert_true(ATK_IS_TABLE_CELL(cell));
  g_assert_true(ATK_IS_TEXT(cell));
  g_assert_true(ATK_IS_ACTION(cell));
  g_assert_true(ATK_IS_COMPONENT(cell));
  gint row, column, row_span, column_span;
  g_assert_true(atk_table_cell_get_row_column_span(
      ATK_TABLE_CELL(cell), &row, &column, &row_span, &column_span));
  g_assert_cmpint(row, ==, 1);
  g_assert_cmpint(column, ==, 1);
  g_assert_cmpint(row_span, ==, 1);
  g_assert_cmpint(column_span, ==, 1);
  g_autoptr(AtkObject) table = atk_table_cell_get_table(ATK_TABLE_CELL(cell));
  g_assert_true(table == f.accessible);
  g_autoptr(GPtrArray) headers =
      atk_table_cell_get_column_header_cells(ATK_TABLE_CELL(cell));
  g_assert_cmpuint(headers->len, ==, 1);
  g_assert_true(g_ptr_array_index(headers, 0) == header);
  g_assert_null(atk_table_ref_at(ATK_TABLE(f.accessible), 2, 0));
  g_assert_null(atk_table_ref_at(ATK_TABLE(f.accessible), 0, 2));
}

void utf8_and_selection() {
  Fixture f;
  g_autoptr(AtkObject) cell = atk_table_ref_at(ATK_TABLE(f.accessible), 0, 0);
  g_autofree gchar* text = atk_text_get_text(ATK_TEXT(cell), 0, -1);
  g_assert_cmpstr(text, ==, "First café 😀");
  g_assert_cmpint(atk_text_get_character_count(ATK_TEXT(cell)), ==, 12);
  g_assert_cmpuint(atk_text_get_character_at_offset(ATK_TEXT(cell), 11), ==,
                   0x1f600);
  g_assert_true(atk_text_add_selection(ATK_TEXT(cell), 6, 10));
  gint start, end;
  g_autofree gchar* selected =
      atk_text_get_selection(ATK_TEXT(cell), 0, &start, &end);
  g_assert_cmpstr(selected, ==, "café");
  g_assert_cmpint(start, ==, 6);
  g_assert_cmpint(end, ==, 10);
  g_assert_false(atk_text_add_selection(ATK_TEXT(cell), -1, 400));
  g_autofree gchar* word = atk_text_get_string_at_offset(
      ATK_TEXT(cell), 7, ATK_TEXT_GRANULARITY_WORD, &start, &end);
  g_assert_cmpstr(word, ==, "café");
  g_assert_true(atk_action_do_action(ATK_ACTION(cell), 2));
  g_autofree gchar* clipboard =
      gtk_clipboard_wait_for_text(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD));
  g_assert_cmpstr(clipboard, ==, "café");
}

void native_actions_are_identity_bound() {
  Fixture f;
  g_autoptr(AtkObject) cell = atk_table_ref_at(ATK_TABLE(f.accessible), 1, 0);
  g_assert_true(atk_action_do_action(ATK_ACTION(cell), 0));
  g_assert_cmpuint(f.requests.size(), ==, 1);
  g_assert_cmpstr(f.requests.back().action.c_str(), ==, "select");
  g_assert_cmpstr(f.requests.back().row_id.c_str(), ==, "second");
  g_assert_cmpint(f.requests.back().generation, ==, 1);
  f.frame.generation = 2;
  f.rows[1].id = "replacement";
  f.rows[1].cells[0] = "Different commit";
  g_assert_true(UpdateGitTable(f.table, f.frame, f.rows));
  g_autoptr(AtkStateSet) state = atk_object_ref_state_set(cell);
  g_assert_true(atk_state_set_contains_state(state, ATK_STATE_DEFUNCT));
  g_assert_false(atk_action_do_action(ATK_ACTION(cell), 0));
  g_assert_cmpuint(f.requests.size(), ==, 1);
  g_autoptr(AtkObject) replacement =
      atk_table_ref_at(ATK_TABLE(f.accessible), 1, 0);
  g_assert_true(replacement != cell);
  g_assert_cmpstr(atk_object_get_name(replacement), ==, "Different commit");
}

void stable_cells_and_selection() {
  Fixture f;
  g_autoptr(AtkObject) cell = atk_table_ref_at(ATK_TABLE(f.accessible), 1, 0);
  f.frame.generation = 2;
  f.frame.selected = {1};
  f.frame.focused = true;
  f.frame.focused_row = 1;
  g_assert_true(UpdateGitTable(f.table, f.frame, f.rows));
  g_autoptr(AtkObject) retained =
      atk_table_ref_at(ATK_TABLE(f.accessible), 1, 0);
  g_assert_true(cell == retained);
  g_autoptr(AtkStateSet) state = atk_object_ref_state_set(retained);
  g_assert_true(atk_state_set_contains_state(state, ATK_STATE_SELECTED));
  g_assert_true(atk_state_set_contains_state(state, ATK_STATE_FOCUSED));
  gint* selected = nullptr;
  g_assert_cmpint(
      atk_table_get_selected_rows(ATK_TABLE(f.accessible), &selected), ==, 1);
  g_assert_cmpint(selected[0], ==, 1);
  g_free(selected);
  g_assert_true(atk_table_add_row_selection(ATK_TABLE(f.accessible), 0));
  g_assert_cmpstr(f.requests.back().action.c_str(), ==, "addSelection");
  g_assert_cmpstr(f.requests.back().row_id.c_str(), ==, "first");
}

void tree_relations_and_scoped_actions() {
  Fixture f;
  f.frame.tree = true;
  f.rows[0].expanded = 1;
  f.rows[1].parent = 0;
  f.rows[1].depth = 1;
  f.rows[1].actions = {{"stage", "Stage file"}};
  g_assert_true(UpdateGitTable(f.table, f.frame, f.rows));
  g_assert_cmpint(atk_object_get_role(f.accessible), ==, ATK_ROLE_TREE_TABLE);
  g_autoptr(AtkObject) child = atk_table_ref_at(ATK_TABLE(f.accessible), 1, 0);
  g_autoptr(AtkRelationSet) relations = atk_object_ref_relation_set(child);
  AtkRelation* relation = atk_relation_set_get_relation_by_type(
      relations, ATK_RELATION_NODE_CHILD_OF);
  g_assert_nonnull(relation);
  GPtrArray* targets = atk_relation_get_target(relation);
  g_assert_cmpuint(targets->len, ==, 1);
  g_assert_cmpstr(
      atk_object_get_name(ATK_OBJECT(g_ptr_array_index(targets, 0))), ==,
      "First café 😀");
  g_assert_cmpstr(atk_action_get_name(ATK_ACTION(child), 3), ==, "Stage file");
  g_assert_true(atk_action_do_action(ATK_ACTION(child), 3));
  g_assert_cmpstr(f.requests.back().action.c_str(), ==, "stage");
  g_assert_cmpstr(f.requests.back().row_id.c_str(), ==, "second");
}

void virtual_rows_are_bounded_and_honestly_pending() {
  Fixture f;
  f.frame.row_count = 100000;
  g_assert_true(UpdateGitTable(f.table, f.frame, f.rows));
  g_assert_cmpint(atk_object_get_n_accessible_children(f.accessible), <, 30);
  g_autoptr(AtkObject) far =
      atk_table_ref_at(ATK_TABLE(f.accessible), 90000, 0);
  g_assert_cmpstr(atk_object_get_name(far), ==, "Loading row");
  g_assert_false(atk_action_do_action(ATK_ACTION(far), 0));
  while (g_main_context_pending(nullptr))
    g_main_context_iteration(nullptr, FALSE);
  g_assert_cmpuint(f.requests.size(), ==, 1);
  g_assert_cmpstr(f.requests.back().action.c_str(), ==, "rows");
  g_assert_cmpint(f.requests.back().count, <=, 128);
  std::vector<TableRow> loaded = {
      {90000, "far", {"Far commit", "Author"}, "", -1, 0, -1, {}}};
  g_assert_false(UpdateGitTableRows(f.table, 0, loaded));
  g_assert_true(UpdateGitTableRows(f.table, 1, loaded));
  g_assert_cmpstr(atk_object_get_name(far), ==, "Far commit");
  g_assert_true(atk_action_do_action(ATK_ACTION(far), 0));
  g_assert_cmpstr(f.requests.back().row_id.c_str(), ==, "far");
}

void geometry_and_teardown() {
  Fixture f;
  g_autoptr(AtkObject) cell = atk_table_ref_at(ATK_TABLE(f.accessible), 1, 1);
  gint x, y, width, height, tx, ty;
  atk_component_get_extents(ATK_COMPONENT(f.accessible), &tx, &ty, nullptr,
                            nullptr, ATK_XY_SCREEN);
  atk_component_get_extents(ATK_COMPONENT(cell), &x, &y, &width, &height,
                            ATK_XY_SCREEN);
  g_assert_cmpint(x, ==, tx + 300);
  g_assert_cmpint(y, ==, ty + 60);
  g_assert_cmpint(width, ==, 180);
  g_assert_cmpint(height, ==, 30);
  gtk_widget_destroy(f.table);
  g_autoptr(AtkStateSet) states = atk_object_ref_state_set(cell);
  g_assert_true(atk_state_set_contains_state(states, ATK_STATE_DEFUNCT));
  g_assert_false(atk_component_grab_focus(ATK_COMPONENT(cell)));
  g_assert_null(atk_table_cell_get_table(ATK_TABLE_CELL(cell)));
}

void pending_rows_can_scroll_without_authorizing_actions() {
  Fixture f;
  f.frame.row_count = 100000;
  g_assert_true(UpdateGitTable(f.table, f.frame, f.rows));
  g_autoptr(AtkObject) far =
      atk_table_ref_at(ATK_TABLE(f.accessible), 90000, 0);
  g_assert_cmpstr(atk_object_get_name(far), ==, "Loading row");
  g_assert_true(atk_component_scroll_to(ATK_COMPONENT(far), ATK_SCROLL_ANYWHERE));
  g_assert_cmpuint(f.requests.size(), ==, 1);
  g_assert_cmpstr(f.requests.back().action.c_str(), ==, "scroll");
  g_assert_cmpint(f.requests.back().generation, ==, 1);
  g_assert_cmpint(f.requests.back().row, ==, 90000);
  g_assert_true(f.requests.back().row_id.empty());
  g_assert_false(atk_action_do_action(ATK_ACTION(far), 0));
  g_assert_false(atk_component_grab_focus(ATK_COMPONENT(far)));
  f.frame.generation = 2;
  g_assert_true(UpdateGitTable(f.table, f.frame, f.rows));
  g_assert_false(atk_component_scroll_to(ATK_COMPONENT(far), ATK_SCROLL_ANYWHERE));
  g_assert_cmpuint(f.requests.size(), ==, 1);
}

void invalid_packets_preserve_the_table() {
  Fixture f;
  TableFrame invalid = f.frame;
  invalid.row_height = 0;
  g_assert_false(UpdateGitTable(f.table, invalid, f.rows));
  invalid = f.frame;
  invalid.focused_row = f.frame.row_count;
  g_assert_false(UpdateGitTable(f.table, invalid, f.rows));
  invalid = f.frame;
  invalid.columns[0] = std::string("Subject\0substitution", 20);
  g_assert_false(UpdateGitTable(f.table, invalid, f.rows));
  auto rows = f.rows;
  rows[0].parent = 0;
  g_assert_false(UpdateGitTableRows(f.table, 1, rows));
  rows = f.rows;
  rows[0].id = "substitution";
  g_assert_false(UpdateGitTableRows(f.table, 1, rows));
  g_autoptr(AtkObject) cell = atk_table_ref_at(ATK_TABLE(f.accessible), 0, 0);
  g_assert_cmpstr(atk_object_get_name(cell), ==, "First café 😀");
  g_assert_cmpint(atk_table_get_n_rows(ATK_TABLE(f.accessible)), ==, 2);
}

void text_geometry_and_pointer_hit_testing() {
  Fixture f;
  f.rows[0].text_insets = {40, 0};
  g_assert_true(UpdateGitTable(f.table, f.frame, f.rows));
  g_autoptr(AtkObject) cell = atk_table_ref_at(ATK_TABLE(f.accessible), 0, 0);
  gint x, y, width, height, cx, cy;
  atk_component_get_extents(ATK_COMPONENT(cell), &cx, &cy, nullptr, nullptr,
                            ATK_XY_SCREEN);
  atk_text_get_character_extents(ATK_TEXT(cell), 0, &x, &y, &width, &height,
                                 ATK_XY_SCREEN);
  g_assert_cmpint(x, ==, cx + 40);
  g_assert_cmpint(y, >=, cy);
  g_assert_cmpint(width, >, 0);
  g_assert_cmpint(height, >, 0);
  g_assert_cmpint(atk_text_get_offset_at_point(ATK_TEXT(cell), x + 1,
                                               y + height / 2, ATK_XY_SCREEN),
                  ==, 0);
  g_autoptr(AtkObject) hit = atk_component_ref_accessible_at_point(
      ATK_COMPONENT(f.accessible), x + 1, y + 1, ATK_XY_SCREEN);
  g_assert_true(hit == cell);
  f.frame.font_size = 28;
  f.frame.row_height = 50;
  g_assert_true(UpdateGitTable(f.table, f.frame, f.rows));
  gint enlarged_height;
  atk_text_get_character_extents(ATK_TEXT(cell), 0, &x, &y, &width,
                                 &enlarged_height, ATK_XY_SCREEN);
  g_assert_cmpint(enlarged_height, >, height);
  g_assert_cmpint(x, ==, cx + 40);
}
void rtl_columns_and_replaced_columns() {
  Fixture f;
  f.frame.rtl = true;
  f.rows[0].text_insets = {40, 0};
  g_assert_true(UpdateGitTable(f.table, f.frame, f.rows));
  g_autoptr(AtkObject) subject =
      atk_table_ref_at(ATK_TABLE(f.accessible), 0, 0);
  g_autoptr(AtkObject) author = atk_table_ref_at(ATK_TABLE(f.accessible), 0, 1);
  gint x, y, width, height, tx;
  atk_component_get_extents(ATK_COMPONENT(f.accessible), &tx, nullptr, nullptr,
                            nullptr, ATK_XY_SCREEN);
  atk_component_get_extents(ATK_COMPONENT(subject), &x, &y, &width, &height,
                            ATK_XY_SCREEN);
  g_assert_cmpint(x, ==, tx + 180);
  atk_text_get_character_extents(ATK_TEXT(subject), 0, &x, &y, &width, &height,
                                 ATK_XY_SCREEN);
  g_assert_cmpint(x + width, <=, tx + 440);
  g_autoptr(AtkObject) hit = atk_component_ref_accessible_at_point(
      ATK_COMPONENT(f.accessible), x, y + 1, ATK_XY_SCREEN);
  g_assert_true(hit == subject);
  atk_component_get_extents(ATK_COMPONENT(author), &x, &y, &width, &height,
                            ATK_XY_SCREEN);
  g_assert_cmpint(x, ==, tx);
  g_autoptr(AtkObject) left_edge = atk_component_ref_accessible_at_point(
      ATK_COMPONENT(f.accessible), x, y + 1, ATK_XY_SCREEN);
  g_assert_true(left_edge == author);
  f.frame.columns[1] = "Full revision";
  f.rows[0].cells[1] = "a different column";
  g_assert_true(UpdateGitTable(f.table, f.frame, f.rows));
  g_autoptr(AtkStateSet) states = atk_object_ref_state_set(author);
  g_assert_true(atk_state_set_contains_state(states, ATK_STATE_DEFUNCT));
  g_assert_false(atk_action_do_action(ATK_ACTION(author), 0));
}

void disposal_notifies_defunct_once() {
  Fixture f;
  g_object_ref(f.table);
  g_autoptr(AtkObject) cell = atk_table_ref_at(ATK_TABLE(f.accessible), 0, 0);
  int notifications = 0;
  g_signal_connect(cell, "state-change",
                   G_CALLBACK(+[](AtkObject*, const gchar* state,
                                  gboolean enabled, gpointer data) {
                     if (enabled && g_strcmp0(state, "defunct") == 0)
                       ++*static_cast<int*>(data);
                   }),
                   &notifications);
  gtk_widget_destroy(f.table);
  g_object_run_dispose(G_OBJECT(f.table));
  g_object_run_dispose(G_OBJECT(f.table));
  g_assert_cmpint(notifications, ==, 1);
  g_object_unref(f.table);
}

void host_overlay_has_consistent_accessible_children() {
  GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  GtkWidget* overlay = gtk_overlay_new();
  gtk_container_add(GTK_CONTAINER(overlay), gtk_label_new("Host content"));
  gtk_container_add(GTK_CONTAINER(window), overlay);
  gtk_widget_show_all(window);
  AtkObject* parent = gtk_widget_get_accessible(overlay);
  g_assert_cmpint(atk_object_get_n_accessible_children(parent), ==, 1);
  int added = 0, removed = 0;
  g_signal_connect(parent, "children-changed::add",
                   G_CALLBACK(+[](AtkObject*, guint, gpointer, gpointer count) {
                     ++*static_cast<int*>(count);
                   }),
                   &added);
  g_signal_connect(parent, "children-changed::remove",
                   G_CALLBACK(+[](AtkObject*, guint, gpointer, gpointer count) {
                     ++*static_cast<int*>(count);
                   }),
                   &removed);
  GtkWidget* table = CreateGitTable({});
  AttachGitTable(GTK_OVERLAY(overlay), table);
  gtk_widget_show(table);
  while (g_main_context_pending(nullptr))
    g_main_context_iteration(nullptr, FALSE);
  g_assert_cmpint(added, ==, 1);
  AtkObject* accessible = gtk_widget_get_accessible(table);
  g_assert_cmpint(atk_object_get_n_accessible_children(parent), ==, 2);
  const int index = atk_object_get_index_in_parent(accessible);
  g_assert_cmpint(index, >=, 0);
  g_assert_cmpint(index, <, atk_object_get_n_accessible_children(parent));
  g_autoptr(AtkObject) child = atk_object_ref_accessible_child(parent, index);
  g_assert_true(child == accessible);
  gtk_widget_destroy(table);
  while (g_main_context_pending(nullptr))
    g_main_context_iteration(nullptr, FALSE);
  g_assert_cmpint(removed, ==, 1);
  g_assert_cmpint(atk_object_get_n_accessible_children(parent), ==, 1);
  gtk_widget_destroy(window);
}

void retire_during_parent_draw() {
  struct DrawFixture { GtkWidget* table; bool retired = false; };
  GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  GtkWidget* overlay = gtk_overlay_new();
  GtkWidget* content = gtk_drawing_area_new();
  gtk_container_add(GTK_CONTAINER(overlay), content);
  gtk_container_add(GTK_CONTAINER(window), overlay);
  gtk_window_set_default_size(GTK_WINDOW(window), 640, 480);
  DrawFixture fixture{CreateGitTable({})};
  g_object_ref_sink(fixture.table);
  GWeakRef weak;
  g_weak_ref_init(&weak, fixture.table);
  AttachGitTable(GTK_OVERLAY(overlay), fixture.table);
  g_signal_connect(content, "draw", G_CALLBACK(+[](GtkWidget*, cairo_t*, gpointer p) {
    auto* state = static_cast<DrawFixture*>(p);
    if (!state->retired) {
      state->retired = true;
      RetireGitTable(state->table);
      RetireGitTable(state->table);
      g_object_unref(state->table);
      state->table = nullptr;
    }
    return FALSE;
  }), &fixture);
  gtk_widget_show_all(window);
  const auto deadline = g_get_monotonic_time() + 5 * G_TIME_SPAN_SECOND;
  bool released = false;
  while (g_get_monotonic_time() < deadline) {
    while (g_main_context_pending(nullptr))
      g_main_context_iteration(nullptr, FALSE);
    GObject* remaining = G_OBJECT(g_weak_ref_get(&weak));
    released = remaining == nullptr;
    if (remaining) g_object_unref(remaining);
    if (fixture.retired && released) break;
    g_usleep(1000);
  }
  g_assert_true(fixture.retired);
  g_assert_true(released);
  g_weak_ref_clear(&weak);
  gtk_widget_destroy(window);
}

void retirement_survives_host_close_before_paint() {
  GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  GtkWidget* overlay = gtk_overlay_new();
  gtk_container_add(GTK_CONTAINER(overlay), gtk_label_new("Host"));
  gtk_container_add(GTK_CONTAINER(window), overlay);
  GtkWidget* table = CreateGitTable({});
  g_object_ref_sink(table);
  GWeakRef weak;
  g_weak_ref_init(&weak, table);
  AttachGitTable(GTK_OVERLAY(overlay), table);
  gtk_widget_show_all(window);
  g_assert_nonnull(gtk_widget_get_frame_clock(table));
  RetireGitTable(table);
  g_object_unref(table);
  gtk_widget_destroy(window);
  while (g_main_context_pending(nullptr))
    g_main_context_iteration(nullptr, FALSE);
  GObject* remaining = G_OBJECT(g_weak_ref_get(&weak));
  g_assert_null(remaining);
  g_weak_ref_clear(&weak);
}
}  // namespace

int main(int argc, char** argv) {
  gtk_test_init(&argc, &argv, nullptr);
  g_test_add_func("/git/table/interfaces-and-headers", interfaces_and_headers);
  g_test_add_func("/git/table/utf8-selection-and-copy", utf8_and_selection);
  g_test_add_func("/git/table/identity-bound-actions",
                  native_actions_are_identity_bound);
  g_test_add_func("/git/table/stable-cells-and-selection",
                  stable_cells_and_selection);
  g_test_add_func("/git/table/tree-relations-and-actions",
                  tree_relations_and_scoped_actions);
  g_test_add_func("/git/table/bounded-virtual-rows",
                  virtual_rows_are_bounded_and_honestly_pending);
  g_test_add_func("/git/table/pending-row-scroll",
                  pending_rows_can_scroll_without_authorizing_actions);
  g_test_add_func("/git/table/geometry-and-teardown", geometry_and_teardown);
  g_test_add_func("/git/table/invalid-packets",
                  invalid_packets_preserve_the_table);
  g_test_add_func("/git/table/text-geometry-and-pointer",
                  text_geometry_and_pointer_hit_testing);
  g_test_add_func("/git/table/rtl-and-replaced-columns",
                  rtl_columns_and_replaced_columns);
  g_test_add_func("/git/table/idempotent-disposal",
                  disposal_notifies_defunct_once);
  g_test_add_func("/git/table/host-overlay-hierarchy",
                  host_overlay_has_consistent_accessible_children);
  g_test_add_func("/git/table/retire-during-parent-draw", retire_during_parent_draw);
  g_test_add_func("/git/table/retire-before-host-close",
                  retirement_survives_host_close_before_paint);
  return g_test_run();
}
