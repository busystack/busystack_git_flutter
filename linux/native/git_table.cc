#include "git_table.h"

#include <gtk/gtk-a11y.h>

#include <algorithm>
#include <cmath>
#include <map>
#include <memory>
#include <set>
#include <unordered_set>
#include <utility>

namespace {
using busystack_git_ui::TableCallback;
using busystack_git_ui::TableFrame;
using busystack_git_ui::TableRequest;
using busystack_git_ui::TableRow;

constexpr int kPageSize = 128;
constexpr size_t kMaximumCachedRows = 2048;
constexpr size_t kMaximumCachedCells = 8192;

struct CellData {
  GWeakRef widget;
  int row = -1;
  int column = 0;
  int64_t generation = -1;
  bool defunct = false;
  bool selected = false;
  bool focused = false;
  std::string id;
  std::string text;
  std::string description;
  std::string loading_label;
  std::vector<std::string> action_labels;
  int parent = -1;
  int depth = 0;
  int expanded = -1;
  double text_inset = 0;
  std::vector<busystack_git_ui::TableAction> actions;
  int selection_start = 0;
  int selection_end = 0;
};

struct TableData {
  TableCallback callback;
  TableFrame frame;
  bool alive = true;
  bool retired = false;
  bool overlay_attached = false;
  std::map<int, TableRow> rows;
  std::map<std::pair<int, int>, AtkObject*> cells;
  std::set<int> requested_pages;
  std::unordered_set<int> selected_rows;
  guint pending_source = 0;
};

typedef struct _BsgGitTable {
  GtkDrawingArea parent_instance;
  TableData* data;
} BsgGitTable;
typedef struct _BsgGitTableClass {
  GtkDrawingAreaClass parent_class;
} BsgGitTableClass;

typedef struct _BsgGitTableAccessible {
  GtkWidgetAccessible parent_instance;
} BsgGitTableAccessible;
typedef struct _BsgGitTableAccessibleClass {
  GtkWidgetAccessibleClass parent_class;
} BsgGitTableAccessibleClass;

typedef struct _BsgGitCell {
  AtkObject parent_instance;
  CellData* data;
} BsgGitCell;
typedef struct _BsgGitCellClass {
  AtkObjectClass parent_class;
} BsgGitCellClass;

static void table_interface(AtkTableIface* iface);
static void selection_interface(AtkSelectionIface* iface);
static void cell_table_interface(AtkTableCellIface* iface);
static void cell_component_interface(AtkComponentIface* iface);
static void cell_text_interface(AtkTextIface* iface);
static void cell_action_interface(AtkActionIface* iface);
static void table_component_interface(AtkComponentIface* iface);

G_DEFINE_TYPE(BsgGitTable, bsg_git_table, GTK_TYPE_DRAWING_AREA)
G_DEFINE_TYPE_WITH_CODE(
    BsgGitTableAccessible, bsg_git_table_accessible, GTK_TYPE_WIDGET_ACCESSIBLE,
    G_IMPLEMENT_INTERFACE(ATK_TYPE_TABLE, table_interface)
        G_IMPLEMENT_INTERFACE(ATK_TYPE_SELECTION, selection_interface)
            G_IMPLEMENT_INTERFACE(ATK_TYPE_COMPONENT,
                                  table_component_interface))
G_DEFINE_TYPE_WITH_CODE(
    BsgGitCell, bsg_git_cell, ATK_TYPE_OBJECT,
    G_IMPLEMENT_INTERFACE(ATK_TYPE_TABLE_CELL, cell_table_interface)
        G_IMPLEMENT_INTERFACE(ATK_TYPE_COMPONENT, cell_component_interface)
            G_IMPLEMENT_INTERFACE(ATK_TYPE_TEXT, cell_text_interface)
                G_IMPLEMENT_INTERFACE(ATK_TYPE_ACTION, cell_action_interface))

static BsgGitTable* table_widget(AtkObject* accessible) {
  if (!GTK_IS_ACCESSIBLE(accessible)) return nullptr;
  GtkWidget* widget = gtk_accessible_get_widget(GTK_ACCESSIBLE(accessible));
  return widget && G_TYPE_CHECK_INSTANCE_TYPE(widget, bsg_git_table_get_type())
             ? reinterpret_cast<BsgGitTable*>(widget)
             : nullptr;
}

static BsgGitTable* cell_widget(CellData* cell) {
  auto* widget = reinterpret_cast<BsgGitTable*>(g_weak_ref_get(&cell->widget));
  if (!widget) return nullptr;
  if (cell->defunct || !widget->data->alive ||
      cell->generation != widget->data->frame.generation) {
    g_object_unref(widget);
    return nullptr;
  }
  return widget;
}

static bool selected(TableData* data, int row) {
  return data->selected_rows.count(row) != 0;
}

static int first_visible(TableData* data) {
  const auto& frame = data->frame;
  return std::clamp(
      static_cast<int>(std::floor(frame.scroll / frame.row_height)) -
          (frame.headers ? 1 : 0),
      0, frame.row_count);
}

static int visible_count(TableData* data) {
  return std::min(
      data->frame.row_count - first_visible(data),
      static_cast<int>(std::ceil(data->frame.height / data->frame.row_height)) +
          1);
}

static bool row_visible(TableData* data, int row) {
  return row >= first_visible(data) &&
         row < first_visible(data) + visible_count(data);
}

static bool request_row(BsgGitTable* widget, const char* action, int row,
                        int column = -1, const std::string& id = "") {
  TableData* data = widget->data;
  if (!data->alive || !data->callback) return false;
  // Scrolling reveals an index in this immutable frame; it does not select a
  // commit or authorize an action. AT can request it before lazy row metadata
  // arrives. Every other row action still requires its opaque identity.
  if (row >= 0 &&
      (row >= data->frame.row_count ||
       (id.empty() && g_strcmp0(action, "scroll") != 0)))
    return false;
  const auto callback = data->callback;
  callback({data->frame.generation, action, id, row, column, 0});
  return true;
}

static gboolean send_requested_rows(gpointer value) {
  auto* widget = reinterpret_cast<BsgGitTable*>(value);
  TableData* data = widget->data;
  data->pending_source = 0;
  auto requests = std::move(data->requested_pages);
  data->requested_pages.clear();
  if (!data->alive || !data->callback) return G_SOURCE_REMOVE;
  const auto generation = data->frame.generation;
  for (int start : requests) {
    if (!data->alive || data->frame.generation != generation) break;
    const auto callback = data->callback;
    callback({generation, "rows", "", start, -1,
              std::min(kPageSize, data->frame.row_count - start)});
  }
  return G_SOURCE_REMOVE;
}

static void need_row(BsgGitTable* widget, int row) {
  if (widget->data->rows.count(row)) return;
  widget->data->requested_pages.insert(row / kPageSize * kPageSize);
  if (!widget->data->pending_source) {
    widget->data->pending_source =
        g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, send_requested_rows,
                        g_object_ref(widget), g_object_unref);
  }
}

