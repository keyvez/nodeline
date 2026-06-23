# nodeline example

A minimal example showing how to embed the [`nodeline`](https://pub.dev/packages/nodeline)
infinite-canvas editor in a Flutter app.

```dart
import 'package:flutter/widgets.dart';
import 'package:nodeline/nodeline.dart';

void main() => runApp(const NodelineExampleApp());

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
              child: FlowDrawToolbar(svgs: []),
            ),
          ),
        ],
      ),
    );
  }
}
```

`FlowDraw` provides the canvas BLoCs and app shell; drop a `FlowDrawCanvas`
inside it and overlay a `FlowDrawToolbar` for the editing tools.

## Run

```sh
flutter run -d macos   # or: -d chrome
```
