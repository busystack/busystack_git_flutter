# Git presentation and lifecycle policy

The parent BusyStack engineering and official-toolchain policy remains binding.

The 2026-11-06 product decision requires one Git UI in both Linux hosts.
GitFeatureSidebar owns the context header and Commit/Git Log navigation;
GitReview/GitReviewTabs and GitReviewSurface own review identity/navigation;
YaruGitPresentation and GitNativeDialog own native Git controls and layout.
Both app presentation adapters are thin bridges without visual overrides.
GitReviewContent retains independent review widgets; BusyMark bridges the same
controller to its real document strip through GitHost.mountReview. Ordinary
history-file activation calls gitOpenComparison. Read-only selector routes use
reviewSelection ownership; never dismiss an operation plan or an unrelated
newer modal. gitSelectHistoryCommit owns the full history-modal composition.
BusyMark retains document-tab/non-Git navigation integration; BusyFiles mounts
these shared surfaces in its main sidebar/content slots and preserves its
browser subtree for Return to Files. No competing GitWorkspace switcher,
split staging workspace, single reusable preview or legacy UI mode is allowed.
Native services, localization, trust policy, documents and transport stay host-owned.
See the maintained shared docs/one-git-ui.md action/ownership map. Actual native
screenshots in both final installed applications remain required acceptance.

Git production views must use the required `GitPresentation` host contract.
No stock Material controls, constructor tear-offs, palette/icons, invocation
helpers or menu/dialog fallback paths belong in Git feature code. Native
construction stays in the canonical shared linux_native.dart implementation;
host adapters only bridge services. Filenames and class names are not exemptions. The audit must start at
each concrete host adapter and follow all reachable first-party
implementations. BusyMark's Git chain may use supported public Yaru controls,
but it must not directly construct prohibited Material controls behind
approved-looking wrappers. A newly named feature wrapper is not an approved
design boundary. See the shared package's
`docs/native-presentation.md` for the exact mappings and action destinations.

Run `tool/check_native_presentation.dart` and its self-test from the shared
package, and audit each consumer's actual Git sources with that tool. BusyMark
must audit the complete `BusyMarkGitPresentation` class and
`BusyMarkGitDialogShell`, not a selected method allowlist. Run the
same gate against materialized pinned sources in consumer verification.
Follow inherited renderers and mixins across the shared Git UI package boundary;
a const-only host adapter is not sufficient evidence. Run the cross-package
adversarial cases so that an empty host class cannot make the audit vacuous.
Resolve symbols; import prefixes, aliases, re-exports and helper references
cannot be exceptions. Missing native provisioning must fail, never fall back.

BusyMark Commit and Git Log are independent sidebar views. The Git Log order is
selected-commit information row with a view-level Actions menu, commit
information, then Changed files. Select another commit is a dedicated native icon action immediately before Commit Actions; it must not also appear in that menu;
the subject has no activation behavior. Its graph/history is a
native selection modal with explicit confirmation and cancellation. Ordinary
file activation opens a normal comparison tab. Repository/worktree, both paths,
immutable endpoints/parent and mutable review context identify that tab; sidebar
navigation never retargets it. Preserve actual tab/editor dismissal guards and
all transaction, draft, native input, history and comparison regressions.
Both hosts use the same shared Git navigation and surfaces. BusyFiles retains
its browser navigation, descendant discovery and authenticated daemon boundary.

The required change-row builder and text inset come from the shared Linux
implementation based on BusyMark's approved Files grid, so both hosts have the
same file/folder/status slots, geometry and accessibility. Preserve flat native
header actions; compact circular actions remain rejected even when aliased.
BusyFiles consumes the same sidebar layout and preserves descendant discovery.

Respect host inline/standard/suggested action distinctions and optional labelled
checkbox requests. Both sidebar hosts put Refresh in Actions and omit its
duplicate Branches entry; all unique workflow destinations remain available. Verify both native adapters whenever a presentation request changes.

Git Log's compact inspector has no information/file splitter or permanent upper
scrollbar. Full messages/exact identities remain accessible in native details.
Historical Changed Files use the required native change-row tree and host-owned
contextual entry actions; they have no staging callbacks. Both hosts use secondary click and keyboard menus without visible entry action
controls. Two-way comparisons use one
measured toolbar and the native checked mode menu at every width. Circular
choice bars are forbidden there, including aliases; three-way editor pane
choices remain separate. Preserve explicit file/selected-line/hunk staging,
version-bound callbacks, editor guards, and both consumers' native adapters.

Commit metadata uses compact host presentation, with natural content height and
host-owned overflow. No expanded metadata modal, permanent Copy/Details icons,
or Copy Text button belongs in the inspector. Commit Actions owns View Commit
Details and the single Copy Commit Hash operation. Historical row menus use the horizontal contextual role through secondary click
and keyboard activation; there are no permanent entry controls.
The required entryActionPlacement contract must never be silently ignored.
Resolve host icon constants too:
an approved catalog/wrapper cannot authorize MaterialIcons. Rendered host tests
must measure the painted dialog surface and complete selectable metadata, not
the full-window Dialog route wrapper or only class names.

Git workflow notifications are shared presentation: both hosts forward localized
messages and lifetime guards to `showGitNotification`; do not build a host-owned
Git toast/snackbar. The resolved native audit follows `GitHost.notify` into
helpers and stateful rendering, with adversarial callback ownership tests.

The non-Git sidebar geometry audit may use `sidebarGeometry`; its real widget
construction/build chains remain checked. All Git roots and GitHost.notify use
the mandatory full rendering/service scope; do not use geometry scope for Git.