static void bind_cell(BsgGitTable* widget, BsgGitCell* cell) {
  auto* value = cell->data;
  auto* data = widget->data;
  value->action_labels = data->frame.action_labels;
  value->loading_label = data->frame.loading_label;
  std::string text;
  if (value->row < 0) {
    text = data->frame.columns[value->column];
    value->id = "header";
    value->text_inset = data->frame.header_insets.empty()
                            ? 0
                            : data->frame.header_insets[value->column];
  } else {
    auto found = data->rows.find(value->row);
    if (found == data->rows.end()) {
      need_row(widget, value->row);
      return;
    }
    const auto& row = found->second;
    value->id = row.id;
    text = row.cells[value->column];
    value->description = row.description;
    value->parent = row.parent;
    value->depth = row.depth;
    value->expanded = row.expanded;
    value->actions = row.actions;
    value->text_inset =
        row.text_insets.empty() ? 0 : row.text_insets[value->column];
  }
  const bool changed = value->text != text;
  const auto old_length = g_utf8_strlen(value->text.c_str(), -1);
  value->text = std::move(text);
  if (changed) {
    value->selection_start = value->selection_end = 0;
    g_object_notify(G_OBJECT(cell), "accessible-name");
    if (old_length)
      g_signal_emit_by_name(cell, "text-changed::delete", 0, old_length);
    g_signal_emit_by_name(cell, "text-changed::insert", 0,
                          g_utf8_strlen(value->text.c_str(), -1));
  }
}

static AtkObject* cell_at(BsgGitTable* widget, int row, int column) {
  auto* data = widget->data;
  const int columns = static_cast<int>(data->frame.columns.size());
  if (!data->alive || row < -1 || row >= data->frame.row_count || column < 0 ||
      column >= columns)
    return nullptr;
  auto key = std::make_pair(row, column);
  auto found = data->cells.find(key);
  if (found != data->cells.end()) return found->second;
  if (data->cells.size() >= kMaximumCachedCells) {
    auto old = std::find_if(
        data->cells.begin(), data->cells.end(), [&](const auto& entry) {
          return entry.first.first >= 0 &&
                 !row_visible(data, entry.first.first) &&
                 entry.first.first != data->frame.focused_row;
        });
    if (old == data->cells.end()) return nullptr;
    reinterpret_cast<BsgGitCell*>(old->second)->data->defunct = true;
    atk_object_set_parent(old->second, nullptr);
    atk_object_notify_state_change(old->second, ATK_STATE_DEFUNCT, TRUE);
    g_object_unref(old->second);
    data->cells.erase(old);
  }
  auto* cell = reinterpret_cast<BsgGitCell*>(
      g_object_new(bsg_git_cell_get_type(), nullptr));
  cell->data->row = row;
  cell->data->column = column;
  cell->data->generation = data->frame.generation;
  g_weak_ref_set(&cell->data->widget, widget);
  atk_object_set_parent(ATK_OBJECT(cell),
                        gtk_widget_get_accessible(GTK_WIDGET(widget)));
  data->cells.emplace(key, ATK_OBJECT(cell));
  bind_cell(widget, cell);
  return ATK_OBJECT(cell);
}

static const gchar* cell_name(AtkObject* object) {
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  return cell->id.empty() ? cell->loading_label.c_str() : cell->text.c_str();
}

static const gchar* cell_description(AtkObject* object) {
  return reinterpret_cast<BsgGitCell*>(object)->data->description.c_str();
}

static AtkRole cell_role(AtkObject* object) {
  return reinterpret_cast<BsgGitCell*>(object)->data->row < 0
             ? ATK_ROLE_COLUMN_HEADER
             : ATK_ROLE_TABLE_CELL;
}

static gint cell_index(AtkObject* object) {
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  BsgGitTable* widget = cell_widget(cell);
  if (!widget) return -1;
  auto* data = widget->data;
  const int columns = static_cast<int>(data->frame.columns.size());
  int index = -1;
  if (cell->row < 0)
    index = data->frame.headers ? cell->column : -1;
  else if (row_visible(data, cell->row))
    index = (data->frame.headers ? columns : 0) +
            (cell->row - first_visible(data)) * columns + cell->column;
  g_object_unref(widget);
  return index;
}

static AtkStateSet* cell_states(AtkObject* object) {
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  AtkStateSet* states = atk_state_set_new();
  BsgGitTable* widget = cell_widget(cell);
  if (!widget) {
    atk_state_set_add_state(states, ATK_STATE_DEFUNCT);
    return states;
  }
  auto* data = widget->data;
  atk_state_set_add_state(states, ATK_STATE_VISIBLE);
  atk_state_set_add_state(states, ATK_STATE_READ_ONLY);
  if (cell->id.empty() || data->frame.busy)
    atk_state_set_add_state(states, ATK_STATE_BUSY);
  if (data->frame.widths[cell->column] > 0 &&
      gtk_widget_get_mapped(GTK_WIDGET(widget)) &&
      (cell->row < 0 ? data->frame.scroll < data->frame.row_height
                     : row_visible(data, cell->row)))
    atk_state_set_add_state(states, ATK_STATE_SHOWING);
  if (cell->row >= 0 && !cell->id.empty()) {
    atk_state_set_add_state(states, ATK_STATE_FOCUSABLE);
    atk_state_set_add_state(states, ATK_STATE_SELECTABLE);
    atk_state_set_add_state(states, ATK_STATE_ENABLED);
    atk_state_set_add_state(states, ATK_STATE_SENSITIVE);
    if (selected(data, cell->row))
      atk_state_set_add_state(states, ATK_STATE_SELECTED);
    if (data->frame.focused && data->frame.focused_row == cell->row &&
        cell->column == 0)
      atk_state_set_add_state(states, ATK_STATE_FOCUSED);
    if (cell->expanded >= 0)
      atk_state_set_add_state(states, ATK_STATE_EXPANDABLE);
    if (cell->expanded > 0) atk_state_set_add_state(states, ATK_STATE_EXPANDED);
  }
  g_object_unref(widget);
  return states;
}

static AtkAttributeSet* cell_attributes(AtkObject* object) {
  const auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  BsgGitTable* widget = cell_widget(const_cast<CellData*>(cell));
  const bool tree = widget && widget->data->frame.tree;
  if (widget) g_object_unref(widget);
  if (!tree) return nullptr;
  auto* attribute = g_new0(AtkAttribute, 1);
  attribute->name = g_strdup("level");
  attribute->value = g_strdup_printf("%d", cell->depth + 1);
  return g_slist_append(nullptr, attribute);
}

static AtkRelationSet* cell_relations(AtkObject* object) {
  AtkRelationSet* result = atk_relation_set_new();
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  BsgGitTable* widget = cell_widget(cell);
  if (widget && cell->parent >= 0 && cell->row >= 0) {
    AtkObject* parent = cell_at(widget, cell->parent, 0);
    if (parent) {
      g_autoptr(AtkRelation) relation =
          atk_relation_new(&parent, 1, ATK_RELATION_NODE_CHILD_OF);
      atk_relation_set_add(result, relation);
    }
  }
  if (widget) g_object_unref(widget);
  return result;
}

