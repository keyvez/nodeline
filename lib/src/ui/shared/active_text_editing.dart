import 'package:nodeline/src/ui/canvas/rich_text_editing_controller.dart';
import 'package:flutter/foundation.dart';

/// App-level channel publishing the rich-text controller for the node whose
/// text is currently being edited inline, or null when no node is in edit mode.
///
/// The inline editor (in the canvas data layer) sets this on begin/finish; the
/// toolbar watches it so its font / bold / italic / color controls retarget
/// from "the selected node" to "the live text selection inside the editor".
/// A single shared notifier avoids threading a new bloc through the widget tree
/// just to bridge these two widgets.
final ValueNotifier<RichTextEditingController?> activeTextEditing =
    ValueNotifier<RichTextEditingController?>(null);
