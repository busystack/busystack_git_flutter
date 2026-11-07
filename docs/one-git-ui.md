# One Git UI: ownership, action inventory and acceptance

2026-11-06. Product decision: both Linux hosts consume one shared Git sidebar,
review and workflow implementation. This supersedes earlier statements allowing
BusyFiles a different workspace or trailing row controls. No Git engine or
third-party modification is authorized. Baseline revisions below are observed,
not reset targets. All four working trees were clean.

## Baseline

```json
[
  {
    "repository": "busystack_git",
    "head": "7d8e55d8034aeb85cddac1c0f498b0f3cc33105b",
    "branch": "main",
    "status": ""
  },
  {
    "repository": "busystack_git_flutter",
    "head": "b58637269fea78008911e598bd0cb19422c46592",
    "branch": "main",
    "status": ""
  },
  {
    "repository": "busymark",
    "head": "b348968c9d71d01dd2b98a9e4fe66790fe9957c9",
    "branch": "feature/git-package",
    "status": ""
  },
  {
    "repository": "busyfiles",
    "head": "e97bf8c4495cfcd281c0e54ab8d2c10dc717216e",
    "branch": "Release/v0.0.1",
    "status": ""
  }
]
```

Both supplied consumers pin engine 7d8e55d8034aeb85cddac1c0f498b0f3cc33105b
and UI b58637269fea78008911e598bd0cb19422c46592. Official installed Flutter
3.47.5 / Dart 3.13.4; both lockfiles resolve Yaru 10.2.0 and Intl 0.20.3.
Ubuntu 26.04.1, DISPLAY :0 and Wayland socket available. Initial disk 39 GiB
and available memory 6.5 GiB; builds and desktop runs must be sequential.

## Before-removal action and destination inventory

The old shared workspace adds Return to Files, Commit/Log choice, compact Back
to Commit, branch management, working comparison file navigation and full Log.
Only the first is a host action. The other routes must resolve through the
canonical sidebar/review model. Removing split/preview routes must not remove
any workflow below. This is a source inventory, not a runtime acceptance claim.

| User-accessible capability in either baseline host | Canonical destination |
| --- | --- |
| Discover repository, descendant discovery in BusyFiles; init/clone without repository | Host attachment/entry, existing GitCreationView |
| Limited passive inspection; trust/revoke, credential prompts | Shared trust notice; host authorization and existing prompt/revoke services |
| Current branch, upstream and known/unknown ahead/behind | Commit context header; branch opens complete GitBranchesView |
| Refresh/F5, Git commands/shortcuts | Commit Actions and host shortcut bridge |
| Staged/Unstaged/Untracked/Conflicts, folders, folding, selection | Shared Commit sidebar tree |
| File, selected, directory and group stage/unstage; discard/restore/delete, ignore; conflict resolution | Existing contextual Commit actions and guarded transactions |
| Working file diff, original/open document, history/blame, source snapshots | Shared review tabs and existing file context/history workflows |
| Whole-file/hunk/line stage/unstage and index editing | Existing GitDiffView and guarded index editor |
| Normal/amend messages, message-only amend, templates/recent messages, AI draft (BusyMark service) | Shared Commit editor/message menu, host persistent draft/AI service |
| Commit, Commit and Push; signoff/signing/identity/hooks and errors | Shared Commit footer/options and commit-then-push review |
| Commit/Log view selection | Shared sidebar navigation; BusyMark existing selector slot |
| Selected commit subject, details/full hash/copy, author/committer/date/message/refs/all parents | Shared Git Log inspector, Commit Actions/details/parent menu |
| Select another commit, graph, paging, Go to, Back to HEAD | Shared full Git Log modal with explicit confirmation/cancel |
| Message/author/path/date/reference filters; search and reference tree groups | Shared Git Log modal and native date fields |
| Historical file/rename/parent-specific diff; history/blame/snapshot | Immutable shared review identity; historical context menu without staging |
| Multi-commit/selected-commit branch/tag/compare/snapshot/cherry-pick/revert/rebase/reset | Existing GitHistoryActions, selected Commit Actions and history context menus |
| Local/Remote/Tags, search, create/checkout/rename/delete/tracking/worktree branch actions | Shared Branches tree and reference context menus |
| General merge/rebase, root/onto/options, branch-specific directions | Shared Branches Actions and reference context workflows |
| Fetch/Pull/Push, preview/force lease/remotes/authentication/errors | Commit Actions and existing network views |
| Conflict editor, current operation, Continue/Abort/Skip, progress/cancel | Existing operation banner and workflow surfaces |
| Stashes, worktrees, submodules, open destination | Commit Actions organization workflows, host openFolder service |
| Reflog/recovery/reset/revert/restore | Existing recovery/history/file workflows |
| Diff mode/display/wrap/context/search/refresh/previous-next file/change | Shared GitDiffView compact toolbar/context actions |
| Independent comparison selection/close/close others/close all, retained scroll/search | Shared review model; host content/tab lifecycle and dismissal guards |
| Return to Files with browser tab/location/selection/scroll/search/sidebar | BusyFiles shell keeps browser subtree mounted and owns exit |
| Document/Local History tabs, dirty buffers, window/repository close guards | BusyMark shell; shared editor/draft guards remain authoritative |
| External Git invalidation, delayed responses, reconnect/Retry | Existing session generations, engine snapshots and authenticated BusyFiles daemon |
| Localization, RTL, IME, keyboard/context menus, accessibility | Existing host localizations/system services; shared controls |

