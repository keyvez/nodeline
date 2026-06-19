import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flutter/material.dart';

/// A [TextEditingController] that carries per-character style runs so a single
/// node's text can mix font families, sizes, weights, slants, and colors.
///
/// The controller keeps an internal parallel array [_runStyles] — one
/// [_RunStyle] per character of [text] — which is the source of truth while
/// editing. Insertions inherit the style of the character to their left (or the
/// pending style set by the toolbar for the empty selection); deletions drop the
/// matching entries. On commit, [toRuns] coalesces the per-character styles back
/// into a compact [TextRun] list.
///
/// Per-character bookkeeping keeps the offset math trivial and robust against
/// arbitrary edits (paste, multi-char replace, IME) — far simpler to reason
/// about than maintaining run boundaries directly.
class RichTextEditingController extends TextEditingController {
  /// The base style every run resolves against (the shape's effective style,
  /// minus per-run overrides). Used to render the live editor.
  final TextStyle base;

  /// One style per character of [text]. Length is always `text.length`.
  List<_RunStyle> _runStyles;

  /// Style applied to the next inserted character when the selection is empty
  /// (i.e. the user toggled bold then types). Null means inherit from the left.
  _RunStyle? _pendingStyle;

  /// Bumped whenever per-character styling changes so listeners (the toolbar)
  /// can refresh even when [text]/[selection] are unchanged.
  int _styleRevision = 0;
  int get styleRevision => _styleRevision;

  /// The most recent ranged (non-collapsed) selection. When the editor's
  /// [TextField] loses focus to a toolbar control, Flutter collapses the live
  /// selection — so toolbar styling actions fall back to this remembered range
  /// instead of becoming a no-op pending style. Updated on every selection
  /// change while focused.
  TextSelection? _lastRangedSelection;
  TextSelection? get lastRangedSelection => _lastRangedSelection;

  RichTextEditingController({required this.base, List<TextRun>? runs})
      : _runStyles = const [],
        super(text: _plainText(runs)) {
    _runStyles = _expand(runs, text.length);
    // Seed the edit-diff baseline to the initial text so the first edit diffs
    // against it (not against empty), preserving the seeded per-char styles.
    _lastText = text;
    addListener(_syncOnEdit);
    addListener(_trackSelection);
  }

  /// Remembers the last non-collapsed selection so toolbar actions can target
  /// it even after focus (and the live selection) moves to a toolbar control.
  void _trackSelection() {
    final sel = selection;
    if (sel.isValid && sel.start != sel.end) {
      _lastRangedSelection = sel;
    }
  }

  static String _plainText(List<TextRun>? runs) =>
      runs == null ? '' : runs.map((r) => r.text).join();

  /// Expands a run list into one [_RunStyle] per character. When [runs] is null
  /// but text exists (shouldn't normally happen), fills with inherited styles.
  static List<_RunStyle> _expand(List<TextRun>? runs, int length) {
    if (runs == null) {
      return List.filled(length, const _RunStyle());
    }
    final out = <_RunStyle>[];
    for (final r in runs) {
      final s = _RunStyle(
        fontFamily: r.fontFamily,
        fontSize: r.fontSize,
        bold: r.bold,
        italic: r.italic,
        color: r.color,
      );
      for (var i = 0; i < r.text.length; i++) {
        out.add(s);
      }
    }
    // Guard against any drift between joined text and run lengths.
    if (out.length < length) {
      out.addAll(List.filled(length - out.length, const _RunStyle()));
    } else if (out.length > length) {
      out.removeRange(length, out.length);
    }
    return out;
  }

  String _lastText = '';

  /// Keeps [_runStyles] aligned with [text] after every edit by diffing the
  /// previous and current strings around their common prefix/suffix.
  void _syncOnEdit() {
    final newText = text;
    if (newText == _lastText) return;
    final old = _lastText;
    _lastText = newText;

    // Common prefix length.
    int pre = 0;
    final minLen = old.length < newText.length ? old.length : newText.length;
    while (pre < minLen && old.codeUnitAt(pre) == newText.codeUnitAt(pre)) {
      pre++;
    }
    // Common suffix length (not overlapping the prefix).
    int suf = 0;
    while (suf < minLen - pre &&
        old.codeUnitAt(old.length - 1 - suf) ==
            newText.codeUnitAt(newText.length - 1 - suf)) {
      suf++;
    }

    final removed = old.length - pre - suf; // chars deleted in [pre, ...]
    final inserted = newText.length - pre - suf; // chars added at pre

    // Style new characters inherit from: explicit pending style, else the
    // character to the left of the insertion, else the one to the right, else base.
    _RunStyle inheritStyle() {
      if (_pendingStyle != null) return _pendingStyle!;
      if (pre > 0 && pre - 1 < _runStyles.length) return _runStyles[pre - 1];
      final rightIdx = pre + removed;
      if (rightIdx < _runStyles.length) return _runStyles[rightIdx];
      return const _RunStyle();
    }

    if (removed > 0) {
      final end = (pre + removed).clamp(0, _runStyles.length);
      _runStyles.removeRange(pre.clamp(0, _runStyles.length), end);
    }
    if (inserted > 0) {
      final style = inheritStyle();
      _runStyles.insertAll(
        pre.clamp(0, _runStyles.length),
        List.filled(inserted, style),
      );
    }

    // Repair any length mismatch defensively.
    if (_runStyles.length != newText.length) {
      _runStyles = _expand(toRuns(), newText.length);
    }
    // Typed characters consumed the pending style.
    if (inserted > 0) _pendingStyle = null;
  }

