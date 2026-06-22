import 'dart:io';
import 'dart:math';

import 'package:flow_draw/flow_draw.dart';
import 'package:flow_draw/src/constants.dart';
import 'package:flow_draw/src/core/utils/renderbox.dart';
import 'package:flow_draw/src/core/utils/snackbar.dart';
import 'package:flow_draw/src/core/utils/svg_exporter.dart';
import 'package:flow_draw/src/gen/assets.gen.dart';
import 'package:flow_draw/src/ui/canvas/rich_text_editing_controller.dart';
import 'package:flow_draw/src/ui/shared/active_text_editing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide TabItem;
import 'package:uuid/uuid.dart';

import 'custom_tab.dart';

/// The Cmd (macOS) / Ctrl (other) symbol for shortcut hints in tooltips.
final String _kCmdKey = Platform.isMacOS ? '⌘' : 'Ctrl';

/// Wraps [child] in a tooltip showing a [description] and an optional
/// [shortcut] hint (already formatted, e.g. "⇧⌘U"). Used by the toolbar's
/// action buttons so hovering reveals what they do and how to trigger them.
Widget _withHint(
  Widget child, {
  required String description,
  String? shortcut,
}) {
  return Tooltip(
    tooltip: (context) => TooltipContainer(
      // TooltipContainer applies `.primaryForeground()` to its child, so let
      // both lines inherit that contrasting colour. The shortcut is only dimmed
      // via Opacity — hard-coding a colour (e.g. white) made it invisible on
      // the light primary background.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description, style: const TextStyle(fontSize: 11)),
          if (shortcut != null)
            Opacity(
              opacity: 0.7,
              child: Text(shortcut, style: const TextStyle(fontSize: 10)),
            ),
        ],
      ),
    ),
    child: child,
  );
}

/// Standard padding around a tool-tab icon (kept in sync with the `padding`
/// local used by the tab builder).
const EdgeInsets _kToolTabPadding = EdgeInsets.symmetric(vertical: 10.0);

/// Builds a tool-tab's visual: the [icon] with its single-key [keyLabel]
/// shortcut shown small in the corner (e.g. "R" for the rectangle tool).
Widget _toolTabChild(Widget icon, String keyLabel) {
  return Padding(
    padding: _kToolTabPadding,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          bottom: -10,
          right: -10,
          child: Text(keyLabel, style: const TextStyle(fontSize: 10)),
        ),
      ],
    ),
  );
}

class FlowDrawToolbar extends StatelessWidget {
  final List<String> svgs;

  /// When non-null, only these tools are shown in the toolbar.
  /// This enables workflow mode or other restricted palettes.
  final Set<EditorTool>? allowedTools;

  const FlowDrawToolbar({super.key, required this.svgs, this.allowedTools});

  bool _isAllowed(EditorTool tool) => allowedTools == null || allowedTools!.contains(tool);