Source inventory: shared workspace.dart, commit_view.dart, log_view.dart,
branch_views.dart, workflow_ui.dart, history_actions.dart, reference_context_menu.dart,
diff_view.dart, organization_views.dart, network_views.dart and both host Git
integration files and command registries. Snapshot/transaction guards are retained.

## Ownership and slots

| Responsibility | Shared owner | BusyMark mount/service | BusyFiles mount/service |
| --- | --- | --- | --- |
| Session/view state and immutable review identity/navigation | busystack_git_flutter | Workspace attachment and document-tab integration | Browser Git attachment and comparison-tab integration |
| Commit/Git Log sidebar composition and workflow navigation | busystack_git_flutter | Established sidebar selector/slot | Main sidebar slot while Git mode active |
| Comparison widget/toolbar | GitDiffView and shared review surface | Ordinary content tabs beside documents/Local History | Independent Git content tabs |
| Branches/history/date/workflows and Linux native contract | busystack_git_flutter | Native menu/dialog lifecycle, locale | Native menu/dialog lifecycle, locale |
| Git workflow feedback/notifications | showGitNotification + NativeGitNotificationSurface | Window/workspace lifetime guard and localization | Window/workspace lifetime guard and localization |
| Git execution/security | busystack_git | Direct adapter with root-only authoring policy | Authenticated typed IPC, controlled daemon supervisor |

## Retired production surfaces and regression ownership

BusyFiles' old shared GitWorkspace segmented Commit/Log control, split staging
workspace and single compact preview have been replaced, not retained behind a
mode. GitWorkspace now mounts GitFeatureSidebar and GitReviewContent, whose
retained tabs use GitReviewSurface. BusyMark's app-owned GitSidebarTab, GitChangesView, GitFileHistoryView,
GitProjectHistoryView and identity dialog formed an unreachable older cluster:
application source mounted the shared integration already at the observed
baseline. Those competing production widgets are removed. The Files status-color
helper and GitDiffViewer used by non-Git document/disk recovery remain host-owned.

Tests of those unreachable widgets are migrated to the shipped shared surfaces.
They are not retained as a legacy test-only UI. Obsolete checkbox-selection,
counted-commit-caption, no-tracking-strip and global-identity-form expectations
never define the new product contract. In particular the pinned shared engine
already configures repository identity; this change does not add a global config
write or revive the disconnected direct gateway. The new identity host test
exercises real shared fields, native Enter/focus, exact identity values and index
scope, and ensures it does not create a commit.

| Retired assertions/capability | Maintained observable coverage |
| --- | --- |
| Working groups, same staged/unstaged path, root/nested/rename/scope and context stage operations | Shared commit_files_state, commit_nested_tree, index_regions, staging_navigation and real-index tests |
| Multiline messages, delayed success/failure, normal/amend/repository drafts | Shared commit_amend_draft, draft_ordering, draft_cross_store; both actual-host dismissal suites |
| File/history actions, historical parent/path and reset/recovery destinations | Shared file_history_selection, log_changed_files_state, action_destinations, git_actions_inventory; BusyMark actual log comparison tests |
| Native form/control layout, trust, unavailable states, menu/keyboard access | Both native presentation/action contracts, BusyFiles location/browser/draft suites; BusyMark root/trust and localization suites |
| Identity form and Git notifications | BusyMark migrated git_author_identity_dialog_test/status_semantics_test; native_notification lifecycle, queue, focus and geometry cases; both actual-host callback contracts and resolved callback audit |
| Non-Git document/disk source comparisons, gutter, font, absent content and dirty banner | Retained BusyMark git_widget_test document comparison cases |

## Intermediate native observations

