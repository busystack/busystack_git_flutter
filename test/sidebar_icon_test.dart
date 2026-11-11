import 'dart:convert';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:busystack_git_flutter/src/sidebar_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL1WQAAAABJRU5ErkJggg==',
);
const _channel = MethodChannel('busystack_git_flutter/icons');

void main() {
  late List<MethodCall> calls;
  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return _png;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets('GTK artwork follows direction, scale, theme and invalidation', (
    tester,
  ) async {
    final options = ValueNotifier((
      rtl: false,
      scale: 1.0,
      color: Colors.black,
    ));
    addTearDown(options.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder(
          valueListenable: options,
          builder: (_, value, _) => MediaQuery(
            data: MediaQueryData(devicePixelRatio: value.scale),
            child: Directionality(
              textDirection: value.rtl ? TextDirection.rtl : TextDirection.ltr,
              child: IconTheme(
                data: IconThemeData(color: value.color),
                child: const Center(child: NativeGitSidebarIcon()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls.single.method, 'sidebar');
    expect(calls.single.arguments, {'scale': 1, 'rtl': false});
    expect(find.byType(Icon), findsNothing);
    expect(tester.widget<Image>(find.byType(Image)).color, Colors.black);
    expect(tester.getSize(find.byType(Image)), const Size(16, 16));
    options.value = (rtl: true, scale: 2.0, color: Colors.white);
    await tester.pumpAndSettle();
    expect(calls.last.arguments, {'scale': 2, 'rtl': true});
    expect(calls, hasLength(2));
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.color, Colors.white);
    expect((image.image as MemoryImage).bytes, _png);
    expect((image.image as MemoryImage).scale, 2);
    final done = tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      _channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('changed')),
      (_) {},
    );
    await done;
    await tester.pumpAndSettle();
    expect(calls, hasLength(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('missing GTK provisioning is reported without another icon', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (_) async => throw MissingPluginException('No native icon service'),
    );
    await tester.pumpWidget(const MaterialApp(home: NativeGitSidebarIcon()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<StateError>());
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(Image), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  for (final width in [800.0, 600.0]) {
    testWidgets('tooltip follows actual sidebar visibility at width $width', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        var wide = true, compact = false;
        await tester.pumpWidget(
          GitTestApp(
            home: Scaffold(
              body: GitHostScope(
                host: host(presentation: const YaruGitPresentation()),
                child: Center(
                  child: SizedBox(
                    width: width,
                    height: 500,
                    child: StatefulBuilder(
                      builder: (_, setState) => GitHistoryLayout(
                        sidebar: const Text('References sidebar'),
                        main: const Text('Commit list'),
                        toolbar: const SizedBox(),
                        sidebarVisible: wide,
                        compactSidebarVisible: compact,
                        onToggle: () => setState(() => wide = !wide),
                        onToggleCompact: () =>
                            setState(() => compact = !compact),
                        onCompactReferences: () {},
                        sidebarFraction: .28,
                        onResize: (_) {},
                        minimumHistoryWidth: 400,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final visible
            in width == 800 ? [true, false, true] : [false, true, false]) {
          final label = visible ? 'Hide sidebar panel' : 'Show sidebar panel';
          expect(find.byTooltip(label), findsOneWidget);
          expect(find.bySemanticsLabel(label), findsOneWidget);
          expect(find.byTooltip('Branches'), findsNothing);
          expect(find.byType(NativeGitSidebarIcon), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('git-history-sidebar-toggle')),
          );
          await tester.pumpAndSettle();
        }
        if (width == 600) expect(wide, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }
}