static void cell_finalize(GObject* object) {
  auto* cell = reinterpret_cast<BsgGitCell*>(object);
  g_weak_ref_clear(&cell->data->widget);
  delete cell->data;
  G_OBJECT_CLASS(bsg_git_cell_parent_class)->finalize(object);
}

static void bsg_git_cell_class_init(BsgGitCellClass* klass) {
  G_OBJECT_CLASS(klass)->finalize = cell_finalize;
  AtkObjectClass* accessible = ATK_OBJECT_CLASS(klass);
  accessible->get_name = cell_name;
  accessible->get_description = cell_description;
  accessible->get_role = cell_role;
  accessible->get_index_in_parent = cell_index;
  accessible->ref_state_set = cell_states;
  accessible->get_attributes = cell_attributes;
  accessible->ref_relation_set = cell_relations;
}

static void bsg_git_cell_init(BsgGitCell* self) {
  self->data = new CellData;
  g_weak_ref_init(&self->data->widget, nullptr);
}

static gint table_children(AtkObject* object) {
  BsgGitTable* widget = table_widget(object);
  if (!widget || !widget->data->alive) return 0;
  const auto* data = widget->data;
  return (visible_count(widget->data) + (data->frame.headers ? 1 : 0)) *
         static_cast<int>(data->frame.columns.size());
}

static AtkObject* table_child(AtkObject* object, gint index) {
  BsgGitTable* widget = table_widget(object);
  if (!widget || index < 0 || index >= table_children(object)) return nullptr;
  const int columns = static_cast<int>(widget->data->frame.columns.size());
  int row = index / columns;
  if (widget->data->frame.headers) row--;
  if (row >= 0) row += first_visible(widget->data);
  AtkObject* cell = cell_at(widget, row, index % columns);
  return cell ? ATK_OBJECT(g_object_ref(cell)) : nullptr;
}

static AtkStateSet* table_states(AtkObject* object) {
  AtkStateSet* states = ATK_OBJECT_CLASS(bsg_git_table_accessible_parent_class)
                            ->ref_state_set(object);
  BsgGitTable* widget = table_widget(object);
  if (!widget || !widget->data->alive) {
    atk_state_set_add_state(states, ATK_STATE_DEFUNCT);
    return states;
  }
  atk_state_set_add_state(states, ATK_STATE_MULTISELECTABLE);
  atk_state_set_add_state(states, ATK_STATE_MANAGES_DESCENDANTS);
  atk_state_set_add_state(states, ATK_STATE_READ_ONLY);
  if (widget->data->frame.busy) atk_state_set_add_state(states, ATK_STATE_BUSY);
  return states;
}

static void bsg_git_table_accessible_class_init(
    BsgGitTableAccessibleClass* klass) {
  ATK_OBJECT_CLASS(klass)->get_n_children = table_children;
  ATK_OBJECT_CLASS(klass)->ref_child = table_child;
  ATK_OBJECT_CLASS(klass)->ref_state_set = table_states;
}
static void bsg_git_table_accessible_init(BsgGitTableAccessible*) {}

static void table_dispose(GObject* object) {
  GtkWidget* widget = GTK_WIDGET(object);
  auto* data = reinterpret_cast<BsgGitTable*>(widget)->data;
  g_autoptr(AtkObject) overlay_parent = nullptr;
  g_autoptr(AtkObject) accessible = nullptr;
  int overlay_index = -1;
  if (data->overlay_attached && gtk_widget_get_parent(widget)) {
    overlay_parent = ATK_OBJECT(
        g_object_ref(gtk_widget_get_accessible(gtk_widget_get_parent(widget))));
    accessible = ATK_OBJECT(g_object_ref(gtk_widget_get_accessible(widget)));
    overlay_index = atk_object_get_index_in_parent(accessible);
    data->overlay_attached = false;
  }
  // GtkWidget::dispose unparents the child before emitting ::destroy. Capture
  // its old index here, then notify with the updated hierarchy still alive.
  G_OBJECT_CLASS(bsg_git_table_parent_class)->dispose(object);
  if (overlay_parent && overlay_index >= 0) {
    g_signal_emit_by_name(overlay_parent, "children-changed::remove",
                          overlay_index, accessible);
  }
}

static void deactivate_table(GtkWidget* widget) {
  auto* data = reinterpret_cast<BsgGitTable*>(widget)->data;
  if (!data->alive) return;
  data->alive = false;
  data->callback = {};
  if (data->pending_source) {
    g_source_remove(data->pending_source);
    data->pending_source = 0;
  }
  for (auto& entry : data->cells) {
    reinterpret_cast<BsgGitCell*>(entry.second)->data->defunct = true;
    atk_object_set_parent(entry.second, nullptr);
    atk_object_notify_state_change(entry.second, ATK_STATE_DEFUNCT, TRUE);
  }
}

static void table_destroy(GtkWidget* widget) {
  // GtkWidget disposal can invoke destroy again after an explicit destroy.
  // Repeating DEFUNCT deregisters the same object twice in atk-bridge.
  deactivate_table(widget);
  GTK_WIDGET_CLASS(bsg_git_table_parent_class)->destroy(widget);
}

struct RetiredTable {
  GtkWidget* widget;
  gulong handler = 0;
};

static void release_retired_table(gpointer pointer, GClosure*) {
  auto* retired = static_cast<RetiredTable*>(pointer);
  gtk_widget_destroy(retired->widget);
  g_object_unref(retired->widget);
  delete retired;
}

static void retire_after_paint(GdkFrameClock* clock, gpointer pointer) {
  const auto handler = static_cast<RetiredTable*>(pointer)->handler;
  // Disconnecting releases the closure, which destroys the retained widget.
  g_signal_handler_disconnect(clock, handler);
}

static void table_finalize(GObject* object) {
  auto* widget = reinterpret_cast<BsgGitTable*>(object);
  for (auto& entry : widget->data->cells) g_object_unref(entry.second);
  delete widget->data;
  G_OBJECT_CLASS(bsg_git_table_parent_class)->finalize(object);
}

static void bsg_git_table_class_init(BsgGitTableClass* klass) {
  GTK_WIDGET_CLASS(klass)->destroy = table_destroy;
  G_OBJECT_CLASS(klass)->dispose = table_dispose;
  G_OBJECT_CLASS(klass)->finalize = table_finalize;
  gtk_widget_class_set_accessible_type(GTK_WIDGET_CLASS(klass),
                                       bsg_git_table_accessible_get_type());
}

static void bsg_git_table_init(BsgGitTable* self) {
  self->data = new TableData;
  gtk_widget_set_can_focus(GTK_WIDGET(self), FALSE);
  gtk_widget_set_app_paintable(GTK_WIDGET(self), TRUE);
  gtk_widget_set_has_window(GTK_WIDGET(self), FALSE);
}

