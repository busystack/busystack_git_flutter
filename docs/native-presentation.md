# Git native presentation and navigation contract

Baseline inspected 2026-10-31: engine 07cf4a1, presentation c64a139,
BusyMark ea47942 (feature/git-package), BusyFiles a1a6721 (Release/v0.0.1).
All four trees were clean. The parent engineering policy applies; there are no
repository-specific AGENTS.md files at this baseline. No engine change is planned.

## Native implementations inspected before migration

| Git control category | BusyMark implementation | BusyFiles implementation |
| --- | --- | --- |
| Actions | BusyMarkGitActionButton, native primitive interaction with Yaru semantic tokens | BusyFilesPushButton standard/suggested |
| Icon actions | BusyMarkHeaderIconButton backed by public YaruIconButton | BusyFilesToolbarButton |
| Text/search/message/editor inputs | BusyMarkGitTextEntry, EditableText plus approved Yaru surface | BusyFilesTextField, extended for existing editor controllers |
| Check choices | BusyMarkCheckbox | BusyFilesCheckbox |
| Selectors | BusyMarkPopupSelector / BusyMarkMenuButton | BusyFilesSelectionButton / BusyFilesNativeMenuButton / BusyFilesModeSelector |
| Rows | BusyMarkSidebarRecordRow / native row surfaces | BusyFilesActionRow / native row surfaces |
| Dialogs | showBusyMarkModalDialog, BusyMarkGitDialogShell/titlebar | BusyFilesDialog/titlebar and existing modal presenter |
| Scrollbars | BusyMark-themed RawScrollbar in the Git adapter | Existing Yaru scrollbar theme in the BusyFiles design boundary |
| Notices/progress | Native surface colors, Yaru control implementations | BusyFilesFeedbackBanner, BusyFilesSpinner/Progress |
| Typography, colors, focus, glyphs | BusyMark design, theme and glyph catalogs | BusyFiles design, surface and glyph catalogs |

These are the required Linux mappings. A design-module location or BusyMark
class name is not approval: BusyMark's complete adapter-to-widget chain is
resolved and must not directly construct prohibited Material controls.
Supported public Yaru components may retain their official upstream
implementation dependencies. The inspected modules do not expose a
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
helper references, including prefixes and typedef aliases. It rejects all
Material widget constructors (including controls not in the explicit
helper/palette list), dialog/menu helpers, Material palette/icons and
feature-created local palettes/themes. Every Git source is checked; there are
no feature-file exceptions. A second resolved pass begins at each concrete
host adapter root and follows first-party declarations across that host package
transitively, so an approved-looking wrapper cannot conceal `TextButton`,
`IconButton`, `Material`, `InkWell`, `Dialog`, or another prohibited control.
BusyMark requires the complete `BusyMarkGitPresentation` and
`BusyMarkGitDialogShell` roots. The gate's own fixtures include forbidden
aliased constructors, helpers, fallback paths, a wrapper-hidden control, and a
legitimate primitive/Yaru implementation. Unresolved code and empty/missing
input sets fail closed.

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

The branch-management control uses BusyMark's neutral native inline action
through `BusyMarkGitActionButton`. It remains an ordinary button opening the complete
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
| Commit details | GitCommitDetails → GitHost.present (compact) → showBusyMarkModalDialog → BusyMarkGitDialogShell/YaruBorderContainer | dialogWide maximum width, natural short-record height; only host-owned scrolling for long records |
| Selectable fields | GitSelectableText → BusyMarkGitPresentation.selectable → SelectableRegion + Text with GitTextContextMenu | exact original message, keyboard/context copy, no permanent Copy Text control |
| Context actions | GitIconButton → BusyMarkGitPresentation.iconAction → BusyMarkHeaderIconButton → public YaruIconButton and external YaruFocusBorder | flat resting state, native hover/press/focus/disabled states and separate row targets |
| Inline text actions | GitButton.inline → BusyMarkGitActionButton → Flutter interaction primitives plus Yaru semantic tokens/focus | native typography/geometry and neutral resting fill, with no first-party Material button construction |
| Commit controls | standard/suggested GitButton → BusyMarkGitActionButton | approved primary/secondary native treatment with no first-party FilledButton/ElevatedButton construction |
| Change rows | GitChangeRow → BusyMarkSidebarTreeRow → BusyMarkSidebarRowSurface | primitive pointer/focus/semantics surface plus Yaru focus border; no first-party Material/InkWell construction |
| Git branch glyph | BusyMarkGlyphs.branch → official YaruIcons.share three-node graph | native Yaru font/package; existing GTK branch-menu artwork remains first-party |
| Historical row actions | GitHistoricalChangeTree → GitMenuButton(moreHorizontal) → host flat icon action/native menu | horizontal contextual glyph, not the generic three-line primary-menu glyph |

