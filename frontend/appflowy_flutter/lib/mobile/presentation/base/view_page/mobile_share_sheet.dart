import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/data/repositories/object_grant_share_repository_impl.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_bloc.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/people_with_access_section.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/share_with_user_widget.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Mobile "Share with people" sheet. Lists the users a page is shared with and lets
/// the user invite / change access / remove. Reuses the share-tab bloc + presentation
/// widgets, but backs them with [ObjectGrantShareRepository] (the team RBAC
/// object-grant API) so sharing works on the OSS self-hosted cloud, which doesn't
/// support AppFlowy's built-in guest-editor share.
void showMobileSharePeopleSheet(
  BuildContext context, {
  required ViewPB view,
  required String workspaceId,
}) {
  if (workspaceId.isEmpty) {
    return;
  }
  showMobileBottomSheet(
    context,
    showDragHandle: true,
    showDivider: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) {
      return BlocProvider(
        create: (_) => ShareTabBloc(
          repository: ObjectGrantShareRepository(workspaceId: workspaceId),
          pageId: view.id,
          workspaceId: workspaceId,
        )..add(ShareTabEvent.initialize()),
        child: const _MobileSharePeopleBody(),
      );
    },
  );
}

class _MobileSharePeopleBody extends StatelessWidget {
  const _MobileSharePeopleBody();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return BlocConsumer<ShareTabBloc, ShareTabState>(
      listenWhen: (prev, curr) =>
          prev.shareResult != curr.shareResult ||
          prev.removeResult != curr.removeResult ||
          prev.updateAccessLevelResult != curr.updateAccessLevelResult,
      listener: (context, state) {
        // Surface invite/remove/update outcomes (incl. backend errors like the
        // self-hosted cloud not supporting guest editors) instead of failing silently.
        void toast(result, String successMsg) {
          result?.fold(
            (_) => showToastNotification(message: successMsg),
            (error) => showToastNotification(
              message: error.msg,
              type: ToastificationType.error,
            ),
          );
        }

        toast(state.shareResult, 'Invitation sent');
        toast(state.removeResult, 'Access removed');
        toast(state.updateAccessLevelResult, 'Access updated');
      },
      builder: (context, state) {
        if (state.isLoading) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator.adaptive()),
          );
        }

        final currentEmail = state.currentUser?.email;

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: theme.spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              VSpace(theme.spacing.l),
              // Invite by email. The server enforces the object.manage permission,
              // so the field is always enabled.
              ShareWithUserWidget(
                onInvite: (emails) => context.read<ShareTabBloc>().add(
                      ShareTabEvent.inviteUsers(
                        emails: emails,
                        accessLevel: ShareAccessLevel.readOnly,
                      ),
                    ),
              ),
              if (state.users.isNotEmpty) ...[
                VSpace(theme.spacing.l),
                PeopleWithAccessSection(
                  isInPublicPage:
                      state.sectionType == SharedSectionType.public,
                  currentUserEmail: currentEmail ?? '',
                  users: state.users,
                  callbacks: PeopleWithAccessSectionCallbacks(
                    onSelectAccessLevel: (user, level) =>
                        context.read<ShareTabBloc>().add(
                              ShareTabEvent.updateUserAccessLevel(
                                email: user.email,
                                accessLevel: level,
                              ),
                            ),
                    onTurnIntoMember: (user) => context.read<ShareTabBloc>().add(
                          ShareTabEvent.convertToMember(email: user.email),
                        ),
                    onRemoveAccess: (user) => context.read<ShareTabBloc>().add(
                          ShareTabEvent.removeUsers(emails: [user.email]),
                        ),
                  ),
                ),
              ],
              VSpace(theme.spacing.xl),
            ],
          ),
        );
      },
    );
  }
}
