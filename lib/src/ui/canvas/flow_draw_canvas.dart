import 'package:flow_draw/flow_draw.dart';
import 'package:flow_draw/src/ui/shared/debug_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../ui/nodes/builders.dart';
import 'flow_draw_editor_data_layer.dart';

export 'flow_draw_editor_data_layer.dart' show FlOverlayData;

class FlowDrawCanvas extends StatelessWidget {
  final bool expandToParent;
  final Size? fixedSize;
  final List<FlOverlayData> Function()? overlay;
  final FlNodeHeaderBuilder? headerBuilder;
  final FlNodeBuilder? nodeBuilder;
  final bool debug;

  const FlowDrawCanvas({
    super.key,
    this.expandToParent = true,
    this.fixedSize,
    this.overlay,
    this.headerBuilder,
    this.nodeBuilder,
    this.debug = false,
  });

  @override
  Widget build(BuildContext context) {
    const FlowDrawEditorStyle style = FlowDrawEditorStyle();

    final Widget editor = Container(
      decoration: style.decoration,
      padding: style.padding,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: FlowDrawEditorDataLayer(
              fragmentShader: 'packages/flow_draw/shaders/grid.frag',
              headerBuilder: headerBuilder,
              nodeBuilder: nodeBuilder,
            ),
          ),
          if (overlay != null)
            ...overlay!().map(
              (overlayData) => Positioned(
                top: overlayData.top,
                left: overlayData.left,
                bottom: overlayData.bottom,
                right: overlayData.right,
                child: RepaintBoundary(child: overlayData.child),
              ),
            ),
          // Floating toolbar appears above selected objects
          BlocBuilder<SelectionBloc, SelectionState>(
            builder: (context, selectionState) {
              final allSelected = selectionState.selectedNodeIds
                  .union(selectionState.selectedDrawingObjectIds);
              if (allSelected.isEmpty) return const SizedBox.shrink();

              return BlocBuilder<CanvasBloc, CanvasState>(
                builder: (context, canvasState) {
                  final pos = _computeToolbarPosition(
                    allSelected,
                    canvasState,
                  );
                  if (pos == null) return const SizedBox.shrink();

                  return FloatingToolbar(
                    selectedIds: allSelected,
                    drawingObjects: canvasState.drawingObjects,
                    position: pos,
                    onDelete: () {
                      context.read<CanvasBloc>().add(ObjectsRemoved(
                            nodeIds: selectionState.selectedNodeIds,
                            drawingObjectIds:
                                selectionState.selectedDrawingObjectIds,
                          ));
                      context
                          .read<SelectionBloc>()
                          .add(SelectionCleared());
                    },
                    onDuplicate: () {
                      context.read<CanvasBloc>().add(SelectionDuplicated(
                            selectionState.selectedDrawingObjectIds,
                          ));
                    },
                    onBringToFront: () {
                      context.read<CanvasBloc>().add(
                            ObjectsBroughtToFront(allSelected),
                          );
                    },
                    onSendToBack: () {
                      context.read<CanvasBloc>().add(
                            ObjectsSentToBack(allSelected),
                          );
                    },
                  );
                },
              );
            },
          ),
          if (debug) const DebugInfoWidget(),
        ],
      ),
    );

    if (expandToParent) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: editor,
          );
        },
      );
    } else {
      return BlocBuilder<CanvasBloc, CanvasState>(
        builder: (context, state) {
          return SizedBox(
            width: fixedSize?.width ?? 100,
            height: fixedSize?.height ?? 100,
            child: editor,
          );
        },
      );
    }
  }

  /// Computes the screen position for the floating toolbar based on the
  /// bounding box of all selected drawing objects.
  static Offset? _computeToolbarPosition(
    Set<String> selectedIds,
    CanvasState canvasState,
  ) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity;

    for (final id in selectedIds) {
      final drawObj = canvasState.drawingObjects[id];
      if (drawObj != null) {
        final r = drawObj.rect;
        if (r.left < minX) minX = r.left;
        if (r.top < minY) minY = r.top;
        if (r.right > maxX) maxX = r.right;
      }
      // For nodes, use the offset (position) — size isn't easily available
      // here since it comes from the rendered widget.
      final node = canvasState.nodes[id];
      if (node != null) {
        final pos = node.offset;
        if (pos.dx < minX) minX = pos.dx;
        if (pos.dy < minY) minY = pos.dy;
        if (pos.dx + 200 > maxX) maxX = pos.dx + 200; // estimated width
      }
    }

    if (minX.isInfinite) return null;

    // Transform world coords to screen coords via viewport offset + zoom.
    final centerX = (minX + maxX) / 2;
    final zoom = canvasState.viewportZoom;
    final vp = canvasState.viewportOffset;
    final screenX = (centerX - vp.dx) * zoom;
    final screenY = (minY - vp.dy) * zoom - 10;

    return Offset(screenX - 100, screenY); // offset left to roughly center
  }
}
