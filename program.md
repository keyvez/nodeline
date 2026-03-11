# fldraw autoresearch — Autonomous Flutter Diagramming App Development

Adapted from [Karpathy's autoresearch](https://github.com/karpathy/autoresearch) and [autoresearch-mlx](https://github.com/trevin-creator/autoresearch-mlx).

Instead of optimizing val_bpb on a neural network, we autonomously build and improve a Flutter diagramming app with measurable quality metrics.

## The Goal

Build a **robust, professional-grade diagramming app** in Flutter with:

1. **Core diagramming** — shapes, connectors, text, styling, canvas operations (AFFiNE-inspired)
2. **Workflow Mode** — a dedicated mode restricted to boxes, connections, forks/decisions, and parallel branches for building executable-style workflows
3. **Prompt-to-workflow** — describe a workflow in natural language and get a diagram generated via the FlowDraw DSL parser
4. **AFFiNE-inspired UX** — infinite canvas, smart snapping, templates, presentation frames, contextual toolbar, keyboard-first design

## Project Context

This is the `fldraw` Flutter package (package name: `flow_draw`). Key files:

- `lib/src/models/drawing_entities.dart` — Shape models (Rectangle, Circle, Arrow, Line, etc.)
- `lib/src/models/styles.dart` — Styling (LineStyle, FlGridStyle)
- `lib/src/blocs/canvas/canvas_bloc.dart` — Main state management
- `lib/src/blocs/canvas/canvas_event.dart` — All canvas events
- `lib/src/blocs/canvas/canvas_state.dart` — Canvas state shape
- `lib/src/blocs/selection/` — Selection state
- `lib/src/blocs/tool/` — Active tool state
- `lib/src/ui/canvas/flow_draw_editor_render_object.dart` — Custom RenderObject
- `lib/src/ui/canvas/flow_draw_editor_data_layer.dart` — Paint/render logic
- `lib/src/ui/shared/toolbar.dart` — Tool selection UI
- `lib/src/core/utils/orthogonal_router.dart` — Smart arrow routing
- `lib/src/core/utils/svg_exporter.dart` — SVG export
- `lib/src/core/mermaid/` — Mermaid import/export
- `lib/src/core/parser/flow_draw_parser.dart` — Text DSL parser
- `lib/src/core/controller/flow_draw_controller.dart` — Programmatic API
- `example/lib/main.dart` — Demo app
- `test/` — Test files

## Already Implemented Features

These are DONE — do not re-implement:
- Shapes: rectangle, circle, arrow, line, pencil, text, figure, SVG icons
- Text: inline editing in shapes
- Selection: single, multi (Cmd+A), marquee, resize handles, rotation
- Canvas: infinite, zoom (0.1-10x), pan, grid toggle, snap to grid
- Styling: line styles (solid/dashed/dotted/rough), zoom-invariant strokes
- Connectors: straight, orthogonal (visibility-graph router), object attachments, bezier curves, waypoints
- Import/export: Mermaid (import+export), SVG export, JSON save/load, FlowDraw DSL parser
- QoL: undo/redo (100 history), copy/cut/paste, keyboard tool shortcuts, nudge, auto-save, history panel
- Quick actions: directional connection buttons on hover
- Duplicate (Cmd+D), Z-ordering, opaque fill on shapes
- Alignment & distribution of selected objects

## Feature Roadmap — What to Build

### Phase 1: Workflow Mode Foundation
1. **Diamond/rhombus shape** — essential for flowchart decision nodes
2. **Parallelogram shape** — for input/output in workflows
3. **Rounded rectangle** — for start/end terminators
4. **Workflow Mode toggle** — UI switch that restricts palette to: rounded-rect (start/end), rectangle (process), diamond (decision), parallelogram (I/O), arrow (connector). Hides pencil, free line, circle, text, figure, SVG when active.
5. **Fork/join node** — horizontal bar shape for parallel branches (like UML activity diagrams)
6. **Auto-connect on drop** — when dragging a new shape near an existing shape's port, auto-create an arrow connection
7. **Connection ports** — visible snap points on shape edges (top/right/bottom/left center) shown on hover

### Phase 2: Smart Workflow Features
8. **Prompt-to-workflow** — text input field where user types a natural language workflow description, parsed into FlowDraw DSL, rendered as a diagram. Use the existing `flow_draw_parser.dart` as the backend.
9. **Workflow templates** — pre-built templates: approval flow, CI/CD pipeline, onboarding process, bug triage
10. **Workflow validation** — check that every path from start reaches an end node, highlight disconnected nodes
11. **Auto-layout** — automatic arrangement of workflow nodes (top-to-bottom or left-to-right) with proper spacing

### Phase 3: AFFiNE-Inspired Polish
12. **Contextual floating toolbar** — appears near selection with: color, stroke, fill, font, alignment. Like AFFiNE's popover toolbar.
13. **Color picker** (stroke + fill per object) — palette with presets + custom color
14. **Snap-to-object guides** — smart alignment lines when dragging (like Figma/AFFiNE)
15. **Minimap** — small overview in corner showing viewport position
16. **Fit-to-screen** (Cmd+0) — zoom to show all objects
17. **Presentation frames** — define rectangular frames on canvas, enter presentation mode to step through them like slides (AFFiNE feature)
18. **Multiple arrowhead styles** — none, triangle, diamond, dot, bar
19. **Arrow label text** — editable text on arrow midpoints
20. **PNG/image export** — export canvas as raster image
21. **Context menu** (right-click) — cut, copy, paste, duplicate, delete, z-order, alignment
22. **Opacity control** per object
23. **Find/replace text** across all objects
24. **Dark/light theme toggle**

### Phase 4: Advanced
25. **Layers panel** — named layers, visibility toggle, lock, reorder
26. **Grouped undo** — batch operations into single undo steps
27. **Keyboard shortcut overlay** (press ?) — shows all available shortcuts
28. **Touch/trackpad gesture refinement** — pinch-to-zoom, two-finger pan smoothness
29. **Embed mode** — read-only viewer widget for embedding diagrams elsewhere

## Setup

To set up a new experiment run:

1. **Agree on a run tag** with the user (e.g. `mar11`). The branch `autoresearch/<tag>` must not already exist.
2. **Create the branch**: `git checkout -b autoresearch/<tag>` from current HEAD.
3. **Read the key files** listed above for full context. At minimum read:
   - This `program.md`
   - `lib/src/models/drawing_entities.dart`
   - `lib/src/blocs/canvas/canvas_bloc.dart` and `canvas_event.dart`
   - `lib/src/ui/canvas/flow_draw_editor_data_layer.dart`
   - `example/lib/main.dart`
   - `pubspec.yaml`
4. **Run the evaluation** to establish baseline: `dart run tool/evaluate.dart`
5. **Initialize results.tsv** with header row and baseline score.
6. **Confirm and go**.

## Evaluation

Instead of val_bpb, we measure a **feature score** (higher is better). The evaluation script `tool/evaluate.dart` checks:

### Build Score (0-20 points)
- `flutter analyze` passes with 0 errors: **10 pts**
- `flutter test` all pass: **10 pts**

### Feature Score (0-80 points)
Static analysis of the codebase for feature presence:

**Shapes & Models (0-15 pts)**
- Diamond/rhombus shape class exists: 3 pts
- Parallelogram shape class exists: 2 pts
- Rounded rectangle variant exists: 2 pts
- Fork/join bar shape exists: 3 pts
- Arrow label text field exists: 2 pts
- Multiple arrowhead styles enum: 3 pts

**Workflow Mode (0-20 pts)**
- WorkflowMode or equivalent toggle exists: 5 pts
- Workflow-restricted tool palette: 5 pts
- Connection ports on shapes: 5 pts
- Workflow validation (path checking): 5 pts

**Smart Features (0-20 pts)**
- Prompt-to-workflow input UI exists: 5 pts
- Workflow templates defined: 5 pts
- Auto-layout algorithm: 5 pts
- Contextual floating toolbar: 5 pts

**AFFiNE Polish (0-15 pts)**
- Color picker UI: 3 pts
- Snap-to-object guides: 3 pts
- Minimap widget: 3 pts
- Context menu (right-click): 3 pts
- PNG export: 3 pts

**Testing (0-10 pts)**
- New test files for workflow features: 5 pts
- Test coverage of new shapes: 5 pts

**Total possible: 100 points**

## The Experiment Loop

The experiment runs on a dedicated branch (e.g. `autoresearch/mar11`).

LOOP FOREVER:

1. **Check state**: Look at git state, current score, what features are missing.
2. **Pick the highest-impact feature** that isn't built yet. Start with Phase 1, then 2, 3, 4 in order. Within a phase, pick the one that adds the most points for the least code.
3. **Implement the feature** by editing the appropriate files. Keep changes focused — one feature per experiment.
4. **Commit**: `git add <specific files> && git commit -m "feat: <description>"`
5. **Evaluate**: Run `dart run tool/evaluate.dart > run.log 2>&1`
6. **Read results**: `grep "^SCORE:" run.log`
7. **Also verify build**: `cd example && flutter build macos 2>&1 | tail -5` (or just `flutter analyze`)
8. **Log to results.tsv** (tab-separated):

```
commit	score	status	description
```

- commit: short git hash (7 chars)
- score: total score from evaluation (e.g. 45)
- status: `keep`, `discard`, or `crash`
- description: short text of what was implemented

9. **If score improved** (higher) AND build succeeds: keep the commit, advance the branch.
10. **If score decreased, build broke, or tests fail**: fix if trivial, otherwise `git reset --hard <previous kept commit>` to discard.

## Rules

**What you CAN do:**
- Add/modify files in `lib/src/`, `example/lib/`, `test/`
- Add new shape classes, blocs, events, UI components
- Add new test files
- Modify the toolbar, render object, data layer
- Add dependencies if truly needed (prefer existing ones)

**What you CANNOT do:**
- Modify `tool/evaluate.dart` — it is the ground truth metric (once created)
- Delete existing working features
- Break the existing JSON save/load format (backward compatibility)
- Remove existing tests that pass

**Simplicity criterion**: Same as Karpathy's — all else being equal, simpler is better. Don't add complexity without corresponding score improvement. Clean, readable Dart code. Follow existing patterns in the codebase.

**Crashes**: If the build fails after your change, attempt to fix. If you can't fix in 2-3 tries, revert and try a different feature.

**NEVER STOP**: Once the loop begins, do NOT pause to ask the human. Work autonomously and indefinitely. If you finish all features in the roadmap, look for polish, edge cases, tests, performance improvements. The loop runs until the human interrupts you.

## Iteration Budget

Each experiment should take roughly 5-15 minutes:
- ~2-5 min to implement a focused feature
- ~1-2 min to run analyze + tests
- ~1 min to evaluate and log

Target: **4-8 experiments per hour**, ~30-60 experiments overnight.
