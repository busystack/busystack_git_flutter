# Git decorations in host file browsers

`GitFileTreeDecorations.fromSnapshot` supplies an immutable, weakly cached
lookup for an engine `GitSnapshot`. `forUri(uri, directory: true)` returns
directory state; file lookups retain that path's own XY status. The lookup
performs no Git or filesystem operations and never supplies filesystem rows.
Hosts continue to own navigation, selection, expansion, menus, trust,
repository attachment and status invalidation.

`GitTreeDecoration` supplies a file status or a `GitDirectoryChangeState`, a
marker, counts and a localized description. `gitTreeDecorationStyle` uses the
canonical native filename palette, with light/dark and contrast correction.
Files prefer their working-tree operation when present; the explanation retains
both staged and unstaged statuses. Conflicts have a separate colour and underline.

Directory states follow [IntelliJ's immediate-child and descendant
distinction](https://www.jetbrains.com/help/idea/adding-files-to-version-control.html):

| State | Presentation | Meaning |
| --- | --- | --- |
| Immediate | Stronger blue; `•` in badge hosts | Changed paths directly in this directory |
| Descendant | Muted blue; `◦` in badge hosts | Changes only in nested directories |
| Clean | No decoration | No reported changes |

Immediate state takes precedence when both locations contain changes. Deleted
paths contribute to location and deletion counts without lending a deletion
colour to directories. Tooltips explain both locations, include deleted-path
counts, and direct users to Git Changes for the paths themselves.

Renames affect the source and destination directories, counting once per common
ancestor. Copies leave their source directory unchanged. Ignored and unchanged
entries do not contribute. Gitlinks and opaque directory records count once;
the lookup does not inspect another repository's contents. URI matching preserves
raw filename bytes and rejects provider/remote-host URIs. Snapshot identity, not
a status token alone, owns the cache and host refresh notification.

BusyMark retains the engine snapshot through its authoring projection. Its thin
adapter also maps the existing authoring gateway's XY enums to engine changes;
it has no colour, priority or directory algorithm. BusyFiles' browser scope
attaches the same lookup to its existing list/grid icon and accessibility slots,
including the Properties description.

The former BusyMark priority reducer made deletion outrank modification and
propagated that file colour to every ancestor. Its status enum, palette,
category helpers, reducer and directory aggregator have been removed. BusyFiles'
separate `GitFileBadge` aggregator and URI encoder have also been removed; byte
URI conversion now belongs to this shared package.

Regression coverage is in `test/file_tree_decorations_test.dart`, BusyMark's
`shared_git_decorations_test.dart` and Files smoke tests, and BusyFiles'
`git_decorations_test.dart` and `git_location_entry_test.dart`. These include
` M topics/named-export-presets.md` plus ` D topics/releasev051.md`, shared Git
Changes activation of the deleted file, clean refresh, both browser modes,
renames, ignored paths, byte paths, repository scoping, themes and a watch event
arriving during a BusyFiles status read.

Acceptance is **open** until these widget regressions execute and both actual
installed applications pass native visual verification. The implementation
session's sandbox rejected loopback/display sockets and escalation; a native
display could not start. Initial compiler attempts also hit temporary-directory
quota limits. Source/static checks and test compilation are not substitutes for
widget execution or installed-app screenshots. The new directory explanation
uses the hosts' ARB catalogs; untranslated locales currently use English fallback.
