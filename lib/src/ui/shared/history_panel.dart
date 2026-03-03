import 'dart:async';

import 'package:fldraw/fldraw.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class HistoryPanel extends StatefulWidget {
  final FlDrawController controller;

  const HistoryPanel({super.key, required this.controller});

  @override
  State<HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<HistoryPanel> {
  late StreamSubscription<CanvasState> _subscription;
  List<HistoryEntry> _undoHistory = [];
  List<HistoryEntry> _redoHistory = [];

  @override
  void initState() {
    super.initState();
    _undoHistory = widget.controller.canvasState.undoStack;
    _redoHistory = widget.controller.canvasState.redoStack;

    _subscription = widget.controller.canvasStateStream.listen((canvasState) {
      if (!identical(_undoHistory, canvasState.undoStack)) {
        _undoHistory = canvasState.undoStack;
      }
      if (!identical(_redoHistory, canvasState.redoStack)) {
        _redoHistory = canvasState.redoStack;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reversedHistory = _undoHistory.reversed.toList();

    return Theme(
      data: ThemeData(colorScheme: ColorSchemes.darkZinc, radius: 0.7),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  IconButton.outline(
                    icon: const Icon(Icons.undo, size: 16),
                    onPressed: _undoHistory.isEmpty
                        ? null
                        : () => widget.controller.undo(),
                  ),
                  Gap(8),
                  IconButton.outline(
                    icon: const Icon(Icons.redo, size: 16),
                    onPressed: _redoHistory.isEmpty
                        ? null
                        : () => widget.controller.redo(),
                  ),
                ],
              ),
              Gap(16),
              Text(
                'History (${reversedHistory.length} actions)',
              ).base.extraBold,
              Gap(10),
              if (reversedHistory.isEmpty)
                const Expanded(child: Center(child: Text('No actions yet.')))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: reversedHistory.length,
                    itemBuilder: (context, index) {
                      final (state, event) = reversedHistory[index];

                      return Basic(
                        title: Text(event.description),
                        subtitle: Text(
                          'Nodes: ${state.nodes.length}, Objects: ${state.drawingObjects.length}',
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
