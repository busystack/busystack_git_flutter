#include "include/busystack_git_flutter/busystack_git_flutter_plugin.h"

#include <cmath>
#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <utility>

#include "native/git_table.h"

namespace {
constexpr char kHostKey[] = "busystack-git-accessibility-host";
constexpr char kChannel[] = "busystack_git_flutter/accessibility";

struct WeakHost {
  GWeakRef overlay;
  explicit WeakHost(GtkOverlay* value) { g_weak_ref_init(&overlay, value); }
  ~WeakHost() { g_weak_ref_clear(&overlay); }
};
struct TableEntry {
  GtkWidget* widget = nullptr;
  GtkAllocation bounds = {0, 0, 1, 1};
  ~TableEntry() {
    if (widget) {
      gtk_widget_destroy(widget);
      g_object_unref(widget);
    }
  }
};
struct PluginState {
  GWeakRef view;
  GWeakRef channel;
  std::map<std::string, std::unique_ptr<TableEntry>> tables;
  PluginState() {
    g_weak_ref_init(&view, nullptr);
    g_weak_ref_init(&channel, nullptr);
  }
  ~PluginState() {
    tables.clear();
    g_weak_ref_clear(&view);
    g_weak_ref_clear(&channel);
  }
};

FlValue* field(FlValue* value, const char* key) {
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_MAP
             ? fl_value_lookup_string(value, key)
             : nullptr;
}
bool integer(FlValue* value, int64_t* result) {
  if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_INT) return false;
  *result = fl_value_get_int(value);
  return true;
}
bool integer(FlValue* value, int* result) {
  int64_t number;
  if (!integer(value, &number) || number < G_MININT || number > G_MAXINT)
    return false;
  *result = static_cast<int>(number);
  return true;
}
bool number(FlValue* value, double* result) {
  if (!value) return false;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT)
    *result = fl_value_get_float(value);
  else if (fl_value_get_type(value) == FL_VALUE_TYPE_INT)
    *result = fl_value_get_int(value);
  else
    return false;
  return std::isfinite(*result);
}
bool boolean(FlValue* value, bool* result) {
  if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) return false;
  *result = fl_value_get_bool(value);
  return true;
}
bool string(FlValue* value, std::string* result, size_t maximum = 65536) {
  if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) return false;
  const char* text = fl_value_get_string(value);
  const size_t length = strlen(text);
  if (length > maximum || !g_utf8_validate(text, length, nullptr)) return false;
  *result = text;
  return true;
}
bool list(FlValue* value, size_t maximum) {
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_LIST &&
         fl_value_get_length(value) <= maximum;
}
bool strings(FlValue* value, std::vector<std::string>* output, size_t maximum) {
  if (!list(value, maximum)) return false;
  for (size_t i = 0; i < fl_value_get_length(value); ++i) {
    std::string item;
    if (!string(fl_value_get_list_value(value, i), &item)) return false;
    output->push_back(std::move(item));
  }
  return true;
}
bool numbers(FlValue* value, std::vector<double>* output, size_t maximum) {
  if (!list(value, maximum)) return false;
  for (size_t i = 0; i < fl_value_get_length(value); ++i) {
    double item;
    if (!number(fl_value_get_list_value(value, i), &item)) return false;
    output->push_back(item);
  }
  return true;
}