static AtkObject* table_ref_at(AtkTable* table, gint row, gint column) {
  if (row < 0) return nullptr;
  BsgGitTable* widget = table_widget(ATK_OBJECT(table));
  AtkObject* cell = widget ? cell_at(widget, row, column) : nullptr;
  return cell ? ATK_OBJECT(g_object_ref(cell)) : nullptr;
}
static gint table_n_rows(AtkTable* table) {
  BsgGitTable* widget = table_widget(ATK_OBJECT(table));
  return widget && widget->data->alive ? widget->data->frame.row_count : 0;
}
static gint table_n_columns(AtkTable* table) {
  BsgGitTable* widget = table_widget(ATK_OBJECT(table));
  return widget && widget->data->alive
             ? static_cast<int>(widget->data->frame.columns.size())
             : 0;
}
static gint table_index_at(AtkTable* table, gint row, gint column) {
  BsgGitTable* widget = table_widget(ATK_OBJECT(table));
  AtkObject* cell = widget ? cell_at(widget, row, column) : nullptr;
  return cell ? cell_index(cell) : -1;
}
static gint table_row_at(AtkTable* table, gint index) {
  BsgGitTable* widget = table_widget(ATK_OBJECT(table));
  if (!widget || index < 0 || index >= table_children(ATK_OBJECT(table)))
    return -1;
  int row =
      index / table_n_columns(table) - (widget->data->frame.headers ? 1 : 0);
  return row < 0 ? -1 : first_visible(widget->data) + row;
}
static gint table_column_at(AtkTable* table, gint index) {
  return index < 0 || index >= table_children(ATK_OBJECT(table))
             ? -1
             : index % table_n_columns(table);
}
static gint table_extent(AtkTable* table, gint row, gint column) {
  return row >= 0 && row < table_n_rows(table) && column >= 0 &&
                 column < table_n_columns(table)
             ? 1
             : 0;
}
static AtkObject* table_header(AtkTable* table, gint column) {
  BsgGitTable* widget = table_widget(ATK_OBJECT(table));
  return widget ? cell_at(widget, -1, column) : nullptr;
}
static const gchar* table_column_description(AtkTable* table, gint column) {
  AtkObject* header = table_header(table, column);
  return header ? atk_object_get_name(header) : nullptr;
}
static const gchar* table_row_description(AtkTable* table, gint row) {
  BsgGitTable* widget = table_widget(ATK_OBJECT(table));
  AtkObject* cell = widget ? cell_at(widget, row, 0) : nullptr;
  return cell ? atk_object_get_description(cell) : nullptr;
}
static gboolean table_row_selected(AtkTable* table, gint row) {
  BsgGitTable* widget = table_widget(ATK_OBJECT(table));
  return widget && row >= 0 && row < widget->data->frame.row_count &&
         selected(widget->data, row);
}
static gboolean table_cell_selected(AtkTable* table, gint row, gint column) {
  return column >= 0 && column < table_n_columns(table) &&
         table_row_selected(table, row);
}
static gint table_selected_rows(AtkTable* table, gint** output) {
  BsgGitTable* widget = table_widget(ATK_OBJECT(table));
  if (!widget) {
    *output = nullptr;
    return 0;
  }
  const auto& values = widget->data->frame.selected;
  *output = values.empty() ? nullptr : g_new(gint, values.size());
  if (!values.empty()) std::copy(values.begin(), values.end(), *output);
  return static_cast<int>(values.size());
}
static gboolean select_row(AtkTable* table, gint row, const char* action) {
  BsgGitTable* widget = table_widget(ATK_OBJECT(table));
  AtkObject* cell = widget ? cell_at(widget, row, 0) : nullptr;
  return cell && request_row(widget, action, row, 0,
                             reinterpret_cast<BsgGitCell*>(cell)->data->id);
}
static gboolean table_add_row(AtkTable* table, gint row) {
  return select_row(table, row, "addSelection");
}
static gboolean table_remove_row(AtkTable* table, gint row) {
  return select_row(table, row, "removeSelection");
}

static void table_interface(AtkTableIface* iface) {
  iface->ref_at = table_ref_at;
  iface->get_n_rows = table_n_rows;
  iface->get_n_columns = table_n_columns;
  iface->get_index_at = table_index_at;
  iface->get_row_at_index = table_row_at;
  iface->get_column_at_index = table_column_at;
  iface->get_row_extent_at = table_extent;
  iface->get_column_extent_at = table_extent;
  iface->get_column_header = table_header;
  iface->get_column_description = table_column_description;
  iface->get_row_description = table_row_description;
  iface->get_selected_rows = table_selected_rows;
  iface->is_row_selected = table_row_selected;
  iface->is_selected = table_cell_selected;
  iface->add_row_selection = table_add_row;
  iface->remove_row_selection = table_remove_row;
}

static gboolean selection_add(AtkSelection* selection, gint index) {
  int row = table_row_at(ATK_TABLE(selection), index);
  return row >= 0 && table_add_row(ATK_TABLE(selection), row);
}
static gboolean selection_clear(AtkSelection* selection) {
  BsgGitTable* widget = table_widget(ATK_OBJECT(selection));
  return widget && request_row(widget, "clearSelection", -1);
}
static AtkObject* selection_ref(AtkSelection* selection, gint index) {
  BsgGitTable* widget = table_widget(ATK_OBJECT(selection));
  if (!widget || index < 0) return nullptr;
  const int columns = table_n_columns(ATK_TABLE(selection));
  if (!columns || static_cast<size_t>(index / columns) >=
                      widget->data->frame.selected.size())
    return nullptr;
  return table_ref_at(ATK_TABLE(selection),
                      widget->data->frame.selected[index / columns],
                      index % columns);
}
static gint selection_count(AtkSelection* selection) {
  BsgGitTable* widget = table_widget(ATK_OBJECT(selection));
  return widget ? static_cast<int>(widget->data->frame.selected.size() *
                                   widget->data->frame.columns.size())
                : 0;
}
static gboolean selection_is_selected(AtkSelection* selection, gint index) {
  return table_row_selected(ATK_TABLE(selection),
                            table_row_at(ATK_TABLE(selection), index));
}
static gboolean selection_remove(AtkSelection* selection, gint index) {
  BsgGitTable* widget = table_widget(ATK_OBJECT(selection));
  if (!widget || index < 0) return FALSE;
  const int columns = table_n_columns(ATK_TABLE(selection));
  if (!columns || static_cast<size_t>(index / columns) >=
                      widget->data->frame.selected.size())
    return FALSE;
  return table_remove_row(ATK_TABLE(selection),
                          widget->data->frame.selected[index / columns]);
}
static gboolean selection_all(AtkSelection* selection) {
  BsgGitTable* widget = table_widget(ATK_OBJECT(selection));
  return widget && request_row(widget, "selectAll", -1);
}
static void selection_interface(AtkSelectionIface* iface) {
  iface->add_selection = selection_add;
  iface->clear_selection = selection_clear;
  iface->ref_selection = selection_ref;
  iface->get_selection_count = selection_count;
  iface->is_child_selected = selection_is_selected;
  iface->remove_selection = selection_remove;
  iface->select_all_selection = selection_all;
}