  /// The selection toolbar actions should target: the live ranged selection if
  /// there is one, otherwise the last remembered range (focus may have moved to
  /// a toolbar control, collapsing the live selection), otherwise the caret.
  TextSelection _effectiveSelection() {
    final sel = selection;
    if (sel.isValid && sel.start != sel.end) return sel;
    final remembered = _lastRangedSelection;
    if (remembered != null &&
        remembered.start <= text.length &&
        remembered.end <= text.length) {
      return remembered;
    }
    return sel;
  }

  /// The aggregate style of the current selection, for driving toolbar state.
  /// Returns null for an attribute when the selection spans mixed values.
  ResolvedSelectionStyle selectionStyle() {
    final sel = _effectiveSelection();
    if (!sel.isValid || _runStyles.isEmpty) {
      final s = _pendingStyle ?? const _RunStyle();
      return ResolvedSelectionStyle._fromRun(s, base);
    }
    int start = sel.start;
    int end = sel.end;
    if (start == end) {
      // Caret: reflect the pending style, or the char to the left.
      final s = _pendingStyle ??
          (start > 0 && start - 1 < _runStyles.length
              ? _runStyles[start - 1]
              : const _RunStyle());
      return ResolvedSelectionStyle._fromRun(s, base);
    }
    start = start.clamp(0, _runStyles.length);
    end = end.clamp(0, _runStyles.length);
    return ResolvedSelectionStyle._fromRange(_runStyles.sublist(start, end), base);
  }

  /// Applies a style change to the current selection (or queues it as pending
  /// for the next typed character when the selection is empty).
  ///
  /// Each parameter is wrapped so callers distinguish "leave unchanged" (null
  /// arg) from "set to null/inherit". Use [Attr.set]/[Attr.clear].
  void applyToSelection({
    Attr<String?>? fontFamily,
    Attr<double?>? fontSize,
    Attr<bool?>? bold,
    Attr<bool?>? italic,
    Attr<int?>? color,
  }) {
    _RunStyle mutate(_RunStyle s) => s.copyWith(
          fontFamily: fontFamily,
          fontSize: fontSize,
          bold: bold,
          italic: italic,
          color: color,
        );

    final sel = _effectiveSelection();
    if (!sel.isValid || sel.start == sel.end) {
      _pendingStyle = mutate(_pendingStyle ??
          (sel.isValid && sel.start > 0 && sel.start - 1 < _runStyles.length
              ? _runStyles[sel.start - 1]
              : const _RunStyle()));
      _styleRevision++;
      notifyListeners();
    } else {
      final start = sel.start.clamp(0, _runStyles.length);
      final end = sel.end.clamp(0, _runStyles.length);
      for (var i = start; i < end; i++) {
        _runStyles[i] = mutate(_runStyles[i]);
      }
      _styleRevision++;
      // Re-assert the selection as the live one so the highlight persists and
      // repeated toolbar actions keep targeting it (setting `selection` here
      // also notifies listeners). Guard against a no-op assignment.
      if (selection != sel) {
        selection = sel;
      } else {
        notifyListeners();
      }
    }
  }

  /// Compact run list for persistence, coalescing equal adjacent characters.
  List<TextRun> toRuns() {
    final runs = <TextRun>[];
    for (var i = 0; i < text.length; i++) {
      final s = i < _runStyles.length ? _runStyles[i] : const _RunStyle();
      final ch = text[i];
      if (runs.isNotEmpty && _styleOf(runs.last).matches(s)) {
        runs[runs.length - 1] =
            runs.last.copyWith(text: runs.last.text + ch);
      } else {
        runs.add(TextRun(
          ch,
          fontFamily: s.fontFamily,
          fontSize: s.fontSize,
          bold: s.bold,
          italic: s.italic,
          color: s.color,
        ));
      }
    }
    return normalizeRuns(runs);
  }