Commit Actions owns one Copy Commit Hash action (complete immutable ID) and
View Commit Details. The inspector shows an abbreviated identity without
dedicated Copy/Details icons. Details have labelled message, author, committer,
commit, parent and reference fields. Full localized dates are normal text;
exact timestamps remain in accessible tooltips. Parent identity is never
fabricated at shallow boundaries. The complete message is selectable verbatim.
The former whole-message Copy Text operation remains contextually available
once as Copy Commit Message; it is distinct from copying selected text through
the native text menu. Neither metadata copy operation mutates the repository.

The resolved audit follows constant IconData through imported host catalogs and
aliases and rejects MaterialIcons. The host-chain pass resolves the entire
BusyMark adapter rather than selected wrappers or methods. It rejects expanded/dynamic presentation of
typed commit metadata, with forbidden and legitimate self-test examples. Actual
host tests measure the painted BusyMarkGitDialogShell/Yaru surface rather than
the full-window route wrapper, natural height, long-content reachability,
native copying, all historical actions, glyphs and disjoint target geometry.
Shared/BusyFiles compact presentation retains each host's own dialog/navigation;
large history browsers and three-way editors retain expanded surfaces.

## History selector and property mappings (2026-11-03)

The selector owns candidate browsing and explicit confirmation only. Its toolbar
keeps message/author/path entries visible at every width. A measured wide row
wraps into field and command rows at narrow widths or larger text sizes; the
native overflow retains filter editors and secondary commands.
Refresh and branch navigation form the adjacent command group. The menu retains
Reset Filters, Go to Commit/Reference, HEAD, ordered cherry-pick and two-revision
comparison. Commit-row context menus retain the historical Git operations and
compact View Commit Details. There is no selector button opening the old 500px
`_detailPane()` surface. Confirm/cancel and immutable comparisons are unchanged.

| Shared request | BusyMark native mapping | BusyFiles native mapping |
| --- | --- | --- |
| `isDense` field | Single-line native entry, titlebar-item minimum, natural scaled content height | Existing grouped entry with compact vertical insets and icon constraints |
| Label/hint | Compact: inline placeholder plus persistent semantic label; standard: label above editor and separate hint | Compact: inline placeholder plus persistent semantic label; standard: existing grouped InputDecorator |
| Prefix/suffix | Logical start/end siblings of editor | Existing entry prefix/suffix slots |
| `contentPadding` field | Requested directional insets on the single native surface | Requested directional insets on the single native surface; internal decorator stays unpadded |
| `alignLabelWithHint`, vertical alignment | Standard label is always above multiline content; hint honors requested vertical alignment; supplied editor requests use top alignment | Forwarded to the existing entry/decorator |
| Disabled/read-only | Disabled excludes pointer/focus and dims text; read-only retains selection/focus/copy | Existing entry disabled/read-only behavior |
| Editing properties | Original controller, focus, selection, composing range, undo/scroll controllers, callbacks, line limits, direction, alignment and editing options are forwarded | Same, through existing native entry |
| Dense row | Sidebar row geometry with compact insets and natural scaled content | Existing sidebar `YaruMasterTile` with BusyFiles sidebar geometry |
| Row insets | `GitCheckRow` forwards its insets to `GitActionRow`; native row uses them | Dense sidebar theme/standard native action row use them |
| Row states | Existing sidebar selected/hover/pressed/focus surface and semantic selected/enabled state | Existing native master/action row states and semantic selected/enabled state |
| Trailing action | Separate sibling outside row selection target | Separate sibling outside row selection target |
| Choice expansion | Full allocated width when `isExpanded` is requested | Same through the native push-button content |
| Choice underline | Native action surface owns boundary/focus; the supplied empty underline requests no additional decoration | Same native equivalent |
| Choice-bar artwork | Current supplied segments are text-only; BusyMark uses labelled native radio choices | Current supplied segments are text-only native tabs |
| Progress stroke/label | Forwarded to official Yaru progress controls | Forwarded to official Yaru progress controls |
| Tooltip, scrollbar, activation, notices | Existing host tooltip/scrollbar/focus/native notice controls | Existing host equivalents |
| Localized sizing/RTL | TextPainter uses active text scale and direction; natural content sizing and directional insets/start/end slots | Same; native entry/row layouts inherit direction |
| Menu positioning | Existing global pointer anchor or control bottom at logical start, passed with direction to native service | Existing native presenter with the same anchor contract |

