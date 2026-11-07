import 'package:flutter/material.dart';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'presentation_fixture.dart' show host;

// Deliberately test-only stock widgets keep the existing behavioral assertions
// independent of either host. Consumer tests exercise the real native adapters.
class TestGitPresentation implements GitPresentation {
  const TestGitPresentation({
    this.entryActionPlacement = GitEntryActionPlacement.trailing,
  });
  @override
  final GitEntryActionPlacement entryActionPlacement;
  @override
  ThemeData theme(BuildContext context) => Theme.of(context);
  @override
  TextStyle? codeStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
  @override
  GitColors colors(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return GitColors(
      accent: c.primary,
      selection: c.secondaryContainer,
      border: c.outline,
      subtleBorder: c.outlineVariant,
      surface: c.surface,
      mutedText: c.onSurfaceVariant,
      added: c.primary,
      removed: c.error,
      staged: c.primary,
      unstaged: c.tertiary,
      conflict: c.error,
      addedBackground: c.primaryContainer,
      removedBackground: c.errorContainer,
      stagedBackground: c.primaryContainer,
      unstagedBackground: c.tertiaryContainer,
      conflictBackground: c.errorContainer,
      searchBackground: c.tertiaryContainer,
    );
  }

  @override
  String formatCommitDate(
    BuildContext context,
    DateTime date, {
    bool full = false,
  }) => full
      ? MaterialLocalizations.of(context).formatFullDate(date.toLocal())
      : MaterialLocalizations.of(context).formatMediumDate(date.toLocal());
  @override
  Future<(DateTime, DateTime)?> dateRange(
    BuildContext context, {
    DateTime? start,
    DateTime? end,
  }) async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1970),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    return r == null ? null : (r.start, r.end);
  }

  @override
  String repositoryActionsLabel(BuildContext context) =>
      GitMessages.repositoryActions;
  @override
  GitToolbarMetrics toolbarMetrics(BuildContext context) =>
      const GitToolbarMetrics(
        iconExtent: 48,
        gap: 4,
        textInsets: 32,
        modeAdornment: 24,
      );
  @override
  double buttonWidth(
    BuildContext context,
    String label,
    GitActionStyle variant,
  ) {
    final style = variant == GitActionStyle.suggested
        ? _MeasuredFilledButton().resolved(context)
        : _MeasuredOutlinedButton().resolved(context);
    final painter = TextPainter(
      text: TextSpan(text: label, style: style.textStyle?.resolve({})),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width =
        painter.width +
        (style.padding
                ?.resolve({})
                ?.resolve(Directionality.of(context))
                .horizontal ??
            0);
    painter.dispose();
    return width < (style.minimumSize?.resolve({})?.width ?? 0)
        ? style.minimumSize!.resolve({})!.width
        : width;
  }

  @override
  Widget button(BuildContext context, GitButton c) => switch (c.variant) {
    GitActionStyle.suggested => FilledButton(
      onPressed: c.onPressed,
      child: c.child,
    ),
    GitActionStyle.standard => OutlinedButton(
      onPressed: c.onPressed,
      child: c.child,
    ),
    GitActionStyle.inline ||
    GitActionStyle.toolbar ||
    GitActionStyle.diffInline => TextButton(
      onPressed: c.onPressed,
      child: c.child,
    ),
  };
  @override
  Widget iconAction(BuildContext context, GitIconButton c) => IconButton(
    tooltip: gitString(context, c.tooltip),
    onPressed: c.onPressed,
    icon: c.icon,
    padding: c.compact ? EdgeInsets.zero : null,
    constraints: c.compact ? const BoxConstraints() : null,
  );
  @override
  Widget field(BuildContext context, GitTextField c) => TextField(
    controller: c.controller,
    focusNode: c.focusNode,
    scrollController: c.scrollController,
    undoController: c.undoController,
    style: c.style,
    autofocus: c.autofocus,
    readOnly: c.readOnly,
    expands: c.expands,
    enabled: c.enabled,
    obscureText: c.obscureText,
    autocorrect: c.autocorrect,
    enableSuggestions: c.enableSuggestions,
    maxLines: c.maxLines,
    minLines: c.minLines,
    textAlign: c.textAlign,
    textAlignVertical: c.textAlignVertical,
    textDirection: c.textDirection,
    onChanged: c.onChanged,
    onSubmitted: c.onSubmitted,
    decoration: InputDecoration(
      labelText: c.decoration?.labelText,
      hintText: c.decoration?.hintText,
      prefixIcon: c.decoration?.prefixIcon,
      suffixIcon: c.decoration?.suffixIcon,
      isDense: c.decoration?.isDense,
      contentPadding: c.decoration?.contentPadding,
    ),
  );
  @override
  Widget checkbox(BuildContext context, GitCheckbox c) => c.label == null
      ? Checkbox(
          value: c.value,
          tristate: c.value == null,
          onChanged: c.onChanged,
        )
      : Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            title: Text(c.label!),
            value: c.value,
            onChanged: c.onChanged,
          ),
        );
  @override
  Widget choice<T>(BuildContext context, GitChoice<T> c) =>
      c.initialValue != null
      ? DropdownButtonFormField<T>(
          initialValue: c.initialValue,
          isExpanded: c.isExpanded,
          decoration: InputDecoration(labelText: c.decoration?.labelText),
          onChanged: c.onChanged,
          items: [
            for (final i in c.items)
              DropdownMenuItem(value: i.value, child: i.child),
          ],
        )
      : DropdownButton<T>(
          value: c.value,
          isExpanded: c.isExpanded,
          onChanged: c.onChanged,
          items: [
            for (final i in c.items)
              DropdownMenuItem(value: i.value, child: i.child),
          ],
        );
  @override
  Widget choiceBar<T>(BuildContext context, GitChoiceBar<T> control) =>
      SegmentedButton<T>(
        segments: [
          for (final segment in control.segments)
            ButtonSegment(
              value: segment.value,
              label: segment.label,
              icon: segment.icon,
            ),
        ],
        selected: control.selected,
        onSelectionChanged: control.onSelectionChanged,
      );
  @override
  Widget row(BuildContext context, GitActionRow c) => GestureDetector(
    onSecondaryTapUp: c.onSecondaryTapUp,
    child: Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: c.contentPadding,
        title: c.title,
        subtitle: c.subtitle,
        leading: c.leading,
        trailing: c.trailing,
        dense: c.dense,
        enabled: c.enabled,
        selected: c.selected,
        onTap: c.onTap,
      ),
    ),
  );
  @override
  double changeRowTextInset(BuildContext context, int depth) => depth * 16 + 24;
  @override
  Widget changeRow(BuildContext context, GitChangeRow c) => activation(
    context,
    GitActivation(
      onTap: c.onTap,
      onDoubleTap: c.onDoubleTap,
      onSecondaryTapUp: c.onSecondaryTapUp,
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: c.depth * 16),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: c.expanded == null
                  ? const SizedBox.shrink()
                  : GestureDetector(
                      onTap: c.onToggle,
                      child: GitIcon(
                        c.expanded! ? GitGlyph.expand : GitGlyph.next,
                      ),
                    ),
            ),
            Expanded(child: Text(c.title)),
            if (c.trailing != null) c.trailing!,
          ],
        ),
      ),
    ),
  );

  @override
  EdgeInsetsGeometry logContentInsets(BuildContext context) =>
      const EdgeInsets.all(8);
  @override
  Widget logHeader(BuildContext context, GitLogHeader c) => Row(
    children: [
      Expanded(child: c.subject),
      c.choose,
      c.actions,
    ],
  );
  @override
  Widget historyLayout(BuildContext context, GitHistoryLayout c) =>
      LayoutBuilder(
        builder: (context, bounds) => Column(
          children: [
            c.toolbar,
            GitIconButton(
              key: const ValueKey('git-history-sidebar-toggle'),
              tooltip: bounds.maxWidth < 1150
                  ? GitMessages.filterBranchesAndTags
                  : GitMessages.toggleBranchesPane,
              icon: const GitIcon(GitGlyph.branch),
              onPressed: bounds.maxWidth < 1150
                  ? c.onCompactReferences
                  : c.onToggle,
            ),
            Expanded(
              child: Row(
                children: [
                  if (c.sidebarVisible && bounds.maxWidth >= 1150)
                    SizedBox(width: 240, child: c.sidebar),
                  Expanded(child: c.main),
                ],
              ),
            ),
            if (c.footer != null)
              Padding(padding: const EdgeInsets.all(16), child: c.footer!),
          ],
        ),
      );
  @override
  Widget referenceRow(BuildContext context, GitReferenceRow c) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GitActionRow(
        dense: true,
        contentPadding: EdgeInsetsDirectional.only(start: 8 + c.depth * 14),
        leading: c.expanded == null
            ? c.leading
            : Icon(c.expanded! ? Icons.expand_more : Icons.chevron_right),
        title: Text(c.title),
        selected: c.selected,
        onTap: c.onTap,
        onSecondaryTapUp: c.onSecondaryTapUp,
      ),
      if (c.expanded ?? false) ...c.children,
    ],
  );
  @override
  Widget expander(BuildContext context, GitExpander c) => ExpansionTile(
    title: c.title,
    initiallyExpanded: c.initiallyExpanded,
    onExpansionChanged: c.onExpansionChanged,
    children: c.children,
  );
  @override
  Widget progress(BuildContext context, GitLoading c) => c.circular
      ? CircularProgressIndicator(
          semanticsLabel: c.semanticsLabel,
          strokeWidth: c.strokeWidth ?? 4,
        )
      : LinearProgressIndicator(semanticsLabel: c.semanticsLabel);
  @override
  Widget tooltip(BuildContext context, GitTooltip c) =>
      Tooltip(message: c.message, child: c.child);
  @override
  Widget scrollbar(BuildContext context, GitScrollbar control) => Scrollbar(
    controller: control.controller,
    thumbVisibility: control.thumbVisibility,
    child: control.child,
  );
  @override
  Widget separator(BuildContext context, GitSeparator c) =>
      c.vertical ? VerticalDivider(width: c.width) : Divider(height: c.height);
  @override
  Widget activation(BuildContext context, GitActivation c) => InkWell(
    focusNode: c.focusNode,
    onTap: c.onTap,
    onDoubleTap: c.onDoubleTap,
    onSecondaryTapUp: c.onSecondaryTapUp,
    child: c.child,
  );
  @override
  Widget notice(BuildContext context, GitNotice c) => MaterialBanner(
    content: c.content,
    leading: c.leading,
    actions: c.actions,
  );
  @override
  Widget selectable(BuildContext context, GitSelectableText control) =>
      SelectableText(
        control.data,
        semanticsLabel: control.data,
        style: control.style,
      );
  @override
  Widget selectionArea(BuildContext context, Widget child) =>
      SelectionArea(child: child);
  @override
  String editingActionLabel(BuildContext context, ContextMenuButtonType type) =>
      type.name;
}

