import 'dart:async';

import 'package:nodeline/nodeline.dart';
import 'package:nodeline/src/core/controller/flow_draw_controller.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class FlowDraw extends StatefulWidget {
  final Widget child;
  final FlowDrawController? controller;
  final Function(FlowDrawController)? onControllerCreated;
  final void Function(CanvasState)? onCanvasStateChanged;
  final void Function(SelectionState)? onSelectionStateChanged;
  final void Function(ToolState)? onToolStateChanged;

  const FlowDraw({
    super.key,
    required this.child,
    this.controller,
    this.onCanvasStateChanged,
    this.onSelectionStateChanged,
    this.onToolStateChanged, this.onControllerCreated,
  });

  @override
  State<FlowDraw> createState() => _FlowDrawState();
}

class _FlowDrawState extends State<FlowDraw> {
  late final FlowDrawController _controller;
  bool _didCreateController = false;

  late final CanvasBloc _canvasBloc;
  late final SelectionBloc _selectionBloc;
  late final ToolBloc _toolBloc;

  StreamSubscription? _canvasSub;
  StreamSubscription? _selectionSub;
  StreamSubscription? _toolSub;

  @override
  void initState() {
    super.initState();
    _canvasBloc = CanvasBloc();
    _selectionBloc = SelectionBloc();
    _toolBloc = ToolBloc();

    if (widget.controller == null) {
      _controller = FlowDrawController();
      _didCreateController = true;
    } else {
      _controller = widget.controller!;
    }

    _controller.init(_canvasBloc, _selectionBloc, _toolBloc);

    if (widget.onControllerCreated != null) {
      widget.onControllerCreated!(_controller);
    }

    if (widget.onCanvasStateChanged != null) {
      _canvasSub = _canvasBloc.stream.listen(widget.onCanvasStateChanged);
    }

    if (widget.onSelectionStateChanged != null) {
      _selectionSub = _selectionBloc.stream.listen(
        widget.onSelectionStateChanged,
      );
    }

    if (widget.onToolStateChanged != null) {
      _toolSub = _toolBloc.stream.listen(widget.onToolStateChanged);
    }
  }

  @override
  void dispose() {
    if (_didCreateController) {
      _controller.dispose();
    }
    _canvasSub?.cancel();
    _selectionSub?.cancel();
    _toolSub?.cancel();

    _canvasBloc.close();
    _selectionBloc.close();
    _toolBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _canvasBloc),
        BlocProvider.value(value: _selectionBloc),
        BlocProvider.value(value: _toolBloc),
      ],
      child: ShadcnApp(
        theme: ThemeData(colorScheme: ColorSchemes.darkZinc, radius: 0.7),
        home: material.Scaffold(
          body: DrawerOverlay(child: widget.child),
        ),
      ),
    );
  }
}
