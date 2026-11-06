import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaru/yaru.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final highContrast in [false, true]) {
      testWidgets(
        'Git palette and dialog controls ignore unrelated host styling $brightness contrast=$highContrast',
        (tester) async {
          const presentation = YaruGitPresentation();
          const accent = Color(0xffe95420);
          final schemes = <ColorScheme>[];
          final actionSizes = <Size>[];
          final bodySizes = <Size>[];
          final actionText = <TextStyle?>[];
          final checkboxText = <TextStyle?>[];
          for (var host = 0; host < 2; host++) {
            final base = brightness == Brightness.dark
                ? createYaruDarkTheme(primaryColor: accent)
                : createYaruLightTheme(primaryColor: accent);
            final theme = base.copyWith(
              extensions: [
                for (final extension in base.extensions.values)
                  if (extension is! YaruToggleButtonThemeData) extension,
                YaruToggleButtonThemeData(
                  titleStyle: TextStyle(
                    fontFamily: host == 0 ? 'Ubuntu' : 'serif',
                    height: host == 0 ? 1 : 1.4,
                    letterSpacing: host == 0 ? 0 : 2.5,
                  ),
                  horizontalSpacing: host == 0 ? 8 : 20,
                ),
              ],
              colorScheme: base.colorScheme.copyWith(
                onSurface: host == 0
                    ? const Color(0xff111111)
                    : const Color(0xffdddddd),
                onSurfaceVariant: host == 0
                    ? const Color(0xff777777)
                    : const Color(0xff222222),
                surfaceContainerHighest: host == 0
                    ? const Color(0xffcccccc)
                    : const Color(0xff333333),
              ),
              textTheme: base.textTheme.apply(
                fontSizeFactor: host == 0 ? 1 : 1.8,
                letterSpacingFactor: host == 0 ? 1 : 2,
                heightFactor: host == 0 ? 1 : 1.4,
              ),
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: Builder(
                    builder: (context) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(highContrast: highContrast),
                      child: Builder(
                        builder: (context) {
                          schemes.add(presentation.theme(context).colorScheme);
                          return GitNativeDialog(
                            title: 'Native dialog',
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Canonical body'),
                                NativeGitCheckbox(
                                  label: 'Canonical checkbox',
                                  value: false,
                                  tristate: false,
                                  onChanged: (_) {},
                                ),
                                NativeGitActionButton(
                                  role: NativeGitActionRole.standard,
                                  onPressed: () {},
                                  child: const Text('Canonical action'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            actionSizes.add(tester.getSize(find.byType(NativeGitActionButton)));
            bodySizes.add(tester.getSize(find.text('Canonical body')));
            actionText.add(
              tester
                  .renderObject<RenderParagraph>(find.text('Canonical action'))
                  .text
                  .style,
            );
            checkboxText.add(
              tester
                  .renderObject<RenderParagraph>(
                    find.text('Canonical checkbox'),
                  )
                  .text
                  .style,
            );
          }
          expect(checkboxText.last, checkboxText.first);
          expect(schemes.last.onSurface, schemes.first.onSurface);
          expect(schemes.last.onSurfaceVariant, schemes.first.onSurfaceVariant);
          expect(
            schemes.last.surfaceContainerHighest,
            schemes.first.surfaceContainerHighest,
          );
          expect(schemes.last.primary, accent);
          expect(actionSizes.last, actionSizes.first);
          expect(bodySizes.last, bodySizes.first);
          expect(actionText.last?.fontSize, actionText.first?.fontSize);
          if (highContrast) {
            final official = brightness == Brightness.dark
                ? yaruHighContrastDark
                : yaruHighContrastLight;
            expect(schemes.last.onSurface, official.colorScheme.onSurface);
            expect(schemes.last.surface, official.colorScheme.surface);
          } else {
            expect(
              schemes.last.onSurfaceVariant,
              isNot(schemes.last.onSurface),
            );
          }
        },
      );
    }
  }
}