bool parse_rows(FlValue* value, std::vector<busystack_git_ui::TableRow>* rows) {
  if (!list(value, 512)) return false;
  for (size_t i = 0; i < fl_value_get_length(value); ++i) {
    auto* item = fl_value_get_list_value(value, i);
    busystack_git_ui::TableRow row;
    if (!integer(field(item, "index"), &row.index) ||
        !string(field(item, "id"), &row.id) ||
        !string(field(item, "description"), &row.description) ||
        !integer(field(item, "parent"), &row.parent) ||
        !integer(field(item, "depth"), &row.depth) ||
        !integer(field(item, "expanded"), &row.expanded) ||
        !strings(field(item, "cells"), &row.cells, 8) ||
        !numbers(field(item, "textInsets"), &row.text_insets, 8))
      return false;
    auto* actions = field(item, "actions");
    if (!list(actions, 16)) return false;
    for (size_t action = 0; action < fl_value_get_length(actions); ++action) {
      auto* source = fl_value_get_list_value(actions, action);
      busystack_git_ui::TableAction target;
      if (!string(field(source, "id"), &target.id, 128) ||
          !string(field(source, "label"), &target.label, 1024))
        return false;
      row.actions.push_back(std::move(target));
    }
    rows->push_back(std::move(row));
  }
  return true;
}
bool parse_frame(FlValue* value, busystack_git_ui::TableFrame* frame,
                 GtkAllocation* bounds) {
  if (!integer(field(value, "generation"), &frame->generation) ||
      !string(field(value, "name"), &frame->name) ||
      !string(field(value, "description"), &frame->description) ||
      !boolean(field(value, "tree"), &frame->tree) ||
      !boolean(field(value, "busy"), &frame->busy) ||
      !boolean(field(value, "focused"), &frame->focused) ||
      !integer(field(value, "focusedRow"), &frame->focused_row) ||
      !integer(field(value, "rowCount"), &frame->row_count) ||
      !strings(field(value, "columns"), &frame->columns, 8) ||
      !number(field(value, "rowHeight"), &frame->row_height) ||
      !number(field(value, "scroll"), &frame->scroll) ||
      !number(field(value, "width"), &frame->width) ||
      !number(field(value, "height"), &frame->height) ||
      !string(field(value, "fontFamily"), &frame->font_family, 1024) ||
      !number(field(value, "fontSize"), &frame->font_size) ||
      !boolean(field(value, "rtl"), &frame->rtl) ||
      !boolean(field(value, "headers"), &frame->headers) ||
      !string(field(value, "loadingLabel"), &frame->loading_label, 1024) ||
      !numbers(field(value, "headerInsets"), &frame->header_insets, 8))
    return false;
  frame->action_labels.clear();
  if (!strings(field(value, "actionLabels"), &frame->action_labels, 3))
    return false;
  auto* widths = field(value, "widths");
  auto* selected = field(value, "selected");
  if (!list(widths, 8) || !list(selected, 1000000)) return false;
  for (size_t i = 0; i < fl_value_get_length(widths); ++i) {
    double width;
    if (!number(fl_value_get_list_value(widths, i), &width)) return false;
    frame->widths.push_back(width);
  }
  for (size_t i = 0; i < fl_value_get_length(selected); ++i) {
    int row;
    if (!integer(fl_value_get_list_value(selected, i), &row)) return false;
    frame->selected.push_back(row);
  }
  double x, y;
  if (!number(field(value, "x"), &x) || !number(field(value, "y"), &y) ||
      std::abs(x) > 65536 || std::abs(y) > 65536 || frame->width <= 0 ||
      frame->width > 65536 || frame->height <= 0 || frame->height > 65536)
    return false;
  *bounds = {static_cast<int>(std::round(x)), static_cast<int>(std::round(y)),
             static_cast<int>(std::ceil(frame->width)),
             static_cast<int>(std::ceil(frame->height))};
  return true;
}

gboolean position_table(GtkOverlay*, GtkWidget*, GdkRectangle* allocation,
                        gpointer data) {
  *allocation = static_cast<TableEntry*>(data)->bounds;
  return TRUE;
}
void invoke(PluginState* state, const std::string& id,
            const busystack_git_ui::TableRequest& request) {
  g_autoptr(GObject) channel = G_OBJECT(g_weak_ref_get(&state->channel));
  if (!channel) return;
  if (request.action == "focus" || request.action == "select") {
    g_autoptr(GObject) view = G_OBJECT(g_weak_ref_get(&state->view));
    if (view) gtk_widget_grab_focus(GTK_WIDGET(view));
  }
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "id", fl_value_new_string(id.c_str()));
  fl_value_set_string_take(args, "generation",
                           fl_value_new_int(request.generation));
  fl_value_set_string_take(args, "action",
                           fl_value_new_string(request.action.c_str()));
  fl_value_set_string_take(args, "rowId",
                           fl_value_new_string(request.row_id.c_str()));
  fl_value_set_string_take(args, "row", fl_value_new_int(request.row));
  fl_value_set_string_take(args, "column", fl_value_new_int(request.column));
  fl_value_set_string_take(args, "count", fl_value_new_int(request.count));
  // Calls are notifications. Dart validates the view generation and row ID
  // before invoking the same typed action as keyboard or pointer interaction.
  fl_method_channel_invoke_method(FL_METHOD_CHANNEL(channel), "request", args,
                                  nullptr, nullptr, nullptr);
}

}  // namespace

struct _BusystackGitFlutterPlugin {
  GObject parent_instance;
  PluginState* state;
};
G_DEFINE_TYPE(BusystackGitFlutterPlugin, busystack_git_flutter_plugin,
              G_TYPE_OBJECT)