  static _RunStyle _styleOf(TextRun r) => _RunStyle(
        fontFamily: r.fontFamily,
        fontSize: r.fontSize,
        bold: r.bold,
        italic: r.italic,
        color: r.color,
      );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = (style ?? const TextStyle()).merge(base);
    if (text.isEmpty) return TextSpan(style: baseStyle);

    final children = <TextSpan>[];
    final buf = StringBuffer();
    _RunStyle? current;
    void flush() {
      if (buf.isEmpty) return;
      children.add(TextSpan(
        text: buf.toString(),
        style: current!.resolve(baseStyle),
      ));
      buf.clear();
    }

    for (var i = 0; i < text.length; i++) {
      final s = i < _runStyles.length ? _runStyles[i] : const _RunStyle();
      if (current == null || !current.matches(s)) {
        flush();
        current = s;
      }
      buf.write(text[i]);
    }
    flush();
    return TextSpan(style: baseStyle, children: children);
  }

  @override
  void dispose() {
    removeListener(_syncOnEdit);
    super.dispose();
  }
}

/// Wraps an optional update so a `null` value is distinguishable from "no
/// change". `Attr.set(x)` writes x (including null); a null `Attr` means skip.
class Attr<T> {
  final T value;
  const Attr.set(this.value);
  static Attr<T> clear<T>() => Attr<T>.set(null as T);
}

/// Per-character style overrides; null fields inherit from the base style.
@immutable
class _RunStyle {
  final String? fontFamily;
  final double? fontSize;
  final bool? bold;
  final bool? italic;
  final int? color;

  const _RunStyle({
    this.fontFamily,
    this.fontSize,
    this.bold,
    this.italic,
    this.color,
  });

  bool matches(_RunStyle o) =>
      fontFamily == o.fontFamily &&
      fontSize == o.fontSize &&
      bold == o.bold &&
      italic == o.italic &&
      color == o.color;

  _RunStyle copyWith({
    Attr<String?>? fontFamily,
    Attr<double?>? fontSize,
    Attr<bool?>? bold,
    Attr<bool?>? italic,
    Attr<int?>? color,
  }) {
    return _RunStyle(
      fontFamily: fontFamily == null ? this.fontFamily : fontFamily.value,
      fontSize: fontSize == null ? this.fontSize : fontSize.value,
      bold: bold == null ? this.bold : bold.value,
      italic: italic == null ? this.italic : italic.value,
      color: color == null ? this.color : color.value,
    );
  }

  TextStyle resolve(TextStyle base) {
    return base.copyWith(
      fontFamily: fontFamily ?? base.fontFamily,
      fontSize: fontSize ?? base.fontSize,
      fontWeight: bold == null
          ? base.fontWeight
          : (bold! ? FontWeight.bold : FontWeight.normal),
      fontStyle: italic == null
          ? base.fontStyle
          : (italic! ? FontStyle.italic : FontStyle.normal),
      color: color != null ? Color(color!) : base.color,
    );
  }
}

/// Snapshot of a selection's resolved attributes for the toolbar. A null field
/// means the selection mixes values for that attribute.
class ResolvedSelectionStyle {
  final String? fontFamily;
  final double? fontSize;
  final bool? bold;
  final bool? italic;
  final int? color;

  const ResolvedSelectionStyle({
    this.fontFamily,
    this.fontSize,
    this.bold,
    this.italic,
    this.color,
  });

  factory ResolvedSelectionStyle._fromRun(_RunStyle s, TextStyle base) {
    return ResolvedSelectionStyle(
      fontFamily: s.fontFamily ?? base.fontFamily,
      fontSize: s.fontSize ?? base.fontSize,
      bold: s.bold ?? (base.fontWeight == FontWeight.bold),
      italic: s.italic ?? (base.fontStyle == FontStyle.italic),
      color: s.color ?? base.color?.value,
    );
  }

  factory ResolvedSelectionStyle._fromRange(
      List<_RunStyle> styles, TextStyle base) {
    if (styles.isEmpty) {
      return ResolvedSelectionStyle._fromRun(const _RunStyle(), base);
    }
    final first = ResolvedSelectionStyle._fromRun(styles.first, base);
    String? family = first.fontFamily;
    double? size = first.fontSize;
    bool? bold = first.bold;
    bool? italic = first.italic;
    int? color = first.color;
    for (final s in styles.skip(1)) {
      final r = ResolvedSelectionStyle._fromRun(s, base);
      if (r.fontFamily != family) family = null;
      if (r.fontSize != size) size = null;
      if (r.bold != bold) bold = null;
      if (r.italic != italic) italic = null;
      if (r.color != color) color = null;
    }
    return ResolvedSelectionStyle(
      fontFamily: family,
      fontSize: size,
      bold: bold,
      italic: italic,
      color: color,
    );
  }
}
