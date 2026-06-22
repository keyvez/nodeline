import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:example/gen/assets.gen.dart';
import 'package:flan_flutter/flan_flutter.dart';
import 'package:flow_draw/flow_draw.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _storageKey = 'flow_draw_project';
const _fileListKey = 'flow_draw_file_list';
const _lastFileKey = 'flow_draw_last_file';
/// Autosave slot for the current *untitled* (never-named) document. A named
/// file is persisted under [_fileKey]; an untitled canvas would otherwise only
/// hit the legacy [_storageKey], which the loader ignores whenever a named file
/// was last open — so unsaved work was lost on restart. This dedicated slot is
/// restored first, so an untitled diagram always comes back.
const _draftKey = 'flow_draw_untitled_draft';
String _fileKey(String name) => 'flow_draw_file_$name';

/// True if a decoded project document has no content worth restoring.
bool _isEmptyDoc(Map<String, dynamic> data) {
  final nodes = data['nodes'];
  final objs = data['drawingObjects'];
  final nodeCount = nodes is List ? nodes.length : 0;
  final objCount = objs is List ? objs.length : 0;
  return nodeCount == 0 && objCount == 0;
}

void main() {
  FlanBinding.ensureInitialized();
  // Flip to true for a live FPS + paint-cost overlay (routing/obstacle timing).
  // Perf overlay defaults off; toggle it in-app via the "Perf" button.
  _warmUpTextPainter();
  runApp(const MyApp());
}

