## 0.1.0 - 2025-07-27

- Updated README.md to include a new "Roadmap & Future Features" section, outlining planned improvements and upcoming features for the library.
- No functional code changes in this version.

## 0.0.1 - 2025-07-26

### Added

This is the initial public release of `flow_draw`, a powerful and extensible infinite canvas and diagramming library for Flutter.

#### 🎨 Core Canvas & Rendering Engine

- High-performance infinite canvas with smooth, responsive panning and zooming.
- Custom `RenderObject` pipeline (`NodeEditorRenderBox`) for efficient drawing of thousands of objects, bypassing standard widget overhead.
- GPU-accelerated grid background via a custom GLSL fragment shader for maximum performance.
- Optimized rendering with object culling (frustum culling) to only draw what's visible in the viewport.
- Robust hit-testing system that correctly delegates pointer events to nodes or the canvas background.

#### 🧱 State Management

- Predictable state management built on the BLoC pattern, with clear separation of concerns:
  - `CanvasBloc`: Manages all canvas objects, viewport state, and the history stack.
  - `SelectionBloc`: Manages the set of currently selected objects.
  - `ToolBloc`: Manages the currently active drawing tool.

#### ✏️ Drawing Tools & Objects

- A comprehensive set of built-in drawing tools: Select, Rectangle, Circle, Arrow, Line, Pencil (free-hand), Text, and Figure (grouping).
- Data models for all drawing objects (`RectangleObject`, `ArrowObject`, etc.).
- Smart snapping and attachment system for arrows, allowing them to connect intelligently to the sides of shapes and nodes.
- Modifier key support for precision control:
  - `Shift`: Draw perfect squares/circles and locked-angle (45° increment) lines/arrows.
  - `Shift` + `Ctrl`/`Cmd`: Draw orthogonal (right-angled) arrows.
  - `Shift`/`Ctrl` + Click: Add or remove objects from the current selection (multi-select).

#### 🧩 Interactive Node System

- Support for complex, interactive nodes (`NodeInstance`) with distinct headers and content values.
- Nodes are collapsible to hide their content and save space.
- Support for in-place editing of node values via a double-click overlay `TextField`.

#### 🕹️ User Interface & Experience

- A clean, pre-built `FlowDrawToolbar` widget for easy tool selection.
- Global keyboard shortcuts for quickly switching between tools (`V`, `R`, `O`, `A`, `L`, `D`, `T`, `F`, `C`).
- A robust Undo/Redo system that correctly handles complex actions like dragging and resizing as single, atomic operations.
- A reactive `HistoryPanel` widget that displays a human-readable list of all undoable actions and includes Undo/Redo buttons.
- Area selection (marquee/rubber-band select) for selecting multiple objects at once.

#### 🚀 Developer API & Extensibility

- A powerful, high-level `FlowDrawController` that provides a clean, programmatic API for interacting with the canvas, managing tools, and manipulating objects from external widgets.
- A simple, declarative `FlowDraw` widget to easily integrate the entire system into any Flutter application.
- **flow_draw-lang**: A custom, text-to-diagram Domain-Specific Language (DSL) with an accompanying `FlowDrawParser` to generate entire, fully-connected diagrams from a simple text format.
- Customizable node appearance through `headerBuilder` and `nodeBuilder` functions passed to the `FlowDrawCanvas` widget.
