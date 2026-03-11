import 'dart:io';
import 'dart:math';

import 'package:flow_draw/flow_draw.dart';
import 'package:flow_draw/src/constants.dart';
import 'package:flow_draw/src/core/utils/renderbox.dart';
import 'package:flow_draw/src/core/utils/snackbar.dart';
import 'package:flow_draw/src/core/utils/svg_exporter.dart';
import 'package:flow_draw/src/gen/assets.gen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide TabItem;
import 'package:uuid/uuid.dart';

import 'custom_tab.dart';

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
                      onToolSelected(index, index == 10 ? context : null),
                  children: [
                    TabItem(
                      index: 10,
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
                    child: Padding(
                      padding: padding,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Assets.icons.arrow.svg(width: 16, color: Colors.white),
                          Positioned(
                            bottom: -10,
                            right: -10,
                            child: Text('V', style: TextStyle(fontSize: 10)),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_isAllowed(EditorTool.square))
                  TabItem(
                    index: EditorTool.square.index,
                    child: Padding(
                      padding: padding,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Assets.icons.square.svg(width: 16, color: Colors.white),
                          Positioned(
                            bottom: -10,
                            right: -10,
                            child: Text('R', style: TextStyle(fontSize: 10)),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_isAllowed(EditorTool.circle))
                  TabItem(
                    index: EditorTool.circle.index,
                    child: Padding(
                      padding: padding,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Assets.icons.circle.svg(width: 16, color: Colors.white),
                          Positioned(
                            bottom: -10,
                            right: -10,
                            child: Text('O', style: TextStyle(fontSize: 10)),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_isAllowed(EditorTool.diamond))
                  TabItem(
                    index: EditorTool.diamond.index,
                    child: Padding(
                      padding: padding,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(Icons.diamond_outlined, size: 16, color: Colors.white),
                          Positioned(
                            bottom: -10,
                            right: -10,
                            child: Text('G', style: TextStyle(fontSize: 10)),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_isAllowed(EditorTool.arrowTopRight))
                  TabItem(
                    index: EditorTool.arrowTopRight.index,
                    child: Padding(
                      padding: padding,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Assets.icons.arrowTopRight.svg(
                            width: 16,
                            color: Colors.white,
                          ),
                          Positioned(
                            bottom: -10,
                            right: -10,
                            child: Text('A', style: TextStyle(fontSize: 10)),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_isAllowed(EditorTool.line))
                  TabItem(
                    index: EditorTool.line.index,
                    child: Padding(
                      padding: padding,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Assets.icons.line.svg(width: 16, color: Colors.white),
                          Positioned(
                            bottom: -10,
                            right: -10,
                            child: Text('L', style: TextStyle(fontSize: 10)),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_isAllowed(EditorTool.pencil))
                  TabItem(
                    index: EditorTool.pencil.index,
                    child: Padding(
                      padding: padding,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Assets.icons.pencil.svg(width: 16, color: Colors.white),
                          Positioned(
                            bottom: -10,
                            right: -10,
                            child: Text('D', style: TextStyle(fontSize: 10)),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_isAllowed(EditorTool.text))
                  TabItem(
                    index: EditorTool.text.index,
                    child: Padding(
                      padding: padding,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Assets.icons.text.svg(width: 16, color: Colors.white),
                          Positioned(
                            bottom: -10,
                          right: -10,
                          child: Text('T', style: TextStyle(fontSize: 10)),
                        ),
                      ],
                    ),
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
                      child: Padding(
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
                  if (_isAllowed(EditorTool.comment))
                    TabItem(
                      index: EditorTool.comment.index,
                      child: Padding(
                        padding: padding,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Assets.icons.comment.svg(
                              width: 16,
                              color: Colors.white,
                            ),
                            Positioned(
                              bottom: -10,
                              right: -10,
                              child: Text('C', style: TextStyle(fontSize: 10)),
                            ),
                          ],
                        ),
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
            Builder(
              builder: (context) {
                return const _MermaidButton();
              },
            ),
            Gap(8),
            const _SvgExportButton(),
            BlocBuilder<CanvasBloc, CanvasState>(
              builder: (context, canvasState) {
                return Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: GhostButton(
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
                    width: 320,
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
        final svg = SvgExporter.export(canvasBloc.state.drawingObjects);
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
  bool _showImport = false;
  final _importController = TextEditingController();

  @override
  void dispose() {
    _importController.dispose();
    super.dispose();
  }

  void _handleExport() {
    final selectedIds = widget.selectionBloc.state.selectedDrawingObjectIds;

    final mermaid = MermaidExporter.export(
      widget.canvasBloc.state.drawingObjects,
      selectedIds: selectedIds.isNotEmpty ? selectedIds : null,
    );

    Clipboard.setData(ClipboardData(text: mermaid));
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
    if (_showImport) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GhostButton(
                density: ButtonDensity.compact,
                onPressed: () => setState(() => _showImport = false),
                child: Icon(Icons.arrow_back, size: 14),
              ),
              const Gap(8),
              Text('Import Mermaid', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const Gap(8),
          TextField(
            controller: _importController,
            placeholder: Text('Paste Mermaid flowchart...'),
            maxLines: 8,
            autofocus: true,
            style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
          const Gap(8),
          PrimaryButton(
            density: ButtonDensity.compact,
            onPressed: _handleImport,
            child: Text('Import'),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GhostButton(
          density: ButtonDensity.compact,
          onPressed: _handleExport,
          child: Row(
            children: [
              Icon(Icons.upload, size: 14),
              const Gap(8),
              Expanded(child: Text('Export to clipboard', style: TextStyle(fontSize: 12))),
            ],
          ),
        ),
        GhostButton(
          density: ButtonDensity.compact,
          onPressed: () => setState(() => _showImport = true),
          child: Row(
            children: [
              Icon(Icons.download, size: 14),
              const Gap(8),
              Expanded(child: Text('Import from Mermaid', style: TextStyle(fontSize: 12))),
            ],
          ),
        ),
      ],
    );
  }
}
