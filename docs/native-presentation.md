# Git native presentation and navigation contract

Baseline inspected 2026-10-31: engine 07cf4a1, presentation c64a139,
BusyMark ea47942 (feature/git-package), BusyFiles a1a6721 (Release/v0.0.1).
All four trees were clean. The parent engineering policy applies; there are no
repository-specific AGENTS.md files at this baseline. No engine change is planned.

## Native implementations inspected before migration

| Git control category | BusyMark implementation | BusyFiles implementation |
| --- | --- | --- |
| Actions | BusyMarkPushButton standard/suggested | BusyFilesPushButton standard/suggested |
| Icon actions | BusyMarkHeaderIconButton (flat native header shape) | BusyFilesToolbarButton |
| Text/search/message/editor inputs | BusyMarkGroupedTextEntry, extended for existing editor controllers | BusyFilesTextField, extended for existing editor controllers |
| Check choices | BusyMarkCheckbox | BusyFilesCheckbox |
| Selectors | BusyMarkPopupSelector / BusyMarkMenuButton | BusyFilesSelectionButton / BusyFilesNativeMenuButton / BusyFilesModeSelector |
| Rows | BusyMarkSidebarRecordRow / native row surfaces | BusyFilesActionRow / native row surfaces |
| Dialogs | showBusyMarkModalDialog, BusyMarkDialogShell/titlebar | BusyFilesDialog/titlebar and existing modal presenter |
| Scrollbars | Existing Yaru scrollbar theme in the BusyMark design boundary | Existing Yaru scrollbar theme in the BusyFiles design boundary |
| Notices/progress | Native surface colors, Yaru control implementations | BusyFilesFeedbackBanner, BusyFilesSpinner/Progress |
| Typography, colors, focus, glyphs | BusyMark design, theme and glyph catalogs | BusyFiles design, surface and glyph catalogs |

These are existing Linux implementations, including the approved foundations
inside their design modules. A feature-level stock Material control is not
approved by inheritance or by renaming it. The inspected modules do not expose a
Fluent adapter; Windows acceptance requires a verified supported host adapter.

## Action destinations to preserve

| Capability | Destination after integration |
| --- | --- |
| Working changes, staging, amend, message/templates/recent messages, commit/push | BusyMark Commit sidebar; existing BusyFiles workspace |
| Selected commit, parent, metadata, changed files | Independent BusyMark Git Log sidebar, metadata before files |
| History graph, refs, filters, pagination, Go to, HEAD | Existing Log browser in host modal for BusyMark selection |
| Branch/tag/commit context operations and ordered cherry-pick/revert | History context menus and existing workflow dialogs |
| Ordinary staged/unstaged/historical file activation | Ordinary BusyMark content comparison tabs; existing BusyFiles comparison placement |
| File/hunk/line staging, search, navigation, wrapping and correspondence | Existing shared comparison renderer and transaction paths |
| Index editing and three-way conflict resolution | Existing guarded shared editors and native workflow surfaces |
| File history, blame, snapshots, revision comparison | Existing history actions/workflow surfaces |
| Branches, clone/init, remotes/tags, network reviews | Existing workflow menu and dialogs |
| Merge/rebase/cherry-pick, continuing operations, cancellation | Existing workflow menu, operation banner and dialogs |
| Stash/worktrees/submodules/reset/revert/restore/recovery | Existing workflow/context menus and dialogs |
| Trust, credentials, signing, hooks, failures | Required host controls, native dialogs and notices |

Selection and opening comparisons do not mutate repositories, save buffers or
change drafts. Historical selection and comparison endpoints are immutable.
Current-content actions retain the engine's reviewed snapshot preconditions.
Evidence is recorded under the existing build/git-verification directories.
This checklist describes required destinations, not completed acceptance.

## Required provisioning and permanent checks

