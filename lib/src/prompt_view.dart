import 'messages.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'host.dart';

Future<Uint8List?> presentGitPrompt(
  BuildContext context,
  GitPresentSurface present,
  GitPrompt prompt,
  GitCancellation cancellation,
) async {
  if (!context.mounted || cancellation.isCancelled) return null;
  return present<Uint8List>(
    context,
    prompt.title,
    _GitPromptView(prompt: prompt, cancellation: cancellation),
    expanded: prompt.kind == GitPromptKind.message,
  );
}

final class _GitPromptView extends StatefulWidget {
  const _GitPromptView({required this.prompt, required this.cancellation});
  final GitPrompt prompt;
  final GitCancellation cancellation;
  @override
  State<_GitPromptView> createState() => _PromptState();
}

final class _PromptState extends State<_GitPromptView> {
  late final TextEditingController text;
  final undo = UndoHistoryController();
  @override
  void initState() {
    super.initState();
    text = TextEditingController(text: widget.prompt.initialText);
    unawaited(
      widget.cancellation.whenCancelled.then((_) {
        if (mounted) {
          final route = ModalRoute.of(context);
          if (route != null) Navigator.of(context).removeRoute(route);
        }
      }),
    );
  }

  @override
  void dispose() {
    text.clear();
    text.dispose();
    undo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.prompt.kind == GitPromptKind.message;
    final field = TextField(
      controller: text,
      undoController: message ? undo : null,
      autofocus: true,
      obscureText: !message,
      enableSuggestions: message,
      autocorrect: false,
      expands: message,
      maxLines: message ? null : 1,
      textAlignVertical: TextAlignVertical.top,
      decoration: InputDecoration(
        labelText: message
            ? gitString(context, GitMessages.gitMessage)
            : widget.prompt.title,
        border: const OutlineInputBorder(),
      ),
      onSubmitted: message ? null : (_) => accept(),
    );
    return Column(
      mainAxisSize: message ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.prompt.repository.root,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (message) Expanded(child: field) else field,
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const GitLabel(GitMessages.cancelPrompt),
            ),
            FilledButton(
              onPressed: accept,
              child: Text(
                message
                    ? gitString(context, GitMessages.useMessageAndContinue)
                    : gitString(context, GitMessages.respondPrivately),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void accept() {
    final answer = Uint8List.fromList(utf8.encode(text.text));
    text.clear();
    Navigator.of(context).pop(answer);
  }
}
