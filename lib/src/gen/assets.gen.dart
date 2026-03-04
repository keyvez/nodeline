/// GENERATED CODE - DO NOT MODIFY BY HAND
/// *****************************************************
///  FlutterGen
/// *****************************************************

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: directives_ordering,unnecessary_import,implicit_dynamic_list_literal,deprecated_member_use

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart' as _svg;
import 'package:vector_graphics/vector_graphics.dart' as _vg;

class $AssetsIconsGen {
  const $AssetsIconsGen();

  /// File path: assets/icons/add.svg
  SvgGenImage get add => const SvgGenImage('assets/icons/add.svg');

  /// File path: assets/icons/arrow-top-right.svg
  SvgGenImage get arrowTopRight =>
      const SvgGenImage('assets/icons/arrow-top-right.svg');

  /// File path: assets/icons/arrow.svg
  SvgGenImage get arrow => const SvgGenImage('assets/icons/arrow.svg');

  /// File path: assets/icons/circle.svg
  SvgGenImage get circle => const SvgGenImage('assets/icons/circle.svg');

  /// File path: assets/icons/comment.svg
  SvgGenImage get comment => const SvgGenImage('assets/icons/comment.svg');

  /// File path: assets/icons/down.svg
  SvgGenImage get down => const SvgGenImage('assets/icons/down.svg');

  /// File path: assets/icons/figure.svg
  SvgGenImage get figure => const SvgGenImage('assets/icons/figure.svg');

  /// File path: assets/icons/line.svg
  SvgGenImage get line => const SvgGenImage('assets/icons/line.svg');

  /// File path: assets/icons/new-doc.svg
  SvgGenImage get newDoc => const SvgGenImage('assets/icons/new-doc.svg');

  /// File path: assets/icons/pencil.svg
  SvgGenImage get pencil => const SvgGenImage('assets/icons/pencil.svg');

  /// File path: assets/icons/search.svg
  SvgGenImage get search => const SvgGenImage('assets/icons/search.svg');

  /// File path: assets/icons/square.svg
  SvgGenImage get square => const SvgGenImage('assets/icons/square.svg');

  /// File path: assets/icons/text.svg
  SvgGenImage get text => const SvgGenImage('assets/icons/text.svg');

  /// List of all assets
  List<SvgGenImage> get values => [
    add,
    arrowTopRight,
    arrow,
    circle,
    comment,
    down,
    figure,
    line,
    newDoc,
    pencil,
    search,
    square,
    text,
  ];
}

class Assets {
  const Assets._();

  static const String package = 'flow_draw';

  static const $AssetsIconsGen icons = $AssetsIconsGen();
}

class SvgGenImage {
  const SvgGenImage(this._assetName, {this.size, this.flavors = const {}})
    : _isVecFormat = false;

  const SvgGenImage.vec(this._assetName, {this.size, this.flavors = const {}})
    : _isVecFormat = true;

  final String _assetName;
  final Size? size;
  final Set<String> flavors;
  final bool _isVecFormat;

  static const String package = 'flow_draw';

  _svg.SvgPicture svg({
    Key? key,
    bool matchTextDirection = false,
    AssetBundle? bundle,
    @Deprecated('Do not specify package for a generated library asset')
    String? package = package,
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    AlignmentGeometry alignment = Alignment.center,
    bool allowDrawingOutsideViewBox = false,
    WidgetBuilder? placeholderBuilder,
    String? semanticsLabel,
    bool excludeFromSemantics = false,
    _svg.SvgTheme? theme,
    ColorFilter? colorFilter,
    Clip clipBehavior = Clip.hardEdge,
    @deprecated Color? color,
    @deprecated BlendMode colorBlendMode = BlendMode.srcIn,
    @deprecated bool cacheColorFilter = false,
  }) {
    final _svg.BytesLoader loader;
    if (_isVecFormat) {
      loader = _vg.AssetBytesLoader(
        _assetName,
        assetBundle: bundle,
        packageName: package,
      );
    } else {
      loader = _svg.SvgAssetLoader(
        _assetName,
        assetBundle: bundle,
        packageName: package,
        theme: theme,
      );
    }
    return _svg.SvgPicture(
      loader,
      key: key,
      matchTextDirection: matchTextDirection,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      allowDrawingOutsideViewBox: allowDrawingOutsideViewBox,
      placeholderBuilder: placeholderBuilder,
      semanticsLabel: semanticsLabel,
      excludeFromSemantics: excludeFromSemantics,
      colorFilter:
          colorFilter ??
          (color == null ? null : ColorFilter.mode(color, colorBlendMode)),
      clipBehavior: clipBehavior,
      cacheColorFilter: cacheColorFilter,
    );
  }

  String get path => _assetName;

  String get keyName => 'packages/flow_draw/$_assetName';
}