Actual debug processes have shown the canonical sidebar in BusyFiles' main slot,
independent staged/working comparison tabs and Log navigation without retargeting,
and Return to Files restoring its browser subtree. Its real daemon used the
bundle's controlled Git and supervisor through authenticated typed IPC; no UI Git
execution was introduced. Source-bound X11 receipts show the mapped engine hash
matches the official SDK. The disposable fixture was unchanged on normal exit.
These observations exposed inherited host typography/button differences, which
are corrected in the shared Yaru metrics resolver and still require new captures.
Earlier images are intermediate evidence, not final acceptance. Empty-tooltip
black-rectangle reproduction and final installed-app matrix remain unaccepted.
A separate tooltip obstruction is reproduced by the actual-host contract test:
the visible overlay covers another native button and consumed its activation.
The shared tooltip now ignores pointer events; both hosts pass the same covered-row
activation test. Its semantic description and placement remain unchanged. BusyMark's
non-Git tooltip received the same narrow pointer/lifetime correction. This evidence
does not establish the cause of the earlier black rectangle.

## Additional comparison-route inventory and consolidation

The workflow audit found ordinary reviews outside the original sidebar:
`GitRevisionComparison`, file-history parent/current comparisons, affected-file
selectors, and standalone `GitLogView`. Their file activation now calls
`gitOpenComparison`; only `GitReviewSurface` constructs an ordinary diff. A
captured read-only selector chain closes its exact routes when dispatching a tab.
An unrelated newer dialog blocks stale activation, and an operation plan below
such a selector remains open. No main document or transaction is implicitly closed.

`GitCommitFiles` embeds `GitReviewSurface` for transaction plans (push, stash,
cherry-pick and rebase); read-only affected-file selection opens normal tabs.
Both contexts use the shared historical tree and captured parent/rename identity.
`gitSelectHistoryCommit` is the one full history-modal factory, used by the Log
inspector and workflow reference selection. Cancel preserves its candidate but
never changes the inspector or repository. The existing specialized conflict-stage
inspection is the only dialog diff construction outside the canonical surface.
The architecture gate tests this precise exception and rejects new ordinary
preview constructors, including aliased and named constructor calls.

## Intermediate verification snapshots

The canonical sidebar/review model and common Yaru renderer are implemented.
The isolated palette-revision verifier passed 429 shared Flutter tests, 142
unchanged-engine tests, 718 daemon tests and 711 BusyFiles UI tests, with explicit
external-service skips retained in its log. Its authenticated packaged adapter
check passed. Native browser keyboard acceptance then stopped on a first-party
rename field exposing `Name\nName` through AT-SPI. Exact-name regressions reproduce
the same label duplication in non-compact shared Git fields in both hosts; the
visible labels now exclude duplicate semantics while the controls retain their
persistent names, native input and focus. Native rerun remains required.

Actual same-fixture light-theme captures at that intermediate revision have
zero differing pixels in the 300 x 348 untrusted sidebar, 300 x 630 Log inspector
and 227 x 117 working-file native menu crops. They exposed inherited checkbox
text height, an unnecessary narrow-history header row and an extra content-slot
separator pixel. Those follow-ups have measured regressions and shared fixes;
new final binaries/captures are required. Light/dark Branches, history, date and
historical/staged/working comparison surfaces have been inspected. The earlier
empty-tooltip black rectangle remains unreproduced; the separate pointer
obstruction has its own proven regression and is not its claimed cause.

The engine also passed explicit configured-hook and authenticated localhost SSH
fixtures. Both complete native rendering chains and their strengthened inherited,
cross-package adversarial audits passed. The 25 non-golden failures from the
BusyMark diagnostic run passed fresh targeted groups after native-menu/finder
migrations and two reproduced first-party baseline corrections; the six revised
Git goldens were visually reviewed and passed normal comparison. A final frozen
BusyMark full run remains pending. None of its earlier diagnostic runs is a
passing full-suite result.

The BusyFiles daemon shutdown regression additionally reproduces a late reply
and a watch left alive after close. Its first-party lifecycle now cancels and
drains active Git requests before private cleanup and suppresses retired replies;
all ten Git IPC tests pass, including reconciled cancelled-operation outcomes.
Final source/pin checks, both frozen application suites/builds, native installed
parity, the supported Ubuntu 26.04 DEB producer and delivery identities remain
pending. Earlier debug captures and package checks are intermediate evidence.

## Official references consulted

