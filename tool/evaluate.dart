#!/usr/bin/env dart
/// fldraw autoresearch evaluation script.
/// Scores the codebase on feature completeness.
/// Adapted from Karpathy's autoresearch val_bpb metric.
///
/// Usage: dart run tool/evaluate.dart
///
/// DO NOT MODIFY THIS FILE — it is the ground truth metric.

import 'dart:io';

int score = 0;
int maxScore = 100;
final List<String> results = [];

void check(String name, int points, bool condition) {
  if (condition) {
    score += points;
    results.add('  [+$points] $name');
  } else {
    results.add('  [   ] $name ($points pts available)');
  }
}

bool fileContains(String path, String pattern) {
  final file = File(path);
  if (!file.existsSync()) return false;
  return file.readAsStringSync().contains(pattern);
}

bool fileContainsRegex(String path, String pattern) {
  final file = File(path);
  if (!file.existsSync()) return false;
  return RegExp(pattern, multiLine: true).hasMatch(file.readAsStringSync());
}

bool fileExists(String path) => File(path).existsSync();

bool anyFileInDirContains(String dirPath, String pattern, {String ext = '.dart'}) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return false;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith(ext)) {
      if (entity.readAsStringSync().contains(pattern)) return true;
    }
  }
  return false;
}

bool anyFileInDirContainsRegex(String dirPath, String pattern, {String ext = '.dart'}) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return false;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith(ext)) {
      if (RegExp(pattern, multiLine: true).hasMatch(entity.readAsStringSync())) return true;
    }
  }
  return false;
}

