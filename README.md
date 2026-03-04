# flow_draw

[![Pub Version](https://img.shields.io/pub/v/flow_draw.svg)](https://pub.dev/packages/flow_draw)
[![Project Status: Alpha](https://img.shields.io/badge/status-alpha-orange.svg)](https://github.com/flow-draw/flow_draw#-project-status-alpha)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub Stars](https://img.shields.io/github/stars/flow-draw/flow_draw.svg)](https://github.com/flow-draw/flow_draw/stargazers)
[![GitHub Issues](https://img.shields.io/github/issues/flow-draw/flow_draw.svg)](https://github.com/flow-draw/flow_draw/issues)
[![GitHub Forks](https://img.shields.io/github/forks/flow-draw/flow_draw.svg)](https://github.com/flow-draw/flow_draw/network/members)

A powerful, extensible, and high-performance infinite canvas and diagramming library for Flutter, inspired by [tldraw](https://www.tldraw.com/) and [eraser.io](https://www.eraser.io)

`flow_draw` provides a complete toolkit for building applications that require node-based editors, whiteboarding, or any kind of interactive canvas. It's built from the ground up with performance and customization in mind, using a custom rendering pipeline to ensure a smooth experience even with a large number of objects.

<p align="center">
  <img src="https://i.ibb.co/tMn7pHjb/Build-using-Flutter.png" alt="Build using Flutter" width="450"/>
</p>

---

## ✨ Features

- **Infinite Canvas**: Pan and zoom on a limitless canvas.
- **Rich Toolset**: Pre-built tools for selection, shapes (rectangles, circles), arrows, lines, free-hand drawing, text, and figures.
- **Node-Based System**: Create complex nodes with custom headers, content, and editable fields.
- **Smart Attachments**: Arrows intelligently snap and attach to the borders of nodes and shapes.
- **High Performance**: Built on a custom `RenderObject` for efficient rendering and smooth interaction.
- **State Management with BLoC**: A clear and predictable state management architecture.
- **Powerful Controller API**: Programmatically control the canvas, manage tools, and manipulate objects from your own widgets.
- **Undo/Redo History**: A robust, built-in history stack for all major actions.
- **Keyboard Shortcuts**: Speed up your workflow with intuitive keyboard shortcuts for tools and actions.
- **Text-to-Diagram (flow_draw-lang)**: A simple, text-based language to programmatically generate entire diagrams.
- **Customizable UI**: Use builders to completely customize the appearance of nodes, context menus, and more coming soon.

## 📖 Table of Contents

- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [Core Concepts](#-core-concepts)
  - [FlowDraw Widget](#flowdraw-widget)
  - [FlowDrawCanvas](#flowdrawcanvas)
  - [FlowDrawController](#flowdrawcontroller)
  - [Toolbar & Tools](#toolbar--tools)
- [Advanced Usage](#-advanced-usage)
  - [Programmatic Control with `FlowDrawController`](#programmatic-control-with-flowdrawcontroller)
  - [Text-to-Diagram with `FlowDrawParser`](#text-to-diagram-with-flowdrawparser)
  - [Customizing Nodes](#customizing-nodes)
- [Contributing](#contributing-❤️)
- [Star History](#star-history)
- [Author](#author-✍️)
- [Support the project](#support-the-project)
- [License](#license-📜)

## 📦 Installation

Add `flow_draw` to your `pubspec.yaml` file:

```yaml
dependencies:
  flow_draw: ^latest_version
```

Then, run `flutter pub get` in your terminal.

## 🚀 Quick Start

Getting started with `flow_draw` is simple. Wrap your canvas area with the `FlowDraw` widget and provide it with a `FlowDrawCanvas` and a `FlowDrawToolbar`.

```dart
import 'package:flow_draw/flow_draw.dart';
import 'package:flutter/material.dart';

class MyDiagramPage extends StatefulWidget {
  const MyDiagramPage({super.key});

  @override
  State<MyDiagramPage> createState() => _MyDiagramPageState();
}

class _MyDiagramPageState extends State<MyDiagramPage> {
  FlowDrawController? controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FlowDraw(
        // The onControllerCreated callback gives you access to the controller
        // for programmatic interaction with the canvas.
        onControllerCreated: (c) {
          setState(() {
            controller = c;
          });
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The main canvas widget
            const FlowDrawCanvas(debug: true), // Set debug to true for helpful overlays

            // The toolbar for selecting tools
            Positioned(
              top: 24,
              child: FlowDrawToolbar(svgs: const []), // svgs list is for a future feature
            ),

            // A panel to show the undo/redo history
            if (controller != null)
              Positioned(
                bottom: 24,
                left: 24,
                child: SizedBox(
                  height: 200,
                  width: 250,
                  child: Card(
                    child: HistoryPanel(controller: controller!),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

![flow_draw Basic UI](https://raw.githubusercontent.com/flow-draw/flow_draw/main/assets/readme/basic_ui.png)

## 🧠 Core Concepts

### `FlowDraw` Widget

This is the root widget of the library. It sets up all the necessary BLoCs (`CanvasBloc`, `ToolBloc`, `SelectionBloc`) and provides them to the widget tree. It is the entry point for using the library.

- **`onControllerCreated`**: A crucial callback that provides you with a `FlowDrawController` instance once the canvas is initialized.

### `FlowDrawCanvas`

This is the main widget that renders the infinite canvas, grid, nodes, and all drawing objects. It handles all user interactions like panning, zooming, and drawing.

- **`debug`**: When set to `true`, it displays useful information like the current viewport coordinates, zoom level, and selection count.

### `FlowDrawController`

The controller is your primary tool for interacting with the canvas programmatically. It provides a clean, high-level API to abstract away the underlying BLoC architecture.

- **Streams**: Listen to `canvasStateStream`, `selectionStateStream`, and `toolStateStream` to react to changes.
- **Methods**: Call methods like `undo()`, `redo()`, `setTool()`, `addNode()`, `zoomIn()`, `centerView()`, and `loadProject()`.

### Toolbar & Tools

The `FlowDrawToolbar` widget provides a ready-made UI for selecting the active tool. The canvas behavior changes based on the currently selected tool in the `ToolBloc`. Keyboard shortcuts are also available to quickly switch between tools.

| Tool      | Shortcut | Description                          |
| :-------- | :------: | :----------------------------------- |
| Select    |   `V`    | Select, move, and resize objects.    |
| Rectangle |   `R`    | Draw a rectangle shape.              |
| Circle    |   `O`    | Draw a circle/oval shape.            |
| Arrow     |   `A`    | Draw an arrow connecting two points. |
| Line      |   `L`    | Draw a line.                         |
| Pencil    |   `D`    | Draw a free-hand stroke.             |
| Text      |   `T`    | Create a text object.                |
| Figure    |   `F`    | Create a dashed group container.     |

![flow_draw Tool Shortcuts GIF](https://raw.githubusercontent.com/flow-draw/flow_draw/main/assets/readme/tool_shortcuts.gif)

### Modifier Keys for Enhanced Control

You can hold down modifier keys to enhance the behavior of tools and actions, providing more precise control over your creations.

| Key(s)                 | Action                             | Description                                                                                                                      |
| :--------------------- | :--------------------------------- | :------------------------------------------------------------------------------------------------------------------------------- |
| `Shift`                | **Draw Perfect Shapes**            | While drawing with the Rectangle or Circle tool, hold `Shift` to lock the aspect ratio, creating a perfect square or circle.     |
| `Shift`                | **Draw Locked-Angle Lines/Arrows** | While drawing with the Line or Arrow tool, hold `Shift` to snap the line to 45-degree angle increments (0°, 45°, 90°, etc.).     |
| `Shift` + Click        | **Multi-Select**                   | While using the Select tool, hold `Shift` and click on objects to add them to your current selection without deselecting others. |
| `Ctrl`/`Cmd` + Click   | **Multi-Select (Alternative)**     | Same as Shift + Click, allows for adding objects to the current selection.                                                       |
| `Shift` + `Ctrl`/`Cmd` | **Draw Orthogonal Arrows**         | While drawing with the Arrow tool, hold both `Shift` and `Ctrl`/`Cmd` to create an orthogonal (right-angled) connector line.     |

![flow_draw Modifier Keys GIF](https://raw.githubusercontent.com/flow-draw/flow_draw/main/assets/readme/modifier_keys.gif)

## 🛠️ Advanced Usage

### Programmatic Control with `FlowDrawController`

Once you have the controller from the `onControllerCreated` callback, you can perform a wide variety of actions.

```dart
// Change the active tool to Rectangle
controller.setTool(EditorTool.square);

// Add a new node to the canvas
controller.addNode(
  NodeInstance(
    state: NodeState(),
    offset: const Offset(100, 150),
    heading: 'My First Node',
    value: 'This was added from code!',
  ),
);

// Zoom out and center the view
controller.zoomOut();
controller.centerView();
```

### Text-to-Diagram with `FlowDrawParser`

`flow_draw` includes a powerful parser for a simple, text-based language to define entire diagrams. This is perfect for generating diagrams from code, versioning them in git, or building integrations.

```dart
void generateDiagramFromText() {
  // 1. Define your diagram using flow_draw-lang syntax
  const myDiagramCode = """
    // This is a comment

    StartPoint [shape: circle, text: "Start"]
    Decision   [shape: node, heading: "Make a Choice"]
    EndPoint   [shape: rect, text: "End"]

    // Define relationships
    StartPoint -> Decision
    Decision -> EndPoint
  """;

  // 2. Create a parser and generate the JSON
  final parser = FlowDrawParser();
  final jsonString = parser.parse(myDiagramCode);
  final projectData = jsonDecode(jsonString);

  // 3. Load the generated project into the canvas
  controller?.loadProject(projectData);
}
```

This will automatically parse the text, lay out the nodes, and render the complete diagram on the canvas.

### Customizing Nodes

You can completely change the appearance of nodes by providing builder functions to the `FlowDrawCanvas` widget.

- **`headerBuilder`**: Customizes the header of a node.
- **`nodeBuilder`**: Replaces the entire node widget with your own implementation, giving you full control.

```dart
FlowDrawCanvas(
  headerBuilder: (context, node, onToggleCollapse) {
    // Return your own custom header widget here
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.deepPurple,
      child: Row(
        children: [
          Icon(Icons.api, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            node.heading ?? 'Custom Node',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  },
)
```

## Roadmap & Future Features

`flow_draw` is under active development. My goal is to make it the most powerful and easy-to-use diagramming library for Flutter. Below is a list of planned features and improvements. Contributions are highly welcome!

☐ **Style & Property Inspector**: Implement a robust styling system (fill color, stroke, text properties) and a property panel widget to edit selected objects.

☐ **Mobile & Touchscreen Enhancements**: Add intuitive two-finger gestures like pinch-to-zoom and two-finger pan.

☐ **Contextual Mobile UI**: Create a "delete" button or menu that appears above selected objects for easier interaction on touch devices.

☐ **Canvas Minimap**: Add a small navigator view, similar to `tldraw`, for a high-level overview and quick panning.

☐ **Desktop-Style Menu Bar**: Implement a classic menu bar (`File`, `Edit`, `View`) with common actions like Export and a list of keyboard shortcuts.

☐ **Enhanced Exporting**: Add functionality to export the canvas as an image (PNG/SVG).

☐ **Improved Example Project**: Enhance the example application to demonstrate saving and loading project state to/from a file.

## Contributing ❤️

Contributions are welcome and greatly appreciated! `flow_draw` is an open-source project, and we'd love to see it grow with the help of the community.

If you'd like to contribute, please feel free to:

1.  **Report a bug**: Create an issue detailing the problem you've encountered.
2.  **Suggest a feature**: Open an issue to discuss a new feature or enhancement.
3.  **Submit a pull request**:
    - Fork the repository.
    - Create a new branch for your feature (`git checkout -b feature/amazing-feature`).
    - Make your changes.
    - Commit your changes (`git commit -m 'Add some amazing feature'`).
    - Push to the branch (`git push origin feature/amazing-feature`).
    - Open a Pull Request.

## Star History

<a href="https://star-history.com/#flow-draw/flow_draw">
	<picture>
	  <source
	    media="(prefers-color-scheme: dark)"
	    srcset="https://api.star-history.com/svg?repos=flow-draw/flow_draw&type=Date&theme=dark"
	  />
	  <source
	    media="(prefers-color-scheme: light)"
	    srcset="https://api.star-history.com/svg?repos=flow-draw/flow_draw&type=Date"
	  />
	  <img src="https://api.star-history.com/svg?repos=flow-draw/flow_draw&type=Date" alt="Star History Chart" width="100%" />
	</picture>
</a>

## Author ✍️

This project is authored and maintained by **Yash Makan**.

Building software in public and sharing everything I learn along the way.

I am currently open looking for new job opportunities and interesting contract projects. If you are looking for a dedicated Flutter developer or have an exciting project in mind, please feel free to reach out 🙏

- **Email**: [contact@yashmakan.com](mailto:contact@yashmakan.com)
- **Website**: [yashmakan.com](https://yashmakan.com)
- **LinkedIn**: [linkedin.com/in/yashmakan](https://www.linkedin.com/in/yashmakan)
- **GitHub**: [@yashmakan](https://github.com/yashmakan)
- **Cal.com**: [@yashmakan](https://cal.com/yashmakan/30min)

## Support The Project

If `flow_draw` has been useful to you, please consider giving it a ⭐️ on GitHub!

For those who wish to provide more direct support, you can:

[![Sponsor on GitHub](https://img.shields.io/badge/Sponsor-ea4aaa?style=for-the-badge&logo=github-sponsors&logoColor=white)](https://github.com/sponsors/yashmakan)

Your support helps in the ongoing development and maintenance of the project. Thank you!

## License 📜

`flow_draw` is released under the [MIT License](https://opensource.org/licenses/MIT). See the `LICENSE` file for more details.
