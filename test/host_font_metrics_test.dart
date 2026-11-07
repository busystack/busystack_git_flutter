import 'dart:io';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaru/yaru.dart';

import 'support/presentation_fixture.dart' as fixture;

class MetricsPresentation extends fixture.TestGitPresentation {
  const MetricsPresentation();
  @override
  ThemeData theme(BuildContext context) => Theme.of(context);
}

Future<void>? _fonts;
Future<void> fonts() => _fonts ??= loadFonts();

Future<void> loadFonts() async {
  for (final family in ['Ubuntu', 'packages/yaru/Ubuntu']) {
    final latin = FontLoader(family);
    latin.addFont(rootBundle.load('packages/yaru/assets/fonts/Ubuntu-R.ttf'));
    latin.addFont(rootBundle.load('packages/yaru/assets/fonts/Ubuntu-B.ttf'));
    await latin.load();
  }
  final arabic = FontLoader('Noto Sans Arabic');
  for (final name in ['Regular', 'Bold']) {
    arabic.addFont(
      File('/usr/share/fonts/truetype/noto/NotoSansArabic-$name.ttf')
          .readAsBytes()
          .then((data) => ByteData.sublistView(Uint8List.fromList(data))),
    );
  }
  await arabic.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'row height contains actual Arabic fallback glyphs and bold groups at native scale 2',
    (tester) async {
      await tester.runAsync(fonts);
      final base = fixture.host(presentation: const MetricsPresentation());
      final host = GitHost(
        presentation: base.presentation,
        icons: base.icons,
        presentMenu: base.presentMenu,
        present: <T>(context, title, child, {expanded = false}) async => null,
        openDocument: base.openDocument,
        prepareMutation: base.prepareMutation,
        chooseDirectory: base.chooseDirectory,
        notify: (_) {},
        drafts: MemoryGitDraftStore(),
        localize: (template, values) => switch (template) {
          GitMessages.staged => 'في الفهرس',
          GitMessages.unstaged => 'خارج الفهرس',
          GitMessages.untracked => 'غير متتبع',
          _ => template,
        },
      );
      double? extent;
      const title = 'في الفهرس';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            textTheme: const TextTheme(
              bodyMedium: TextStyle(
                fontFamily: 'Ubuntu',
                fontFamilyFallback: ['Noto Sans Arabic'],
                fontSize: 14,
              ),
            ),
          ),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: GitHostScope(
                  host: host,
                  child: Builder(
                    builder: (context) {
                      extent = host.rowHeight(context);
                      return Center(
                        child: Text(
                          title,
                          key: const ValueKey('heading'),
                          style: GitTheme.of(context).textTheme.bodyMedium!
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byKey(const ValueKey('heading')),
      );
      expect(
        extent,
        greaterThanOrEqualTo(paragraph.size.height + host.spacing),
        reason:
            'Uniform native tree rows must contain the actual localized bold label, not just Latin ascenders.',
      );
    },
  );
  testWidgets('native footer width measures its exact painted label style', (
    tester,
  ) async {
    await tester.runAsync(fonts);
    const label = 'إنشاء إيداع ودفع';
    final nativeHost = fixture.host(presentation: const YaruGitPresentation());
    double? measured;
    await tester.pumpWidget(
      MaterialApp(
        theme: createYaruDarkTheme(primaryColor: YaruColors.orange),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: GitHostScope(
                host: nativeHost,
                child: Builder(
                  builder: (context) {
                    measured = nativeHost.presentation.buttonWidth(
                      context,
                      label,
                      GitActionStyle.standard,
                    );
                    return Center(
                      child: NativeGitActionButton(
                        role: NativeGitActionRole.standard,
                        onPressed: () {},
                        child: const Text(label, key: ValueKey('caption')),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byKey(const ValueKey('caption')),
    );
    expect(
      measured,
      closeTo(
        paragraph.getMaxIntrinsicWidth(double.infinity) + GitSpacing.lg * 2,
        .01,
      ),
    );
  });
  for (final history in [false, true]) {
    testWidgets(
      'native ${history ? 'history' : 'dialog'} header contains fallback title metrics',
      (tester) async {
        await tester.runAsync(fonts);
        const title = 'سجل Git';
        final base = fixture.host(presentation: const YaruGitPresentation());
        final host = GitHost(
          presentation: base.presentation,
          icons: base.icons,
          presentMenu: base.presentMenu,
          present: <T>(context, title, child, {expanded = false}) async => null,
          openDocument: base.openDocument,
          prepareMutation: base.prepareMutation,
          chooseDirectory: base.chooseDirectory,
          notify: (_) {},
          drafts: MemoryGitDraftStore(),
          localize: (template, values) =>
              template == GitMessages.gitLog ? title : template,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: createYaruDarkTheme(primaryColor: YaruColors.orange),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(3)),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: GitHostScope(
                    host: host,
                    child: history
                        ? GitHistoryLayout(
                            sidebar: const Text('References'),
                            main: const Text('History'),
                            toolbar: const SizedBox(),
                            sidebarVisible: true,
                            onToggle: () {},
                            onCompactReferences: () {},
                            sidebarFraction: .24,
                            onResize: (_) {},
                            minimumHistoryWidth: 560,
                          )
                        : const GitNativeDialog(
                            title: title,
                            child: Text('Contents'),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final titleFinder = find.text(title);
        final paragraph = tester.renderObject<RenderParagraph>(titleFinder);
        SizedBox? titleRow;
        tester.element(titleFinder).visitAncestorElements((element) {
          if (element.widget case final SizedBox box when box.height != null) {
            titleRow = box;
            return false;
          }
          return true;
        });
        expect(titleRow, isNotNull);
        expect(
          titleRow!.height,
          greaterThanOrEqualTo(
            paragraph.getMaxIntrinsicHeight(double.infinity) + GitSpacing.sm,
          ),
          reason:
              'Measure the unclipped paragraph, including fallback glyphs, before allocating its title row.',
        );
      },
    );
  }
}