void main() {
  final libDir = 'lib/src';
  final testDir = 'test';
  final exampleDir = 'example/lib';
  final modelsFile = '$libDir/models/drawing_entities.dart';
  final stylesFile = '$libDir/models/styles.dart';
  final blocFile = '$libDir/blocs/canvas/canvas_bloc.dart';
  final eventFile = '$libDir/blocs/canvas/canvas_event.dart';
  final dataLayerFile = '$libDir/ui/canvas/flow_draw_editor_data_layer.dart';
  final renderObjectFile = '$libDir/ui/canvas/flow_draw_editor_render_object.dart';
  final toolbarFile = '$libDir/ui/shared/toolbar.dart';
  final mainFile = '$exampleDir/main.dart';

  print('=== fldraw autoresearch evaluation ===');
  print('');

  // ---- SHAPES & MODELS (0-15 pts) ----
  print('--- Shapes & Models (0-15 pts) ---');

  check(
    'Diamond/rhombus shape class',
    3,
    anyFileInDirContains(libDir, 'DiamondObject') ||
        anyFileInDirContains(libDir, 'RhombusObject'),
  );

  check(
    'Parallelogram shape class',
    2,
    anyFileInDirContains(libDir, 'ParallelogramObject'),
  );

  check(
    'Rounded rectangle variant',
    2,
    anyFileInDirContains(libDir, 'borderRadius') &&
        fileContainsRegex(modelsFile, r'RoundedRect|cornerRadius|borderRadius'),
  );

  check(
    'Fork/join bar shape',
    3,
    anyFileInDirContains(libDir, 'ForkObject') ||
        anyFileInDirContains(libDir, 'ForkJoinObject') ||
        anyFileInDirContains(libDir, 'BarObject') ||
        anyFileInDirContains(libDir, 'ForkNode'),
  );

  check(
    'Arrow label text field',
    2,
    fileContainsRegex(modelsFile, r'class ArrowObject[^}]*?label') ||
        fileContainsRegex(modelsFile, r'ArrowObject[^;]*midLabel|ArrowObject[^;]*arrowLabel'),
  );

  check(
    'Multiple arrowhead styles',
    3,
    anyFileInDirContains(libDir, 'ArrowheadStyle') ||
        anyFileInDirContains(libDir, 'ArrowHeadType') ||
        anyFileInDirContainsRegex(libDir, r'enum\s+\w*[Aa]rrow[Hh]ead'),
  );

  // ---- WORKFLOW MODE (0-20 pts) ----
  print('');
  print('--- Workflow Mode (0-20 pts) ---');

  check(
    'Workflow mode toggle',
    5,
    anyFileInDirContains(libDir, 'WorkflowMode') ||
        anyFileInDirContains(libDir, 'workflowMode') ||
        anyFileInDirContains(libDir, 'isWorkflowMode') ||
        anyFileInDirContains(exampleDir, 'WorkflowMode') ||
        anyFileInDirContains(exampleDir, 'workflowMode'),
  );

  check(
    'Workflow-restricted tool palette',
    5,
    anyFileInDirContainsRegex(libDir, r'workflow.*tool|tool.*workflow|restrictedTools|workflowTools') ||
        anyFileInDirContainsRegex(exampleDir, r'workflow.*tool|tool.*workflow'),
  );

  check(
    'Connection ports on shapes',
    5,
    anyFileInDirContains(libDir, 'ConnectionPort') ||
        anyFileInDirContains(libDir, 'connectionPort') ||
        anyFileInDirContains(libDir, 'snapPort') ||
        anyFileInDirContainsRegex(libDir, r'port.*top.*right.*bottom.*left|anchorPoint'),
  );

  check(
    'Workflow validation',
    5,
    anyFileInDirContains(libDir, 'validateWorkflow') ||
        anyFileInDirContains(libDir, 'WorkflowValidator') ||
        anyFileInDirContains(libDir, 'workflowValidation') ||
        anyFileInDirContains(libDir, 'validatePaths') ||
        anyFileInDirContains(libDir, 'disconnectedNodes'),
  );

  // ---- SMART FEATURES (0-20 pts) ----
  print('');
  print('--- Smart Features (0-20 pts) ---');

  check(
    'Prompt-to-workflow input UI',
    5,
    anyFileInDirContains(libDir, 'PromptToWorkflow') ||
        anyFileInDirContains(libDir, 'promptToWorkflow') ||
        anyFileInDirContains(libDir, 'WorkflowPrompt') ||
        anyFileInDirContains(exampleDir, 'PromptToWorkflow') ||
        anyFileInDirContains(exampleDir, 'promptToWorkflow') ||
        anyFileInDirContains(exampleDir, 'WorkflowPrompt'),
  );

  check(
    'Workflow templates',
    5,
    anyFileInDirContains(libDir, 'WorkflowTemplate') ||
        anyFileInDirContains(libDir, 'workflowTemplate') ||
        anyFileInDirContains(libDir, 'templateApproval') ||
        anyFileInDirContains(exampleDir, 'WorkflowTemplate') ||
        anyFileInDirContainsRegex(libDir, r'template.*workflow|workflow.*template'),
  );

  check(
    'Auto-layout algorithm',
    5,
    anyFileInDirContains(libDir, 'autoLayout') ||
        anyFileInDirContains(libDir, 'AutoLayout') ||
        anyFileInDirContains(libDir, 'layoutWorkflow') ||
        anyFileInDirContains(libDir, 'dagLayout') ||
        anyFileInDirContains(libDir, 'hierarchicalLayout'),
  );

  check(
    'Contextual floating toolbar',
    5,
    anyFileInDirContains(libDir, 'FloatingToolbar') ||
        anyFileInDirContains(libDir, 'ContextualToolbar') ||
        anyFileInDirContains(libDir, 'SelectionToolbar') ||
        anyFileInDirContains(libDir, 'floatingToolbar') ||
        anyFileInDirContains(libDir, 'contextToolbar'),
  );

  // ---- AFFINE POLISH (0-15 pts) ----
  print('');
  print('--- AFFiNE Polish (0-15 pts) ---');

  check(
    'Color picker UI',
    3,
    anyFileInDirContains(libDir, 'ColorPicker') ||
        anyFileInDirContains(libDir, 'colorPicker') ||
        anyFileInDirContains(libDir, 'StrokeColorPicker') ||
        anyFileInDirContains(libDir, 'FillColorPicker'),
  );

  check(
    'Snap-to-object guides',
    3,
    anyFileInDirContains(libDir, 'SnapGuide') ||
        anyFileInDirContains(libDir, 'snapGuide') ||
        anyFileInDirContains(libDir, 'AlignmentGuide') ||
        anyFileInDirContains(libDir, 'objectSnap') ||
        anyFileInDirContains(libDir, 'smartGuide'),
  );

  check(
    'Minimap widget',
    3,
    anyFileInDirContains(libDir, 'Minimap') ||
        anyFileInDirContains(libDir, 'minimap') ||
        anyFileInDirContains(libDir, 'MiniMap') ||
        anyFileInDirContains(exampleDir, 'Minimap') ||
        anyFileInDirContains(exampleDir, 'MiniMap'),
  );

  check(
    'Context menu (right-click)',
    3,
    anyFileInDirContainsRegex(libDir, r'ContextMenu|contextMenu|showMenu.*right|secondaryTap.*menu') ||
        anyFileInDirContainsRegex(exampleDir, r'ContextMenu|contextMenu'),
  );

  check(
    'PNG export',
    3,
    anyFileInDirContains(libDir, 'exportPng') ||
        anyFileInDirContains(libDir, 'PngExporter') ||
        anyFileInDirContains(libDir, 'toImage') ||
        anyFileInDirContains(libDir, 'exportImage') ||
        anyFileInDirContains(libDir, 'pngExport'),
  );

  // ---- TESTING (0-10 pts) ----
  print('');
  print('--- Testing (0-10 pts) ---');

  check(
    'New test files for workflow features',
    5,
    fileExists('$testDir/workflow_test.dart') ||
        fileExists('$testDir/workflow_mode_test.dart') ||
        fileExists('$testDir/workflow_validation_test.dart'),
  );

  check(
    'Test coverage of new shapes',
    5,
    anyFileInDirContains(testDir, 'DiamondObject') ||
        anyFileInDirContains(testDir, 'RhombusObject') ||
        anyFileInDirContains(testDir, 'ParallelogramObject') ||
        anyFileInDirContains(testDir, 'ForkObject') ||
        anyFileInDirContains(testDir, 'new shape') ||
        anyFileInDirContains(testDir, 'diamond') ||
        anyFileInDirContains(testDir, 'parallelogram'),
  );

  // ---- INTEGRATION & DEPTH (0-20 pts) ----
  print('');
  print('--- Integration & Depth (0-20 pts) ---');

  check(
    'Keyboard shortcuts help/overlay',
    2,
    anyFileInDirContains(libDir, 'ShortcutOverlay') ||
        anyFileInDirContains(libDir, 'KeyboardShortcuts') ||
        anyFileInDirContains(libDir, 'shortcutsHelp') ||
        anyFileInDirContains(libDir, 'HotkeyHelp'),
  );

  check(
    'Undo/redo stack with descriptions',
    2,
    anyFileInDirContains(libDir, 'UndoStack') ||
        anyFileInDirContainsRegex(libDir, r'undoStack.*description|undo.*history|_undoStack'),
  );

  check(
    'Object fill color support',
    3,
    fileContainsRegex(modelsFile, r'fillColor|fill_color|backgroundColor.*Color') &&
        fileContainsRegex(renderObjectFile, r'fillColor|fill.*color.*paint'),
  );

  check(
    'Object stroke color support',
    3,
    fileContainsRegex(modelsFile, r'strokeColor|stroke_color|borderColor.*Color') &&
        fileContainsRegex(renderObjectFile, r'strokeColor|stroke.*color.*paint'),
  );

  check(
    'Shape text editing inline',
    2,
    fileContainsRegex(dataLayerFile, r'_beginShapeTextEditing|shapeTextEditing|isEditing.*true'),
  );

  check(
    'Clipboard copy/paste drawing objects',
    3,
    fileContainsRegex(blocFile, r'clipboard|_clipboard|copyBuffer|pasteBuffer') ||
        fileContainsRegex(dataLayerFile, r'clipboard|_copiedObjects|pasteObjects'),
  );

  check(
    'JSON project save/load',
    2,
    anyFileInDirContains(libDir, 'saveProject') ||
        anyFileInDirContains(libDir, 'loadProject'),
  );

  check(
    'Mermaid import with arrow labels',
    3,
    fileContainsRegex('$libDir/core/mermaid/mermaid_importer.dart', r'label|arrowLabel|edgeLabel'),
  );

  // ---- SUMMARY ----
  print('');
  print('=== RESULTS ===');
  for (final r in results) {
    print(r);
  }
  print('');
  print('SCORE: $score / $maxScore');
  print('score: $score');
}
