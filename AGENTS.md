# Git presentation and lifecycle policy

The parent BusyStack engineering and official-toolchain policy remains binding.

Git production views must use the required `GitPresentation` host contract.
No stock Material controls, constructor tear-offs, palette/icons, invocation
helpers or menu/dialog fallback paths belong in Git feature code. Native
construction stays in the existing approved host design implementations, but
their filenames and class names are not an exemption. The audit must start at
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
Resolve symbols; import prefixes, aliases, re-exports and helper references
cannot be exceptions. Missing native provisioning must fail, never fall back.

BusyMark Commit and Git Log are independent sidebar views. The Git Log order is
selected-commit information row with a view-level Actions menu, commit
information, then Changed files. Select another commit… belongs in that menu;
the subject has no activation behavior. Its graph/history is a
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
Historical Changed Files use the required native change-row tree and host-owned
contextual entry actions; they have no staging callbacks. BusyMark uses secondary
click and keyboard menus without visible entry action controls; BusyFiles retains
its trailing native controls. Two-way comparisons use one
measured toolbar and the native checked mode menu at every width. Circular
choice bars are forbidden there, including aliases; three-way editor pane
choices remain separate. Preserve explicit file/selected-line/hunk staging,
version-bound callbacks, editor guards, and both consumers' native adapters.

Commit metadata uses compact host presentation, with natural content height and
host-owned overflow. No expanded metadata modal, permanent Copy/Details icons,
or Copy Text button belongs in the inspector. Commit Actions owns View Commit
Details and the single Copy Commit Hash operation. Where a host permits visible
entry controls, historical row menus request the horizontal contextual glyph.
The required entryActionPlacement contract must never be silently ignored.
Resolve host icon constants too:
an approved catalog/wrapper cannot authorize MaterialIcons. Rendered host tests
must measure the painted dialog surface and complete selectable metadata, not
the full-window Dialog route wrapper or only class names.