const testGitIcons = {
  GitGlyph.repository: Icons.folder_outlined,
  GitGlyph.selectCommit: Icons.account_tree_outlined,
  GitGlyph.copy: Icons.copy,
  GitGlyph.options: Icons.settings,
  GitGlyph.moreHorizontal: Icons.more_horiz,
  GitGlyph.back: Icons.arrow_back,
  GitGlyph.branch: Icons.account_tree_outlined,
  GitGlyph.history: Icons.history,
  GitGlyph.refresh: Icons.refresh,
  GitGlyph.more: Icons.more_vert,
  GitGlyph.actions: Icons.menu,
  GitGlyph.expand: Icons.expand_more,
  GitGlyph.previous: Icons.chevron_left,
  GitGlyph.next: Icons.chevron_right,
  GitGlyph.up: Icons.arrow_upward,
  GitGlyph.down: Icons.arrow_downward,
  GitGlyph.search: Icons.search,
  GitGlyph.add: Icons.add,
  GitGlyph.remove: Icons.remove,
  GitGlyph.check: Icons.check,
  GitGlyph.tag: Icons.label_outline,
  GitGlyph.error: Icons.error_outline,
  GitGlyph.warning: Icons.warning_amber_outlined,
  GitGlyph.close: Icons.close,
};
Future<String?> testGitMenu(
  BuildContext context,
  List<GitMenuEntry> entries, {
  Offset? position,
}) => showDialog<String>(
  context: context,
  builder: (context) => Dialog(
    child: ListView(
      shrinkWrap: true,
      children: [
        for (final e in entries)
          ListTile(
            enabled: e.enabled,
            title: Text(e.label),
            onTap: e.enabled ? () => Navigator.of(context).pop(e.id) : null,
          ),
      ],
    ),
  ),
);

