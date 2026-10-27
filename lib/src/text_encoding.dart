import 'package:flutter/widgets.dart';
import 'host.dart';
import 'messages.dart';

String _label(
  BuildContext? context,
  String template, [
  Map<String, Object?> values = const {},
]) => context == null
    ? template.replaceAllMapped(
        RegExp(r'\{([A-Za-z0-9_]+)\}'),
        (match) =>
            values.containsKey(match[1]) ? '${values[match[1]]}' : match[0]!,
      )
    : gitString(context, template, values: values);

String gitUtf8EncodingLabel(String text, {BuildContext? context}) => _label(
  context,
  text.startsWith('\uFEFF') ? GitMessages.utf8Bom : GitMessages.utf8NoBom,
);

String? gitUtf8BomChange(
  String reviewed,
  String edited, {
  BuildContext? context,
}) {
  if (reviewed.startsWith('\uFEFF') == edited.startsWith('\uFEFF')) return null;
  return _label(
    context,
    edited.startsWith('\uFEFF') ? GitMessages.addsBom : GitMessages.removesBom,
  );
}

final _bareLf = RegExp(r'(^|[^\r])\n');
final _bareCr = RegExp(r'\r($|[^\n])');
Set<String> _lineEndings(String text) => {
  if (text.contains('\r\n')) 'CRLF',
  if (_bareLf.hasMatch(text)) 'LF',
  if (_bareCr.hasMatch(text)) 'CR',
};

String gitLineEndingLabel(String text, {BuildContext? context}) {
  final endings = _lineEndings(text).toList()..sort();
  final format = endings.isEmpty
      ? _label(context, GitMessages.noLineTerminators)
      : endings.length == 1
      ? _label(context, GitMessages.lineEndings, {'format': endings.single})
      : _label(context, GitMessages.mixedLineEndings, {
          'formats': endings.join(', '),
        });
  return text.isNotEmpty && !text.endsWith('\n')
      ? _label(context, GitMessages.noFinalLf, {'format': format})
      : format;
}

String? gitLineEndingChange(
  String reviewed,
  String edited, {
  BuildContext? context,
}) {
  final before = _lineEndings(reviewed), after = _lineEndings(edited);
  // Joining/deleting all lines or introducing the first line break is ordinary
  // editing. A change of an existing newline convention needs explicit review.
  if (before.isEmpty ||
      after.isEmpty ||
      before.length == after.length && before.containsAll(after))
    return null;
  return _label(context, GitMessages.lineEndingChange, {
    'before': gitLineEndingLabel(reviewed, context: context),
    'after': gitLineEndingLabel(edited, context: context),
  });
}

String gitTextFormatLabel(String text, {BuildContext? context}) =>
    '${gitUtf8EncodingLabel(text, context: context)} · ${gitLineEndingLabel(text, context: context)}';

String? gitTextFormatChange(
  String reviewed,
  String edited, {
  BuildContext? context,
}) {
  final changes = [
    gitUtf8BomChange(reviewed, edited, context: context),
    gitLineEndingChange(reviewed, edited, context: context),
  ].whereType<String>().toList();
  return changes.isEmpty ? null : changes.join('\n\n');
}
