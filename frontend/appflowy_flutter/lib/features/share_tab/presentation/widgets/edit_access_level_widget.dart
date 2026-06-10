import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/access_level_list_widget.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/material.dart';
import 'package:universal_platform/universal_platform.dart';

class EditAccessLevelWidget extends StatefulWidget {
  const EditAccessLevelWidget({
    super.key,
    required this.callbacks,
    required this.selectedAccessLevel,
    required this.supportedAccessLevels,
    required this.additionalUserManagementOptions,
    this.disabled = false,
  });

  /// Callbacks
  final AccessLevelListCallbacks callbacks;

  /// The currently selected access level
  final ShareAccessLevel selectedAccessLevel;

  /// Whether the widget is disabled
  final bool disabled;

  /// Supported access levels
  final List<ShareAccessLevel> supportedAccessLevels;

  /// Additional user management options
  final List<AdditionalUserManagementOptions> additionalUserManagementOptions;

  @override
  State<EditAccessLevelWidget> createState() => _EditAccessLevelWidgetState();
}

class _EditAccessLevelWidgetState extends State<EditAccessLevelWidget> {
  final popoverController = AFPopoverController();

  @override
  void dispose() {
    popoverController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    // Mobile: present the access-level list in a bottom sheet (native pattern),
    // not a desktop popover which is cramped/awkward on touch.
    if (UniversalPlatform.isMobile) {
      return AFGhostButton.normal(
        disabled: widget.disabled,
        onTap: () => _showMobileAccessLevelSheet(context),
        padding: EdgeInsets.symmetric(
          vertical: theme.spacing.s,
          horizontal: theme.spacing.l,
        ),
        builder: (context, isHovering, disabled) =>
            _buildButtonChild(context, disabled),
      );
    }

    return AFPopover(
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(), // the access level widget has a border
      controller: popoverController,
      popover: (_) {
        return AccessLevelListWidget(
          selectedAccessLevel: widget.selectedAccessLevel,
          supportedAccessLevels: widget.supportedAccessLevels,
          additionalUserManagementOptions:
              widget.additionalUserManagementOptions,
          callbacks: widget.callbacks.copyWith(
            onSelectAccessLevel: (accessLevel) {
              widget.callbacks.onSelectAccessLevel(accessLevel);

              popoverController.hide();
            },
            onRemoveAccess: () {
              widget.callbacks.onRemoveAccess();

              popoverController.hide();
            },
          ),
        );
      },
      child: AFGhostButton.normal(
        disabled: widget.disabled,
        onTap: () {
          popoverController.show();
        },
        padding: EdgeInsets.symmetric(
          vertical: theme.spacing.s,
          horizontal: theme.spacing.l,
        ),
        builder: (context, isHovering, disabled) =>
            _buildButtonChild(context, disabled),
      ),
    );
  }

  Widget _buildButtonChild(BuildContext context, bool disabled) {
    final theme = AppFlowyTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.selectedAccessLevel.title,
          style: theme.textStyle.body.standard(
            color: disabled
                ? theme.textColorScheme.secondary
                : theme.textColorScheme.primary,
          ),
        ),
        HSpace(theme.spacing.xs),
        FlowySvg(
          FlowySvgs.arrow_down_s,
          color: theme.textColorScheme.secondary,
        ),
      ],
    );
  }

  void _showMobileAccessLevelSheet(BuildContext context) {
    showMobileBottomSheet(
      context,
      showDragHandle: true,
      showDivider: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        return AccessLevelListWidget(
          selectedAccessLevel: widget.selectedAccessLevel,
          supportedAccessLevels: widget.supportedAccessLevels,
          additionalUserManagementOptions:
              widget.additionalUserManagementOptions,
          callbacks: widget.callbacks.copyWith(
            onSelectAccessLevel: (accessLevel) {
              widget.callbacks.onSelectAccessLevel(accessLevel);
              Navigator.of(sheetContext).pop();
            },
            onRemoveAccess: () {
              widget.callbacks.onRemoveAccess();
              Navigator.of(sheetContext).pop();
            },
          ),
        );
      },
    );
  }
}
