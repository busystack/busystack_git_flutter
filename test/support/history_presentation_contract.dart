import 'dart:convert';
import 'presentation_fixture.dart' show FixtureClient, repo;
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

/// Measured against actual consumer controls, including their painted surfaces.
void historyPresentationContract({
  required Future<void> Function(WidgetTester, Widget, Brightness) mount,
}) {
  for (final brightness in Brightness.values) {
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
