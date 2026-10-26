import 'dart:async';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'host.dart';

final class GitCreationView extends StatefulWidget {
  const GitCreationView({
    super.key,
    required this.client,
    required this.chooseDirectory,
    this.initialize = false,
    this.initialDestination = '',
  });
  final GitWorkflowClient client;
  final Future<String?> Function(BuildContext) chooseDirectory;
  final bool initialize;
  final String initialDestination;
  @override
  State<GitCreationView> createState() => _CreationState();
}

final class _CreationState extends State<GitCreationView> {
  final source = TextEditingController(),
      destination = TextEditingController(),
      branch = TextEditingController();
  GitCancellation? cancellation;
  GitProgress? progress;
  GitCreationOutcome? outcome;
  GitException? error;
  bool running = false, recursive = false;
  @override
  void initState() {
    super.initState();
    destination.text = widget.initialDestination;
  }

  @override
  void dispose() {
    cancellation?.cancel();
    source.dispose();
    destination.dispose();
    branch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) GitFailurePanel(error: error!),
        if (!widget.initialize)
          TextField(
            controller: source,
            enabled: !running,
            decoration: InputDecoration(
              labelText: gitString(
                context,
                'Repository URL or local Git source',
              ),
              hintText: gitString(context, 'HTTPS, SSH, or local path'),
            ),
          ),
        if (!widget.initialize)
          SizedBox(height: GitHostScope.of(context)?.spacing ?? 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: destination,
                enabled: !running,
                decoration: InputDecoration(
                  labelText: widget.initialize
                      ? 'Folder to initialize'
                      : 'Final clone destination',
                ),
              ),
            ),
            TextButton(
              onPressed: running
                  ? null
                  : () async {
                      final value = await widget.chooseDirectory(context);
                      if (mounted && value != null)
                        setState(() => destination.text = value);
                    },
              child: const GitLabel('Choose…'),
            ),
          ],
        ),
        Text(
          widget.initialize
              ? 'Creates Git metadata only. Existing files are not staged or committed.'
              : 'The final destination must be absent or empty. Existing user data is never overwritten.',
        ),
        ExpansionTile(
          title: const GitLabel('Options'),
          children: [
            TextField(
              controller: branch,
              enabled: !running,
              decoration: InputDecoration(
                labelText: widget.initialize
                    ? 'Initial branch · blank uses effective Git policy'
                    : 'Selected branch · optional',
              ),
            ),
            if (!widget.initialize)
              CheckboxListTile(
                dense: true,
                value: recursive,
                title: const GitLabel(
                  'Explicitly initialize/update submodules recursively',
                ),
                onChanged: running
                    ? null
                    : (v) => setState(() => recursive = v!),
              ),
          ],
        ),
        if (running)
          Column(
            children: [
              const LinearProgressIndicator(),
              Text(progress?.text ?? 'Preparing Git operation…'),
            ],
          ),
        if (outcome != null &&
            !{GitOperationPhase.completed}.contains(outcome!.phase))
          Text(
            '${outcome!.createdDirectory ? 'This attempt created' : 'The destination existed before this attempt:'} ${destination.text}\n'
            '${outcome!.destinationStillExists ? 'The directory remains for inspection. Review it before another clone attempt.' : 'No destination directory remains.'}',
          ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: running
                  ? () => cancellation?.cancel()
                  : () => Navigator.of(context).pop(),
              child: Text(running ? 'Cancel process' : 'Cancel'),
            ),
            FilledButton(
              onPressed: running ? null : () => unawaited(start()),
              child: Text(widget.initialize ? 'Initialize' : 'Clone'),
            ),
          ],
        ),
      ],
    ),
  );
  Future<void> start() async {
    final target = destination.text;
    setState(() {
      running = true;
      error = null;
      outcome = null;
    });
    cancellation = GitCancellation();
    try {
      final result = await widget.client.create(
        widget.initialize
            ? InitializeRepository(
                target,
                initialBranch: branch.text.isEmpty ? null : branch.text,
              )
            : CloneRepository(
                source.text,
                target,
                branch: branch.text.isEmpty ? null : branch.text,
                recurseSubmodules: recursive,
              ),
        cancellation: cancellation,
        onProgress: (value) {
          if (mounted) setState(() => progress = value);
        },
      );
      if (!mounted) return;
      setState(() {
        outcome = result;
        error = result.error;
      });
      if (result.phase == GitOperationPhase.completed &&
          result.repository != null) {
        // Close this repository-bound surface before a host changes folders.
        // Its caller opens the result after the presentation future completes.
        gitCompleteSurface(context, result.repository!);
      }
    } on Object catch (failure) {
      if (mounted)
        setState(
          () => error = failure is GitException
              ? failure
              : GitException(
                  GitErrorCode.commandFailed,
                  diagnostic: sanitizeGitDiagnostic('$failure'),
                ),
        );
    } finally {
      if (mounted) setState(() => running = false);
    }
  }
}
