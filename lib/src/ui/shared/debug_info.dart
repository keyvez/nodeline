import 'package:flow_draw/flow_draw.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DebugInfoWidget extends StatelessWidget {
  const DebugInfoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, canvasState) {
        return BlocBuilder<SelectionBloc, SelectionState>(
          builder: (context, selectionState) {
            final selectionCount = selectionState.selectedNodeIds.length +
                selectionState.selectedDrawingObjectIds.length;

            return Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8.0),
                color: Colors.black.withOpacity(0.5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'X: ${canvasState.viewportOffset.dx.toStringAsFixed(2)}, Y: ${canvasState.viewportOffset.dy.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.red, fontSize: 14, inherit: false),
                    ),
                    Text(
                      'Zoom: ${canvasState.viewportZoom.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.green, fontSize: 14, inherit: false),
                    ),
                    Text(
                      'Selection: $selectionCount',
                      style: const TextStyle(
                          color: Colors.blue, fontSize: 14, inherit: false),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}