/// Forces Flutter to load the default system font before any TextPainter
/// is called inside a RenderObject.paint(), which would otherwise block
/// the UI thread for up to 30 seconds on first use.
void _warmUpTextPainter() {
  final painter = TextPainter(
    text: const TextSpan(text: ' ', style: TextStyle(fontSize: 16)),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.dispose();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late List<String> svgs;
  FlowDrawController controller = FlowDrawController();
  Timer? _autoSaveTimer;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String? _currentFileName;
  List<String> _savedFileNames = [];
  bool _isWorkflowMode = false;
  bool _showShortcuts = false;
  bool _showChat = false;

  @override
  void initState() {
    super.initState();
    svgs = Assets.svgs.values.map((e) => e.path).toList();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveProject();
    }
  }

  Future<void> _loadFileList() async {
    final prefs = await SharedPreferences.getInstance();
    final listJson = prefs.getString(_fileListKey);
    if (listJson != null) {
      _savedFileNames =
          (jsonDecode(listJson) as List).cast<String>();
    }
  }

  Future<void> _saveFileList() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fileListKey, jsonEncode(_savedFileNames));
  }

  Future<void> _setLastFile(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    if (name != null) {
      await prefs.setString(_lastFileKey, name);
    } else {
      await prefs.remove(_lastFileKey);
    }
  }

  Future<void> _loadSavedProject() async {
    await _loadFileList();
    final prefs = await SharedPreferences.getInstance();

    // An untitled draft (unsaved work) takes precedence — it's the most recent
    // thing the user was working on and would otherwise be lost on restart.
    final draft = prefs.getString(_draftKey);
    if (draft != null) {
      try {
        final data = jsonDecode(draft) as Map<String, dynamic>;
        if (!_isEmptyDoc(data)) {
          controller.loadProject(data);
          setState(() => _currentFileName = null); // still untitled
          return;
        }
        await prefs.remove(_draftKey); // empty draft — discard
      } catch (_) {
        await prefs.remove(_draftKey); // corrupt — discard
      }
    }

    final lastName = prefs.getString(_lastFileKey);

    if (lastName != null) {
      // Try loading by name even if it's not in the file list (list may be stale)
      final savedData = prefs.getString(_fileKey(lastName));
      if (savedData != null) {
        try {
          final data = jsonDecode(savedData) as Map<String, dynamic>;
          controller.loadProject(data);
          setState(() => _currentFileName = lastName);
          // Re-add to list if missing
          if (!_savedFileNames.contains(lastName)) {
            _savedFileNames.add(lastName);
            await _saveFileList();
          }
          return;
        } catch (_) {}
      }
    }

    // Legacy migration: check old single-project key
    final saved = prefs.getString(_storageKey);
    if (saved != null) {
      try {
        final data = jsonDecode(saved) as Map<String, dynamic>;
        controller.loadProject(data);
        return;
      } catch (_) {}
    }
    _loadDefaultProject();
  }

  Future<void> _loadFileByName(String name,
      {bool autoSaveCurrent = true}) async {
    if (autoSaveCurrent) {
      await _saveProjectToPrefs();
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_fileKey(name));
    if (saved != null) {
      try {
        final data = jsonDecode(saved) as Map<String, dynamic>;
        controller.loadProject(data);
        setState(() => _currentFileName = name);
        await _setLastFile(name);
        // Deliberately opening a named file makes it the active doc, so the
        // untitled draft is no longer "the last thing open" — clear it so it
        // doesn't override this file on the next launch. (The autoSaveCurrent
        // step above already re-persisted any untitled work to the draft; that
        // is intentional only up until an explicit navigation like this.)
        await prefs.remove(_draftKey);
        return;
      } catch (_) {}
    }
  }

  void _loadDefaultProject() {
    // Seed new builds with the dense consciousness diagram — it doubles as the
    // heavy routing benchmark (see TestDiagrams.consciousness).
    try {
      final projectData = MermaidImporter.import(TestDiagrams.consciousness);
      controller.loadProject(projectData);
      return;
    } catch (_) {
      // Fall through to the legacy flow-draw sample on any parse failure.
    }

    final flowDrawCode = """
   // Vertical workflow with grouped steps

start [shape: node, heading: "Start", text: "Begin the process"]

// Group for input & validation phase
inputPhase [label: "Input Phase"] {
  collect [shape: rect, text: "Collect User Info"]
  validate [shape: node, heading: "Validate", text: "Check Input Data"]
}

// Group for processing phase
processPhase [label: "Processing Phase"] {
  transform [shape: rect, text: "Transform Data"]
  compute [shape: node, heading: "Compute", text: "Perform Calculations"]
  cache [shape: rect, text: "Cache Results"]
}

// Group for output & cleanup
outputPhase [label: "Output Phase", figure: true] {
  save [shape: circle, text: "Save to Database"]
  notify [shape: node, heading: "Notify", text: "Send Confirmation"]
  cleanup [shape: rect, text: "Clean Temp Files"]
}

end [shape: node, heading: "End", text: "Workflow Complete"]

// --- Relationships ---
start -> inputPhase
inputPhase -> processPhase
processPhase -> outputPhase
outputPhase -> end

start -> outputPhase
  """;

    try {
      final parser = FlowDrawParser();
      final jsonString = parser.parse(flowDrawCode);
      final projectData = jsonDecode(jsonString);
      controller.loadProject(projectData);
    } on FormatException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Syntax Error: ${e.message}')));
    }
  }

  Future<void> _saveProjectToPrefs() async {
    final completer = Completer<void>();
    controller.saveProject((data) async {
      try {
        final home = Platform.environment['HOME'] ?? '';
        final file = File('$home/Downloads/flow_draw_debug.json');
        file.writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(data));
      } catch (_) {}
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(data);
      if (_currentFileName != null) {
        await prefs.setString(_fileKey(_currentFileName!), encoded);
        // The work now lives under a named file — drop any stale untitled draft
        // so we don't restore it over the named file on next launch.
        await prefs.remove(_draftKey);
      } else if (!_isEmptyDoc(data)) {
        // Untitled but non-empty: keep it in the dedicated draft slot so it
        // survives a restart even when a named file was last open.
        await prefs.setString(_draftKey, encoded);
      } else {
        await prefs.remove(_draftKey);
      }
      // Also save to legacy key for backwards compat
      await prefs.setString(_storageKey, encoded);
      completer.complete();
    });
    return completer.future;
  }

  void _saveProject() {
    _saveProjectToPrefs();
  }

  Future<void> _saveCurrentFile() async {
    if (_currentFileName == null) {
      final name = await _showNameDialog('Save As');
      if (name == null || name.isEmpty) return;
      await _saveAsNewFile(name);
    } else {
      await _saveProjectToPrefs();
    }
  }

  Future<void> _saveAsNewFile(String name) async {
    if (_savedFileNames.contains(name)) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('File exists'),
          content: Text('"$name" already exists. Overwrite?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Overwrite')),
          ],
        ),
      );
      if (overwrite != true) return;
    }

    setState(() => _currentFileName = name);
    if (!_savedFileNames.contains(name)) {
      _savedFileNames.add(name);
      await _saveFileList();
    }
    await _saveProjectToPrefs();
    await _setLastFile(name);
  }

  Future<void> _loadFile(String name) async {
    await _loadFileByName(name);
    if (mounted) Navigator.pop(context); // close drawer
  }

  Future<void> _deleteFile(String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete file'),
        content: Text('Delete "$name"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_fileKey(name));
    setState(() {
      _savedFileNames.remove(name);
      if (_currentFileName == name) {
        _currentFileName = null;
      }
    });
    await _saveFileList();
  }

  Future<void> _renameFile(String oldName) async {
    final newName = await _showNameDialog('Rename', initialValue: oldName);
    if (newName == null || newName.isEmpty || newName == oldName) return;
    if (_savedFileNames.contains(newName)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"$newName" already exists')));
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_fileKey(oldName));
    if (data != null) {
      await prefs.setString(_fileKey(newName), data);
    }
    await prefs.remove(_fileKey(oldName));

    setState(() {
      final idx = _savedFileNames.indexOf(oldName);
      if (idx >= 0) _savedFileNames[idx] = newName;
      if (_currentFileName == oldName) _currentFileName = newName;
    });
    await _saveFileList();
    await _setLastFile(_currentFileName);
  }

  Future<void> _createNewFile() async {
    await _saveProjectToPrefs();
    setState(() => _currentFileName = null);
    controller.loadProject({
      'viewport': {'offset': [0.0, 0.0], 'zoom': 1.0},
      'nodes': <dynamic>[],
      'drawingObjects': <dynamic>[],
    });
    await _setLastFile(null);
    if (mounted) Navigator.pop(context); // close drawer
  }

  Future<String?> _showNameDialog(String title,
      {String? initialValue}) async {
    final textController = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'File name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, textController.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 3), _saveProject);
  }

  Future<void> _exportPng(BuildContext blocContext) async {
    final canvasBloc = blocContext.read<CanvasBloc>();
    final objects = canvasBloc.state.drawingObjects;
    if (objects.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to export')),
        );
      }
      return;
    }
    try {
      final pngBytes = await PngExporter.exportPng(objects);
      if (pngBytes == null) return;
      final home = Platform.environment['HOME'] ?? '';
      final file = File('$home/Downloads/fldraw_export.png');
      await file.writeAsBytes(pngBytes);
      if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [file.path]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', file.path]);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PNG saved to Downloads')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export PNG: $e')),
        );
      }
    }
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Text('Files',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'New file',
                    onPressed: _createNewFile,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _savedFileNames.isEmpty
                  ? const Center(
                      child: Text('No saved files',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _savedFileNames.length,
                      itemBuilder: (context, index) {
                        final name = _savedFileNames[index];
                        final isCurrent = name == _currentFileName;
                        return ListTile(
                          title: Text(name),
                          selected: isCurrent,
                          selectedTileColor:
                              Colors.white.withValues(alpha: 0.1),
                          onTap: () => _loadFile(name),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'rename') {
                                _renameFile(name);
                              } else if (action == 'delete') {
                                _deleteFile(name);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Rename')),
                              const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete')),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: [
        PlatformMenu(label: 'File', menus: [
          PlatformMenuItem(
            label: 'Save',
            shortcut:
                const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
            onSelected: _saveCurrentFile,
          ),
          PlatformMenuItem(
            label: 'Save As...',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyS,
                meta: true, shift: true),
            onSelected: () async {
              final name = await _showNameDialog('Save As');
              if (name != null && name.isNotEmpty) {
                await _saveAsNewFile(name);
              }
            },
          ),
        ]),
      ],
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.black,
        drawer: _buildDrawer(),
        floatingActionButtonLocation:
            FloatingActionButtonLocation.centerFloat,
        floatingActionButton: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 250,
                  maxWidth: 250,
                ),
                child: HistoryPanel(controller: controller),
              ),
            ),
          ],
        ),
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
                _saveCurrentFile,
            const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                _saveCurrentFile,
            const SingleActivator(LogicalKeyboardKey.question):
                () => setState(() => _showShortcuts = !_showShortcuts),
          },
          child: Focus(
            autofocus: true,
            child: FlowDraw(
              controller: controller,
              onControllerCreated: (controller) {
                _loadSavedProject();
              },
              onCanvasStateChanged: (state) {
                _scheduleAutoSave();
              },
              child: Row(
                children: [
                  if (_showChat)
                    CanvasChatPanel(
                      documentId: _currentFileName,
                      onClose: () => setState(() => _showChat = false),
                      onSendTranscript: (turns) => FlanBinding.sendChatLog(
                        turns: [
                          for (final t in turns)
                            <String, dynamic>{...t},
                        ],
                        summary:
                            'Canvas Mode AI chat transcript (${turns.length} turns) from ${_currentFileName ?? 'Untitled'}',
                        screen: 'Canvas Mode',
                      ),
                    ),
                  Expanded(
                    child: Stack(
                children: [
                  FlowDrawCanvas(),
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 32.0),
                      child: FlowDrawToolbar(
                        svgs: svgs,
                        allowedTools: _isWorkflowMode ? workflowTools : null,
                      ),
                    ),
                  ),
                  // Drawer icon + file name (top-left)
                  Positioned(
                    top: 32,
                    left: 16,
                    child: Row(
                      children: [
                        Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                          child: IconButton(
                            icon: const Icon(Icons.menu, color: Colors.white),
                            tooltip: 'Files',
                            onPressed: () {
                              _scaffoldKey.currentState?.openDrawer();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _currentFileName ?? 'Untitled',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Material(
                          color: _isWorkflowMode ? Colors.blue.withValues(alpha: 0.3) : Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() => _isWorkflowMode = !_isWorkflowMode),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.account_tree_outlined,
                                    color: _isWorkflowMode ? Colors.blue : Colors.white70,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Workflow',
                                    style: TextStyle(
                                      color: _isWorkflowMode ? Colors.blue : Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: _showChat ? Colors.purple.withValues(alpha: 0.3) : Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() => _showChat = !_showChat),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_awesome,
                                    color: _showChat ? Colors.purpleAccent : Colors.white70,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Canvas Mode',
                                    style: TextStyle(
                                      color: _showChat ? Colors.purpleAccent : Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Save + PNG export buttons (top-right)
                  Positioned(
                    top: 32,
                    right: 16,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _saveCurrentFile,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.save_outlined,
                                      color: Colors.white70, size: 16),
                                  SizedBox(width: 6),
                                  Text('Save',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Builder(
                          builder: (blocContext) => Material(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _exportPng(blocContext),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.image_outlined,
                                        color: Colors.white70, size: 16),
                                    SizedBox(width: 6),
                                    Text('PNG',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Minimap (bottom-right, raised above the history panel which
                  // floats at the very bottom-right).
                  const Positioned(
                    bottom: 80,
                    right: 16,
                    child: MiniMap(),
                  ),
                  // Shortcut overlay
                  if (_showShortcuts)
                    Positioned.fill(
                      child: ShortcutOverlay(
                        onClose: () =>
                            setState(() => _showShortcuts = false),
                      ),
                    ),
                ],
              ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
