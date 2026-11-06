import 'package:flutter/widgets.dart';
import 'dismissal.dart';
import 'feature.dart';
import 'host.dart';
import 'messages.dart';
import 'presentation.dart';
import 'session.dart';

/// Canonical sidebar and independent review-tab slots for hosts without a
/// document-tab strip. BusyMark mounts the same sidebar/review surfaces in its
/// existing document shell. There is no alternate Git split/preview layout.
final class GitWorkspace extends StatelessWidget {
  const GitWorkspace({
    super.key,
    required this.session,
    this.onReturn,
    this.trusted = true,
    this.onTrust,
    this.mayCloseReview,
    this.protectMessageDrafts = true,
  });
  final GitSession session;
  final bool trusted;
  final VoidCallback? onTrust;
  final VoidCallback? onReturn;
  final bool protectMessageDrafts;
  final Future<bool> Function()? mayCloseReview;
  @override
  Widget build(BuildContext context) => GitHostScope(
    host: session.host,
    child: ListenableBuilder(
      listenable: session.feature,
      builder: (context, _) {
        final feature = session.feature;
        final content = Row(
          children: [
            Offstage(
              offstage: !feature.sidebarVisible,
              child: ExcludeFocus(
                excluding: !feature.sidebarVisible,
                child: SizedBox(
                  width: gitSidebarMinimumWidth(context),
                  child: Column(
                    children: [
                      Expanded(
                        child: GitFeatureSidebar(
                          controller: feature,
                          active: feature.sidebarVisible,
                          trusted: trusted,
                          onTrust: onTrust,
                          view: feature.view,
                          onSelectView: feature.select,
                          onReview: feature.open,
                          selectedComparison: feature.tabs.active?.comparison,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  if (onReturn != null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: GitButton.icon(
                        onPressed: onReturn,
                        icon: const GitIcon(GitGlyph.back),
                        label: const GitLabel(GitMessages.returnToFiles),
                      ),
                    ),
                  Expanded(
                    child: GitReviewContent(
                      controller: feature,
                      mayClose: mayCloseReview,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        return !protectMessageDrafts
            ? content
            : ListenableBuilder(
                listenable: session,
                builder: (context, _) => GitDraftGuard(
                  host: session.host,
                  canDismiss: !session.hasUnpersistedMessageDrafts,
                  isDismissible: () => !session.hasUnpersistedMessageDrafts,
                  revisionChanges: session,
                  revisionIdentity: () => session.messageDraftRevisions,
                  confirmDiscard: () =>
                      gitMayDismissMessageDrafts(context, () => [session]),
                  child: content,
                ),
              );
      },
    ),
  );
}
