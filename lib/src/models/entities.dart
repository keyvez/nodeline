import 'package:equatable/equatable.dart';
import 'package:flow_draw/flow_draw.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

final class NodeState extends Equatable {
  bool isSelected;
  bool isCollapsed;

  NodeState({this.isSelected = false, this.isCollapsed = false});

  factory NodeState.fromJson(Map<String, dynamic> json) {
    return NodeState(
      isSelected: json['isSelected'],
      isCollapsed: json['isCollapsed'],
    );
  }

  Map<String, dynamic> toJson() {
    return {'isSelected': isSelected, 'isCollapsed': isCollapsed};
  }

  @override
  List<Object?> get props => [isSelected, isCollapsed];
}

final class Source {
  final String url;
  final Map<String, dynamic> source;

  Source(this.url, this.source);
}

final class NodeInfo {
  final String nodePrototypeId;
  final String title;
  final String description;
  final List<Source> sources;

  NodeInfo(this.nodePrototypeId, this.title, this.description, this.sources);
}

final class NodeInstance extends Equatable {
  late String id;

  bool forceRecompute;

  // The resolved style for the node.
  late FlNodeStyle builtStyle;
  late FlNodeHeaderStyle builtHeaderStyle;

  final FlNodeStyleBuilder styleBuilder;
  final FlNodeHeaderStyleBuilder headerStyleBuilder;
  final Widget Function(dynamic data)? valueBuilder;
  final EditorBuilder? editorBuilder;

  final String? heading;
  String? value;

  late NodeState state;
  Offset offset;
  final GlobalKey key;

  NodeInstance({
    String? id,
    NodeState? state,
    this.styleBuilder = defaultNodeStyle,
    this.headerStyleBuilder = defaultNodeHeaderStyle,
    this.editorBuilder,
    this.heading,
    this.value,
    this.valueBuilder,
    this.forceRecompute = true,
    this.offset = Offset.zero,
    GlobalKey? key,
  }) : key = key ?? GlobalKey() {
    this.id = id ?? const Uuid().v4();
    this.state = state ?? NodeState();
  }

  NodeInstance copyWith({
    String? id,
    Color? color,
    NodeState? state,
    Function(NodeInstance node)? onRendered,
    Offset? offset,
    String? value,
    Widget Function(dynamic data)? valueBuilder,
    String? heading,
    EditorBuilder? editorBuilder,
    FlNodeStyleBuilder? styleBuilder,
    FlNodeHeaderStyleBuilder? headerStyleBuilder,
  }) {
    return NodeInstance(
      id: id ?? this.id,
      valueBuilder: valueBuilder ?? this.valueBuilder,
      state: state ?? this.state,
      offset: offset ?? this.offset,
      value: value ?? this.value,
      heading: heading ?? this.heading,
      editorBuilder: editorBuilder ?? this.editorBuilder,
      styleBuilder: styleBuilder ?? this.styleBuilder,
      headerStyleBuilder: headerStyleBuilder ?? this.headerStyleBuilder,
      key: key, // preserve the same GlobalKey across copies
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'heading': heading,
      'value': value,
      'state': state.toJson(),
      'offset': [offset.dx, offset.dy],
    };
  }

  factory NodeInstance.fromJson(Map<String, dynamic> json) {
    final instance = NodeInstance(
      id: json['id'],
      heading: json['heading'],
      value: json['value'],
      state: NodeState(isCollapsed: json['state']['isCollapsed']),
      offset: Offset(json['offset'][0], json['offset'][1]),
    );

    return instance;
  }

  @override
  List<Object?> get props => [
    id,
    heading,
    value,
    state,
    offset,
  ];

  @override
  bool get stringify => true;
}