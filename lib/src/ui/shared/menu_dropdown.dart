// import 'package:flow_draw/flow_draw.dart';
// import 'package:flow_draw/src/core/utils/renderbox.dart';
// import 'package:shadcn_flutter/shadcn_flutter.dart';
//
// class MenuDropdown extends StatelessWidget {
//   final Offset position;
//
//   const MenuDropdown(
//       {super.key, required this.controller, required this.position});
//
//   Offset get offset => controller.viewportOffset;
//
//   double get zoom => controller.viewportZoom;
//
//   Offset? get worldPosition => screenToWorld(
//         position,
//         offset,
//         zoom,
//       );
//
//   @override
//   Widget build(BuildContext context) {
//     return DropdownMenu(children: [
//       const MenuLabel(child: Text("Editor Menu")),
//       const MenuDivider(),
//       MenuButton(
//         leading: const Icon(Icons.center_focus_strong),
//         onPressed: (context) => controller.setViewportOffset(
//           Offset.zero,
//           absolute: true,
//         ),
//         child: const Text('Center View'),
//       ),
//       MenuButton(
//         leading: const Icon(Icons.zoom_in),
//         onPressed: (context) => controller.setViewportZoom(1.0),
//         child: const Text('Reset Zoom'),
//       ),
//       const MenuDivider(),
//       MenuButton(
//         leading: const Icon(Icons.add),
//         // subMenu: createSubmenuEntries(position),
//         child: const Text('Create'),
//       ),
//       MenuButton(
//         leading: const Icon(Icons.paste),
//         onPressed: (context) =>
//             controller.clipboard.pasteSelection(position: worldPosition),
//         child: const Text('Paste'),
//       ),
//       const MenuDivider(),
//       MenuButton(
//         leading: const Icon(Icons.folder),
//         subMenu: [
//           MenuButton(
//             leading: const Icon(Icons.undo),
//             onPressed: (context) => controller.history.undo(),
//             child: const Text('Undo'),
//           ),
//           MenuButton(
//             leading: const Icon(Icons.redo),
//             onPressed: (context) => controller.history.redo(),
//             child: const Text('Redo'),
//           ),
//           MenuButton(
//             leading: const Icon(Icons.save),
//             onPressed: (context) => controller.project.save(),
//             child: const Text('Save'),
//           ),
//           MenuButton(
//             leading: const Icon(Icons.folder_open),
//             onPressed: (context) => controller.project.load(),
//             child: const Text('Open'),
//           ),
//           MenuButton(
//             leading: const Icon(Icons.new_label),
//             onPressed: (context) => controller.project.create(),
//             child: const Text('New'),
//           ),
//         ],
//         child: const Text('Project'),
//       ),
//     ]);
//   }
// }