`GitHost.presentation`, its complete semantic glyph map and `presentMenu` are
required. `GitPresentation` has no default. Missing scopes and glyphs fail
clearly; a failed native menu service reports an operational error and never
opens Flutter menu chrome. Native text selection menus use the host service
while preserving the original controller, selection, composition and undo.
BusyMark Git header/context menus use the native-required constructor of its
existing header menu control. Generic menus with a Flutter fallback are rejected
in Git source by resolved constructor/helper identity.

The resolved analyzer gate visits constructor calls and tear-offs, types and
helper references, including prefixes and typedef aliases. It rejects all Material widget constructors (including controls not in the explicit
helper/palette list), dialog/menu helpers, Material palette/icons and feature-created local
palettes/themes. Every Git source is checked; there are no feature-file
exceptions. The gate's own fixtures include forbidden aliased constructors,
helpers, fallback paths and a legitimate native-required host menu. Unresolved
code and empty/missing input sets fail closed.

Both consumers run this gate over the shared sources they materialize and their
Git integration sources. The source archives include the gate, its tests and the
native contract fixture. Real host tests exercise all 26 workflow surfaces and
both prompt kinds through each application's actual adapter in light/dark
modes; fixture requests cannot authorize mutation. Existing tests retain the
transaction, editor, graph, history and dismissal assertions. Runtime captures
and native interaction acceptance remain separate from static compliance.

Font-family assignments in Git sources must reference the existing host catalog
(`BusyMarkTypography.monoFontFamily` / `monoFontFamilyFallback` in the approved
design module); shared views use `GitPresentation.codeStyle`. The analyzer
resolves those exact symbols. A newly named feature constant is not an exception.

## BusyMark Commit correction (2026-11-01)

The non-Git Writerside usage header in `workspace_screen.dart` uses
`BusyMarkHeaderIconButton`; its semantic style explicitly uses the native
rounded rectangle, including hover/pressed/disabled states. Git icon actions
must use that flat treatment, including stage/unstage and Branches menus.
`BusyMarkCompactIconButton` and its pill focus outline are not approved for Git.
The non-Git Files tree uses `BusyMarkSidebarTreeRow`: Git change rows reuse that
row, disclosure, indentation and native surface through the required host
presentation contract. Branch records use the same row surface and spacing.
Do not expand an allowlist or accept a golden to excuse circular Git actions.

BusyMark's Commit layout is the compact sidebar allocation: branch/path tooltip,
Refresh and Repository actions, then compact local tracking, then the tree.
Commit and Commit and Push… share a measured, spaced row. BusyFiles retains its
workspace layout, history shortcut, trust presentation and descendant browsing.
BusyMark alone requires the canonical opened workspace to equal the discovered
working-tree root, at attachment and authoring-command boundaries. Untrusted
Commit shows only the native trust screen; drafts remain owned by the session.
All action destinations in the checklist above are retained by this correction.

The 2026-11-01 tracking correction requires one read-only engine contract bit:
`GitSnapshot.trackingCountsKnown` distinguishes an omitted porcelain `branch.ab`
(unavailable upstream object) from a measured `+0 -0`. Both previously became
zero in the typed snapshot. Parser, background status and JSON handoff preserve
this bit; old packets remain honestly unknown. Discovery, mutation/preconditions,
Git invocations and transaction semantics are unchanged. BusyMark renders
unknown counts as question marks with localized accessible descriptions.

## Commit refinement (2026-11-01, graphical review)

The branch-management control uses the existing neutral, borderless TextButton
style of BusyMark's non-Git native popup selector, through
`BusyMarkPushButton.flat`. It remains an ordinary button opening the complete
Branches modal, without copying the selector's interaction. Inline requests
must not map to filled standard buttons. Resting fills, interaction states,
localized truncation and actual modal/menu destinations are tested.

BusyMark's Commit repository menu contains Refresh and excludes its duplicate
Branches entry. F5 and the dedicated branch keyboard commands remain. Other
hosts retain the default repository menu and workspace toolbar. Workspace
identity owns the full-path tooltip. The earlier branch-path-tooltip and
standalone-Refresh mapping above is superseded by this refinement.

