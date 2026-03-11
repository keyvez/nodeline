import 'package:flutter/material.dart';

/// Represents an action the user can trigger from the right-click context menu.
enum CanvasContextMenuAction {
  cut,
  copy,
  paste,
  delete,
  selectAll,
  duplicate,
  bringForward,
  sendBackward,
  bringToFront,
  sendToBack,
  alignLeft,
  alignCenterH,
  alignRight,
  alignTop,
  alignCenterV,
  alignBottom,
  distributeHorizontal,
  distributeVertical,
}

/// Shows a right-click context menu for the canvas at the given screen
/// [position].
///
/// [hasSelection] -- whether any objects are currently selected.
/// [selectedCount] -- the number of selected drawing objects (used to
///   conditionally show alignment / distribution items).
/// [onAction] -- callback invoked with the chosen action.
///
/// The menu adapts its items based on the current selection state:
///   - Cut / Copy / Paste / Delete are always shown but Cut, Copy and Delete
///     are disabled when nothing is selected.
///   - Select All is always available.
///   - Duplicate, Bring to Front, Send to Back, etc. require a selection.
///   - Alignment items appear only when >= 2 objects are selected.
///   - Distribution items appear only when >= 3 objects are selected.
Future<void> showCanvasContextMenu({
  required BuildContext context,
  required Offset position,
  required bool hasSelection,
  required int selectedCount,
  required ValueChanged<CanvasContextMenuAction> onAction,
}) async {
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox;

  final result = await showMenu<CanvasContextMenuAction>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      overlay.size.width - position.dx,
      overlay.size.height - position.dy,
    ),
    color: Theme.of(context).colorScheme.surfaceContainer,
    items: _buildContextMenuItems(
      hasSelection: hasSelection,
      selectedCount: selectedCount,
    ),
  );

  if (result != null) {
    onAction(result);
  }
}

List<PopupMenuEntry<CanvasContextMenuAction>> _buildContextMenuItems({
  required bool hasSelection,
  required int selectedCount,
}) {
  return [
    _item(CanvasContextMenuAction.cut, 'Cut', enabled: hasSelection),
    _item(CanvasContextMenuAction.copy, 'Copy', enabled: hasSelection),
    _item(CanvasContextMenuAction.paste, 'Paste'),
    const PopupMenuDivider(),
    _item(CanvasContextMenuAction.selectAll, 'Select All'),
    const PopupMenuDivider(),
    if (hasSelection) ...[
      _item(CanvasContextMenuAction.duplicate, 'Duplicate'),
      const PopupMenuDivider(),
    ],
    if (selectedCount >= 2) ...[
      _item(CanvasContextMenuAction.alignLeft, 'Align Left'),
      _item(CanvasContextMenuAction.alignCenterH, 'Align Center'),
      _item(CanvasContextMenuAction.alignRight, 'Align Right'),
      _item(CanvasContextMenuAction.alignTop, 'Align Top'),
      _item(CanvasContextMenuAction.alignCenterV, 'Align Middle'),
      _item(CanvasContextMenuAction.alignBottom, 'Align Bottom'),
      const PopupMenuDivider(),
    ],
    if (selectedCount >= 3) ...[
      _item(
          CanvasContextMenuAction.distributeHorizontal,
          'Distribute Horizontally'),
      _item(
          CanvasContextMenuAction.distributeVertical,
          'Distribute Vertically'),
      const PopupMenuDivider(),
    ],
    if (hasSelection) ...[
      _item(CanvasContextMenuAction.bringForward, 'Bring Forward'),
      _item(CanvasContextMenuAction.sendBackward, 'Send Backward'),
      _item(CanvasContextMenuAction.bringToFront, 'Bring to Front'),
      _item(CanvasContextMenuAction.sendToBack, 'Send to Back'),
      const PopupMenuDivider(),
    ],
    _item(
      CanvasContextMenuAction.delete,
      'Delete',
      enabled: hasSelection,
      textStyle: const TextStyle(color: Colors.red),
    ),
  ];
}

PopupMenuItem<CanvasContextMenuAction> _item(
  CanvasContextMenuAction value,
  String label, {
  bool enabled = true,
  TextStyle? textStyle,
}) {
  return PopupMenuItem<CanvasContextMenuAction>(
    value: value,
    enabled: enabled,
    child: Text(label, style: textStyle),
  );
}
