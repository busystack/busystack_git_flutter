import 'dart:convert';
import 'dart:ui' show Tristate;
import 'presentation_fixture.dart' show FixtureClient, repo;
import 'package:busystack_git_flutter/src/reference_context_menu.dart';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:yaru/yaru.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference arrow ownership and both Tab boundaries use the same real rows
/// under the shared presentation and both actual host adapters.
void referenceNavigationContract({
  required Future<void> Function(WidgetTester, Widget, Brightness) mount,
}) {
  for (final brightness in Brightness.values) {
    testWidgets(
      'reference arrows stay local while Tab reaches the toolbar $brightness',
      (tester) async {
        final search = TextEditingController(), searchFocus = FocusNode();
        addTearDown(search.dispose);
        addTearDown(searchFocus.dispose);
        await mount(
          tester,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GitReferenceNavigation(
                builder: (results) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    gitReferenceSearchNavigation(
                      controller: search,
                      results: results,
                      child: GitTextField(
                        controller: search,
                        focusNode: searchFocus,
                      ),
                    ),
                    gitReferenceResults(
                      focus: results,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final title in [
                            'First reference',
                            'Middle reference',
                            'Last reference',
                          ])
                            GitReferenceRow(title: title, onTap: () {}),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              NativeGitActionButton(
                role: NativeGitActionRole.standard,
                onPressed: () {},
                child: const Text('Date after references'),
              ),
            ],
          ),
          brightness,
        );
        FocusNode rowFocus(String title) =>
            Focus.of(tester.element(find.text(title)));
        final dateFocus = Focus.of(
          tester.element(find.text('Date after references')),
        );
        Future<void> key(LogicalKeyboardKey key) async {
          await tester.sendKeyEvent(key);
          await tester.pump();
        }

        searchFocus.requestFocus();
        await tester.pump();
        await key(LogicalKeyboardKey.arrowDown);
        expect(rowFocus('First reference').hasPrimaryFocus, isTrue);
        await key(LogicalKeyboardKey.arrowUp);
        expect(rowFocus('Last reference').hasPrimaryFocus, isTrue);
        await key(LogicalKeyboardKey.arrowDown);
        expect(rowFocus('First reference').hasPrimaryFocus, isTrue);
        await key(LogicalKeyboardKey.tab);
        expect(rowFocus('Middle reference').hasPrimaryFocus, isTrue);
        await key(LogicalKeyboardKey.tab);
        expect(rowFocus('Last reference').hasPrimaryFocus, isTrue);
        await key(LogicalKeyboardKey.tab);
        expect(
          dateFocus.hasPrimaryFocus,
          isTrue,
          reason: 'Tab must leave reference results and reach Date.',
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await key(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(rowFocus('Last reference').hasPrimaryFocus, isTrue);
        await key(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await key(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(searchFocus.hasPrimaryFocus, isTrue);
        search.value = const TextEditingValue(
          text: 'ma',
          composing: TextRange(start: 0, end: 2),
        );
        await tester.pump();
        await key(LogicalKeyboardKey.arrowDown);
        expect(searchFocus.hasPrimaryFocus, isTrue);
        dateFocus.requestFocus();
        await tester.pump();
        await key(LogicalKeyboardKey.arrowDown);
        expect(dateFocus.hasPrimaryFocus, isTrue);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }
}

/// Measured against actual consumer controls, including their painted surfaces.
void historyPresentationContract({
  required Future<void> Function(WidgetTester, Widget, Brightness) mount,
  required Widget Function(FocusNode, VoidCallback) referenceAction,
}) {
  historyToggleSemanticsContract(mount: mount);
  referenceNavigationContract(mount: mount);
  for (final brightness in Brightness.values) {
    testWidgets(
      'native tooltip timers retire with empty text, reused candidates and disposed anchors $brightness',
      (tester) async {
        final message = ValueNotifier<String>('');
        addTearDown(message.dispose);
        await mount(
          tester,
          ValueListenableBuilder<String>(
            valueListenable: message,
            builder: (context, text, _) => text == 'disposed'
                ? const Text('Replacement')
                : NativeGitTooltip.wrap(
                    context,
                    message: text,
                    child: const SizedBox(
                      width: 160,
                      height: 32,
                      child: Text('Candidate'),
                    ),
                  ),
          ),
          brightness,
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.text('Candidate')));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(OverlayPortal), findsNothing);
        message.value = '   ';
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(OverlayPortal), findsNothing);
        message.value = 'Reference label';
        await tester.pump();
        await mouse.moveTo(Offset.zero);
        await mouse.moveTo(tester.getCenter(find.text('Candidate')));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Reference label'), findsOneWidget);
        message.value = 'New candidate';
        await tester.pump();
        expect(find.text('Reference label'), findsNothing);
        await mouse.moveTo(Offset.zero);
        await mouse.moveTo(tester.getCenter(find.text('Candidate')));
        await tester.pump(const Duration(milliseconds: 200));
        message.value = 'disposed';
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('New candidate'), findsNothing);
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'native Date pointer and keyboard focus return without a stuck outline $brightness',
      (tester) async {
        final referenceFocus = FocusNode();
        addTearDown(referenceFocus.dispose);
        await mount(
          tester,
          Builder(
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                referenceAction(referenceFocus, () async {
                  await gitPresentation(context).dateRange(context);
                }),
                NativeGitActionButton(
                  role: NativeGitActionRole.standard,
                  child: const Text('Date test'),
                  onPressed: () async {
                    await gitPresentation(context).dateRange(context);
                  },
                ),
                NativeGitActionButton(
                  role: NativeGitActionRole.standard,
                  child: const Text('Next action'),
                  onPressed: () {},
                ),
              ],
            ),
          ),
          brightness,
        );
        double borderAlpha() {
          final button = find.ancestor(
            of: find.text('Date test'),
            matching: find.byType(NativeGitActionButton),
          );
          final border = find.descendant(
            of: button,
            matching: find.byType(YaruFocusBorder),
          );
          final container = tester.widget<AnimatedContainer>(
            find
                .descendant(
                  of: border,
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          );
          return ((container.foregroundDecoration! as BoxDecoration).border!
                  as Border)
              .top
              .color
              .a;
        }

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        Future<void> mouseTap(Finder target) async {
          final point = tester.getCenter(target);
          await mouse.moveTo(point);
          await mouse.down(point);
          await tester.pump(const Duration(milliseconds: 50));
          await mouse.up();
          await tester.pumpAndSettle();
        }

        await mouseTap(find.text('Approved secondary'));
        await mouseTap(
          find
              .text(
                MaterialLocalizations.of(
                  tester.element(find.text('Date filter')),
                ).cancelButtonLabel,
              )
              .last,
        );
        expect(
          referenceFocus.hasFocus,
          isFalse,
          reason:
              'The approved BusyMark secondary button does not force mouse focus.',
        );
        expect(borderAlpha(), 0);
        await mouseTap(find.text('Date test'));
        await tester.pumpAndSettle();
        expect(find.text('Date filter'), findsOneWidget);
        await mouseTap(
          find
              .text(
                MaterialLocalizations.of(
                  tester.element(find.text('Date filter')),
                ).cancelButtonLabel,
              )
              .last,
        );
        await tester.pumpAndSettle();
        expect(borderAlpha(), 0);
        final dateButton = find.ancestor(
          of: find.text('Date test'),
          matching: find.byType(NativeGitActionButton),
        );
        bool dateFocused() => tester
            .widget<FocusableActionDetector>(
              find.descendant(
                of: dateButton,
                matching: find.byType(FocusableActionDetector),
              ),
            )
            .focusNode!
            .hasPrimaryFocus;
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        for (var step = 0; step < 4 && !dateFocused(); step++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
        }
        expect(
          dateFocused(),
          isTrue,
          reason: 'Date stays reachable by keyboard.',
        );
        expect(borderAlpha(), greaterThan(0));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('Date filter'), findsOneWidget);
        await tester.tap(
          find
              .text(
                MaterialLocalizations.of(
                  tester.element(find.text('Date filter')),
                ).cancelButtonLabel,
              )
              .last,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
    testWidgets(
      'native history close exposes one named enabled button $brightness',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await mount(
          tester,
          Center(
            child: SizedBox(
              width: 674,
              height: 500,
              child: GitHistoryLayout(
                sidebar: const Text('Reference tree'),
                main: const Text('Commit history'),
                toolbar: const Text('Filters'),
                sidebarVisible: true,
                onToggle: () {},
                onCompactReferences: () {},
                sidebarFraction: .28,
                onResize: (_) {},
                minimumHistoryWidth: 560,
              ),
            ),
          ),
          brightness,
        );
        final label = MaterialLocalizations.of(
          tester.element(find.byType(GitHistoryLayout)),
        ).closeButtonTooltip;
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          matchesSemantics(
            label: label,
            textDirection: TextDirection.ltr,
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            isFocusable: true,
            hasFocusAction: true,
            hasTapAction: true,
          ),
        );
        semantics.dispose();
      },
    );
    testWidgets(
      'labelled native field exposes one persistent accessible name $brightness',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await mount(
            tester,
            const GitTextField(
              decoration: GitFieldDecoration(labelText: 'Native field'),
            ),
            brightness,
          );
          expect(
            tester
                .getSemantics(find.byType(GitTextField))
                .getSemanticsData()
                .label,
            'Native field',
          );
          await tester.enterText(find.byType(EditableText), 'composing value');
          await tester.pump();
          expect(
            tester
                .getSemantics(find.byType(GitTextField))
                .getSemanticsData()
                .label,
            'Native field',
          );
        } finally {
          semantics.dispose();
        }
      },
    );
    for (final width in [400.0, 674.0]) {
      testWidgets(
        'narrow history keeps its toggle in the title header when it fits $brightness $width',
        (tester) async {
          var visible = false, compactToggles = 0, hostToggles = 0;
          await mount(
            tester,
            Center(
              child: SizedBox(
                width: width,
                height: 500,
                child: StatefulBuilder(
                  builder: (context, setState) => GitHistoryLayout(
                    sidebar: const Text('Reference tree'),
                    main: const Text('Commit history'),
                    toolbar: const Text('Filters'),
                    sidebarVisible: true,
                    compactSidebarVisible: visible,
                    onToggle: () => hostToggles++,
                    onToggleCompact: () => setState(() {
                      visible = !visible;
                      compactToggles++;
                    }),
                    onCompactReferences: () {},
                    sidebarFraction: .28,
                    onResize: (_) {},
                    minimumHistoryWidth: 560,
                  ),
                ),
              ),
            ),
            brightness,
          );
          final title = find.byKey(const ValueKey('git-history-title'));
          final toggle = find.byKey(
            const ValueKey('git-history-sidebar-toggle'),
          );
          expect(
            tester.getCenter(toggle).dy,
            closeTo(tester.getCenter(title).dy, 1),
          );
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(visible, isTrue);
          expect(
            tester.getRect(toggle).overlaps(tester.getRect(title)),
            isFalse,
          );
          if (width == 674) {
            expect(
              tester.getCenter(toggle).dy,
              closeTo(tester.getCenter(title).dy, 1),
            );
          }
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(visible, isFalse);
          expect(compactToggles, 2);
          expect(hostToggles, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'compact action requests retain distinct native roles $brightness',
      (tester) async {
        await mount(
          tester,
          Column(
            children: [
              GitButton.standard(
                key: const ValueKey('normal-action'),
                onPressed: () {},
                child: const Text('Action'),
              ),
              GitButton.standard(
                key: const ValueKey('compact-action'),
                compact: true,
                onPressed: () {},
                child: const Text('Action'),
              ),
              GitButton(
                key: const ValueKey('inline-action'),
                compact: true,
                onPressed: () {},
                child: const Text('Metadata'),
              ),
              GitButton.primary(
                key: const ValueKey('suggested-action'),
                compact: true,
                onPressed: () {},
                child: const Text('Select this commit'),
              ),
              const GitButton.standard(
                key: ValueKey('disabled-action'),
                compact: true,
                onPressed: null,
                child: Text('Disabled'),
              ),
            ],
          ),
          brightness,
        );
        final compact = find.byKey(const ValueKey('compact-action'));
        expect(tester.getSize(compact).height, lessThanOrEqualTo(40));
        expect(
          tester.getSize(compact).height,
          lessThanOrEqualTo(
            tester.getSize(find.byKey(const ValueKey('normal-action'))).height,
          ),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('suggested-action'))).height,
          closeTo(tester.getSize(compact).height, 2),
        );
        await tester.tap(find.text('Disabled'), warnIfMissed: false);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'history fields honor native density and adornments $brightness',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await mount(
          tester,
          Column(
            children: [
              GitTextField(
                key: const ValueKey('dense'),
                controller: controller,
                decoration: const GitFieldDecoration(
                  labelText: 'Message',
                  isDense: true,
                  prefixIcon: Text('prefix'),
                  suffixIcon: Text('suffix'),
                ),
              ),
              const GitTextField(
                key: ValueKey('standard'),
                decoration: GitFieldDecoration(labelText: 'Message'),
              ),
            ],
          ),
          brightness,
        );
        expect(find.text('prefix'), findsOneWidget);
        expect(find.text('suffix'), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const ValueKey('dense'))).height,
          lessThan(
            tester.getSize(find.byKey(const ValueKey('standard'))).height,
          ),
        );
        // Native compact entry: one text line plus desktop insets, never a
        // permanently stacked label and editor in the history toolbar.
        expect(
          tester.getSize(find.byKey(const ValueKey('dense'))).height,
          lessThanOrEqualTo(40),
        );
        await tester.tap(find.byKey(const ValueKey('dense')));
        const value = TextEditingValue(
          text: '入力 composing',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 2),
        );
        tester.testTextInput.updateEditingValue(value);
        await tester.pump();
        expect(controller.value, value);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'reference rows honor density and separate trailing actions $brightness',
      (tester) async {
        var selected = 0, actions = 0, contexts = 0;
        await mount(
          tester,
          Column(
            children: [
              GitActionRow(
                key: const ValueKey('dense'),
                dense: true,
                title: const Text('feature/long-reference'),
                onTap: () => selected++,
                onSecondaryTapUp: (_) => contexts++,
                trailing: GitIconButton(
                  tooltip: 'Reference actions',
                  icon: const GitIcon(GitGlyph.moreHorizontal),
                  onPressed: () => actions++,
                ),
              ),
              GitActionRow(
                key: const ValueKey('standard'),
                title: const Text('Standard row'),
                onTap: () {},
              ),
              GitActionRow(
                enabled: false,
                dense: true,
                title: const Text('Disabled reference'),
                onTap: () => selected++,
                onSecondaryTapUp: (_) => contexts++,
              ),
            ],
          ),
          brightness,
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('dense'))).height,
          lessThan(
            tester.getSize(find.byKey(const ValueKey('standard'))).height,
          ),
        );
        await tester.tap(find.byTooltip('Reference actions'));
        await tester.pump();
        expect(actions, 1);
        expect(selected, 0);
        await tester.tap(find.text('feature/long-reference'));
        await tester.pump();
        expect(selected, 1);
        final secondary = await tester.startGesture(
          tester.getCenter(find.text('feature/long-reference')),
          buttons: kSecondaryMouseButton,
        );
        await secondary.up();
        await tester.pump();
        expect(contexts, 1);
        expect(selected, 1, reason: 'Secondary activation never selects');
        final disabled = await tester.startGesture(
          tester.getCenter(find.text('Disabled reference')),
          buttons: kSecondaryMouseButton,
        );
        await disabled.up();
        await tester.tap(find.text('Disabled reference'));
        await tester.pump();
        expect(contexts, 1);
        expect(selected, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'native fields retain padding, RTL, read-only and disabled semantics $brightness',
      (tester) async {
        final controller = TextEditingController(text: 'unchanged');
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        await mount(
          tester,
          Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              children: [
                GitTextField(
                  key: const ValueKey('padded'),
                  controller: controller,
                  focusNode: focus,
                  readOnly: true,
                  decoration: const GitFieldDecoration(
                    isDense: true,
                    labelText: 'Read only',
                    prefixIcon: Text('start'),
                    suffixIcon: Text('end'),
                    contentPadding: EdgeInsetsDirectional.only(
                      start: 24,
                      end: 8,
                      top: 20,
                      bottom: 20,
                    ),
                  ),
                ),
                const GitTextField(
                  key: ValueKey('disabled'),
                  enabled: false,
                  decoration: GitFieldDecoration(
                    isDense: true,
                    labelText: 'Disabled',
                  ),
                ),
              ],
            ),
          ),
          brightness,
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('padded'))).height,
          greaterThan(50),
        );
        expect(
          tester.getCenter(find.text('start')).dx,
          greaterThan(tester.getCenter(find.text('end')).dx),
        );
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasFocus, isTrue);
        final fields = tester
            .widgetList<EditableText>(find.byType(EditableText))
            .toList();
        expect(fields.first.readOnly, isTrue);
        expect(controller.text, 'unchanged');
        await tester.tap(find.byKey(const ValueKey('disabled')));
        await tester.pump();
        expect(fields.last.focusNode.hasFocus, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'actual native diff separates line and changed-word emphasis $brightness',
      (tester) async {
        GitSession? session;
        late GitColors colors;
        await mount(
          tester,
          Builder(
            builder: (context) {
              colors = GitColors.of(context);
              session ??= GitSession(
                client: _WordsClient(),
                repository: repo,
                host: GitHostScope.of(context)!,
              );
              return GitDiffView(
                session: session!,
                comparison: GitComparison(
                  RepoPath.text('chapter/notes.md'),
                  const ContentVersion.index(),
                  const ContentVersion.working(),
                ),
                initialSideBySide: true,
              );
            },
          ),
          brightness,
        );
        for (
          var i = 0;
          i < 100 && find.byType(GitLoading).evaluate().isNotEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        final spans = <TextSpan>[];
        void collect(InlineSpan span) {
          if (span is TextSpan) {
            spans.add(span);
            for (final child in span.children ?? <InlineSpan>[]) {
              collect(child);
            }
          }
        }

        for (final text in tester.widgetList<Text>(find.byType(Text))) {
          if (text.textSpan != null) collect(text.textSpan!);
        }
        expect(
          spans.where(
            (span) =>
                span.text == 'old' &&
                span.style?.backgroundColor == colors.removedBackground,
          ),
          isNotEmpty,
        );
        expect(
          spans.where(
            (span) =>
                span.text == 'new' &&
                span.style?.backgroundColor == colors.addedBackground,
          ),
          isNotEmpty,
        );
        final boxes = tester.widgetList<ColoredBox>(find.byType(ColoredBox));
        expect(
          boxes.any((box) => box.color == colors.addedLineBackground),
          isTrue,
        );
        expect(
          boxes.any((box) => box.color == colors.removedLineBackground),
          isTrue,
        );
        expect(
          colors.addedLineBackground.a,
          lessThan(colors.addedBackground.a),
        );
        expect(
          colors.removedLineBackground.a,
          lessThan(colors.removedBackground.a),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        session!.dispose();
      },
    );

    testWidgets(
      'semantic diff backgrounds preserve text contrast $brightness',
      (tester) async {
        late GitColors colors;
        late Color foreground;
        await mount(
          tester,
          Builder(
            builder: (context) {
              colors = GitColors.of(context);
              foreground = GitTheme.of(context).colorScheme.onSurface;
              return const SizedBox();
            },
          ),
          brightness,
        );
        for (final background in [
          colors.addedBackground,
          colors.removedBackground,
          colors.stagedBackground,
          colors.unstagedBackground,
          colors.conflictBackground,
        ]) {
          final painted = Color.alphaBlend(background, colors.surface);
          final a = foreground.computeLuminance(),
              b = painted.computeLuminance();
          final contrast = ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05);
          expect(
            contrast,
            greaterThanOrEqualTo(4.5),
            reason: 'Ordinary and changed-word text must remain readable',
          );
          expect(
            background.a,
            lessThanOrEqualTo(.28),
            reason: 'A semantic foreground is not a diff background treatment',
          );
        }
        expect(colors.searchBackground, isNot(colors.addedBackground));
        expect(colors.searchBackground, isNot(colors.removedBackground));
        expect(colors.selection, isNot(colors.searchBackground));
      },
    );
  }
}

