/// Pre-built workflow templates expressed as Mermaid flowchart strings.
///
/// Each template can be imported via [MermaidImporter.import] to produce
/// a ready-to-render project JSON.
class WorkflowTemplate {
  /// Human-readable name shown in a template picker.
  final String name;

  /// Short description of what the workflow models.
  final String description;

  /// A valid Mermaid flowchart string that [MermaidImporter] can parse.
  final String mermaidDiagram;

  const WorkflowTemplate({
    required this.name,
    required this.description,
    required this.mermaidDiagram,
  });

  /// All bundled workflow templates.
  static const List<WorkflowTemplate> templates = [
    approvalFlow,
    cicdPipeline,
    bugTriage,
  ];

  /// Approval flow: start -> request -> review -> approve/reject -> end.
  static const approvalFlow = WorkflowTemplate(
    name: 'Approval Flow',
    description:
        'A standard approval workflow with request submission, review, '
        'and approve/reject decision paths.',
    mermaidDiagram: '''flowchart TD
START(("Start"))
REQ["Submit Request"]
REV["Review Request"]
DEC{"Approve?"}
APP["Approved"]
REJ["Rejected"]
END(("End"))
START --> REQ
REQ --> REV
REV --> DEC
DEC -->|Yes| APP
DEC -->|No| REJ
APP --> END
REJ --> END''',
  );

  /// CI/CD pipeline: push -> build -> test -> deploy -> monitor.
  static const cicdPipeline = WorkflowTemplate(
    name: 'CI/CD Pipeline',
    description:
        'A continuous integration and deployment pipeline covering push, '
        'build, test, deploy, and monitoring stages.',
    mermaidDiagram: '''flowchart TD
PUSH(("Push"))
BUILD["Build"]
TEST["Run Tests"]
GATE{"Tests Pass?"}
DEPLOY["Deploy"]
MONITOR["Monitor"]
FAIL["Fix & Retry"]
PUSH --> BUILD
BUILD --> TEST
TEST --> GATE
GATE -->|Yes| DEPLOY
GATE -->|No| FAIL
DEPLOY --> MONITOR
FAIL --> BUILD''',
  );

  /// Bug triage: report -> assess -> assign -> fix -> verify -> close.
  static const bugTriage = WorkflowTemplate(
    name: 'Bug Triage',
    description:
        'A bug lifecycle workflow from initial report through triage, '
        'assignment, fix, verification, and closure.',
    mermaidDiagram: '''flowchart TD
REPORT(("Report Bug"))
ASSESS["Assess Severity"]
PRI{"Priority?"}
HIGH["Assign Immediately"]
LOW["Add to Backlog"]
FIX["Fix Bug"]
VERIFY["Verify Fix"]
CHECK{"Verified?"}
CLOSE(("Close"))
REPORT --> ASSESS
ASSESS --> PRI
PRI -->|High| HIGH
PRI -->|Low| LOW
HIGH --> FIX
LOW --> FIX
FIX --> VERIFY
VERIFY --> CHECK
CHECK -->|Yes| CLOSE
CHECK -->|No| FIX''',
  );
}