- IntelliJ IDEA current Help pages identify themselves as **2026.3**: [Commit and push](https://www.jetbrains.com/help/idea/commit-and-push-changes.html), [Git Log](https://www.jetbrains.com/help/idea/log-tab.html), [Compare versions](https://www.jetbrains.com/help/idea/comparing-file-versions.html), [Conflicts](https://www.jetbrains.com/help/idea/resolve-conflicts.html).
- GNOME HIG [Sidebars](https://developer.gnome.org/hig/patterns/nav/sidebars.html), [Header Bars](https://developer.gnome.org/hig/patterns/containers/header-bars.html), [Menus](https://developer.gnome.org/hig/patterns/controls/menus.html), [List/Column Views](https://developer.gnome.org/hig/patterns/containers/list-column-views.html), [Buttons](https://developer.gnome.org/hig/patterns/controls/buttons.html).
- [Official Yaru changelog](https://pub.dev/packages/yaru/changelog); installed pinned 10.2.0 source APIs remain authoritative, regardless of newer published versions.
- Flutter official Actions/Shortcuts, Focus, PopScope, TextEditingController and Semantics documentation; pinned installed SDK APIs.
- Git 2.56 rev-parse, status, diff, apply, rebase and push manuals. No Git semantics or execution paths are being replaced.

## Notification rendering-chain correction

A final rendering-chain review found the previous feedback ownership paragraph
incorrectly allowed BusyMark's toast and BusyFiles' snackbar to design Git
notifications independently. GitHost.notify now forwards to one shared native
queue/surface. The strengthened audit failed against both actual prior paths
and rejects an indirect snackbar, stateful Material toast and app-owned native-
looking notification tree. It follows the notification callback rather than
unrelated application feedback, and allows only shared notification rendering.
Actual-host tests invoke the shipped callbacks and verify common geometry and
preserved keyboard focus. This change requires fresh builds and native captures;
earlier 0aaaf1d receipts are intermediate evidence, not final acceptance.

## Artifact-bound acceptance

The verification observations above retain their original implementation scope.
Current complete-corpus qualification, installed-source/payload checks and native
acceptance are recorded in the consumer acceptance documentation and its local
artifact report (BusyMark: `docs/git-ui-acceptance.md`). A prior source screenshot
or a package build alone never establishes final installed parity.

Git audits always trace full rendering and deferred stateful notification
services. The consumer's non-Git sidebar geometry audit uses its explicit
geometry scope; that scope still follows real widget constructors/build trees,
and is rejected for Git presentation/shared-feature roots. No feature-file or
widget-name allowlist replaces the required Git audit.


## Native action accessibility investigation

Final-source native partial staging confirmed exact hunk/line index scope and
preserved a dirty BusyMark document. AT-SPI then exposed a first-party rendering
defect: enabled text-action names occupied a panel child below an unnamed button.
The supported Flutter semantics dump and common red regressions in both hosts
confirm the split. The shared NativeGitActionButton/row focus boundary now owns
one complete named action; the common Git modal-close wrapper supplies equivalent
keyboard/accessibility semantics while retaining official Yaru rendering. Both
hosts' complete action/presentation contracts pass after the correction. This is
source/test evidence; new package builds and final native/installed acceptance
must be completed before calling the correction accepted.

## 2026-11-07 correction contract

Application navigation belongs to each shell. BusyMark always retains its real
workspace identity and ordinary sidebar-view menu. BusyFiles uses the same host
sidebar header for Files, Commit and Git Log, with retained browser/Git subtrees.
The shared feature takes a typed view and never constructs a repository-basename
header or a Commit/Log selector. This supersedes the earlier header ownership
statements above without retiring any shared workflows.

`GitChangeRow` carries `GitFileStatus` and `GitEntryIdentity`. Index and working
rows resolve their own XY side; historical rows resolve the selected commit's
recorded index-side metadata. Filename styling belongs only to
`gitFilenameStyle`, with approved native semantic roles and contrast correction.
No status abbreviation cell or reserved status width is permitted. Change groups
have disclosure/count semantics, without pretending to be filesystem folders.
Reference roots/headings do not reserve nonexistent icons or disclosure cells.
Filesystem siblings retain the Files disclosure grid (base 4, indent 14,
control 18, gap 4, optional icon/control 18 plus gap 8; outer inset 8).
The measured Files root filename begins 60 logical pixels inside its sidebar.

Both footer labels come from localization: Commit and Commit and Push. Their
shared measured width and horizontal spacing remain authoritative. The history
toggle retains expanded/toggled accessibility state with neutral resting paint.
Date and other text actions distinguish pointer focus from visible keyboard
focus using supported public focus/border APIs. Official Yaru/Flutter remain
unmodified.

Closable review mounts require a nonnullable dismissal guard. Requests capture
controller generation and exact review objects and coalesce repeated close
requests. Both hosts retain their real draft/save/close registries. Files Stage
and Unstage delegate to the canonical session's snapshot/content-token staging
boundary; they do not orchestrate a second gateway mutation.

Current correction evidence lives in the consumer's local
`build/git-corrections-20261107/` directory. Baseline images are explicitly
baseline evidence. Final source builds, installed parity and all native gates
must be completed separately before this correction is accepted.

Native accessibility change-tree rows use the same side-specific semantic status
and identity-aware text grid as painted rows. Change-group headings have no file
icon cell; their accessible descriptions include localized counts. Rename/copy
paths belong to the side being described, rather than leaking index rename
metadata into an ordinary unstaged modification. Wire-level regressions compare
the actual native requests with rendered label bounds.