class GitTestApp extends StatelessWidget {
  const GitTestApp({
    super.key,
    this.home,
    this.navigatorKey,
    this.theme,
    this.darkTheme,
    this.themeMode,
    this.locale,
    this.localizationsDelegates,
    this.supportedLocales = const [Locale('en', 'US')],
    this.shortcuts,
    this.actions,
    this.routes = const {},
    this.onGenerateRoute,
    this.debugShowCheckedModeBanner = true,
    this.builder,
    this.navigatorObservers = const [],
  });
  final Widget? home;
  final GlobalKey<NavigatorState>? navigatorKey;
  final ThemeData? theme, darkTheme;
  final ThemeMode? themeMode;
  final Locale? locale;
  final Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates;
  final Iterable<Locale> supportedLocales;
  final Map<ShortcutActivator, Intent>? shortcuts;
  final Map<Type, Action<Intent>>? actions;
  final Map<String, WidgetBuilder> routes;
  final RouteFactory? onGenerateRoute;
  final bool debugShowCheckedModeBanner;
  final TransitionBuilder? builder;
  final List<NavigatorObserver> navigatorObservers;
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: home,
    navigatorKey: navigatorKey,
    theme: theme,
    darkTheme: darkTheme,
    themeMode: themeMode,
    locale: locale,
    localizationsDelegates: localizationsDelegates,
    supportedLocales: supportedLocales,
    shortcuts: shortcuts,
    actions: actions,
    routes: routes,
    onGenerateRoute: onGenerateRoute,
    debugShowCheckedModeBanner: debugShowCheckedModeBanner,
    navigatorObservers: navigatorObservers,
    builder: (context, child) => GitHostScope(
      host: host(),
      child: builder?.call(context, child) ?? child!,
    ),
  );
}

// Official protected APIs are called only from their supported subclasses.
class _MeasuredFilledButton extends FilledButton {
  _MeasuredFilledButton() : super(onPressed: () {}, child: const SizedBox());
  ButtonStyle resolved(BuildContext context) =>
      defaultStyleOf(context).merge(themeStyleOf(context));
}

class _MeasuredOutlinedButton extends OutlinedButton {
  _MeasuredOutlinedButton() : super(onPressed: () {}, child: const SizedBox());
  ButtonStyle resolved(BuildContext context) =>
      defaultStyleOf(context).merge(themeStyleOf(context));
}