static gboolean cell_position(AtkTableCell* object, gint* row, gint* column) {
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  BsgGitTable* widget = cell_widget(cell);
  if (!widget || cell->row < 0) {
    if (widget) g_object_unref(widget);
    return FALSE;
  }
  *row = cell->row;
  *column = cell->column;
  g_object_unref(widget);
  return TRUE;
}
static gint cell_span(AtkTableCell*) { return 1; }
static gboolean cell_row_column_span(AtkTableCell* cell, gint* row,
                                     gint* column, gint* rows, gint* columns) {
  *rows = *columns = 1;
  return cell_position(cell, row, column);
}
static AtkObject* cell_table(AtkTableCell* object) {
  BsgGitTable* widget =
      cell_widget(reinterpret_cast<BsgGitCell*>(object)->data);
  if (!widget) return nullptr;
  AtkObject* result =
      ATK_OBJECT(g_object_ref(gtk_widget_get_accessible(GTK_WIDGET(widget))));
  g_object_unref(widget);
  return result;
}
static GPtrArray* cell_headers(AtkTableCell* object) {
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  GPtrArray* result = g_ptr_array_new_with_free_func(g_object_unref);
  BsgGitTable* widget = cell_widget(cell);
  if (widget) {
    AtkObject* header = cell_at(widget, -1, cell->column);
    if (header) g_ptr_array_add(result, g_object_ref(header));
    g_object_unref(widget);
  }
  return result;
}
static void cell_table_interface(AtkTableCellIface* iface) {
  iface->get_position = cell_position;
  iface->get_row_span = cell_span;
  iface->get_column_span = cell_span;
  iface->get_row_column_span = cell_row_column_span;
  iface->get_table = cell_table;
  iface->get_column_header_cells = cell_headers;
}

// Geometry belongs to the host GTK overlay, rather than Flutter's AtkPlug.
// Calling an in-process plug synchronously over AT-SPI can deadlock its own
// GTK dispatch loop; GtkWidgetAccessible resolves this owner locally.
static void cell_extents(AtkComponent* object, gint* x, gint* y, gint* width,
                         gint* height, AtkCoordType coords) {
  *x = *y = *width = *height = 0;
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  BsgGitTable* widget = cell_widget(cell);
  if (!widget) return;
  const auto& frame = widget->data->frame;
  atk_component_get_extents(
      ATK_COMPONENT(gtk_widget_get_accessible(GTK_WIDGET(widget))), x, y,
      nullptr, nullptr, coords);
  double left = 0;
  for (int c = 0; c < cell->column; ++c) left += frame.widths[c];
  const double cell_width = frame.widths[cell->column];
  if (frame.rtl) left = frame.width - left - cell_width;
  *x += static_cast<int>(std::round(left));
  *y += static_cast<int>(std::round(
      (cell->row + (frame.headers ? 1 : 0)) * frame.row_height - frame.scroll));
  *width = static_cast<int>(std::ceil(cell_width));
  *height = static_cast<int>(std::ceil(frame.row_height));
  g_object_unref(widget);
}
static gboolean cell_focus(AtkComponent* object) {
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  BsgGitTable* widget = cell_widget(cell);
  if (!widget) return FALSE;
  const bool result = cell->row >= 0 && request_row(widget, "focus", cell->row,
                                                    cell->column, cell->id);
  g_object_unref(widget);
  return result;
}
static gboolean cell_scroll(AtkComponent* object, AtkScrollType) {
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  BsgGitTable* widget = cell_widget(cell);
  if (!widget) return FALSE;
  const bool result = cell->row >= 0 && request_row(widget, "scroll", cell->row,
                                                    cell->column, cell->id);
  g_object_unref(widget);
  return result;
}
static gboolean cell_contains(AtkComponent* cell, gint x, gint y,
                              AtkCoordType coords) {
  gint cx, cy, width, height;
  cell_extents(cell, &cx, &cy, &width, &height, coords);
  return x >= cx && y >= cy && x < cx + width && y < cy + height;
}
static AtkLayer cell_layer(AtkComponent*) { return ATK_LAYER_WIDGET; }
static void cell_component_interface(AtkComponentIface* iface) {
  iface->get_extents = cell_extents;
  iface->grab_focus = cell_focus;
  iface->scroll_to = cell_scroll;
  iface->contains = cell_contains;
  iface->get_layer = cell_layer;
}

static AtkObject* table_at_point(AtkComponent* component, gint x, gint y,
                                 AtkCoordType coords) {
  BsgGitTable* widget = table_widget(ATK_OBJECT(component));
  if (!widget || !widget->data->alive) return nullptr;
  gint left, top, width, height;
  atk_component_get_extents(component, &left, &top, &width, &height, coords);
  if (x < left || x >= left + width || y < top || y >= top + height)
    return nullptr;
  const auto& frame = widget->data->frame;
  const int row = static_cast<int>(
                      std::floor((y - top + frame.scroll) / frame.row_height)) -
                  (frame.headers ? 1 : 0);
  double local = frame.rtl
                     ? std::nextafter(frame.width - (x - left), -G_MAXDOUBLE)
                     : x - left;
  int column = 0;
  while (column < static_cast<int>(frame.widths.size()) &&
         local >= frame.widths[column]) {
    local -= frame.widths[column++];
  }
  AtkObject* cell = cell_at(widget, row, column);
  return cell ? ATK_OBJECT(g_object_ref(cell)) : nullptr;
}

static void table_component_interface(AtkComponentIface* iface) {
  iface->ref_accessible_at_point = table_at_point;
}