namespace {
void clear_tables(BusystackGitFlutterPlugin* self) {
  self->state->tables.clear();
}
void respond_error(FlMethodCall* call, const char* code, const char* message) {
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_error_response_new(code, message, nullptr));
  fl_method_call_respond(call, response, nullptr);
}
void method_call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* self = BUSYSTACK_GIT_FLUTTER_PLUGIN(data);
  auto* state = self->state;
  auto* args = fl_method_call_get_args(call);
  const std::string method = fl_method_call_get_name(call);
  std::string id;
  if (!string(field(args, "id"), &id, 128) || id.empty()) {
    respond_error(call, "invalid", "Invalid accessibility view identity");
    return;
  }
  if (method == "remove")
    state->tables.erase(id);
  else if (method == "rows") {
    int64_t generation;
    std::vector<busystack_git_ui::TableRow> rows;
    auto found = state->tables.find(id);
    if (!integer(field(args, "generation"), &generation) ||
        !parse_rows(field(args, "rows"), &rows) ||
        found == state->tables.end() ||
        !busystack_git_ui::UpdateGitTableRows(found->second->widget, generation,
                                              rows)) {
      respond_error(call, "stale", "Accessibility view changed");
      return;
    }
  } else if (method == "update") {
    g_autoptr(GObject) view = G_OBJECT(g_weak_ref_get(&state->view));
    auto* host = view
                     ? static_cast<WeakHost*>(g_object_get_data(view, kHostKey))
                     : nullptr;
    g_autoptr(GObject) overlay =
        host ? G_OBJECT(g_weak_ref_get(&host->overlay)) : nullptr;
    if (!overlay) {
      respond_error(call, "hostUnavailable",
                    "The application has no Git accessibility host");
      return;
    }
    busystack_git_ui::TableFrame frame;
    GtkAllocation bounds;
    std::vector<busystack_git_ui::TableRow> rows;
    if (!parse_frame(args, &frame, &bounds) ||
        !parse_rows(field(args, "rows"), &rows)) {
      respond_error(call, "invalid",
                    "Invalid accessibility presentation metadata");
      return;
    }
    auto found = state->tables.find(id);
    bool created = found == state->tables.end();
    if (created) {
      if (state->tables.size() >= 16) {
        respond_error(call, "limit", "Too many accessibility surfaces");
        return;
      }
      auto entry = std::make_unique<TableEntry>();
      entry->widget = busystack_git_ui::CreateGitTable(
          [state, id](const auto& request) { invoke(state, id, request); });
      g_object_ref_sink(entry->widget);
      found = state->tables.emplace(id, std::move(entry)).first;
    }
    auto* entry = found->second.get();
    if (!busystack_git_ui::UpdateGitTable(entry->widget, frame, rows)) {
      if (created) state->tables.erase(found);
      respond_error(call, "invalid", "Invalid accessibility table state");
      return;
    }
    entry->bounds = bounds;
    if (created) {
      gtk_widget_set_can_focus(entry->widget, FALSE);
      gtk_overlay_add_overlay(GTK_OVERLAY(overlay), entry->widget);
      gtk_overlay_set_overlay_pass_through(GTK_OVERLAY(overlay), entry->widget,
                                           TRUE);
      // A separate handler per child must ignore other overlay children.
      g_object_set_data(G_OBJECT(entry->widget), "busystack-git-table-entry",
                        entry);
    }
    gtk_widget_queue_resize(GTK_WIDGET(overlay));
    gtk_widget_show(entry->widget);
  } else {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(call, response, nullptr);
    return;
  }
  g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  fl_method_call_respond(call, response, nullptr);
}
gboolean position_overlay(GtkOverlay*, GtkWidget* child,
                          GdkRectangle* allocation, gpointer) {
  auto* entry = static_cast<TableEntry*>(
      g_object_get_data(G_OBJECT(child), "busystack-git-table-entry"));
  return entry ? position_table(nullptr, child, allocation, entry) : FALSE;
}
}  // namespace

static void busystack_git_flutter_plugin_finalize(GObject* object) {
  auto* self = BUSYSTACK_GIT_FLUTTER_PLUGIN(object);
  delete self->state;
  G_OBJECT_CLASS(busystack_git_flutter_plugin_parent_class)->finalize(object);
}
static void busystack_git_flutter_plugin_class_init(
    BusystackGitFlutterPluginClass* klass) {
  G_OBJECT_CLASS(klass)->finalize = busystack_git_flutter_plugin_finalize;
}
static void busystack_git_flutter_plugin_init(BusystackGitFlutterPlugin* self) {
  self->state = new PluginState();
}
void busystack_git_flutter_plugin_set_accessibility_host(FlView* view,
                                                         GtkOverlay* overlay) {
  g_return_if_fail(FL_IS_VIEW(view));
  g_return_if_fail(GTK_IS_OVERLAY(overlay));
  g_object_set_data_full(
      G_OBJECT(view), kHostKey, new WeakHost(overlay),
      [](gpointer data) { delete static_cast<WeakHost*>(data); });
  g_signal_connect(overlay, "get-child-position", G_CALLBACK(position_overlay),
                   nullptr);
}
void busystack_git_flutter_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  g_autoptr(BusystackGitFlutterPlugin) self = BUSYSTACK_GIT_FLUTTER_PLUGIN(
      g_object_new(busystack_git_flutter_plugin_get_type(), nullptr));
  FlView* view = fl_plugin_registrar_get_view(registrar);
  g_weak_ref_set(&self->state->view, view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            kChannel, FL_METHOD_CODEC(codec));
  g_weak_ref_set(&self->state->channel, channel);
  fl_method_channel_set_method_call_handler(channel, method_call,
                                            g_object_ref(self), g_object_unref);
  if (view)
    g_signal_connect_object(view, "destroy", G_CALLBACK(clear_tables), self,
                            G_CONNECT_SWAPPED);
}
