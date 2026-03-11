import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:example/gen/assets.gen.dart';
import 'package:flan_flutter/flan_flutter.dart';
import 'package:flow_draw/flow_draw.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _storageKey = 'flow_draw_project';
const _fileListKey = 'flow_draw_file_list';
const _lastFileKey = 'flow_draw_last_file';
String _fileKey(String name) => 'flow_draw_file_$name';

void main() {
  FlanBinding.ensureInitialized();
  runApp(const MyApp());
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
        state == AppLifecycleState.inactive) {
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
    final lastName = prefs.getString(_lastFileKey);

    if (lastName != null && _savedFileNames.contains(lastName)) {
      await _loadFileByName(lastName, autoSaveCurrent: false);
      return;
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
        return;
      } catch (_) {}
    }
  }

  void _loadDefaultProject() {
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
      if (_currentFileName != null) {
        await prefs.setString(
            _fileKey(_currentFileName!), jsonEncode(data));
      }
      // Also save to legacy key for backwards compat
      await prefs.setString(_storageKey, jsonEncode(data));
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
      'objects': <dynamic>[],
      'connections': <dynamic>[],
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
              child: Stack(
                children: [
                  FlowDrawCanvas(),
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 32.0),
                      child: FlowDrawToolbar(svgs: svgs),
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