static gint text_count(AtkText* object) {
  return static_cast<gint>(g_utf8_strlen(
      reinterpret_cast<BsgGitCell*>(object)->data->text.c_str(), -1));
}
static gchar* text_get(AtkText* object, gint start, gint end) {
  const std::string& value = reinterpret_cast<BsgGitCell*>(object)->data->text;
  const int count = text_count(object);
  start = std::clamp(start, 0, count);
  end = end < 0 ? count : std::clamp(end, start, count);
  const char* first = g_utf8_offset_to_pointer(value.c_str(), start);
  const char* last = g_utf8_offset_to_pointer(value.c_str(), end);
  return g_strndup(first, last - first);
}
static gunichar text_character(AtkText* object, gint index) {
  if (index < 0 || index >= text_count(object)) return 0;
  return g_utf8_get_char(g_utf8_offset_to_pointer(
      reinterpret_cast<BsgGitCell*>(object)->data->text.c_str(), index));
}
static gchar* text_string(AtkText* object, gint offset,
                          AtkTextGranularity granularity, gint* start,
                          gint* end) {
  const int count = text_count(object);
  if (offset < 0 || offset >= count) {
    *start = *end = count;
    return g_strdup("");
  }
  *start = offset;
  *end = offset + 1;
  if (granularity != ATK_TEXT_GRANULARITY_CHAR) {
    const auto& text = reinterpret_cast<BsgGitCell*>(object)->data->text;
    std::vector<PangoLogAttr> attributes(count + 1);
    pango_get_log_attrs(text.c_str(), -1, -1, pango_language_get_default(),
                        attributes.data(), count + 1);
    auto boundary_start = [&](int i) {
      if (granularity == ATK_TEXT_GRANULARITY_WORD)
        return attributes[i].is_word_start || i == 0;
      if (granularity == ATK_TEXT_GRANULARITY_SENTENCE)
        return attributes[i].is_sentence_start || i == 0;
      return i == 0 || text_character(object, i - 1) == '\n';
    };
    auto boundary_end = [&](int i) {
      if (granularity == ATK_TEXT_GRANULARITY_WORD)
        return attributes[i].is_word_end || i == count;
      if (granularity == ATK_TEXT_GRANULARITY_SENTENCE)
        return attributes[i].is_sentence_end || i == count;
      return i == count || text_character(object, i - 1) == '\n';
    };
    while (*start > 0 && !boundary_start(*start)) --*start;
    while (*end < count && !boundary_end(*end)) ++*end;
  }
  return text_get(object, *start, *end);
}
static gint text_caret(AtkText* object) {
  return reinterpret_cast<BsgGitCell*>(object)->data->selection_end;
}
static gboolean text_set_caret(AtkText* object, gint offset) {
  if (offset < 0 || offset > text_count(object)) return FALSE;
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  cell->selection_start = cell->selection_end = offset;
  g_signal_emit_by_name(object, "text-caret-moved", offset);
  return TRUE;
}
static gint text_selection_count(AtkText* object) {
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  return cell->selection_start != cell->selection_end ? 1 : 0;
}
static gchar* text_selection(AtkText* object, gint number, gint* start,
                             gint* end) {
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  if (number != 0 || !text_selection_count(object)) return nullptr;
  *start = cell->selection_start;
  *end = cell->selection_end;
  return text_get(object, *start, *end);
}
static gboolean text_add_selection(AtkText* object, gint start, gint end) {
  if (start < 0 || end < start || end > text_count(object)) return FALSE;
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  cell->selection_start = start;
  cell->selection_end = end;
  g_signal_emit_by_name(object, "text-selection-changed");
  return TRUE;
}
static gboolean text_remove_selection(AtkText* object, gint number) {
  if (number != 0) return FALSE;
  return text_add_selection(object, 0, 0);
}
static gboolean text_set_selection(AtkText* object, gint number, gint start,
                                   gint end) {
  return number == 0 && text_add_selection(object, start, end);
}

static PangoLayout* text_layout(BsgGitTable* widget, CellData* cell) {
  const auto& frame = widget->data->frame;
  PangoLayout* layout =
      gtk_widget_create_pango_layout(GTK_WIDGET(widget), cell->text.c_str());
  g_autoptr(PangoFontDescription) font = pango_font_description_new();
  pango_font_description_set_family(font, frame.font_family.c_str());
  pango_font_description_set_absolute_size(font, frame.font_size * PANGO_SCALE);
  pango_font_description_set_weight(
      font, cell->row < 0 ? PANGO_WEIGHT_SEMIBOLD : PANGO_WEIGHT_NORMAL);
  pango_layout_set_font_description(layout, font);
  pango_layout_set_width(
      layout, static_cast<int>(
                  std::max(0.0, frame.widths[cell->column] - cell->text_inset) *
                  PANGO_SCALE));
  pango_layout_set_height(layout,
                          static_cast<int>(frame.row_height * PANGO_SCALE));
  pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);
  pango_layout_set_auto_dir(layout, FALSE);
  pango_layout_set_alignment(layout,
                             frame.rtl ? PANGO_ALIGN_RIGHT : PANGO_ALIGN_LEFT);
  return layout;
}

static void text_extents(AtkText* object, gint offset, gint* x, gint* y,
                         gint* width, gint* height, AtkCoordType coords) {
  *x = *y = *width = *height = 0;
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  BsgGitTable* widget = cell_widget(cell);
  if (!widget || offset < 0 || offset >= text_count(object)) {
    if (widget) g_object_unref(widget);
    return;
  }
  gint cell_width, cell_height;
  cell_extents(ATK_COMPONENT(object), x, y, &cell_width, &cell_height, coords);
  if (!widget->data->frame.rtl)
    *x += static_cast<int>(std::round(cell->text_inset));
  g_autoptr(PangoLayout) layout = text_layout(widget, cell);
  PangoRectangle position;
  const char* point = g_utf8_offset_to_pointer(cell->text.c_str(), offset);
  pango_layout_index_to_pos(
      layout, static_cast<int>(point - cell->text.c_str()), &position);
  gint layout_height;
  pango_layout_get_pixel_size(layout, nullptr, &layout_height);
  *x += static_cast<int>(
      std::floor(std::min(position.x, position.x + position.width) /
                 static_cast<double>(PANGO_SCALE)));
  *y +=
      std::max(0, (cell_height - layout_height) / 2) + position.y / PANGO_SCALE;
  *width =
      std::min(cell_width,
               static_cast<int>(std::ceil(std::abs(position.width) /
                                          static_cast<double>(PANGO_SCALE))));
  *height = std::min(cell_height,
                     static_cast<int>(std::ceil(
                         position.height / static_cast<double>(PANGO_SCALE))));
  g_object_unref(widget);
}

static gint text_offset_at_point(AtkText* object, gint x, gint y,
                                 AtkCoordType coords) {
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  BsgGitTable* widget = cell_widget(cell);
  if (!widget) return -1;
  gint cx, cy, width, height;
  cell_extents(ATK_COMPONENT(object), &cx, &cy, &width, &height, coords);
  g_autoptr(PangoLayout) layout = text_layout(widget, cell);
  gint layout_height, index, trailing;
  pango_layout_get_pixel_size(layout, nullptr, &layout_height);
  const bool inside = pango_layout_xy_to_index(
      layout,
      (x - cx -
       (widget->data->frame.rtl
            ? 0
            : static_cast<int>(std::round(cell->text_inset)))) *
          PANGO_SCALE,
      (y - cy - std::max(0, (height - layout_height) / 2)) * PANGO_SCALE,
      &index, &trailing);
  gint result = inside ? static_cast<gint>(g_utf8_pointer_to_offset(
                             cell->text.c_str(), cell->text.c_str() + index)) +
                             trailing
                       : -1;
  g_object_unref(widget);
  return result;
}
static void cell_text_interface(AtkTextIface* iface) {
  iface->get_text = text_get;
  iface->get_character_count = text_count;
  iface->get_character_at_offset = text_character;
  iface->get_string_at_offset = text_string;
  iface->get_caret_offset = text_caret;
  iface->set_caret_offset = text_set_caret;
  iface->get_n_selections = text_selection_count;
  iface->get_selection = text_selection;
  iface->add_selection = text_add_selection;
  iface->remove_selection = text_remove_selection;
  iface->set_selection = text_set_selection;
  iface->get_character_extents = text_extents;
  iface->get_offset_at_point = text_offset_at_point;
}

