# Log inspector and comparison toolbar refinement, 2026-11-02

This records action destinations before repository-menu entries are removed.
BusyMark retains its independent sidebars and ordinary comparison tabs. The
engine and Git semantics do not change. BusyFiles retains its workspace layout.

| Existing capability | Retained destination |
| --- | --- |
| Select historical commit, graph/filter/ref/search/paging, ordered history operations | Existing full Log selection modal and context actions |
| Author/committer, exact dates, full object/message, references, all parents | Compact inspector; explicit complete native Commit details surface and copy actions |
| Parent-specific comparison | Inspector parent menu, all actual parents; immutable captured comparison endpoints |
| Historical file review/history/blame/snapshot | Native grouped Changed Files tree, separate file action target |
| Selected commit branch/tag/compare/snapshot/cherry-pick/revert/rebase/reset | Existing history action implementation through one Commit Actions icon |
| Refresh, Fetch/Pull/Push, remotes | Native Repository Actions, maintenance separated from remote operations |
| General Merge/Rebase, configurable arbitrary revisions/root/onto and policies | Full Branches modal's native Actions menu, same existing workflow classes |
| Branch-specific Merge/Rebase directions and reviewed targets | Existing non-current branch context actions, unchanged |
| Conflicts and operation Continue/Abort/Skip | Existing operation status/banner and retained Repository Actions entry |
| Stash/worktree/submodule/reflog/recovery | Repository Actions organization group |
| Clone | Retained Repository Actions entry: no fully verified global replacement at this baseline |
| Trust revocation | Separated security entry, existing execution authorization |
| Two-way review, both modes, search/display/navigation/refresh/source | One measured native toolbar, checked mode menu, narrow secondary overflow |
| Whole-file, hunk and selected-line staging | Contextual explicitly named file/line actions and unchanged hunk controls/transactions |
| Three-way index editing and guarded Apply | Native staging menu opens existing editor, unchanged draft/undo/dismissal guards |

Native references: BusyMark's Files tree / `BusyMarkSidebarTreeRow`, flat
`BusyMarkGitActionButton`, Writerside header's `BusyMarkHeaderIconButton`, and
native menu service. The inspector requests those through the existing shared
presentation contract; no application imports or palette/control fallbacks are
added. Human-readable commit dates use required host localization, while the
complete exact data remains selectable/copyable in explicit details.

References read: GNOME HIG Buttons, Menus and Header Bars; official IntelliJ Log,
Diff Viewer and Commit/Push; Git diff/show/commit/revisions/apply documentation.
They inform action grouping and semantics, not alternate application placement.
Native appearance and real transaction/regression checks remain required.

## Required native mappings and regression gates

| Request | BusyMark / BusyFiles implementation |
| --- | --- |
| Flat selected-commit and mode buttons | Existing host inline action; BusyMarkGitActionButton / BusyFiles native inline button |
| Historical rows and separate trailing actions | Existing required changeRow; BusyMarkSidebarTreeRow / BusyFiles tree-row adapter |
| Copy, Commit Actions, Display Options | Required semantic copy/moreHorizontal/options glyphs mapped to existing host glyph catalogs |
| Human-readable metadata dates | Required formatCommitDate in each approved design boundary, host localized date/time and 12/24-hour preference |
| Full exact message/identity/timestamps | Existing host native details modal, selectable text and clipboard interaction |
| File/commit/mode/overflow menus | Existing required host menu service; logical leading-edge anchors in LTR/RTL |

The resolved gate rejects a boolean GitChoiceBar in the two-way diff source,
including typedef constructors and tear-offs; its self-test proves those fail
while the existing integer three-way pane choice passes. Existing Material and
fallback checks remain. Actual BusyMark rendered tests inspect native shape,
states, one-row geometry, text height, disjoint targets, checked menu values,
keyboard menu activation/anchors, metadata completeness and enlarged RTL.
Consumer checks continue auditing the exact materialized archives. No golden or
wrapper allowlist grants approval for a visually incorrect control.
