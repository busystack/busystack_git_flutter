#ifndef BUSYSTACK_GIT_FLUTTER_NATIVE_GIT_TABLE_H_
#define BUSYSTACK_GIT_FLUTTER_NATIVE_GIT_TABLE_H_

#include <gtk/gtk.h>

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

namespace busystack_git_ui {

// This is presentation metadata only. Native accessibility never executes Git,
// opens repository files, or interprets a display label as a mutation path.
struct TableAction {
  std::string id;
  std::string label;
};

struct TableRow {
  int index = 0;
  std::string id;
  std::vector<std::string> cells;
  std::string description;
  int parent = -1;
  int depth = 0;
  // -1: leaf, 0: collapsed, 1: expanded.
  int expanded = -1;
  std::vector<TableAction> actions;
  std::vector<double> text_insets = {};
};

struct TableFrame {
  int64_t generation = 0;
  std::string name;
  std::string description;
  bool tree = false;
  bool busy = false;
  bool focused = false;
  int focused_row = -1;
  int row_count = 0;
  std::vector<std::string> columns;
  std::vector<double> widths;
  std::vector<int> selected;
  double row_height = 30;
  double scroll = 0;
  double width = 0;
  double height = 0;
  std::string font_family = "Sans";
  double font_size = 14;
  bool rtl = false;
  bool headers = true;
  std::vector<std::string> action_labels = {"Select", "Context menu",
                                            "Copy text"};
  std::string loading_label = "Loading row";
  std::vector<double> header_insets;
};

struct TableRequest {
  int64_t generation = 0;
  std::string action;
  std::string row_id;
  int row = -1;
  int column = -1;
  int count = 0;
};

using TableCallback = std::function<void(const TableRequest&)>;

GtkWidget* CreateGitTable(TableCallback callback);
// GtkOverlay's add_overlay does not emit GtkContainer::add. Explicitly notify
// accessibility clients after parenting so their cached hierarchy stays valid.
void AttachGitTable(GtkOverlay* host, GtkWidget* table);
// Retire a presentation without invalidating a child during its parent's draw.
// The caller retains responsibility for releasing its own reference.
void RetireGitTable(GtkWidget* table);
// The initial visible rows travel with their frame, so the accessible tree
// never briefly claims an empty table while real rows are being prepared.
bool UpdateGitTable(GtkWidget* widget, const TableFrame& frame,
                    const std::vector<TableRow>& rows);
bool UpdateGitTableRows(GtkWidget* widget, int64_t generation,
                        const std::vector<TableRow>& rows);

}  // namespace busystack_git_ui

#endif
