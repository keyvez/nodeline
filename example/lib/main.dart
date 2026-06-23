import 'package:flutter/widgets.dart';
import 'package:nodeline/nodeline.dart';

void main() {
  runApp(const NodelineExampleApp());
}

/// A minimal nodeline example: an infinite canvas with the editing toolbar.
///
/// The [FlowDraw] widget wires up the canvas BLoCs and the app shell, so all
/// you need to do is drop a [FlowDrawCanvas] inside it. The [FlowDrawToolbar]
/// is overlaid on top to provide the shape, arrow, text and drawing tools.
class NodelineExampleApp extends StatelessWidget {
  const NodelineExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const FlowDraw(
      child: Stack(
        children: [
          FlowDrawCanvas(),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: 24),
              // Pass SVG asset paths here to enable the SVG-stamp tool.
              child: FlowDrawToolbar(svgs: []),
            ),
          ),
        ],
      ),
    );
  }
}