static gint action_count(AtkAction* object) {
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  BsgGitTable* widget = cell_widget(cell);
  const int count = widget && cell->row >= 0 && !cell->id.empty()
                        ? 3 + static_cast<int>(cell->actions.size())
                        : 0;
  if (widget) g_object_unref(widget);
  return count;
}
static const gchar* action_name(AtkAction* object, gint index) {
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  if (index < 0 || index >= action_count(object)) return nullptr;
  if (index < 3) return cell->action_labels[index].c_str();
  return cell->actions[index - 3].label.c_str();
}
static gboolean action_do(AtkAction* object, gint index) {
  if (index < 0 || index >= action_count(object)) return FALSE;
  auto* cell = reinterpret_cast<BsgGitCell*>(object)->data;
  BsgGitTable* widget = cell_widget(cell);
  if (!widget) return FALSE;
  bool result = true;
  if (index == 2) {
    g_autofree gchar* text =
        cell->selection_start == cell->selection_end
            ? g_strdup(cell->text.c_str())
            : text_get(ATK_TEXT(object), cell->selection_start,
                       cell->selection_end);
    gtk_clipboard_set_text(gtk_clipboard_get_for_display(
                               gtk_widget_get_display(GTK_WIDGET(widget)),
                               GDK_SELECTION_CLIPBOARD),
                           text, -1);
  } else {
    const std::string action = index == 0   ? "select"
                               : index == 1 ? "context"
                                            : cell->actions[index - 3].id;
    result =
        request_row(widget, action.c_str(), cell->row, cell->column, cell->id);
  }
  g_object_unref(widget);
  return result;
}
static void cell_action_interface(AtkActionIface* iface) {
  iface->get_n_actions = action_count;
  iface->get_name = action_name;
  iface->get_localized_name = action_name;
  iface->get_description = action_name;
  iface->do_action = action_do;
}

static bool valid_text(const std::string& value, size_t limit) {
  return value.size() <= limit && value.find('\0') == std::string::npos &&
         g_utf8_validate(value.data(), value.size(), nullptr);
}
static bool valid_frame(const TableFrame& frame) {
  if (frame.generation < 0 || frame.columns.empty() ||
      frame.columns.size() > 8 || frame.widths.size() != frame.columns.size() ||
      frame.row_count < 0 || frame.row_count > 1000000 ||
      !std::isfinite(frame.row_height) || frame.row_height < 1 ||
      frame.row_height > 4096 || !std::isfinite(frame.scroll) ||
      frame.scroll < 0 || !std::isfinite(frame.width) || frame.width <= 0 ||
      frame.width > 65536 || !std::isfinite(frame.height) ||
      frame.height <= 0 || frame.height > 65536 ||
      frame.height / frame.row_height * frame.columns.size() > 8000 ||
      !std::isfinite(frame.font_size) || frame.font_size <= 0 ||
      frame.font_size > 4096 || frame.action_labels.size() != 3 ||
      frame.focused_row < -1 || frame.focused_row >= frame.row_count ||
      (!frame.header_insets.empty() &&
       frame.header_insets.size() != frame.columns.size()))
    return false;
  for (double inset : frame.header_insets)
    if (!std::isfinite(inset) || inset < 0 || inset > frame.width) return false;
  for (double width : frame.widths)
    if (!std::isfinite(width) || width < 0 || width > frame.width) return false;
  std::set<int> selected;
  for (int row : frame.selected)
    if (row < 0 || row >= frame.row_count || !selected.insert(row).second)
      return false;
  for (const auto& label : frame.action_labels)
    if (!valid_text(label, 1024)) return false;
  for (const auto& column : frame.columns)
    if (!valid_text(column, 1024)) return false;
  return valid_text(frame.loading_label, 1024) &&
         valid_text(frame.font_family, 1024) && valid_text(frame.name, 65536) &&
         valid_text(frame.description, 65536);
}
static bool valid_rows(const TableFrame& frame,
                       const std::vector<TableRow>& rows) {
  if (rows.size() > 512) return false;
  size_t bytes = 0;
  std::set<int> indices;
  std::set<std::string> identities;
  for (const auto& row : rows) {
    if (row.index < 0 || row.index >= frame.row_count || row.id.empty() ||
        row.id.size() > 65536 || row.parent < -1 || row.parent >= row.index ||
        row.depth < 0 || row.depth > 4096 || row.expanded < -1 ||
        row.expanded > 1 || row.cells.size() != frame.columns.size() ||
        row.actions.size() > 16 || !valid_text(row.id, 65536) ||
        !indices.insert(row.index).second ||
        !identities.insert(row.id).second ||
        (!row.text_insets.empty() &&
         row.text_insets.size() != frame.columns.size()))
      return false;
    for (double inset : row.text_insets)
      if (!std::isfinite(inset) || inset < 0 || inset > frame.width)
        return false;
    for (const auto& text : row.cells) {
      bytes += text.size();
      if (!valid_text(text, 65536)) return false;
    }
    bytes += row.id.size() + row.description.size();
    if (!valid_text(row.description, 65536)) return false;
    std::set<std::string> actions;
    for (const auto& action : row.actions) {
      bytes += action.id.size() + action.label.size();
      if (action.id.empty() || !valid_text(action.id, 128) ||
          !valid_text(action.label, 1024) || !actions.insert(action.id).second)
        return false;
    }
  }
  return bytes <= 8 * 1024 * 1024;
}

}  // namespace

