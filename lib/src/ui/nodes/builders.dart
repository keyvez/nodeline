import 'package:flow_draw/flow_draw.dart';
import 'package:flutter/material.dart';

typedef FlNodeHeaderBuilder =
    Widget Function(
      BuildContext context,
      NodeInstance node,
      VoidCallback onToggleCollapse,
    );

typedef EditorBuilder =
    Widget Function(
      BuildContext context,
      Function() removeOverlay,
      dynamic data,
      Function(dynamic data) setData,
    );
typedef FlNodeBuilder =
    Widget Function(BuildContext context, NodeInstance node);