Branch/reference entries use shared mouse and keyboard context menus without
permanent action buttons in either host. Historical file entry controls follow
the host placement policy and request the horizontal glyph explicitly. Other menu defaults are unchanged. Diff semantic foregrounds still
come from each host's Yaru semantic colors. Backgrounds are host-owned translucent
treatments: word changes 20%, staged/unstaged 16%, conflict 24%; ordinary line
backgrounds multiply the word treatment by 0.4 rather than replacing its opacity.
The editor renderer consumes the supplied staged/unstaged/conflict treatment
without making it opaque. Search uses the host accent background, active matches
retain bold/underline, native selection retains its own treatment, and +/- line
markers and labelled staging/conflict contexts retain non-color meaning.

BusyMark feedback follows `BusyMarkToastOverlay`. BusyFiles Git feedback calls
`busyFilesMessage` through `ScaffoldMessenger`, as do its existing non-Git browser
and recovery flows. This is the established in-window BusyFiles feedback control;
the daemon's freedesktop notification coordinator serves background operation
and activation events, with a different message/destination contract. Routing
these short Git messages through that daemon would change their semantics. No
Git-only Snackbar construction or substitute notification path is introduced.

The consumer contract tests execute actual adapters and inspect field/row sizes,
requested icons, editing state, directional padding, disabled/read-only behavior,
line and word rendering, and light/dark background contrast. Additional shared
regressions cover selector routing, initial selection, confirmation/cancellation,
branch glyphs and retained history actions. These assertions do not replace real
native captures or the existing resolved-construction enforcement. Acceptance
must report separately whether the test runner and native display were available.

## Seven-sidebar consistency contract (2026-11-03)

This revision supersedes the earlier BusyMark sibling action-column and inline
branch-button requirements. `GitPresentation.entryActionPlacement` is required:
BusyMark declares `contextMenu`; BusyFiles declares `trailing`. This is a host
native equivalent, not an optional fallback. Shared Commit, historical-file and
historical file entries only construct trailing controls for the latter. Branch
and reference entries use contextual commands in both hosts. All existing
entry action destinations remain in their context menus. View-level commands,
disclosure controls, status markers and metadata remain visible in both hosts.

BusyMark change rows reuse Files' horizontal sidebar insets, depth base/step,
disclosure slot/gap, row surface and scaled status extent. Historical tree roots
start at depth zero. Tree and information-rich record entries share
BusyMarkSidebarRowSurface for hover, pressed, selected, focus and disabled
behavior; neither constructs first-party Material, InkWell, YaruListTile or an
entry menu button. Standard TOC hierarchy uses the Files geometry. Record
content uses natural single/secondary-line height, preserving clipboard previews
and date-grouped history event information.

`GitActionRow.onSecondaryTapUp` reaches the actual host row. BusyMark requests
row focus without invoking primary activation. Reference-row Menu/Shift+F10
uses the same native operation list and a direction-aware row anchor. The shared
release-safe `GitContextMenuKeys` is also exported for existing BusyMark sidebar
rows. Clipboard History retains collection-owned focus and forwards the keyboard
context command to the selected record's native action; navigation and paste
keys retain their original destinations. Menu dismissal restores live focus.
No Flutter popup route is used when the native menu service is unavailable.

