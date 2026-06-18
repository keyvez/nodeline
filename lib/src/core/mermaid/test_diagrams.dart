/// Canonical Mermaid test diagrams used to seed new builds and to exercise
/// routing/rendering performance in tests.
///
/// These are intentionally large and densely connected so they stress the
/// orthogonal router and the routing cache. Keep them in sync with any fixtures
/// referenced by tests.
class TestDiagrams {
  TestDiagrams._();

  /// A dense ~46-node / ~45-edge non-dual philosophy graph with cycles
  /// (e.g. F --> D, AI --> A) and many multi-line labels. Used as the default
  /// seed diagram and as the heavy routing benchmark.
  static const String consciousness = '''
flowchart TD

    A["Absolute / Parabrahman / Self<br/>Beyond being and non-being"]
    B["Pure Awareness<br/>Prior to consciousness"]
    C["Consciousness<br/>Field in which experience appears"]
    D["I Am<br/>Basic sense of being"]
    E["Witness / Observer<br/>Knowing of appearances"]
    F["Attention<br/>Turns toward or away from I Am"]

    A --> B
    B --> C
    C --> D
    D --> E
    E --> F
    F --> D

    D --> G["Identification"]
    G --> H["Person / Ego<br/>'I am this body-mind'"]
    H --> I["Body"]
    H --> J["Mind"]
    J --> K["Thoughts"]
    J --> L["Memory"]
    J --> M["Concepts / Names / Forms"]

    K --> N["Desire"]
    K --> O["Fear"]
    N --> P["Suffering"]
    O --> P

    I --> Q["Birth"]
    I --> R["Death"]
    Q --> S["Time"]
    R --> S

    C --> T["World"]
    T --> U["Universe"]
    U --> V["Space"]
    U --> S

    C --> W["Waking"]
    C --> X["Dream"]
    C --> Y["Deep Sleep"]
    W --> T
    X --> T
    Y --> Z["Absence of person-world appearance"]

    H --> AA["Ignorance<br/>Mistaking the transient for Self"]
    F --> AB["Self-inquiry<br/>Stay with I Am"]
    AB --> AC["Knowledge<br/>I am not body, mind, thought, or person"]
    AC --> AD["Disidentification"]
    AD --> E

    D --> AE["Being"]
    A --> AF["Non-being / Beyond being"]

    T --> AG["Maya / Manifestation"]
    AG --> C

    A --> AH["Love / Peace / Freedom"]
    AH --> AI["Liberation / Realization"]

    AJ["Guru / Grace"] --> AB
    AB --> AI

    AI --> A
''';
}
