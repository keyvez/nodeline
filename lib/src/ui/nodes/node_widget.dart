import 'package:nodeline/nodeline.dart';
import 'package:nodeline/src/core/utils/platform_info/platform_info.dart';
import 'package:nodeline/src/core/utils/renderbox.dart';
import 'package:nodeline/src/ui/shared/improved_listener.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DefaultNodeWidget extends StatefulWidget {
  final NodeInstance node;
  final FlNodeHeaderBuilder? headerBuilder;
  final FlNodeBuilder? nodeBuilder;

  const DefaultNodeWidget({
    super.key,
    required this.node,
    this.headerBuilder,
    this.nodeBuilder,
  });

  @override
  State<DefaultNodeWidget> createState() => _DefaultNodeWidgetState();
}

class _DefaultNodeWidgetState extends State<DefaultNodeWidget> {
  late CanvasBloc _canvasBloc;
  late SelectionBloc _selectionBloc;

  @override
  void initState() {
    super.initState();
    _canvasBloc = context.read<CanvasBloc>();
    _selectionBloc = context.read<SelectionBloc>();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateBuiltStyles();
  }

  @override
  void didUpdateWidget(DefaultNodeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateBuiltStyles();
  }

  void _updateBuiltStyles() {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    widget.node.builtStyle = widget.node.styleBuilder(widget.node.state, devicePixelRatio: dpr);
    widget.node.builtHeaderStyle = widget.node.headerStyleBuilder(
      widget.node.state,
      devicePixelRatio: dpr,
    );
    widget.node.forceRecompute = false;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons == kPrimaryMouseButton) {
      final platform = PlatformInfoImpl();
      final isCtrlPressed =
          HardwareKeyboard.instance.isControlPressed ||
          (platform.isMacOS && HardwareKeyboard.instance.isMetaPressed);

      if (!widget.node.state.isSelected) {
        if (isCtrlPressed) {
          _selectionBloc.add(SelectionObjectsAdded(nodeIds: {widget.node.id}));
        } else {
          _selectionBloc.add(SelectionReplaced(nodeIds: {widget.node.id}));
        }
      }
    }
  }

  void _showFieldEditorOverlay(
    Offset nodeScreenPosition,
    Size nodeScreenSize, {
    bool isHeading = false,
  }) {
    final overlay = Overlay.of(context);
    final textController = TextEditingController(
      text: isHeading ? widget.node.heading : widget.node.value,
    );
    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) {
        return MultiBlocProvider(
          providers: [
            BlocProvider.value(value: _canvasBloc),
            BlocProvider.value(value: _selectionBloc),
          ],
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    if (isHeading) {
                      _canvasBloc.add(
                        NodeHeadingUpdated(widget.node.id, textController.text),
                      );
                    } else {
                      _canvasBloc.add(
                        NodeValueUpdated(widget.node.id, textController.text),
                      );
                    }
                    overlayEntry?.remove();
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),
              Positioned(
                left: nodeScreenPosition.dx,
                top: nodeScreenPosition.dy,
                width: nodeScreenSize.width,
                height: nodeScreenSize.height,
                child: Material(
                  color: widget.node.builtStyle.decoration.color,
                  borderRadius: widget.node.builtStyle.decoration.borderRadius,
                  child:
                      widget.node.editorBuilder?.call(
                        context,
                        () => overlayEntry?.remove(),
                        widget.node.value,
                        (dynamic data) {
                          if (isHeading) {
                            _canvasBloc.add(
                              NodeHeadingUpdated(widget.node.id, data),
                            );
                          } else {
                            _canvasBloc.add(
                              NodeValueUpdated(widget.node.id, data),
                            );
                          }
                        },
                      ) ??
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: TextFormField(
                            controller: textController,
                            autofocus: true,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                            ),
                            onFieldSubmitted: (value) {
                              if (isHeading) {
                                _canvasBloc.add(
                                  NodeHeadingUpdated(widget.node.id, value),
                                );
                              } else {
                                _canvasBloc.add(
                                  NodeValueUpdated(widget.node.id, value),
                                );
                              }
                              overlayEntry?.remove();
                            },
                          ),
                        ),
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );

    overlay.insert(overlayEntry);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.nodeBuilder != null) {
      return widget.nodeBuilder!(context, widget.node);
    }

    final lodLevel = context.select((CanvasBloc bloc) {
      final zoom = bloc.state.viewportZoom;
      if (zoom > 0.5) {
        return 4;
      } else if (zoom > 0.25) {
        return 3;
      } else if (zoom > 0.125) {
        return 2;
      } else if (zoom > 0.0625) {
        return 1;
      } else {
        return 0;
      }
    });

    return ImprovedListener(
      onPointerPressed: _onPointerDown,
      child: IntrinsicWidth(
        child: Container(
          key: widget.node.key,
          decoration: widget.node.builtStyle.decoration,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onDoubleTapDown: (details) {
                  var values = _getNodePositionAndSize();
                  if (values != null) {
                    _showFieldEditorOverlay(
                      values.$1,
                      values.$2,
                      isHeading: true,
                    );
                  }
                },
                child: widget.headerBuilder != null
                    ? widget.headerBuilder!(
                        context,
                        widget.node,
                        () => _canvasBloc.add(NodeToggled(widget.node.id)),
                      )
                    : _NodeHeaderWidget(
                        lodLevel: lodLevel,
                        nodeDisplayName: widget.node.heading ?? "",
                        style: widget.node.builtHeaderStyle,
                        onToggleCollapse: () =>
                            _canvasBloc.add(NodeToggled(widget.node.id)),
                      ),
              ),
              if (!widget.node.state.isCollapsed)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: GestureDetector(
                      onDoubleTapDown: (details) {
                        var values = _getNodePositionAndSize();
                        if (values != null) {
                          _showFieldEditorOverlay(values.$1, values.$2);
                        }
                      },
                      child:
                          (widget.node.valueBuilder?.call(widget.node.value)) ??
                          (widget.node.value == null
                              ? const SizedBox.shrink()
                              : Text(
                                  '${widget.node.value}',
                                  style: const TextStyle(color: Colors.white),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                )),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  (Offset, Size)? _getNodePositionAndSize() {
    final nodeRenderBox =
        widget.node.key.currentContext?.findRenderObject() as RenderBox?;
    if (nodeRenderBox == null) return null;

    final canvasState = _canvasBloc.state;
    final nodeScreenPosition = worldToScreen(
      widget.node.offset,
      canvasState.viewportOffset,
      canvasState.viewportZoom,
    );
    if (nodeScreenPosition == null) return null;

    final nodeScreenSize = nodeRenderBox.size * canvasState.viewportZoom;
    return (nodeScreenPosition, nodeScreenSize);
  }
}

class _NodeHeaderWidget extends StatelessWidget {
  final int lodLevel;
  final FlNodeHeaderStyle style;
  final String nodeDisplayName;
  final VoidCallback onToggleCollapse;

  const _NodeHeaderWidget({
    required this.lodLevel,
    required this.style,
    required this.nodeDisplayName,
    required this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: style.padding,
      decoration: lodLevel <= 2
          ? style.decoration.copyWith(
              color: style.decoration.color?.withAlpha(255),
              borderRadius: BorderRadius.zero,
            )
          : style.decoration,
      child: Row(
        children: [
          Visibility(
            visible: lodLevel >= 3,
            maintainState: true,
            maintainSize: true,
            maintainAnimation: true,
            child: InkWell(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              onTap: onToggleCollapse,
              child: Icon(style.icon, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              nodeDisplayName,
              style: style.textStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