Commit's branch identity opens the complete original Branches modal. Git Log's
selected subject is a neutral information row without activation, hover-button
treatment or a semantic tap action. Its separate view-level Actions menu owns
Select another commit… and all applicable commit commands. The menu opens the
authoritative history selector, initialized from the inspector selection. Parent navigation remains
secondary metadata with parent-specific comparisons, including merge parents.
The commit hash is bounded so long references cannot displace the subject.
Opening context menus causes no comparison activation or repository mutation.
Commit menu mutation also revalidates session, snapshot and index identity after
native dismissal; files that appeared after review are never added to a group.

The existing constructor gate is paired with BusyMark's resolved sidebar gate
and actual host tests for geometry, states, keyboard release, native menu packets
and side effects. Native packet probes replace only the transport in tests, and
never render fake GTK menus. These assertions do not substitute for running the
actual application and judging all seven populated sidebars. Restricted-session
build/source results must remain separate from native and release acceptance.

## Compact native Git navigation (2026-11-04)

`GitButton.compact` requests desktop toolbar/dialog insets without changing the
Commit footer's default geometry. Standard New branch… and Date actions use
native neutral push surfaces; Select this commit uses the suggested role;
metadata parent navigation uses neutral inline treatment. Both hosts implement
and measure the request. BusyMark uses the installed Yaru 10.2.0 public theme
borders, titlebar-item minimum (34 logical pixels) and button radius. Dense
fields have one themed border, one line of text and no permanent label row.

BusyMark text entry keeps EditableText's controller, focus, composition, undo,
selection and editing callbacks. The public TextSelectionGestureDetectorBuilder
and desktop selection controls provide pointer selection and native editing.
The decorative placeholder excludes semantics; the editor exposes one persistent
accessible name. Informational sidebar surfaces register no no-op tap callback.

Branches uses explicit host spacing between flexible search and natural-size
commands, wrapping the commands below search when measured labels need it.
Repository basename and full-path tooltip preserve identity under the concise
Branches title. Row metadata truncates on one line with complete tooltips.
Content determines height up to 68% of the host's available screen; long lists
scroll in that bound. A keyed controller preserves selection/composition across
responsive rearrangement. Down moves from search into the reference focus scope;
Up/Down traverse results and Menu/Shift+F10 opens the same native commands as
secondary click. Selection itself never switches or merges a branch.

The inspector header is outside the entry-action placement policy: its
information row has no trailing action; the adjacent menu is a view command.
There is no duplicate commit selector or metadata Actions button. Commit hash,
parents and explicit merge-parent comparisons remain in metadata/Changed Files.
The full graph, filters, immutable comparison identity, cancellation/generation
checks and reviewed mutation operations retain their existing implementations.

BusyMark's measured visual contract runs against production Branches and Log
views in both themes, four locales, two widths and enlarged text. The same test
fails all 19 cases on the original checkouts, including missing gaps, oversized
controls, painted button surfaces, activating subjects and hidden filters.
Source audit adversarial fixtures separately reject prohibited Material fallbacks
and alias/wrapper escapes. Real GTK screenshots and sealed build receipts come
from `busymark/tools/git_native_smoke.py`; human inspection remains required.

History's three primary filters also retain keyed editor subtrees while moving
between the wide row and wrapped field group. This preserves the actual editor,
focus node, selection, undo state and IME connection; retaining only controller
text is insufficient. Shared and BusyMark regressions resize with a live
composing range and assert the same editor/focus and complete editing value.

## Git Log navigation correction (2026-11-05)

`GitLogHeader`, `GitHistoryLayout`, and `GitReferenceRow` are explicit required
host requests. They do not change `GitExpander` in Rebase or other workflows.
BusyMark supplies its existing native dialog titlebar, independent modal sidebar
toggle, Files sidebar surface/tree rows, and dialog footer insets. The main
filters belong inside the history pane. The modal retains reference search,
selection, expansion and width when hidden. Narrow layouts open the same pane
temporarily over the table; resizing does not retire a focused filter editor.
BusyFiles retains its full-width filter area, splitter, compact reference dialog
and native expandable reference groups through its own adapter.

The selected subject is neutral information with complete tooltip/semantics.
Select another commit is a dedicated icon immediately before Commit Actions,
with the host's normal spacing. It is absent from the menu. Commit Actions still
owns full details, exact hash/message copying and all commit workflows.
Historical status markers occupy the Files icon slot at every text scale;
they never add a second hierarchy offset. Selection/comparison ownership is
unchanged. The confirmation footer is outside the table scroll area and uses
the native lg inset on every side, including logical end in RTL.

