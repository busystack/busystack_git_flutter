# busystack_git_flutter

The shared core requires Linux 5.3 or newer with process pidfds. Both applications
ship its native supervisor and Git runtime; installed helpers use no SDK.

Shared specialized desktop Git views for BusyMark and BusyFiles. Depends only
on Flutter and the sibling `busystack_git` engine. Requires Flutter 3.47.5 or
newer and Dart `>=3.12.1 <4.0.0` within the consuming application's approved
toolchain. It contains no application shell, nested MaterialApp, independent
theme, application navigator or cloud/global state container.

The primary surfaces are `GitCommitView`, `GitLogView`, `GitDiffView` and
`GitWorkspace`. Focused components handle branches/remotes/tags, creation,
fetch/pull/push review, history/snapshots/blame, conflict results, Git rebase plans,
stashes, worktrees, submodules and reflog recovery. `GitWorkflowUi` connects
context actions to those views. `GitSession` owns one immutable worktree identity,
presentation lifecycle, drafts and refresh/cancellation state.
Stash creation virtualizes its eligible path list, explains empty selections,
and excludes hidden paths when the reviewed content options change.
Stash requests bind the reviewed working snapshot. An explicit refresh after a
stale review preserves the name, options and still-eligible path selections.
The full Git workspace keeps its worktree root, current branch or detached HEAD,
and recovered operation visible in Log. Returning to Commit retains its draft.
When the active font and available width cannot support both Commit and a
readable comparison, selecting a file opens a full-width review with Back to
Commit. Resizing preserves the draft, selection and review. Compact diff controls
keep display settings and explicit staging actions in focused menus; search is
opened on demand with Ctrl+F inside the review.

`GitHost` supplies native application dialogs, document/folder opening, directory
selection, native contextual menus, mutation/inspection preflight, draft persistence
and notifications. Native menu cancellation remains distinct from an unavailable
menu service; only the latter falls back to the host dialog presenter.
It also supplies host density, text measurement, icons and translation hooks.
Every shared icon uses a semantic `GitGlyph` key in `GitHost.icons`, so hosts can
use their existing glyph catalog throughout Commit, Log and workflow dialogs.
BusyMark's optional message drafting remains a host action. Native Git prompts
use `presentGitPrompt` with the host's own dialog presenter. BusyFiles transports
those prompts through its authenticated private daemon channel.

`GitHost.present` installs `GitHostScope` around dialog contents. Main Commit,
Log, diff and workspace surfaces install it themselves; hosts embedding other
focused components directly must provide that scope. `GitLabel`/`gitString`
resolve English message templates through `translate`, then substitute named
values. Filenames, refs, messages and repository content bypass translation.
Density and row heights use the active host font and text scale. Drafts and view
preferences use the worktree's stable presentation key, separate from command
authorization and stale-review identities.

Ordinary refresh uses restricted inspection. A trust-required state offers an
explicit host preflight for authorized status; revoking trust restores restricted
inspection. Open mutable diffs retain their reviewed versions and disable
staging when a refreshed snapshot changes. Display preferences never renew a
content precondition or push lease.
Hosts can provide `GitCommitView.reviewContext` to identify their current
document/review even before a rebuild. A completed staging operation preserves
later navigation and selection rather than reopening its earlier review.

Network progress keeps a fixed height derived from the host font, so wrapping
diagnostics do not move the commit editor, caret or primary actions.

Commit selection is the real Git index. Clicking a file reviews it; explicit
file/hunk/line actions stage it. Index editing labels the editable index result;
conflict editing labels the editable working result. Failed operations preserve
user input, and closing a resolution view does not abort Git's operation.
Asynchronous completion dismisses only its owning surface; closing an editor
while Git finishes cannot close its parent review or a newer dialog.
Conflict metadata, contents and staging preconditions refresh as one review;
editing stays unavailable during that read, and saving retains the caret.
Revision panes use real IME-aware text fields, logical line-number gutters based
on actual wrapped text geometry, undo and explicit read-only/editable roles.
Git drafts use bounded application-owned undo through Flutter's public text
actions. An immediate undo retains its redo, committed IME text is one edit,
and cancelling preedit preserves the prior redo. No Flutter implementation or
runtime is patched. Index undo never changes working files before explicit apply.
Index and conflict editors disclose UTF-8 BOM state, line-ending format and a
missing final LF. They review a BOM or newline-format change before applying it,
including changes introduced by native clipboard text conversion. The reviewed
result becomes read-only while it is being applied; a failed write retains it.
Conflict navigation aligns source anchors through the exact merge preview;
a changed index or working file invalidates a conflict load before editing is
offered. A saved working Result is kept separate from staging a resolution.
Management dialogs finish before asking the host to open another worktree or
nested repository. Embedded branch/worktree/submodule views can supply their own
`onOpenFolder` callback when they own a different presentation surface.

Consume this package as a sibling path dependency (`../busystack_git_flutter`
from BusyMark, `../../../busystack_git_flutter` from either BusyFiles app).
Materialize the core sibling too, rather than resolving a second hosted copy.

On Linux the package includes a GTK accessibility plugin for Commit's change
tree and Log's virtualized table. It exposes native ATK table/cell, selection,
text and action interfaces, with bounded metadata pages and generation-bound
callbacks. The native code never executes Git or opens repository files.
Flutter retains visual rendering, keyboard operations and action preconditions.
Each application supplies its existing content `GtkOverlay` using
`busystack_git_flutter_plugin_set_accessibility_host` before plugin registration;
the plugin keeps weak references and never owns or reparents a window. BusyFiles
registers it through its content-only registrar. Other platforms keep Flutter
semantics. A failed native handoff preserves those semantics and offers retry.
Native builds require CMake 3.24, GTK 3.24 and ATK 2.30 or newer, already within
the consuming Linux distributions' approved toolchains.

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
cmake -S linux/native -B build/native -G Ninja
cmake --build build/native
dbus-run-session -- xvfb-run -a ctest --test-dir build/native --output-on-failure
```

Widget tests verify presentation interactions. Native accessibility, input,
scaling, window integration and installed-helper behavior must additionally be
verified through each consuming application's native workflows.
