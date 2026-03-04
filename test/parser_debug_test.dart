import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_draw/src/core/parser/flow_draw_parser.dart';

void main() {
  test('parse default project and print arrow data', () {
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

    final parser = FlowDrawParser();
    final jsonString = parser.parse(flowDrawCode);
    final data = jsonDecode(jsonString);

    // Print all drawing objects
    final drawingObjects = data['drawingObjects'] as List;
    for (final obj in drawingObjects) {
      if (obj['type'] == 'arrow') {
        print('ARROW: start=${obj['start']} end=${obj['end']} pathType=${obj['pathType']} startAttach=${obj['startAttachment']} endAttach=${obj['endAttachment']}');
      } else {
        print('OBJECT: type=${obj['type']} id=${obj['id']} rect=${obj['rect']}');
      }
    }

    // Print nodes
    final nodes = data['nodes'] as List;
    for (final node in nodes) {
      print('NODE: id=${node['id']} heading=${node['heading']} offset=${node['offset']}');
    }
  });
}
