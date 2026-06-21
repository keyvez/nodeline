# Canvas Mode — Design Report

A design for turning fldraw's one-shot "Text to Diagram" popover into an
interactive, chat-driven **Canvas Mode** — in the spirit of ChatGPT Canvas and
the FasMac GenUI canvas (`~/dev/fasmac`) — where natural-language directions
both *create* and *manipulate* the diagram, grounded by web search and
authenticated via Claude / OpenAI sign-in.

---

## 1. Goal

Let the user converse with the diagram. Representative directions the design
must support:

1. **Create from a description** — "an e-commerce checkout flow with payment and
   shipping steps" (today's feature, kept).
2. **Create from world knowledge + web search** — "create nodes with the top 8
   actors in Hollywood" → the agent web-searches, then creates the nodes.
3. **Semantic recolor** — "select all the nodes in the *Emotions* frame and color
   them with the cultural color given to each emotion."
4. **Bulk style change on a selection** — "turn all the selected edges to dashed."
5. **Style-transfer from a drawing** — "take the selected R-nodes and their two
   child branches, and lay them out in *this* style (a drawing in the app) —
   applying it to the nodes, the edges, and the child nodes."

The throughline: the user points (selection / a drawn guide) and speaks; the
agent resolves the referent and acts, live, on the canvas.

---

## 2. Decisions (locked)

These were chosen up front; the rest of the design follows from them.