Pinned Yaru 10.2.0's public `YaruDateTimeEntry` constructor has no decoration or
label override; its build always supplies `MaterialLocalizations.dateInputLabel`.
Its controller is a nullable DateTime ValueNotifier. BusyMark therefore uses
its existing native `BusyMarkGitTextEntry` composition with a single external
label, compact localized hint, native editing menu, clear action and explicit
field/action spacing. `MaterialLocalizations.formatCompactDate` preserves the
locale's displayed date. Strict parsing and the placeholder use the pinned
Intl locale date pattern. Parsing ignores invisible direction-format marks
and accepts both the locale's native digits and ordinary keyboard digits;
field order, separators and calendar-date validation remain strict. This avoids
requiring Arabic users to type invisible CLDR marks or follow a stock hint with
a different field order. The controller value and IME composition are untouched.
An invisible reserved clear-control slot keeps empty and populated fields the
same height. These corrections were established by inspecting the native images
and are covered by actual-host input/geometry tests. Blank
input remains absent; both valid dates are required to save. The accepted date
bounds and inclusive UI end/exclusive history-query upper bound are unchanged.
No Yaru, Flutter, engine, SDK or dependency source/version is changed.

The actual-host regressions measure native surfaces, header centering, search
and row insets, tree/status geometry, separated main filters, retained state,
footer bounds, RTL/narrow/scaled layouts and date editing/validation/save/cancel.
Four strengthened geometry checks were run first against the original source;
all four failed. Native shipping-binary captures and source receipts are recorded
under BusyMark's `build/git-verification/2026-11-05-navigation`. Widget and native
desktop acceptance remain separate; screenshots must be inspected.

Interaction references consulted: [GNOME header bars](https://developer.gnome.org/hig/patterns/containers/header-bars.html),
[sidebars](https://developer.gnome.org/hig/patterns/nav/sidebars.html),
[lists](https://developer.gnome.org/hig/patterns/containers/list-column-views.html),
[text fields](https://developer.gnome.org/hig/patterns/controls/text-fields.html),
[menus](https://developer.gnome.org/hig/patterns/controls/menus.html),
[dialogs](https://developer.gnome.org/hig/patterns/feedback/dialogs.html),
[keyboard](https://developer.gnome.org/hig/guidelines/keyboard.html),
[accessibility](https://developer.gnome.org/hig/guidelines/accessibility.html),
and official pinned Flutter source/API documentation for constraints, Focus,
EditableText/controllers, ModalRoute dismissal, Semantics and Directionality.


## Semantic Actions and comparison geometry

View-level menus request `GitMenuRole.viewActions`; dynamic repository and
selected-commit menus request `GitIconButton.actions`. Callers cannot override
their icon. `GitGlyph.actions` is mapped once by each real host: BusyMark uses
its approved three-bar `menuVertical` artwork, while BusyFiles retains `more`.
Entry menus request `entryContext`; display and checked choice menus retain
separate roles. The source inventory test enumerates every production menu,
including remote, worktree, snapshot, and historical-file contexts. The resolved
symbol audit rejects direct overflow artwork in feature controls.

`GitButton.toolbar` and `GitButton.diffInline` distinguish compact toolbar and
inline region actions from ordinary/suggested push actions. Required native
`toolbarMetrics` drive shared width measurement and overflow allocation, rather
than guessed icon widths. The host owns repository-action captions and compact
Log content insets. BusyMark's modal composition places headers inside each pane;
its narrow overlay retains the confirmation footer outside the overlay.

`test/support/actions_presentation_contract.dart` runs in both applications'
actual theme/control adapters. It checks artwork, native hit geometry, semantic
names, RTL menu anchoring, complete menu transport, keyboard activation and
reentrant opening. `tool/check_consumer_consistency.py` checks equal approved
pins, byte-identical archives, required consumer tests/audits and duplicate
shared workflow declarations. Run it after refreshing both source archives.

The final semantic change passed all 418 shared UI tests with the controlled
Git executable and supervisor configured. Native application and release
acceptance remain separate from this package result.
