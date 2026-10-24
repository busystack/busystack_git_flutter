String gitUtf8EncodingLabel(String text) => text.startsWith('\uFEFF')
    ? 'UTF-8 with byte-order mark (BOM)'
    : 'UTF-8 without byte-order mark (BOM)';

String? gitUtf8BomChange(String reviewed, String edited) {
  if (reviewed.startsWith('\uFEFF') == edited.startsWith('\uFEFF')) return null;
  return edited.startsWith('\uFEFF')
      ? 'This edit adds a UTF-8 byte-order mark (BOM) at the start of the file.'
      : 'This edit removes the UTF-8 byte-order mark (BOM) from the start of the file.';
}

final _bareLf = RegExp(r'(^|[^\r])\n');
final _bareCr = RegExp(r'\r($|[^\n])');
Set<String> _lineEndings(String text) => {
  if (text.contains('\r\n')) 'CRLF',
  if (_bareLf.hasMatch(text)) 'LF',
  if (_bareCr.hasMatch(text)) 'CR',
};

String gitLineEndingLabel(String text) {
  final endings = _lineEndings(text).toList()..sort();
  final format = endings.isEmpty
      ? 'No line terminators'
      : endings.length == 1
      ? '${endings.single} line endings'
      : 'Mixed line endings (${endings.join(', ')})';
  return text.isNotEmpty && !text.endsWith('\n')
      ? '$format · no final LF'
      : format;
}

String? gitLineEndingChange(String reviewed, String edited) {
  final before = _lineEndings(reviewed), after = _lineEndings(edited);
  // Joining/deleting all lines or introducing the first line break is ordinary
  // editing. A change of an existing newline convention needs explicit review.
  if (before.isEmpty ||
      after.isEmpty ||
      before.length == after.length && before.containsAll(after))
    return null;
  return 'Line ending format changes from ${gitLineEndingLabel(reviewed)} to ${gitLineEndingLabel(edited)}. Clipboard text can use different line endings from the original file.';
}

String gitTextFormatLabel(String text) =>
    '${gitUtf8EncodingLabel(text)} · ${gitLineEndingLabel(text)}';

String? gitTextFormatChange(String reviewed, String edited) {
  final changes = [
    gitUtf8BomChange(reviewed, edited),
    gitLineEndingChange(reviewed, edited),
  ].whereType<String>().toList();
  return changes.isEmpty ? null : changes.join('\n\n');
}
