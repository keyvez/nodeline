/// The tool declarations advertised to the model. These mirror the tools the
/// [ToolDispatcher] handles; the parameter shapes are intentionally permissive
/// because the dispatcher does loose-typed parsing and never throws on bad args.
///
/// The schema dialect is the JSON-Schema subset Gemini's `functionDeclarations`
/// accepts (type/description/properties/items/enum). Other providers' clients
/// translate from this same list, so there is one source of truth.
library;

/// A single tool's declaration: name, description, and a JSON-Schema parameters
/// object.
class ToolSchema {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  const ToolSchema({
    required this.name,
    required this.description,
    required this.parameters,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'parameters': parameters,
      };
}

Map<String, dynamic> _object(Map<String, dynamic> properties, {List<String> required = const []}) => {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
    };

Map<String, dynamic> _string(String desc, {List<String>? enumValues}) => {
      'type': 'string',
      'description': desc,
      if (enumValues != null) 'enum': enumValues,
    };

Map<String, dynamic> _array(Map<String, dynamic> items, String desc) => {
      'type': 'array',
      'description': desc,
      'items': items,
    };

const _kinds = [
  'any', 'node', 'edge', 'arrow', 'line', 'rectangle', 'circle',
  'diamond', 'parallelogram', 'forkJoin', 'text', 'frame',
];
const _lineStyles = ['solid', 'dashed', 'dotted', 'rough'];
const _shapes = ['rectangle', 'circle', 'diamond', 'parallelogram'];
const _alignments = ['left', 'centerH', 'right', 'top', 'centerV', 'bottom'];

/// The full tool list advertised to the model. Order is stable.
final List<ToolSchema> canvasToolSchemas = [
  ToolSchema(
    name: 'select',
    description:
        'Select objects on the canvas by frame, type, and/or label. Replaces the '
        'current selection. Use this before tools that act on "the selection".',
    parameters: _object({
      'frame': _string('Select only objects inside the frame with this label (substring, case-insensitive).'),
      'kind': _string('Restrict to a kind of object.', enumValues: _kinds),
      'labelContains': _string('Restrict to objects whose label contains this text (case-insensitive).'),
      'labelMatches': _string('Restrict to objects whose label matches this regular expression.'),
      'spatialFallback': {
        'type': 'boolean',
        'description': 'When selecting within a frame, also include objects geometrically inside it (default true).',
      },
    }),
  ),
  const ToolSchema(
    name: 'clear_selection',
    description: 'Deselect everything.',
    parameters: {'type': 'object', 'properties': {}},
  ),
  ToolSchema(
    name: 'color_objects',
    description:
        'Set fill and/or stroke color on objects. Works on shapes (fill + stroke) '
        'and on edges/arrows/lines (stroke only — the line + arrowhead color). '
        'Omit "ids" to color the current selection. Colors are hex like "#C1272D".',
    parameters: _object({
      'ids': _array({'type': 'string'}, 'Target object ids. Omit to use the current selection.'),
      'fill': _string('Fill color as hex, e.g. "#F2C94C".'),
      'stroke': _string('Stroke/border color as hex.'),
      'clearFill': {'type': 'boolean', 'description': 'Remove the fill color.'},
      'clearStroke': {'type': 'boolean', 'description': 'Remove the stroke color.'},
    }),
  ),
  ToolSchema(
    name: 'set_line_style',
    description:
        'Set the line/border style of objects (e.g. make edges dashed). Omit "ids" '
        'to use the current selection.',
    parameters: _object({
      'ids': _array({'type': 'string'}, 'Target object ids. Omit to use the current selection.'),
      'style': _string('The line style.', enumValues: _lineStyles),
    }, required: ['style']),
  ),
  ToolSchema(
    name: 'set_text_style',
    description:
        'Apply a named text-style preset to objects — this is a FONT change only '
        '(family + size), never a color change. Use this for requests like "make '
        'these caption style" or "title style". Omit ids to use the selection.',
    parameters: _object({
      'ids': _array({'type': 'string'}, 'Target object ids. Omit to use the current selection.'),
      'style': _string('The text style preset.',
          enumValues: ['title', 'heading 1', 'heading 2', 'subtitle', 'body', 'leaf node', 'caption']),
    }, required: ['style']),
  ),
  ToolSchema(
    name: 'create_nodes',
    description:
        'Create one or more node shapes. Each node may set label, shape, optional '
        'x/y position (omit to auto-place), size, and colors.',
    parameters: _object({
      'nodes': _array(
        _object({
          'label': _string('Text label for the node.'),
          'shape': _string('Node shape (default rectangle).', enumValues: _shapes),
          'x': {'type': 'number', 'description': 'Left position in world coords (optional).'},
          'y': {'type': 'number', 'description': 'Top position in world coords (optional).'},
          'width': {'type': 'number', 'description': 'Width (optional).'},
          'height': {'type': 'number', 'description': 'Height (optional).'},
          'fill': _string('Fill color as hex (optional).'),
          'stroke': _string('Stroke color as hex (optional).'),
        }),
        'The nodes to create.',
      ),
    }, required: ['nodes']),
  ),
  ToolSchema(
    name: 'create_edges',
    description:
        'Connect nodes with arrows. Reference endpoints by node id or by unique '
        'node label.',
    parameters: _object({
      'edges': _array(
        _object({
          'from': _string('Source node id or label.'),
          'to': _string('Target node id or label.'),
          'label': _string('Optional edge label.'),
          'style': _string('Optional line style.', enumValues: _lineStyles),
        }, required: ['from', 'to']),
        'The edges to create.',
      ),
    }, required: ['edges']),
  ),
  ToolSchema(
    name: 'delete_objects',
    description: 'Delete objects by id. Omit "ids" to delete the current selection.',
    parameters: _object({
      'ids': _array({'type': 'string'}, 'Target object ids. Omit to use the current selection.'),
    }),
  ),
  ToolSchema(
    name: 'align',
    description: 'Align objects to an edge or center. Omit "ids" to use the selection.',
    parameters: _object({
      'ids': _array({'type': 'string'}, 'Target object ids. Omit to use the current selection.'),
      'alignment': _string('How to align.', enumValues: _alignments),
    }, required: ['alignment']),
  ),
  ToolSchema(
    name: 'distribute',
    description: 'Distribute objects evenly. Omit "ids" to use the selection.',
    parameters: _object({
      'ids': _array({'type': 'string'}, 'Target object ids. Omit to use the current selection.'),
      'direction': _string('Distribution direction.', enumValues: ['horizontal', 'vertical']),
    }, required: ['direction']),
  ),
  const ToolSchema(
    name: 'auto_layout',
    description: 'Tidy the whole diagram with an automatic layered layout.',
    parameters: {'type': 'object', 'properties': {}},
  ),
  const ToolSchema(
    name: 'lay_along_guide',
    description:
        'Distribute the selected nodes along the selected drawn guide stroke. '
        'Requires a guide shape and nodes to be selected.',
    parameters: {'type': 'object', 'properties': {}},
  ),
  ToolSchema(
    name: 'read_drawing',
    description:
        'Read a drawn shape/stroke as a guide path: returns its sampled points, '
        'whether it is closed, and its bounding box. Use to understand a sketch '
        'the user drew before laying nodes along it or mimicking its shape.',
    parameters: _object({
      'id': _string('The id of the drawing/shape to read.'),
    }, required: ['id']),
  ),
  ToolSchema(
    name: 'apply_style_template',
    description:
        'Copy appearance (fill, stroke, line style) from source object(s) onto '
        'target object(s). Use for "make these look like that" / style transfer. '
        'Omit targetIds to use the current selection.',
    parameters: _object({
      'sourceIds': _array({'type': 'string'}, 'Object id(s) to copy style from.'),
      'targetIds': _array({'type': 'string'}, 'Object id(s) to apply style to. Omit to use the selection.'),
    }, required: ['sourceIds']),
  ),
  const ToolSchema(
    name: 'get_selection',
    description: 'Read the current selection: ids, types, and labels.',
    parameters: {'type': 'object', 'properties': {}},
  ),
  const ToolSchema(
    name: 'get_canvas_summary',
    description:
        'Read a summary of the canvas: object counts by type, the frames present, '
        'and the labels of existing nodes. Call this before creating nodes so you '
        'can connect to what already exists instead of duplicating it.',
    parameters: {'type': 'object', 'properties': {}},
  ),
  const ToolSchema(
    name: 'list_nodes',
    description:
        'List existing nodes (id, type, label) and edges (with endpoint labels). '
        'Use the ids/labels to connect new edges to existing nodes rather than '
        'creating new copies of nodes that are already on the canvas.',
    parameters: {'type': 'object', 'properties': {}},
  ),
];
