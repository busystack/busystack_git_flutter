String gitUtf8EncodingLabel(String text) => text.startsWith('\uFEFF')
    ? 'UTF-8 with byte-order mark (BOM)'
    : 'UTF-8 without byte-order mark (BOM)';

String? gitUtf8BomChange(String reviewed, String edited) {
  if (reviewed.startsWith('\uFEFF') == edited.startsWith('\uFEFF')) return null;
  return edited.startsWith('\uFEFF')
      ? 'This edit adds a UTF-8 byte-order mark (BOM) at the start of the file.'
      : 'This edit removes the UTF-8 byte-order mark (BOM) from the start of the file.';
}
