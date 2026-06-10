import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/data/repositories/rust_share_with_user_repository_impl.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_bloc.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/people_with_access_section.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/share_with_user_widget.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:collection/collection.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Mobile "Share with people" sheet. Lists the users a page is shared with and lets
/// a full-access user invite / change access / remove. Reuses the desktop share-tab
/// logic + data layer (ShareTabBloc + RustShareWithUserRepositoryImpl) and the
/// share_tab presentation widgets — only the mobile container is new.
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
          repository: RustShareWithUserRepositoryImpl(),
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
    return BlocBuilder<ShareTabBloc, ShareTabState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator.adaptive()),
          );
        }

        final currentEmail = state.currentUser?.email;
        final myLevel = state.users
            .firstWhereOrNull((u) => u.email == currentEmail)
            ?.accessLevel;
        final isFullAccess = myLevel == ShareAccessLevel.fullAccess;

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: theme.spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              VSpace(theme.spacing.l),
              // Invite by email; only a full-access user may invite.
              ShareWithUserWidget(
                disabled: !isFullAccess,
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