namespace busystack_git_ui {
GtkWidget* CreateGitTable(TableCallback callback) {
  auto* widget = reinterpret_cast<BsgGitTable*>(
      g_object_new(bsg_git_table_get_type(), nullptr));
  widget->data->callback = std::move(callback);
  return GTK_WIDGET(widget);
}

void AttachGitTable(GtkOverlay* host, GtkWidget* table) {
  g_return_if_fail(GTK_IS_OVERLAY(host));
  g_return_if_fail(G_TYPE_CHECK_INSTANCE_TYPE(table, bsg_git_table_get_type()));
  g_return_if_fail(gtk_widget_get_parent(table) == nullptr);
  AtkObject* parent = gtk_widget_get_accessible(GTK_WIDGET(host));
  gtk_overlay_add_overlay(host, table);
  gtk_overlay_set_overlay_pass_through(host, table, TRUE);
  reinterpret_cast<BsgGitTable*>(table)->data->overlay_attached = true;
  AtkObject* child = gtk_widget_get_accessible(table);
  g_signal_emit_by_name(parent, "children-changed::add",
                        atk_object_get_index_in_parent(child), child);
}

void RetireGitTable(GtkWidget* table) {
  g_return_if_fail(G_TYPE_CHECK_INSTANCE_TYPE(table, bsg_git_table_get_type()));
  auto* data = reinterpret_cast<BsgGitTable*>(table)->data;
  if (data->retired) return;
  data->retired = true;
  GdkFrameClock* clock = gtk_widget_get_frame_clock(table);
  deactivate_table(table);
  gtk_widget_hide(table);
  if (!clock) {
    gtk_widget_destroy(table);
    return;
  }
  // Flutter can dispatch platform messages while GTK is drawing its parent.
  // GtkOverlay's draw traversal still contains this child at that point.
  // Retain it until after-paint, even when its Dart view has already gone away.
  auto* retired = new RetiredTable{GTK_WIDGET(g_object_ref(table))};
  retired->handler = g_signal_connect_data(
      clock, "after-paint", G_CALLBACK(retire_after_paint), retired,
      release_retired_table, G_CONNECT_DEFAULT);
  gdk_frame_clock_request_phase(clock, GDK_FRAME_CLOCK_PHASE_AFTER_PAINT);
}

bool UpdateGitTableRows(GtkWidget* value, int64_t generation,
                        const std::vector<TableRow>& rows) {
  if (!G_TYPE_CHECK_INSTANCE_TYPE(value, bsg_git_table_get_type()))
    return false;
  auto* widget = reinterpret_cast<BsgGitTable*>(value);
  auto* data = widget->data;
  if (!data->alive || data->frame.generation != generation ||
      !valid_rows(data->frame, rows))
    return false;
  for (const auto& row : rows) {
    auto prior = data->rows.find(row.index);
    if (prior != data->rows.end() && prior->second.id != row.id) return false;
  }
  for (const auto& row : rows) {
    data->rows[row.index] = row;
    for (size_t column = 0; column < data->frame.columns.size(); ++column) {
      auto found = data->cells.find({row.index, static_cast<int>(column)});
      if (found != data->cells.end()) {
        bind_cell(widget, reinterpret_cast<BsgGitCell*>(found->second));
        atk_object_notify_state_change(found->second, ATK_STATE_BUSY, FALSE);
      }
    }
  }
  // Offscreen cells are lightweight and created only when requested by AT.
  // Keep the table's own cache bounded; external AT references retain their
  // immutable cell data, with generation checks still guarding every action.
  for (auto it = data->rows.begin();
       data->rows.size() > kMaximumCachedRows && it != data->rows.end();) {
    if (row_visible(data, it->first) || it->first == data->frame.focused_row) {
      ++it;
      continue;
    }
    int row = it->first;
    it = data->rows.erase(it);
    for (size_t column = 0; column < data->frame.columns.size(); ++column) {
      auto cell = data->cells.find({row, static_cast<int>(column)});
      if (cell != data->cells.end()) {
        reinterpret_cast<BsgGitCell*>(cell->second)->data->defunct = true;
        atk_object_set_parent(cell->second, nullptr);
        atk_object_notify_state_change(cell->second, ATK_STATE_DEFUNCT, TRUE);
        g_object_unref(cell->second);
        data->cells.erase(cell);
      }
    }
  }
  return true;
}

bool UpdateGitTable(GtkWidget* value, const TableFrame& frame,
                    const std::vector<TableRow>& rows) {
  if (!G_TYPE_CHECK_INSTANCE_TYPE(value, bsg_git_table_get_type()) ||
      !valid_frame(frame) || !valid_rows(frame, rows))
    return false;
  auto* widget = reinterpret_cast<BsgGitTable*>(value);
  auto* data = widget->data;
  if (!data->alive) return false;
  if (frame.generation == data->frame.generation &&
      frame.columns == data->frame.columns) {
    for (const auto& row : rows) {
      auto prior = data->rows.find(row.index);
      if (prior != data->rows.end() && prior->second.id != row.id) return false;
    }
  }
  const auto previous = data->frame;
  const bool columns_changed = frame.columns != previous.columns;
  const bool replacement =
      frame.generation != previous.generation || columns_changed;
  std::map<std::pair<std::string, int>, AtkObject*> retained;
  if (replacement) {
    for (const auto& cell : data->cells) {
      auto* info = reinterpret_cast<BsgGitCell*>(cell.second)->data;
      if (!info->id.empty() && !columns_changed)
        retained[{info->id, info->column}] = cell.second;
      else {
        info->defunct = true;
        atk_object_set_parent(cell.second, nullptr);
        atk_object_notify_state_change(cell.second, ATK_STATE_DEFUNCT, TRUE);
        g_object_unref(cell.second);
      }
    }
    data->cells.clear();
    data->rows.clear();
    data->requested_pages.clear();
  }
  data->frame = frame;
  gtk_widget_set_direction(value,
                           frame.rtl ? GTK_TEXT_DIR_RTL : GTK_TEXT_DIR_LTR);
  data->selected_rows =
      std::unordered_set<int>(frame.selected.begin(), frame.selected.end());
  if (replacement) {
    for (const auto& row : rows) {
      for (size_t column = 0; column < frame.columns.size(); ++column) {
        auto found = retained.find({row.id, static_cast<int>(column)});
        if (found == retained.end()) continue;
        auto* cell = reinterpret_cast<BsgGitCell*>(found->second);
        cell->data->row = row.index;
        cell->data->generation = frame.generation;
        data->cells[{row.index, static_cast<int>(column)}] = found->second;
        retained.erase(found);
      }
    }
    for (auto& cell : retained) {
      atk_object_set_parent(cell.second, nullptr);
      reinterpret_cast<BsgGitCell*>(cell.second)->data->defunct = true;
      atk_object_notify_state_change(cell.second, ATK_STATE_DEFUNCT, TRUE);
      g_object_unref(cell.second);
    }
  }
  if (!UpdateGitTableRows(value, frame.generation, rows)) return false;
  AtkObject* accessible = gtk_widget_get_accessible(value);
  atk_object_set_role(accessible,
                      frame.tree ? ATK_ROLE_TREE_TABLE : ATK_ROLE_TABLE);
  atk_object_set_name(accessible, frame.name.c_str());
  atk_object_set_description(accessible, frame.description.c_str());
  for (auto& cell : data->cells) {
    auto* info = reinterpret_cast<BsgGitCell*>(cell.second)->data;
    const bool now_selected = selected(data, info->row);
    if (info->selected != now_selected)
      atk_object_notify_state_change(cell.second, ATK_STATE_SELECTED,
                                     now_selected);
    const bool now_focused =
        frame.focused && frame.focused_row == info->row && info->column == 0;
    if (info->focused != now_focused)
      atk_object_notify_state_change(cell.second, ATK_STATE_FOCUSED,
                                     now_focused);
    info->selected = now_selected;
    info->focused = now_focused;
  }
  if (replacement || frame.scroll != previous.scroll ||
      frame.width != previous.width || frame.height != previous.height)
    g_signal_emit_by_name(accessible, "model-changed");
  if (frame.selected != previous.selected)
    g_signal_emit_by_name(accessible, "selection-changed");
  if (frame.busy != previous.busy)
    atk_object_notify_state_change(accessible, ATK_STATE_BUSY, frame.busy);
  if (frame.focused && frame.focused_row >= 0 &&
      (!previous.focused || frame.focused_row != previous.focused_row ||
       replacement)) {
    AtkObject* focused = cell_at(widget, frame.focused_row, 0);
    if (focused)
      g_signal_emit_by_name(accessible, "active-descendant-changed", focused);
  }
  return true;
}
}  // namespace busystack_git_ui