Git change rows use the Files-tree metrics with an explicit sibling action
column, separated by the existing xs gap. The native row activation/selection
surface ends before the stage/unstage hit region. Disabled actions, disclosure,
selection and file activation retain their independent handlers.

BusyMarkCheckbox's labelled form uses official YaruCheckButton/YaruCheckbox,
with its native geometry, state painting, label activation, focus and merged
semantics. Existing unlabelled non-Git checkboxes remain unchanged. Amend uses
this labelled form; its draft/transaction logic is untouched. BusyFiles maps
optional labelled requests to its established BusyFilesCheckOption; its current
workspace amend layout is retained.

The exclusive trust sidebar is concise. The native confirmation identifies the
repository and distinguishes limited passive metadata from authorization of
potentially executable hooks, filters, credential helpers and signing tools.
Neither UI copy nor choosing trust authorizes a queued operation.

Interaction references consulted for this correction:
[GNOME buttons](https://developer.gnome.org/hig/patterns/controls/buttons.html),
[menus](https://developer.gnome.org/hig/patterns/controls/menus.html),
[dialogs](https://developer.gnome.org/hig/patterns/feedback/dialogs.html),
[checkboxes](https://developer.gnome.org/hig/patterns/controls/checkboxes.html),
and [Git rev-parse](https://git-scm.com/docs/git-rev-parse).
The pinned local Yaru checkbox/check-button APIs were inspected without changes.
BusyMark's host components and the explicit product requirements remain the
presentation authority; no upstream dependency or runtime pin changes apply.

## Commit metadata remediation (2026-11-02)

The rendering chain is part of the contract, not a wrapper allowlist:

| Git request | BusyMark rendering path | Observable rule |
| --- | --- | --- |
| Commit details | GitCommitDetails → GitHost.present (compact) → showBusyMarkModalDialog → BusyMarkDialogShell → Yaru-themed Dialog | dialogWide maximum width, natural short-record height; only host-owned scrolling for long records |
| Selectable fields | GitSelectableText → BusyMarkGitPresentation.selectable → SelectableText with GitTextContextMenu | exact original message, keyboard/context copy, no permanent Copy Text control |
| Context actions | GitIconButton → BusyMarkGitPresentation.iconAction → BusyMarkHeaderIconButton → IconButton with official Yaru defaults and semantic rectangular focus | flat resting state, native hover/press/focus/disabled states and separate row targets |
| Inline text actions | GitButton.inline → BusyMarkPushButton.flat → Yaru-themed TextButton | native typography/geometry and neutral resting fill; a TextButton class name alone is insufficient |
| Commit controls | standard/suggested GitButton → existing BusyMarkPushButton → themed FilledButton/ElevatedButton | approved primary/secondary native treatment, not feature-local Material appearance |
| Git branch glyph | BusyMarkGlyphs.branch → official YaruIcons.share three-node graph | native Yaru font/package; existing GTK branch-menu artwork remains first-party |
| Historical row actions | GitHistoricalChangeTree → GitMenuButton(moreHorizontal) → host flat icon action/native menu | horizontal contextual glyph, not the generic three-line primary-menu glyph |

Commit Actions owns one Copy Commit Hash action (complete immutable ID) and
View Commit Details. The inspector shows an abbreviated identity without
dedicated Copy/Details icons. Details have labelled message, author, committer,
commit, parent and reference fields. Full localized dates are normal text;
exact timestamps remain in accessible tooltips. Parent identity is never
fabricated at shallow boundaries. The complete message is selectable verbatim.

The resolved audit follows constant IconData through imported host catalogs and
aliases and rejects MaterialIcons. It rejects expanded/dynamic presentation of
typed commit metadata, with forbidden and legitimate self-test examples. Actual
host tests measure the painted dialog Material surface (the Dialog widget's
route wrapper spans the window), natural height, long-content reachability,
native copying, all historical actions, glyphs and disjoint target geometry.
Shared/BusyFiles compact presentation retains each host's own dialog/navigation;
large history browsers and three-way editors retain expanded surfaces.
