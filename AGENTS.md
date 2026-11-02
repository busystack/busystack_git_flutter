# Git presentation and lifecycle policy

The parent BusyStack engineering and official-toolchain policy remains binding.

Git production views must use the required `GitPresentation` host contract.
No stock Material controls, constructor tear-offs, palette/icons, invocation
helpers or menu/dialog fallback paths belong in Git feature code. Native
construction stays in the existing approved host design implementations:
`busymark_design.dart` and `busyfiles_design.dart`. A newly named feature wrapper
is not an approved design boundary. See the shared package's
`docs/native-presentation.md` for the exact mappings and action destinations.

Run `tool/check_native_presentation.dart` and its self-test from the shared
package, and audit each consumer's actual Git sources with that tool. Run the
same gate against materialized pinned sources in consumer verification.
Resolve symbols; import prefixes, aliases, re-exports and helper references
cannot be exceptions. Missing native provisioning must fail, never fall back.

BusyMark Commit and Git Log are independent sidebar views. The Git Log order is
selected-commit button, information, then Changed files. Its graph/history is a
native selection modal with explicit confirmation and cancellation. Ordinary
file activation opens a normal comparison tab. Repository/worktree, both paths,
immutable endpoints/parent and mutable review context identify that tab; sidebar
navigation never retargets it. Preserve actual tab/editor dismissal guards and
all transaction, draft, native input, history and comparison regressions.
BusyFiles retains its existing navigation and authenticated daemon boundary.

The required change-row builder and text inset come from each real host, so
native tree geometry and accessibility agree. BusyMark uses its existing flat
header action and sidebar tree treatment; compact circular actions are rejected
by resolved symbol identity even when aliased. Preserve BusyFiles' workspace
layout and descendant navigation when changing shared Commit presentation.

Respect host inline/standard/suggested action distinctions and optional labelled
checkbox requests. Compact sidebar hosts may put Refresh in their repository
menu and omit its duplicate Branches entry; default workspace navigation stays
available. Verify both native adapters whenever a presentation request changes.

Git Log's compact inspector has no information/file splitter or permanent upper
scrollbar. Full messages/exact identities remain accessible in native details.
Historical Changed Files use the required native change-row tree and a separate
file-menu target; they have no staging callbacks. Two-way comparisons use one
measured toolbar and the native checked mode menu at every width. Circular
choice bars are forbidden there, including aliases; three-way editor pane
choices remain separate. Preserve explicit file/selected-line/hunk staging,
version-bound callbacks, editor guards, and both consumers' native adapters.