class _WordsClient extends FixtureClient {
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async => GitContent(
    path: path,
    version: version,
    availability: ContentAvailability.present,
    token: version.label,
    mode: '100644',
    bytes: utf8.encode(
      version.kind == ContentKind.indexVersion
          ? 'first old word\nunchanged\ndeleted line\n'
          : 'first new word\nunchanged\nadded line\n',
    ),
  );
}

/// Verify the semantic node exported to the native accessibility bridge.
void historyToggleSemanticsContract({
  required Future<void> Function(WidgetTester, Widget, Brightness) mount,
}) {
  for (final brightness in Brightness.values) {
    testWidgets(
      'native history toggle has one named state and semantic activation $brightness',
      (tester) async {
        final semantics = tester.ensureSemantics();
        var visible = true, activations = 0;
        try {
          await mount(
            tester,
            SizedBox(
              width: 800,
              height: 500,
              child: StatefulBuilder(
                builder: (context, setState) => GitHistoryLayout(
                  sidebar: const Text('Native references'),
                  main: const Text('Native history'),
                  toolbar: const Text('Native filters'),
                  sidebarVisible: visible,
                  onToggle: () => setState(() {
                    visible = !visible;
                    activations++;
                  }),
                  onCompactReferences: () {},
                  sidebarFraction: .28,
                  onResize: (_) {},
                  minimumHistoryWidth: 400,
                ),
              ),
            ),
            brightness,
          );
          for (final expanded in [true, false, true]) {
            final label = gitString(
              tester.element(find.byType(GitHistoryLayout)),
              expanded
                  ? GitMessages.hideSidebarPanel
                  : GitMessages.showSidebarPanel,
            );
            final named = find.bySemanticsLabel(label);
            expect(named, findsOneWidget);
            final node = tester.getSemantics(named);
            final data = node.getSemanticsData();
            expect(data.flagsCollection.isButton, isTrue);
            expect(data.flagsCollection.isToggled != Tristate.none, isTrue);
            expect(data.flagsCollection.isToggled == Tristate.isTrue, expanded);
            expect(data.hasAction(SemanticsAction.tap), isTrue);
            expect(data.hasAction(SemanticsAction.focus), isTrue);
            final button = tester.widget<YaruIconButton>(
              find.descendant(
                of: find.byKey(const ValueKey('git-history-sidebar-toggle')),
                matching: find.byType(YaruIconButton),
              ),
            );
            expect(button.isSelected, expanded);
            final renderedIcon = find.descendant(
              of: find.byKey(const ValueKey('git-history-sidebar-toggle')),
              matching: find.byType(Icon),
            );
            expect(
              IconTheme.of(tester.element(renderedIcon)).color,
              button.style!.foregroundColor!.resolve(
                expanded ? {WidgetState.selected} : {},
              ),
            );

            final fill = button.style!.backgroundColor!.resolve(
              expanded ? {WidgetState.selected} : {},
            )!;
            expect(fill.a, expanded ? closeTo(.10, .005) : 0);
            for (final state in [WidgetState.hovered, WidgetState.pressed]) {
              expect(
                button.style!.backgroundColor!.resolve({
                  if (expanded) WidgetState.selected,
                  state,
                })!.a,
                greaterThan(fill.a),
              );
            }
            expect(visible, expanded);
            node.owner!.performAction(node.id, SemanticsAction.tap);
            await tester.pumpAndSettle();
          }
          expect(activations, 3);
          expect(visible, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
