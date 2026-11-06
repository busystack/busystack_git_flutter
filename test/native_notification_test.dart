import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaru/yaru.dart';

Future<BuildContext> _mount(WidgetTester tester, {FocusNode? focus}) async {
  late BuildContext owner;
  await tester.pumpWidget(
    MaterialApp(
      theme: createYaruLightTheme(primaryColor: const Color(0xffe95420)),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            owner = context;
            return Focus(focusNode: focus, child: const SizedBox.expand());
          },
        ),
      ),
    ),
  );
  return owner;
}

Future<void> _settleNotification(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets(
    'feedback queues, deduplicates and expires without stealing focus',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final owner = await _mount(tester, focus: focus);
      focus.requestFocus();
      await tester.pump();
      final originalFocus = FocusManager.instance.primaryFocus;
      showGitNotification(
        owner,
        message: ' First ',
        duration: const Duration(seconds: 1),
      );
      await _settleNotification(tester);
      expect(find.text('First'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, same(originalFocus));
      await tester.pump(const Duration(milliseconds: 500));
      showGitNotification(
        owner,
        message: 'First',
        duration: const Duration(seconds: 1),
      );
      showGitNotification(
        owner,
        message: 'Second',
        duration: const Duration(seconds: 1),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text('First'),
        findsOneWidget,
        reason: 'The duplicate restarts its timer.',
      );
      await tester.pump(const Duration(milliseconds: 501));
      await _settleNotification(tester);
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await _settleNotification(tester);
      expect(find.byType(NativeGitNotificationSurface), findsNothing);
      expect(FocusManager.instance.primaryFocus, same(originalFocus));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('outgoing notification cannot dismiss the next queued message', (
    tester,
  ) async {
    final owner = await _mount(tester);
    showGitNotification(owner, message: 'First', duration: Duration.zero);
    showGitNotification(owner, message: 'Second', duration: Duration.zero);
    await _settleNotification(tester);
    final oldDismiss = tester
        .widget<NativeGitNotificationSurface>(
          find.byType(NativeGitNotificationSurface),
        )
        .onDismiss;
    oldDismiss();
    await tester.pump();
    oldDismiss(); // A click already queued on the outgoing animated child.
    await _settleNotification(tester);
    expect(find.text('Second'), findsOneWidget);
    tester
        .widget<NativeGitNotificationSurface>(
          find.byType(NativeGitNotificationSurface),
        )
        .onDismiss();
    await _settleNotification(tester);
    expect(find.byType(NativeGitNotificationSurface), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'disposed queued owner is skipped and window disposal cancels timers',
    (tester) async {
      final showChild = ValueNotifier(true);
      addTearDown(showChild.dispose);
      late BuildContext parent, child;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              parent = context;
              return ValueListenableBuilder<bool>(
                valueListenable: showChild,
                builder: (_, visible, _) => visible
                    ? Builder(
                        builder: (context) {
                          child = context;
                          return const SizedBox();
                        },
                      )
                    : const SizedBox(),
              );
            },
          ),
        ),
      );
      showGitNotification(parent, message: 'First', duration: Duration.zero);
      showGitNotification(child, message: 'Obsolete', duration: Duration.zero);
      showGitNotification(parent, message: 'Current');
      await _settleNotification(tester);
      showChild.value = false;
      await tester.pump();
      tester
          .widget<NativeGitNotificationSurface>(
            find.byType(NativeGitNotificationSurface),
          )
          .onDismiss();
      await _settleNotification(tester);
      expect(find.text('Obsolete'), findsNothing);
      expect(find.text('Current'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      showGitNotification(child, message: 'Disposed');
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1000.0]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
          'native notification geometry and live region $brightness $width $scale',
          (tester) async {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            late BuildContext owner;
            final semantics = tester.ensureSemantics();
            try {
              await tester.pumpWidget(
                MaterialApp(
                  theme: brightness == Brightness.dark
                      ? createYaruDarkTheme(
                          primaryColor: const Color(0xffe95420),
                        )
                      : createYaruLightTheme(
                          primaryColor: const Color(0xffe95420),
                        ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: Builder(
                    builder: (context) {
                      owner = context;
                      return const SizedBox.expand();
                    },
                  ),
                ),
              );
              showGitNotification(
                owner,
                message: 'Repository refreshed',
                duration: Duration.zero,
              );
              await _settleNotification(tester);
              final surface = find.byType(NativeGitNotificationSurface);
              final rect = tester.getRect(surface);
              expect(rect.width, lessThanOrEqualTo(GitSizes.dialogWide));
              expect(rect.left, greaterThanOrEqualTo(GitSpacing.lg));
              expect(width - rect.right, greaterThanOrEqualTo(GitSpacing.lg));
              expect(800 - rect.bottom, GitSpacing.lg);
              expect(
                tester.getSemantics(surface).flagsCollection.isLiveRegion,
                isTrue,
              );
              expect(find.byType(SnackBar), findsNothing);
              await tester.tap(
                find.descendant(
                  of: surface,
                  matching: find.byType(NativeGitActionButton),
                ),
              );
              await _settleNotification(tester);
              expect(surface, findsNothing);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox());
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
  }
}