  @override
  Widget build(BuildContext context) {
    final padding = const EdgeInsets.symmetric(vertical: 10.0);

    final toolBloc = context.watch<ToolBloc>();

    void onToolSelected(int index, BuildContext? popoverContext) {
      final tool = EditorTool.values.elementAt(index);

      if (tool == EditorTool.add) {
        if (popoverContext == null) return;
        _showAddPopover(context);
      } else {
        toolBloc.add(ToolSelected(tool));
      }
    }

    return BlocBuilder<ToolBloc, ToolState>(
      builder: (context, state) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (context) {
                return CustomTabs(
                  index: state.activeTool.index,
                  onChanged: (index) =>
                      onToolSelected(index, index == EditorTool.add.index ? context : null),
                  children: [
                    TabItem(
                      index: EditorTool.add.index,
                      child: SizedBox(
                        child: Padding(
                          padding: padding.copyWith(
                            top: padding.top + 2,
                            bottom: padding.bottom + 2,
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Assets.icons.add.svg(width: 16),
                              Positioned(
                                bottom: -10,
                                right: -10,
                                child: Text(
                                  '/',
                                  style: TextStyle(fontSize: 10),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            Gap(16),
            CustomTabs(
              index: state.activeTool.index,
              onChanged: (index) => onToolSelected(index, null),
              children: [
                if (_isAllowed(EditorTool.arrow))
                  TabItem(
                    index: EditorTool.arrow.index,
                    child: _withHint(
                      description: 'Select / move tool',
                      shortcut: 'V',
                      _toolTabChild(
                          Assets.icons.arrow.svg(
                              width: 16, color: Colors.white),
                          'V'),
                    ),
                  ),
                if (_isAllowed(EditorTool.square))
                  TabItem(
                    index: EditorTool.square.index,
                    child: _withHint(
                      description: 'Rectangle',
                      shortcut: 'R',
                      _toolTabChild(
                          Assets.icons.square.svg(
                              width: 16, color: Colors.white),
                          'R'),
                    ),
                  ),
                if (_isAllowed(EditorTool.circle))
                  TabItem(
                    index: EditorTool.circle.index,
                    child: _withHint(
                      description: 'Ellipse / circle',
                      shortcut: 'O',
                      _toolTabChild(
                          Assets.icons.circle.svg(
                              width: 16, color: Colors.white),
                          'O'),
                    ),
                  ),
                if (_isAllowed(EditorTool.diamond))
                  TabItem(
                    index: EditorTool.diamond.index,
                    child: _withHint(
                      description: 'Diamond',
                      shortcut: 'G',
                      _toolTabChild(
                          const Icon(Icons.diamond_outlined,
                              size: 16, color: Colors.white),
                          'G'),
                    ),
                  ),
                if (_isAllowed(EditorTool.parallelogram))
                  TabItem(
                    index: EditorTool.parallelogram.index,
                    child: _withHint(
                      description: 'Parallelogram',
                      shortcut: 'P',
                      _toolTabChild(
                          Transform.rotate(
                            angle: 1.5708, // 90 degrees
                            child: const Icon(Icons.change_history,
                                size: 16, color: Colors.white),
                          ),
                          'P'),
                    ),
                  ),
                if (_isAllowed(EditorTool.forkJoin))
                  TabItem(
                    index: EditorTool.forkJoin.index,
                    child: _withHint(
                      description: 'Fork / join bar',
                      shortcut: 'J',
                      _toolTabChild(
                          const Icon(Icons.horizontal_rule,
                              size: 16, color: Colors.white),
                          'J'),
                    ),
                  ),
                if (_isAllowed(EditorTool.arrowTopRight))
                  TabItem(
                    index: EditorTool.arrowTopRight.index,
                    child: _withHint(
                      description: 'Arrow (connects shapes)',
                      shortcut: 'A',
                      _toolTabChild(
                          Assets.icons.arrowTopRight.svg(
                              width: 16, color: Colors.white),
                          'A'),
                    ),
                  ),
                if (_isAllowed(EditorTool.line))
                  TabItem(
                    index: EditorTool.line.index,
                    child: _withHint(
                      description: 'Line',
                      shortcut: 'L',
                      _toolTabChild(
                          Assets.icons.line.svg(
                              width: 16, color: Colors.white),
                          'L'),
                    ),
                  ),
                if (_isAllowed(EditorTool.pencil))
                  TabItem(
                    index: EditorTool.pencil.index,
                    child: _withHint(
                      description: 'Pencil (freehand)',
                      shortcut: 'D',
                      _toolTabChild(
                          Assets.icons.pencil.svg(
                              width: 16, color: Colors.white),
                          'D'),
                    ),
                  ),
                if (_isAllowed(EditorTool.text))
                  TabItem(
                    index: EditorTool.text.index,
                    child: _withHint(
                      description: 'Text',
                      shortcut: 'T',
                      _toolTabChild(
                          Assets.icons.text.svg(
                              width: 16, color: Colors.white),
                          'T'),
                    ),
                  ),
              ],
            ),
            if (_isAllowed(EditorTool.figure) || _isAllowed(EditorTool.comment)) ...[
              Gap(16),
              CustomTabs(
                index: state.activeTool.index,
                onChanged: (index) => onToolSelected(index, null),
                children: [
                  if (_isAllowed(EditorTool.figure))
                    TabItem(
                      index: EditorTool.figure.index,
                      child: _withHint(
                        description: 'Figure / SVG shape',
                        shortcut: 'F',
                        Padding(
                          padding: padding.copyWith(
                            top: padding.top + 2,
                            bottom: padding.bottom + 2,
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Assets.icons.figure.svg(width: 16, color: Colors.white),
                              Positioned(
                                bottom: -10,
                                right: -10,
                                child: Text('F', style: TextStyle(fontSize: 10)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_isAllowed(EditorTool.comment))
                    TabItem(
                      index: EditorTool.comment.index,
                      child: _withHint(
                        description: 'Comment pin',
                        shortcut: 'C',
                        _toolTabChild(
                            Assets.icons.comment.svg(
                                width: 16, color: Colors.white),
                            'C'),
                      ),
                    ),
                ],
              ),
            ],
            Gap(16),
            Builder(
              builder: (context) {
                return _LineStyleButton(lineStyle: state.lineStyle, toolBloc: toolBloc);
              },
            ),
            Gap(16),
            const _GlobalFontButton(),
            Gap(16),
            Builder(
              builder: (context) {
                return const _MermaidButton();
              },
            ),
            Gap(8),
            const PromptToWorkflowButton(),
            Gap(8),
            const _SvgExportButton(),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: _withHint(
                description: 'Auto-layout to reduce edge crossings',
                shortcut: '⇧$_kCmdKey L',
                GhostButton(
                  density: ButtonDensity.compact,
                  onPressed: () {
                    context.read<CanvasBloc>().add(const AutoLayoutRequested());
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.auto_awesome_mosaic, size: 16),
                      SizedBox(width: 6),
                      Text('Tidy', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _withHint(
                description:
                    'Distribute selected nodes along a selected guide shape',
                shortcut: '⇧$_kCmdKey U',
                GhostButton(
                  density: ButtonDensity.compact,
                  onPressed: () {
                    context
                        .read<CanvasBloc>()
                        .add(const LayoutAlongGuideRequested());
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.timeline, size: 16),
                      SizedBox(width: 6),
                      Text('Lay on path', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _withHint(
                description:
                    'Swap two selected nodes’ positions, or two edges’ endpoints',
                shortcut: '⇧$_kCmdKey S',
                GhostButton(
                  density: ButtonDensity.compact,
                  onPressed: () {
                    context.read<CanvasBloc>().add(const SwapRequested());
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.swap_horiz, size: 16),
                      SizedBox(width: 6),
                      Text('Swap', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: _FitButton(),
            ),
            BlocBuilder<CanvasBloc, CanvasState>(
              builder: (context, canvasState) {
                return Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: _withHint(
                    description: 'Toggle the alignment grid',
                    GhostButton(
                      density: ButtonDensity.compact,
                      onPressed: () {
                        context.read<CanvasBloc>().add(const GridToggled());
                      },
                      child: Icon(
                        Icons.grid_4x4,
                        size: 16,
                        color: canvasState.showGrid ? Colors.white : Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                );
              },
            ),
            BlocBuilder<SelectionBloc, SelectionState>(
              builder: (context, selectionState) {
                final hasSelection =
                    selectionState.selectedNodeIds.isNotEmpty ||
                    selectionState.selectedDrawingObjectIds.isNotEmpty;
                if (!hasSelection) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      context.read<CanvasBloc>().add(ObjectsRemoved(
                        nodeIds: selectionState.selectedNodeIds,
                        drawingObjectIds:
                            selectionState.selectedDrawingObjectIds,
                      ));
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(Icons.delete, size: 24, color: Colors.red),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showAddPopover(BuildContext context) {
    final canvasBloc = context.read<CanvasBloc>();
    List<String> assets = svgs;
    List<String> filteredAssets = assets;

    showPopover(
      context: context,
      alignment: Alignment.topCenter,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return ModalContainer(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 200),
                child: SizedBox(
                  width: 460,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        placeholder: Text('Search over 2500+ icons...'),
                        autofocus: true,
                        onChanged: (value) {
                          setState(() {
                            filteredAssets = svgs
                                .where(
                                  (e) => e
                                      .split('/')
                                      .last
                                      .split('.')
                                      .first
                                      .toLowerCase()
                                      .contains(value.toLowerCase()),
                                )
                                .toList();
                          });
                        },
                      ),
                      Gap(16),
                      Expanded(
                        child: GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 8,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                          itemCount: filteredAssets.length,
                          itemBuilder: (context, index) => IconButton.outline(
                            onPressed: () {
                              closeOverlay(
                                context,
                                filteredAssets.elementAt(index),
                              );
                            },
                            icon: SvgPicture.asset(filteredAssets[index]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ).withPadding(top: 16);
          },
        );
      },
    ).future.then((value) async {
      if (value != null && value is String) {
        final String svgString = await rootBundle.loadString(value);
        final pictureInfo = await vg.loadPicture(
          SvgStringLoader(svgString),
          null,
        );
        final Size svgSize = pictureInfo.size;

        final canvasState = canvasBloc.state;
        final editorBounds = getEditorBoundsInScreen(kNodeEditorWidgetKey);
        final centerOfScreenWorldPos =
            screenToWorld(
              editorBounds?.center ?? Offset.zero,
              canvasState.viewportOffset,
              canvasState.viewportZoom,
            ) ??
            Offset.zero;

        final initialRect = Rect.fromCenter(
          center: centerOfScreenWorldPos,
          width: svgSize.width.isFinite ? svgSize.width : 100.0,
          height: svgSize.height.isFinite ? svgSize.height : 100.0,
        );

        final newObject = SvgObject(
          id: const Uuid().v4(),
          rect: initialRect,
          assetPath: value,
          pictureInfo: pictureInfo,
        );

        canvasBloc.add(DrawingObjectAdded(newObject));
      }
    });
  }
}

class _LineStyleButton extends StatelessWidget {
  final LineStyle lineStyle;
  final ToolBloc toolBloc;

  const _LineStyleButton({required this.lineStyle, required this.toolBloc});

  void _applyToSelection(BuildContext context, LineStyle style) {
    final canvasBloc = context.read<CanvasBloc>();
    final selectionBloc = context.read<SelectionBloc>();
    final selectedIds = selectionBloc.state.selectedDrawingObjectIds;

    // If objects are selected, apply to them; otherwise apply to all styleable objects
    final targetIds = selectedIds.isNotEmpty
        ? selectedIds
        : canvasBloc.state.drawingObjects.keys.toSet();

    for (final id in targetIds) {
      final obj = canvasBloc.state.drawingObjects[id];
      if (obj == null) continue;
      DrawingObject? updated;
      if (obj is RectangleObject) {
        updated = obj.copyWith(lineStyle: style);
      } else if (obj is CircleObject) {
        updated = obj.copyWith(lineStyle: style);
      } else if (obj is ArrowObject) {
        updated = obj.copyWith(lineStyle: style);
      } else if (obj is LineObject) {
        updated = obj.copyWith(lineStyle: style);
      }
      if (updated != null) {
        canvasBloc.add(DrawingObjectUpdated(updated));
      }
    }
  }

  String _label(LineStyle style) {
    switch (style) {
      case LineStyle.solid: return 'Solid';
      case LineStyle.dashed: return 'Dashed';
      case LineStyle.dotted: return 'Dotted';
      case LineStyle.rough: return 'Rough';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GhostButton(
      density: ButtonDensity.compact,
      onPressed: () {
        showPopover(
          context: context,
          alignment: Alignment.topCenter,
          builder: (popoverContext) {
            return ModalContainer(
              child: SizedBox(
                width: 140,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: LineStyle.values.map((style) {
                    final isActive = style == lineStyle;
                    return GhostButton(
                      density: ButtonDensity.compact,
                      onPressed: () {
                        toolBloc.add(LineStyleSelected(style));
                        // Apply to currently selected objects
                        _applyToSelection(context, style);
                        closeOverlay(popoverContext);
                      },
                      child: Row(
                        children: [
                          SizedBox(
                            width: 40,
                            height: 20,
                            child: CustomPaint(
                              painter: _LineStylePreviewPainter(style),
                            ),
                          ),
                          const Gap(8),
                          Expanded(
                            child: Text(
                              _label(style),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isActive)
                            Icon(Icons.check, size: 14),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ).withPadding(top: 8);
          },
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 16,
            child: CustomPaint(
              painter: _LineStylePreviewPainter(lineStyle),
            ),
          ),
          const Gap(4),
          Icon(Icons.arrow_drop_down, size: 14),
        ],
      ),
    );
  }
}

class _LineStylePreviewPainter extends CustomPainter {
  final LineStyle style;

  _LineStylePreviewPainter(this.style);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final y = size.height / 2;
    final path = Path()
      ..moveTo(0, y)
      ..lineTo(size.width, y);

    switch (style) {
      case LineStyle.solid:
        canvas.drawPath(path, paint);
        break;
      case LineStyle.dashed:
        const dashWidth = 5.0;
        const dashSpace = 3.0;
        double x = 0;
        while (x < size.width) {
          final end = min(x + dashWidth, size.width);
          canvas.drawLine(Offset(x, y), Offset(end, y), paint);
          x = end + dashSpace;
        }
        break;
      case LineStyle.dotted:
        const spacing = 4.0;
        const radius = 1.0;
        final dotPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        double x = 0;
        while (x < size.width) {
          canvas.drawCircle(Offset(x, y), radius, dotPaint);
          x += spacing;
        }
        break;
      case LineStyle.rough:
        final rng = Random(42);
        const step = 3.0;
        final points = <Offset>[];
        double x = 0;
        while (x < size.width) {
          final offset = (rng.nextDouble() - 0.5) * 0.6;
          points.add(Offset(x, y + offset));
          x += step;
        }
        points.add(Offset(size.width, y));
        if (points.length >= 2) {
          final roughPath = Path()..moveTo(points[0].dx, points[0].dy);
          for (int i = 0; i < points.length - 1; i++) {
            final p0 = points[i];
            final p1 = points[i + 1];
            roughPath.quadraticBezierTo(p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
          }
          roughPath.lineTo(points.last.dx, points.last.dy);
          canvas.drawPath(roughPath, paint);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(_LineStylePreviewPainter oldDelegate) => oldDelegate.style != style;
}

/// Toolbar control for the global default font (family + size).
///
/// Changing it re-fonts every shape whose font has not been individually
/// customized (via the floating selection toolbar). Customized shapes keep
/// their own font until reset.
/// "Fit to content" button. Clicking the label fits immediately using the
/// current margin; the caret opens a popover to adjust the margin. Fits the
/// selected shapes if any, otherwise every text-bearing shape.
class _FitButton extends StatefulWidget {
  const _FitButton();

  @override
  State<_FitButton> createState() => _FitButtonState();
}

class _FitButtonState extends State<_FitButton> {
  // Remembered between clicks so the chosen margin sticks for the session.
  double _margin = kDefaultFitMargin;

  void _fit(BuildContext context) {
    final selected =
        context.read<SelectionBloc>().state.selectedDrawingObjectIds;
    context
        .read<CanvasBloc>()
        .add(NodesFittedToContent(selected, margin: _margin));
  }

  void _openMarginPopover(BuildContext context) {
    showPopover(
      context: context,
      alignment: Alignment.topCenter,
      builder: (popoverContext) {
        return ModalContainer(
          child: SizedBox(
            width: 200,
            child: StatefulBuilder(
              builder: (context, setLocal) {
                void update(double v) {
                  setState(() => _margin = v.clamp(0, 80));
                  setLocal(() {});
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Fit margin',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const Gap(8),
                    Row(
                      children: [
                        const Text('Margin', style: TextStyle(fontSize: 12)),
                        const Spacer(),
                        _StepButton(
                            icon: Icons.remove,
                            onTap: () => update(_margin - 2)),
                        SizedBox(
                          width: 36,
                          child: Text('${_margin.round()}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 13)),
                        ),
                        _StepButton(
                            icon: Icons.add, onTap: () => update(_margin + 2)),
                      ],
                    ),
                    const Gap(8),
                    PrimaryButton(
                      density: ButtonDensity.compact,
                      onPressed: () {
                        _fit(context);
                        closePopover(popoverContext);
                      },
                      child: const Text('Fit now', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                );
              },
            ),
          ),
        ).withPadding(top: 8);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GhostButton(
      density: ButtonDensity.compact,
      onPressed: () => _fit(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fit_screen, size: 16),
          const SizedBox(width: 6),
          const Text('Fit', style: TextStyle(fontSize: 12)),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openMarginPopover(context),
            child: const Padding(
              padding: EdgeInsets.only(left: 2),
              child: Icon(Icons.arrow_drop_down, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlobalFontButton extends StatelessWidget {
  const _GlobalFontButton();

  /// Resolves the font shown for the currently-selected shapes: whether any
  /// carry text, the effective family/size of the first such shape, and whether
  /// the selection has been individually customized.
  ({bool hasText, String family, double size, bool customized})
      _selectionFont(Set<String> ids, CanvasState state) {
    bool hasText = false;
    bool customized = false;
    String family = state.defaultFontFamily;
    double size = state.defaultFontSize;
    bool gotFirst = false;

    for (final id in ids) {
      final obj = state.drawingObjects[id];
      TextStyle? style;
      bool objCustomized = false;
      if (obj is RectangleObject) {
        style = obj.textStyle;
        objCustomized = obj.fontCustomized;
      } else if (obj is CircleObject) {
        style = obj.textStyle;
        objCustomized = obj.fontCustomized;
      } else if (obj is DiamondObject) {
        style = obj.textStyle;
        objCustomized = obj.fontCustomized;
      } else if (obj is ParallelogramObject) {
        style = obj.textStyle;
        objCustomized = obj.fontCustomized;
      } else if (obj is TextObject) {
        // A text box owns its font explicitly (no global-default fallback).
        style = obj.style;
        objCustomized = true;
      } else {
        continue;
      }

      hasText = true;
      if (objCustomized) customized = true;
      if (!gotFirst) {
        gotFirst = true;
        final resolved = effectiveShapeTextStyle(
          style: style,
          customized: objCustomized,
          defaultFamily: state.defaultFontFamily,
          defaultSize: state.defaultFontSize,
        );
        family = resolved.fontFamily ?? state.defaultFontFamily;
        size = resolved.fontSize ?? state.defaultFontSize;
      }
    }
    return (hasText: hasText, family: family, size: size, customized: customized);
  }

  @override
  Widget build(BuildContext context) {
    // While a node's text is being edited inline, the control retargets the
    // live text selection inside that node (so styling applies per-character).
    return ValueListenableBuilder<RichTextEditingController?>(
      valueListenable: activeTextEditing,
      builder: (context, activeController, _) {
        if (activeController != null) {
          return _RichFontButton(controller: activeController);
        }
        return _buildShapeOrGlobal(context);
      },
    );
  }

  Widget _buildShapeOrGlobal(BuildContext context) {
    // Rebuild on selection OR global-font changes so the button label and the
    // seeded popup values always reflect what would be edited.
    return BlocBuilder<SelectionBloc, SelectionState>(
      builder: (context, selection) {
        return BlocBuilder<CanvasBloc, CanvasState>(
          buildWhen: (a, b) =>
              a.defaultFontFamily != b.defaultFontFamily ||
              a.defaultFontSize != b.defaultFontSize ||
              a.drawingObjects != b.drawingObjects,
          builder: (context, state) {
            // Selected shapes that carry text become the edit target; if none
            // are selected (or none have text), the control edits the global
            // default instead.
            final selectedTextIds = selection.selectedDrawingObjectIds;
            final sel = _selectionFont(selectedTextIds, state);
            final editingSelection = sel.hasText;

            final family = editingSelection ? sel.family : state.defaultFontFamily;
            final size = editingSelection ? sel.size : state.defaultFontSize;

            return GhostButton(
              density: ButtonDensity.compact,
              onPressed: () {
                final canvasBloc = context.read<CanvasBloc>();
                showPopover(
                  context: context,
                  alignment: Alignment.topCenter,
                  builder: (popoverContext) {
                    return ModalContainer(
                      child: SizedBox(
                        width: 220,
                        child: _FontControls(
                          editingSelection: editingSelection,
                          customized: sel.customized,
                          family: family,
                          size: size,
                          onChanged: (f, s) {
                            if (editingSelection) {
                              // Edit only the selected shapes; marks them
                              // customized so global changes no longer touch them.
                              canvasBloc.add(ObjectFontChanged(
                                selectedTextIds,
                                fontFamily: f,
                                fontSize: s,
                              ));
                            } else {
                              canvasBloc.add(GlobalFontChanged(
                                fontFamily: f,
                                fontSize: s,
                              ));
                            }
                          },
                          onReset: editingSelection && sel.customized
                              ? () => canvasBloc
                                  .add(ObjectFontReset(selectedTextIds))
                              : null,
                        ),
                      ),
                    ).withPadding(top: 8);
                  },
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    editingSelection ? Icons.title : Icons.text_fields,
                    size: 16,
                  ),
                  const Gap(4),
                  Text(
                    '$family ${size.round()}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Font control shown while a node's text is being edited inline. Targets the
/// live text selection inside [controller], so family/size/bold/italic/color
/// apply per-character. Rebuilds on the controller's selection/style changes so
/// the displayed values track the caret.
class _RichFontButton extends StatelessWidget {
  final RichTextEditingController controller;
  const _RichFontButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final sel = controller.selectionStyle();
        final family = sel.fontFamily ?? '—';
        final sizeLabel = sel.fontSize != null ? sel.fontSize!.round().toString() : '—';
        final bold = sel.bold ?? false;
        final italic = sel.italic ?? false;

        void openPopover() {
          showPopover(
            context: context,
            alignment: Alignment.topCenter,
            builder: (popoverContext) {
              return ModalContainer(
                child: SizedBox(
                  width: 240,
                  child: _FontControls(
                    editingSelection: true,
                    customized: false,
                    family: sel.fontFamily ?? kEditorDefaultFontFamily,
                    size: sel.fontSize ?? kEditorDefaultFontSize,
                    // Rich mode: route family/size to the live selection.
                    onChanged: (f, s) {
                      controller.applyToSelection(
                        fontFamily: Attr.set(f),
                        fontSize: Attr.set(s),
                      );
                    },
                    // Extra rich-text attributes (only present in this mode).
                    richController: controller,
                    selBold: sel.bold,
                    selItalic: sel.italic,
                    selColor: sel.color,
                  ),
                ),
              ).withPadding(top: 8);
            },
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GhostButton(
              density: ButtonDensity.compact,
              onPressed: openPopover,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.text_format, size: 16),
                  const Gap(4),
                  Text('$family $sizeLabel',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            _FormatToggle(
              icon: Icons.format_bold,
              active: bold,
              onTap: () => controller.applyToSelection(bold: Attr.set(!bold)),
            ),
            _FormatToggle(
              icon: Icons.format_italic,
              active: italic,
              onTap: () =>
                  controller.applyToSelection(italic: Attr.set(!italic)),
            ),
          ],
        );
      },
    );
  }
}

/// A compact toggle button for bold/italic in the inline format bar.
class _FormatToggle extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _FormatToggle(
      {required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: active ? const Color(0x3DFFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 16),
      ),
    );
  }
}

/// Reusable family-picker + size-stepper used by both the global font control
/// and the per-node floating-toolbar control. [onChanged] reports the full
/// desired (family, size) on every interaction.
class _FontControls extends StatefulWidget {
  final String family;
  final double size;
  final void Function(String family, double size) onChanged;

  /// True when this control is editing the selected shapes (vs the global
  /// default) — changes the header so the user knows the scope.
  final bool editingSelection;

  /// Whether the selection is already individually customized (enables Reset).
  final bool customized;

  /// Clears the per-shape override so the selection follows the global default.
  final VoidCallback? onReset;

  /// When non-null, the popover is editing live rich text: bold/italic/color
  /// rows are shown and applied to the controller's current selection.
  final RichTextEditingController? richController;

  /// Current selection's bold/italic/color (null = mixed), for rich mode.
  final bool? selBold;
  final bool? selItalic;
  final int? selColor;

  const _FontControls({
    required this.family,
    required this.size,
    required this.onChanged,
    this.editingSelection = false,
    this.customized = false,
    this.onReset,
    this.richController,
    this.selBold,
    this.selItalic,
    this.selColor,
  });

  @override
  State<_FontControls> createState() => _FontControlsState();
}

class _FontControlsState extends State<_FontControls> {
  late String _family = widget.family;
  late double _size = widget.size;

  static const double _minSize = 6;
  static const double _maxSize = 96;

  void _emit() => widget.onChanged(_family, _size);

  /// Whether [preset] matches the current family + size.
  bool _isActivePreset(TextStylePreset preset) =>
      preset.family == _family && (preset.size - _size).abs() < 0.5;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 440),
      child: SingleChildScrollView(
        child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.editingSelection ? 'Font (selected)' : 'Font (all)',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const Gap(8),
        // Text-style presets (Title / Heading 1 / … / Leaf node), Docs-style.
        Text('Text style',
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
        const Gap(2),
        for (final p in kTextStylePresets)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                _family = p.family;
                _size = p.size;
              });
              _emit();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    _isActivePreset(p) ? Icons.check : Icons.text_fields,
                    size: 14,
                    color: _isActivePreset(p)
                        ? null
                        : Colors.white.withValues(alpha: 0.35),
                  ),
                  const Gap(8),
                  Expanded(
                    child: Text(
                      p.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: p.family,
                        fontSize: p.size.clamp(11, 18).toDouble(),
                      ),
                    ),
                  ),
                  Text('${p.size.round()}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.white.withValues(alpha: 0.35))),
                ],
              ),
            ),
          ),
        const Gap(8),
        Text('Font',
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
        const Gap(2),
        // Family choices.
        for (final family in kEditorFontFamilies)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _family = family);
              _emit();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    family == _family
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 16,
                  ),
                  const Gap(8),
                  Text(
                    family,
                    style: TextStyle(fontSize: 13, fontFamily: family),
                  ),
                ],
              ),
            ),
          ),
        const Gap(8),
        // Size stepper.
        Row(
          children: [
            const Text('Size', style: TextStyle(fontSize: 12)),
            const Spacer(),
            _StepButton(
              icon: Icons.remove,
              onTap: () {
                setState(() => _size = (_size - 1).clamp(_minSize, _maxSize));
                _emit();
              },
            ),
            SizedBox(
              width: 36,
              child: Text(
                '${_size.round()}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            _StepButton(
              icon: Icons.add,
              onTap: () {
                setState(() => _size = (_size + 1).clamp(_minSize, _maxSize));
                _emit();
              },
            ),
          ],
        ),
        if (widget.richController != null) ..._richFormatRows(),
        if (widget.editingSelection && widget.customized && widget.onReset != null) ...[
          const Gap(8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onReset,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.restart_alt, size: 16),
                  Gap(8),
                  Text('Reset to default', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ],
        ),
      ),
    );
  }

  /// Bold/italic toggles + a small color palette, shown only in rich-text mode.
  /// These act immediately on the controller's current selection.
  static const List<Color> _textColors = [
    Colors.white,
    Colors.black,
    Color(0xFFE53935), // red
    Color(0xFFFB8C00), // orange
    Color(0xFFFDD835), // yellow
    Color(0xFF43A047), // green
    Color(0xFF1E88E5), // blue
    Color(0xFF8E24AA), // purple
  ];

  List<Widget> _richFormatRows() {
    final c = widget.richController!;
    final bold = widget.selBold ?? false;
    final italic = widget.selItalic ?? false;
    return [
      const Gap(12),
      const Text('Format',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      const Gap(8),
      Row(
        children: [
          _FormatToggle(
            icon: Icons.format_bold,
            active: bold,
            onTap: () => c.applyToSelection(bold: Attr.set(!bold)),
          ),
          const Gap(4),
          _FormatToggle(
            icon: Icons.format_italic,
            active: italic,
            onTap: () => c.applyToSelection(italic: Attr.set(!italic)),
          ),
        ],
      ),
      const Gap(10),
      const Text('Color', style: TextStyle(fontSize: 12)),
      const Gap(6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final color in _textColors)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  c.applyToSelection(color: Attr.set(color.value)),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.selColor == color.value
                        ? const Color(0xFF448AFF)
                        : const Color(0x4DFFFFFF),
                    width: widget.selColor == color.value ? 2 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    ];
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16),
      ),
    );
  }
}

class _MermaidButton extends StatelessWidget {
  const _MermaidButton();

  @override
  Widget build(BuildContext context) {
    return GhostButton(
      density: ButtonDensity.compact,
      onPressed: () {
        // Capture blocs before opening popover (popover context won't have them)
        final canvasBloc = context.read<CanvasBloc>();
        final selectionBloc = context.read<SelectionBloc>();

        showPopover(
          context: context,
          alignment: Alignment.topCenter,
          builder: (popoverContext) {
            return StatefulBuilder(
              builder: (context, setState) {
                return ModalContainer(
                  child: SizedBox(
                    width: 380,
                    child: _MermaidPopoverContent(
                      popoverContext: popoverContext,
                      canvasBloc: canvasBloc,
                      selectionBloc: selectionBloc,
                    ),
                  ),
                ).withPadding(top: 8);
              },
            );
          },
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.code, size: 16),
          const Gap(4),
          Text('Mermaid', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _SvgExportButton extends StatelessWidget {
  const _SvgExportButton();

  @override
  Widget build(BuildContext context) {
    return GhostButton(
      density: ButtonDensity.compact,
      onPressed: () async {
        final canvasBloc = context.read<CanvasBloc>();
        final svg = SvgExporter.export(
          canvasBloc.state.drawingObjects,
          defaultFontFamily: canvasBloc.state.defaultFontFamily,
          defaultFontSize: canvasBloc.state.defaultFontSize,
        );
        if (svg.isEmpty) {
          showNodeEditorSnackbar('Nothing to export', SnackbarType.error);
          return;
        }
        try {
          final tempDir = Directory.systemTemp;
          final file = File('${tempDir.path}/fldraw_export.svg');
          await file.writeAsString(svg);

          if (Platform.isMacOS) {
            await Process.run('open', [file.path]);
          } else if (Platform.isLinux) {
            await Process.run('xdg-open', [file.path]);
          } else if (Platform.isWindows) {
            await Process.run('cmd', ['/c', 'start', '', file.path]);
          }
          showNodeEditorSnackbar('SVG opened in viewer', SnackbarType.success);
        } catch (e) {
          showNodeEditorSnackbar('Failed to open SVG: $e', SnackbarType.error);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image, size: 16),
          const Gap(4),
          Text('SVG', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _MermaidPopoverContent extends StatefulWidget {
  final BuildContext popoverContext;
  final CanvasBloc canvasBloc;
  final SelectionBloc selectionBloc;

  const _MermaidPopoverContent({
    required this.popoverContext,
    required this.canvasBloc,
    required this.selectionBloc,
  });

  @override
  State<_MermaidPopoverContent> createState() => _MermaidPopoverContentState();
}

class _MermaidPopoverContentState extends State<_MermaidPopoverContent> {
  bool _showExport = false;
  final _importController = TextEditingController();
  final _exportController = TextEditingController();

  @override
  void dispose() {
    _importController.dispose();
    _exportController.dispose();
    super.dispose();
  }

  void _handleExport() {
    final selectedIds = widget.selectionBloc.state.selectedDrawingObjectIds;
    final mermaid = MermaidExporter.export(
      widget.canvasBloc.state.drawingObjects,
      selectedIds: selectedIds.isNotEmpty ? selectedIds : null,
    );
    setState(() {
      _exportController.text = mermaid;
      _showExport = true;
    });
  }

  void _handleCopyExport() {
    Clipboard.setData(ClipboardData(text: _exportController.text));
    closeOverlay(widget.popoverContext);
    showNodeEditorSnackbar('Mermaid copied to clipboard', SnackbarType.success);
  }

  void _handleImport() {
    final text = _importController.text.trim();
    if (text.isEmpty) return;

    try {
      final projectData = MermaidImporter.import(text);
      widget.canvasBloc.add(ProjectLoaded(projectData));
      closeOverlay(widget.popoverContext);
      showNodeEditorSnackbar('Mermaid diagram imported', SnackbarType.success);
    } catch (e) {
      showNodeEditorSnackbar('Failed to import: $e', SnackbarType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showExport) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GhostButton(
                density: ButtonDensity.compact,
                onPressed: () => setState(() => _showExport = false),
                child: Icon(Icons.arrow_back, size: 14),
              ),
              const Gap(8),
              Text('Export as Mermaid', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const Gap(8),
          TextField(
            controller: _exportController,
            maxLines: 8,
            readOnly: true,
            style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
          const Gap(8),
          PrimaryButton(
            density: ButtonDensity.compact,
            onPressed: _handleCopyExport,
            child: Text('Copy to clipboard'),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Paste Mermaid diagram',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const Gap(4),
        Text(
          'Supports flowchart (graph) syntax',
          style: TextStyle(fontSize: 11, color: Color(0x8AFFFFFF)),
        ),
        const Gap(8),
        TextField(
          key: const ValueKey('mermaid_import_field'),
          controller: _importController,
          placeholder: Text('graph TD\n  A[Start] --> B[End]'),
          maxLines: 8,
          autofocus: true,
          style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
        const Gap(8),
        PrimaryButton(
          density: ButtonDensity.compact,
          onPressed: _handleImport,
          child: Text('Render diagram'),
        ),
        const Gap(4),
        GhostButton(
          density: ButtonDensity.compact,
          onPressed: _handleExport,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.upload, size: 14),
              const Gap(6),
              Text('Export current diagram', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
