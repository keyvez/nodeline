import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:example/gen/assets.gen.dart';
import 'package:flan_flutter/flan_flutter.dart';
import 'package:fldraw/fldraw.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _storageKey = 'fldraw_project';

void main() {
  FlanBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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
  FlDrawController controller = FlDrawController();
  Timer? _autoSaveTimer;

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

  Future<void> _loadSavedProject() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_storageKey);
    if (saved != null) {
      try {
        final data = jsonDecode(saved) as Map<String, dynamic>;
        controller.loadProject(data);
        return;
      } catch (_) {
        // Corrupted data — fall through to default
      }
    }
    _loadDefaultProject();
  }

  void _loadDefaultProject() {
    final fldrawCode = """
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
      final parser = FlDrawParser();
      final jsonString = parser.parse(fldrawCode);
      final projectData = jsonDecode(jsonString);
      controller.loadProject(projectData);
    } on FormatException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Syntax Error: ${e.message}')));
    }
  }

  void _saveProject() {
    controller.saveProject((data) async {
      // Write debug dump to Downloads folder
      try {
        final home = Platform.environment['HOME'] ?? '';
        final file = File('$home/Downloads/fldraw_debug.json');
        file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
      } catch (_) {}
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(data));
    });
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 3), _saveProject);
  }

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: [
        PlatformMenu(label: 'File', menus: [
          PlatformMenuItem(
            label: 'Save',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
            onSelected: _saveProject,
          ),
        ]),
      ],
      child: Scaffold(
      backgroundColor: Colors.black,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveProject,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveProject,
        },
        child: Focus(
          autofocus: true,
          child: FlDraw(
        controller: controller,
        onControllerCreated: (controller) {
          _loadSavedProject();
        },
        onCanvasStateChanged: (state) {
          _scheduleAutoSave();
        },
        child: Stack(
          children: [
            FlDrawCanvas(),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 32.0),
                child: FlToolbar(svgs: svgs),
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