| Decision | Choice | Why |
| --- | --- | --- |
| **How the model applies changes** | **Tool / function calling** | Incremental edits ("color these", "dash those", "select in frame") map 1:1 onto existing `CanvasBloc` events. Whole-canvas DSL regeneration (FasMac's approach) rewrites everything each turn and loses manual edits — wrong fit for manipulation. |
| **Where the loop & web search run** | **In-app, direct from Flutter** | No backend to build/deploy for a desktop app. Tool loop runs in Dart; web search uses the provider's native server-side search tool. |
| **Auth** | **Subscription OAuth** (Claude Pro/Max + ChatGPT), API key as fallback | Matches "sign in like Claude Code / Codex CLI." See the caveat in §8. |

### Why tool-calling over FasMac's DSL

FasMac emits a complete DSL JSON per turn and re-renders atomically. That's
ideal for *generating a single widget from a query*, but Canvas Mode's core verbs
are **mutations of existing objects** identified by selection. Regenerating the
whole canvas would (a) clobber manual edits, (b) make "color *these* 3"
awkward, and (c) can't interleave a `web_search` mid-generation. Tool-calling
gives us an agentic loop where each step is a real, undoable canvas operation.

We keep one DSL-ish escape hatch: a `generate_diagram` tool that emits Mermaid
for big from-scratch creates, reusing the existing `MermaidImporter`. So the
architecture is effectively **hybrid**: tools for manipulation, Mermaid for
bulk creation.

---

## 3. Architecture overview

```
┌──────────────────────────── Flutter app ────────────────────────────┐
│                                                                      │
│  Canvas Chat Panel  ──user text──►  CanvasAgent (tool-use loop)      │
│  (docked side panel)               │                                 │
│        ▲                           ├─ build context: canvas + sel.   │
│        │ live tool results         ├─ call provider (stream)         │
│        │                           │     │                           │
│        │                           │     ├─ web_search ─┐ (server-   │
│        │                           │     │              │  side)     │
│        │                           │     ▼              ▼            │
│        │                      tool calls          api.anthropic.com  │
│        │                           │              chatgpt backend    │
│        │                           ▼                                 │
│   CanvasBloc / SelectionBloc  ◄─ ToolDispatcher (Dart)              │
│        │                                                             │
│        ▼                                                             │
│   live canvas update                                                 │
│                                                                      │
│  AuthProvider (OAuth PKCE / API key)  ──tokens──► flutter_secure_storage
└──────────────────────────────────────────────────────────────────┘
```

The loop is the standard tool-use cycle: **send context + tools → model emits
tool calls → dispatcher executes each against the BLoCs → append results → repeat
until the model returns a final message.** Each executed tool is visible on the
canvas immediately, and a **Stop** button cancels the in-flight loop.

---

## 4. The tool surface

The payoff of tool-calling: most tools are thin wrappers over events that
**already exist**. Three are net-new (marked ★).

| Tool | Backed by | Serves direction |
| --- | --- | --- |
| `web_search(query)` | Provider **server-side** web search (Anthropic `web_search` tool / OpenAI Responses search) | #2 top-8 actors |
| `generate_diagram(mermaid)` | `MermaidImporter.import` → `ProjectLoaded` | #1 from-scratch creation |
| `create_nodes([{label, shape, x?, y?, fill?, stroke?}])` | `DrawingObjectAdded` | #2 create the actor nodes |
| `create_edges([{from, to, label?, style?}])` | `DrawingObjectAdded` (ArrowObject) | connecting created nodes |
| `select(spec)` ★resolver | `SelectionReplaced` | #3 "all nodes in the Emotions frame" |
| `color_objects(ids, fill?, stroke?, clearFill?, clearStroke?)` | `ObjectColorsChanged` | #3 cultural colors |
| `set_line_style(ids, style)` ★event | new `ObjectsLineStyleChanged` | #4 dashed edges |
| `set_font(ids, family?, size?)` / `fit_to_content(ids)` | `ObjectFontChanged`, `NodesFittedToContent` | layout polish |
| `align(ids, type)` / `distribute(ids, type)` / `auto_layout()` | `ObjectsAligned`, `ObjectsDistributed`, `AutoLayoutRequested` | layout directions |
| `read_drawing(id)` | reads guide polyline + reference styles | #5 drawing-as-input |
| `lay_along_guide(guideId, nodeIds)` | `LayoutAlongGuideRequested` | #5 distribute along the stroke |
| `apply_style_template(sourceIds, targetIds)` ★composite | reads source styling, applies via color/line/font tools | #5 "this style for nodes, edges, child nodes" |
| `get_selection()` / `get_canvas_summary()` | read-only context refresh | grounding |

### ★ Net-new work

1. **`ObjectsLineStyleChanged` event** — there is currently *no* bloc event for
   line style; it's only set at construction / via direct `copyWith`. Add the
   event + handler in `canvas_bloc.dart`, mirroring `ObjectColorsChanged`.
2. **Selection resolver** — a `select(spec)` that supports:
   - `frame: "Emotions"` → all objects whose id ∈ that `FigureObject.childrenIds`
     (and, optionally, spatial containment as a fallback since membership is
     explicit today and may be stale).
   - `type: "edge" | "rectangle" | ...`, `labelMatches: regex`, `scope: "selection" | "all"`.
   - Emits `SelectionReplaced`. This is what makes "all the nodes in a given
     frame" and "the selected edges" first-class.
3. **`apply_style_template`** — composite: read fill/stroke/lineStyle/font from
   `sourceIds`, partition `targetIds` into nodes vs edges vs children, and apply
   the matching attributes. Reuses the color/line/font tools internally.

Everything else dispatches to existing events (see project memory / the
`canvas_event.dart` inventory).

---

## 5. Context & targeting — how the model knows what "these" means

Every request carries a compact, **stable-id** serialization so the model can
refer to existing objects and resolve deictic references:

- **Selection** (the primary referent): `selectedIds`, each with `{id, type,
  label, frameId?}`. "color these" / "the selected edges" resolve directly.
- **Canvas summary**: frames (`{id, label, childrenIds}`), and per-object
  `{id, type, label, fill, stroke, lineStyle}` — kept terse; large canvases get
  summarized (counts + selection + nearby objects) to control tokens.
- **Drawings as input** (#5): `read_drawing(id)` returns the guide's polyline
  (via the existing `_guidePolylineFromObject` extraction) **plus** the styling
  of any reference objects, so "lay these out in *this* style" =
  `read_drawing` (positions) + `apply_style_template` (appearance).

This mirrors FasMac's lesson — **a semantic schema beats raw structure**: we
tell the model what a "frame", "edge", "child node", and "guide" *mean*, and
that opaque ids are join keys, not labels to display.

### Worked example — direction #3

```
user: select all the nodes in the Emotions frame and color them
      with the cultural color for each emotion
─────────────────────────────────────────────────────────────
agent → select({frame: "Emotions", type: "node"})
        → SelectionReplaced({joy, anger, grief, ...})
agent → (reasons: joy→gold, anger→red, grief→white in many East-Asian
         cultures; optionally web_search to ground specific palettes)
agent → color_objects(["joy"],   fill: "#F2C94C")
agent → color_objects(["anger"], fill: "#C1272D")
agent → color_objects(["grief"], fill: "#FFFFFF", stroke: "#999999")
agent → "Colored 6 emotion nodes using a culturally-grounded palette."
```

No hardcoded color map — semantic reasoning + optional web search, which the
fixed-DSL approach can't do. That's the core advantage we're buying.

---

## 6. Streaming & live application

Apply tool calls **as they stream**, not in a batch:

- Each tool call lands on the canvas the moment it's parsed → the diagram
  visibly assembles/recolors, ChatGPT-Canvas style.
- A **Stop** button cancels the loop (abort the HTTP stream, halt dispatch).
- Group a turn's mutations so **one Undo** reverts the whole agent turn
  (wrap dispatched events in a single undo transaction where the bloc supports
  it; otherwise coalesce at the history layer).

FasMac is batch-only and that's fine for single-widget regen; for incremental
canvas edits, live streaming is the better feel and is cheap here because each
tool is already an instant local op.

---

## 7. UI

Retire the `showPromptToWorkflowDialog` popover; introduce a **docked chat side
panel** (`canvas_chat_panel.dart`):

- Conversation transcript (user turns + the agent's tool-call trace, collapsible).
- Composer: multiline, Enter submits / Shift+Enter newline, Stop while running.
- A **"use selection"** affordance and a chip showing the current selection /
  picked drawing, so the referent for "these" / "this style" is explicit
  (FasMac's draw-region-then-annotate pattern, adapted to our object selection).
- Auth status + a settings affordance (sign in / switch provider / advanced API
  key).

The existing `convertSimpleFlowToMermaid` + `MermaidImporter` path stays reachable
through `generate_diagram`, so nothing regresses.

---

## 8. Auth — pluggable `AuthProvider`

> **Caveat (on the record).** Driving a third-party app with Claude Pro/Max or
> ChatGPT subscription OAuth uses those credentials outside their intended
> products (Claude Code / Codex CLI). The flows are technically reusable and
> people do it, but it's a gray area w.r.t. provider ToS: Anthropic gates
> subscription tokens toward Claude Code (beta headers / system-prompt
> expectations) and OpenAI scopes the Codex token to its own endpoint. Either
> provider can break or block this at any time. The design therefore keeps the
> **API-key path as a first-class fallback** so the feature degrades gracefully.

`AuthProvider` is an interface (`bearerToken()`, `refreshIfNeeded()`,
`provider`), with three implementations:

### Claude subscription (PKCE)
- Authorize at `https://claude.ai/oauth/authorize` (client_id from the Claude
  Code flow), `code_challenge_method=S256`.
- Exchange + refresh at `https://console.anthropic.com/v1/oauth/token`
  (`grant_type=authorization_code` then `refresh_token`).
- Access tokens ~8h; refresh tokens long-lived. Send required `anthropic-beta`
  header(s) for OAuth.

### OpenAI / ChatGPT subscription (PKCE)
- Authorization-code + PKCE against the ChatGPT/Codex flow, with a loopback
  `http://127.0.0.1:<port>` callback capturing the code.
- Calls the Responses API endpoint used by Codex (Chat Completions was
  deprecated for that endpoint Feb 2026).

### API key (fallback / "advanced")
- Current behavior, relocated into the panel's settings. Anthropic `x-api-key`
  / OpenAI `Authorization: Bearer`.

**Token storage:** `flutter_secure_storage` (OS keychain), replacing the plain
`SharedPreferences` key storage used today.

**References (OAuth):**
[Claude Code authentication](https://code.claude.com/docs/en/authentication) ·
[Claude OAuth token vs API key (2026)](https://lalatenduswain.medium.com/claude-code-on-claude-max-plan-understanding-oauth-token-vs-api-key-authentication-in-2026-96a6213d2cde) ·
[openai-auth PKCE](https://github.com/querymt/openai-auth) ·
[Zed: ChatGPT subscription provider via OAuth PKCE](https://github.com/zed-industries/zed/pull/56811)

---

## 9. Versioning & history — reverting agent turns

Canvas Mode must let the user **revert** — both fine-grained (one Undo) and
coarse-grained (jump back to "the diagram as it was 3 prompts ago"). The good
news: fldraw already has a full snapshot-based history we extend rather than
replace.

### What already exists (ground truth)

- `CanvasState` carries `undoStack` / `redoStack`, each a `List<HistoryEntry>`.
- `HistoryEntry` is a record **`(CanvasState snapshot, CanvasEvent cause)`** —
  i.e. history is *full state snapshots*, not deltas. `CanvasState.historic(...)`
  builds the snapshot (nodes, drawingObjects, viewport, comments, grid, fonts).
- A `_maxHistoryStack` cap trims the oldest entries.
- A `_preOperationSnapshot` already **coalesces a multi-event operation** (e.g. a
  drag = many `ObjectsDragged` + one `ObjectsDragEnded`) into a *single* undo
  step. This is exactly the hook we need for grouping an agent turn.
- A history UI already exists: `lib/src/ui/shared/history_panel.dart`.

### Design: a *turn* is the unit of revert

Map "version" onto the existing model so undo/redo and versioning are one system,
not two competing ones.

1. **Group each agent turn into one undo entry.** Open an agent-turn transaction
   before dispatching the turn's tools and close it after the loop ends —
   reusing the `_preOperationSnapshot` mechanism (snapshot once at turn start,
   push one `HistoryEntry` at turn end). Result: **one Cmd-Z reverts an entire
   prompt's worth of changes**, no matter how many tools it fired. A new
   `AgentTurnApplied` undoable event carries the turn metadata as its `cause`.

2. **Label history entries semantically.** Today `HistoryEntry.cause` is a raw
   `CanvasEvent`. Add an optional `label` (and `kind: manual | agentTurn`) so the
   history/version panel can show *"Colored 6 emotion nodes"* or *"Created top-8
   actors"* — the agent's own one-line summary of the turn — instead of an event
   class name. For manual edits the label is derived from the event as today.

3. **Version timeline = a view over `undoStack`.** Reuse `history_panel.dart`,
   but render agent-turn entries as **named checkpoints** (FasMac-style version
   list): version number, the turn's summary, relative time, and a **Restore**
   button. Clicking an entry previews that snapshot (non-destructive) and
   Restore makes it current. Because entries are full snapshots, restore is
   instant and needs **no LLM call** — same property FasMac relies on.

4. **Named checkpoints / branches (optional, phase 2).** Let the user pin a
   snapshot ("Checkpoint: before recolor") so it survives the `_maxHistoryStack`
   trim. Pinned checkpoints live in a separate `checkpoints: List<NamedSnapshot>`
   on `CanvasState`, exempt from trimming. Restoring a checkpoint after later
   edits pushes the *current* state onto the undo stack first, so the jump is
   itself undoable (no lost work).

### What's net-new for versioning

| Change | Where | Note |
| --- | --- | --- |
| `AgentTurnApplied` undoable event + turn transaction | `canvas_bloc.dart` | Reuses `_preOperationSnapshot` coalescing |
| `label` + `kind` on `HistoryEntry` | history record / `canvas_state.dart` | Backwards-compatible; manual entries derive label from event |
| Restore-to-entry action (`HistoryRestored(index)`) | `canvas_bloc.dart` | Push current state to undo, then load the chosen snapshot |
| Version-timeline rendering | `history_panel.dart` | Checkpoints + Restore button, agent turns named |
| `checkpoints` list + pinning (phase 2) | `canvas_state.dart` | Survives history trim |

### Persistence note

History is in-memory today (lives on `CanvasState`). Reverts within a session
work immediately. **Cross-session** version history (reopen the file, still see
prior versions) would require serializing `undoStack` / `checkpoints` into the
project JSON via the existing `ProjectSaved` / `ProjectLoaded` path — list this
as an explicit phase-2 decision, since full-snapshot history can bloat the saved
file (mitigate by persisting only pinned checkpoints + the last N turns).

### Interaction with §6 (live streaming)

Streaming tools land individually for *feedback*, but they're wrapped in the
single turn transaction, so the **undo granularity is the turn, not the
tool** — pressing Stop mid-turn still closes the transaction cleanly, leaving one
revertible entry for whatever was applied so far.

---

## 10. New code layout

```
lib/src/core/agent/
  canvas_agent.dart        # the tool-use loop, streaming, cancellation
  tools.dart               # tool JSON schemas + dispatch table
  tool_dispatcher.dart     # executes a tool call against the BLoCs
  context_builder.dart     # canvas + selection → compact model context
  providers/
    anthropic_client.dart  # messages API + server-side web_search tool
    openai_client.dart     # Responses API + search
  auth/
    auth_provider.dart     # interface + API-key impl
    claude_oauth.dart      # PKCE flow + refresh
    openai_oauth.dart      # PKCE flow + refresh
    token_store.dart       # flutter_secure_storage wrapper

lib/src/blocs/canvas/
  canvas_event.dart        # + ObjectsLineStyleChanged, AgentTurnApplied, HistoryRestored
  canvas_bloc.dart         # + handlers; + selection-resolver; + turn transaction
  canvas_state.dart        # + label/kind on HistoryEntry; + checkpoints (phase 2)

lib/src/blocs/selection/
  selection_resolver.dart  # frame / type / label → id set

lib/src/ui/canvas/
  canvas_chat_panel.dart   # docked chat UI (replaces the popover)

lib/src/ui/shared/
  history_panel.dart       # extend: named version timeline + Restore
```

Retire / fold in: `lib/src/ui/shared/prompt_to_workflow.dart` (keep the Mermaid
helpers; move them next to the importer).

---

## 11. Build order (risk-first)

1. **Selection resolver + `ObjectsLineStyleChanged`** — pure model/bloc work,
   fully unit-testable, unblocks the tool layer. *(No LLM.)*
2. **Tool dispatch layer** over existing events — unit-testable without any LLM;
   proves every verb works against the BLoCs.
3. **Agent loop on the API-key path** — proves the end-to-end tool-use cycle
   fast, before touching OAuth.
4. **Chat side panel** with live streaming + Stop + selection chip.
5. **Turn-grouped history + version timeline** (§9) — `AgentTurnApplied`
   transaction + `HistoryRestored` + named entries in `history_panel.dart`. Goes
   in alongside the panel so every turn is revertible from day one.
6. **`web_search` tool** — direction #2.
7. **`read_drawing` + `apply_style_template`** — direction #5.
8. **OAuth (Claude, then OpenAI)** — last and isolated, since it's the riskiest
   and the API-key path lets earlier steps ship independently.
9. **Phase 2:** pinned checkpoints + cross-session persisted history.

Each step is independently demoable; steps 1–2 carry the most risk reduction
because they're testable with zero model dependency.

---

## 12. Open questions / risks

- **Undo granularity** — *resolved by design* (§9): the existing
  `_preOperationSnapshot` coalescing already groups multi-event operations, so an
  agent turn reuses it to become one undo entry. Risk is only in confirming Stop
  mid-turn closes the transaction cleanly.
- **History memory / persistence** — full-snapshot history (§9) is fine
  in-memory but bloats the project file if persisted. Phase-2 decision: persist
  only pinned checkpoints + last N turns.
- **Frame membership staleness** — `FigureObject.childrenIds` is explicit, not
  spatial. The resolver should optionally fall back to geometric containment so
  "nodes in the frame" stays correct after manual moves.
- **Token budget on big canvases** — need the summarization tier in
  `context_builder` before this is usable on large diagrams.
- **OAuth durability** — per §8; mitigated by the API-key fallback.
- **Provider parity** — Anthropic and OpenAI differ in tool-call + server-side
  search shapes; the `providers/` clients normalize to one internal tool-call
  representation.
```
