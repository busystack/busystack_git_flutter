# busystack_git_flutter

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

Commit selection is the real Git index. Clicking a file reviews it; explicit
file/hunk/line actions stage it. Index editing labels the editable index result;
conflict editing labels the editable working result. Failed operations preserve
user input, and closing a resolution view does not abort Git's operation.
Revision panes use real IME-aware text fields, logical line-number gutters based
on actual wrapped text geometry, undo and explicit read-only/editable roles.
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

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
```

Widget tests verify presentation interactions. Native accessibility, input,
scaling, window integration and installed-helper behavior must additionally be
verified through each consuming application's native workflows.
