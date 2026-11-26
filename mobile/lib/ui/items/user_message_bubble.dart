import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../chat/chat_models.dart';
import '../../chat/user_message_style.dart';
import '../md/inline_code.dart';
import '../md/md_theme.dart';
import 'assistant_text.dart';
import 'fade_curve.dart';
import 'image_preview.dart';

/// A sent user message, echoed as text. Clicking it opens it when [onEdit]
/// is set. Dragging still selects text.
///
/// Its images show as thumbnails under the text (the desktop embeds them
/// as tags in it, by its composer's vocabulary, which the phone lacks).
///
/// A long message shows its first lines, fading out at the bottom over an
/// expand icon; the click that opens it shows it all.
///
/// The click is read from raw pointer events rather than a tap recognizer:
/// a recognizer would compete with the text's selection for the same
/// press.
class UserMessageBubble extends StatefulWidget {
  const UserMessageBubble({
    super.key,
    required this.text,
    this.images = const [],
    this.queued = false,
    this.onEdit,
  });

  final String text;
  final List<ImageAttachment> images;

  /// Sent while the agent works, waiting its turn: marked as queued.
  final bool queued;
  final VoidCallback? onEdit;

  /// Its corners; what answers it is inset this much at either side.
  static const radius = 8.0;

  /// Lines a long message shows of itself until opened.
  static const collapsedLines = _collapsedLines;

  @override
  State<UserMessageBubble> createState() => _UserMessageBubbleState();
}

/// Lines shown of a collapsed message. Messages up to one line longer show
/// in full: hiding a single line is not worth it. As the desktop's.
const _collapsedLines = 3;
const _lineHeight = 13.5 * 1.5;

TextStyle get _messageStyle => TextStyle(
  color: AppColors.onUserBubble,
  fontSize: 13.5,
  height: 1.5,
  // Centers glyphs in the line box, which the inline tags center on.
  leadingDistribution: TextLeadingDistribution.even,
);

class _UserMessageBubbleState extends State<UserMessageBubble> {
  Offset? _pressedAt;

  /// The press went to an image (which opens it whole instead). It hears
  /// the press first, being deeper (see [PreviewPressScope]).
  bool _pressOnImage = false;

  void _handleDown(PointerDownEvent event) {
    final primary =
        event.kind != PointerDeviceKind.mouse ||
        event.buttons == kPrimaryMouseButton;
    final onImage = _pressOnImage;
    _pressOnImage = false;
    _pressedAt =
        primary && !onImage && !HardwareKeyboard.instance.isShiftPressed
        ? event.position
        : null;
  }

  void _handleUp(PointerUpEvent event) {
    final pressedAt = _pressedAt;
    _pressedAt = null;
    if (pressedAt == null) return;
    // A click, not the end of a drag selection.
    if ((event.position - pressedAt).distance <= kTouchSlop) {
      widget.onEdit?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: UserMessageStyle.current,
      builder: (context, style, _) => _build(context, style),
    );
  }

  Widget _build(BuildContext context, UserMessageStyle style) {
    final fitted = style == UserMessageStyle.bubble;
    final message = _buildBubble(context, fitted: fitted);
    // As tall a tree either way, the bubble moving nowhere as the style
    // changes. Fitted: at the right, as wide as its text up to most of the
    // column; the Align takes the column's width, which centers what is
    // narrower.
    return Align(
      alignment: Alignment.centerRight,
      child: _WidthFactor(
        maxWidthFactor: fitted ? _fittedWidth : 1,
        child: message,
      ),
    );
  }

  /// The most of the column a [UserMessageStyle.bubble] bubble takes.
  static const _fittedWidth = 0.85;

  Widget _buildBubble(BuildContext context, {required bool fitted}) {
    return Listener(
      onPointerDown: _handleDown,
      onPointerUp: _handleUp,
      onPointerCancel: (_) => _pressedAt = null,
      child: PreviewPressScope(
        onPress: () => _pressOnImage = true,
        child: Container(
          // Constraints either way: a Container without them leaves out their
          // box, building its child anew as the style changes.
          constraints: fitted
              ? const BoxConstraints()
              : const BoxConstraints.tightFor(width: double.infinity),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          // As its editor and viewer: the chat input's.
          decoration: fitted
              ? ShapeDecoration(
                  color: AppColors.userBubble,
                  shape: _MessageShape(
                    side: BorderSide(
                      color: AppColors.userBubble.withValues(alpha: 0.6),
                    ),
                  ),
                )
              : BoxDecoration(
                  color: AppColors.bubbleFill,
                  borderRadius: BorderRadius.circular(UserMessageBubble.radius),
                  border: Border.all(color: AppColors.bubbleBorder()),
                ),
          child: _Collapsed(
            shrinkWrap: fitted,
            collapsedHeight: _lineHeight * _collapsedLines,
            collapseAbove: _lineHeight * (_collapsedLines + 1),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.queued)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 11,
                          color: AppColors.onUserBubble.withValues(
                            alpha: 0.55,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '排队中',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.onUserBubble.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                InlineCodeText(
                  _messageSpan(widget.text, widget.images),
                ),
              ],
            ),
            overlay: const _CollapsedOverlay(),
          ),
        ),
      ),
    );
  }
}

/// [text] as the desktop shows a sent message: its `[Image #n]`
/// references as inline image chips in the text's flow, a chip for each
/// picture the text does not refer to after it. There are no thumbnails.
TextSpan _messageSpan(String text, List<ImageAttachment> images) {
  if (images.isEmpty) return inlineCodeSpan(text, _messageStyle);
  final byNumber = {for (final image in images) ?image.number: image};
  // Numbered as they would be in the text; one sent before images were
  // numbered by its place among them.
  final numbered = [
    for (final (i, image) in images.indexed) (image.number ?? i + 1, image),
  ];
  ImageAttachment? imageOf(int number) =>
      byNumber[number] ??
      numbered.where((entry) => entry.$1 == number).firstOrNull?.$2;
  final children = <InlineSpan>[];
  final referred = <int>{};
  var at = 0;
  for (final match in imageReferencePattern.allMatches(text)) {
    final number = int.tryParse(match[1]!) ?? 0;
    final image = imageOf(number);
    if (image == null) continue;
    referred.add(number);
    if (match.start > at) {
      children.add(inlineCodeSpan(text.substring(at, match.start), _messageStyle));
    }
    children.add(_ImageChip.span(number, image, _messageStyle));
    at = match.end;
  }
  if (at < text.length) {
    children.add(inlineCodeSpan(text.substring(at), _messageStyle));
  }
  // The pictures the text never names tag along at its end, as the
  // desktop's.
  for (final (number, image) in numbered) {
    if (!referred.contains(number)) {
      children.add(const TextSpan(text: ' '));
      children.add(_ImageChip.span(number, image, _messageStyle));
    }
  }
  return TextSpan(style: _messageStyle, children: children);
}

/// An image's inline reference in a sent message: its 14 px glimpse and
/// "图片N", a click shows it whole — as the desktop's ComposerImageChip.
class _ImageChip extends StatelessWidget {
  const _ImageChip({
    required this.number,
    required this.image,
    required this.textStyle,
  });

  final int number;
  final ImageAttachment? image;
  final TextStyle textStyle;

  static InlineSpan span(
    int number,
    ImageAttachment? image,
    TextStyle textStyle,
  ) => WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: _ImageChip(number: number, image: image, textStyle: textStyle),
  );

  static const _pictureSize = 14.0;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    Widget chip = _CenteredOnText(
      textStyle: textStyle,
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          height: 1.25,
          leadingDistribution: TextLeadingDistribution.even,
        ),
        child: SelectionContainer.disabled(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.fromLTRB(2, 1, 5, 1),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.bubbleBorder()),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2.5),
                  child: SizedBox.square(
                    dimension: _pictureSize,
                    child: image == null
                        ? Icon(
                            Icons.image_outlined,
                            size: 12,
                            color: AppColors.textMuted,
                          )
                        : Image.memory(
                            image.bytes,
                            fit: BoxFit.cover,
                            cacheWidth: (_pictureSize * 3).round(),
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.broken_image_outlined,
                              size: 12,
                              color: AppColors.textFaint,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '图片$number',
                  style: TextStyle(color: AppColors.text, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (image != null) {
      chip = ImagePreviewClick(image: image, child: chip);
    }
    return chip;
  }
}

/// A chip centered on the text around it, as the desktop's: its baseline
/// reported so the glyph centers line up.
class _CenteredOnText extends SingleChildRenderObjectWidget {
  const _CenteredOnText({required this.textStyle, required super.child});

  final TextStyle textStyle;

  double _glyphCenterAboveBaseline(TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'x',
        style: textStyle.copyWith(
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final metrics = painter.computeLineMetrics().first;
    painter.dispose();
    return (metrics.ascent - metrics.descent) / 2;
  }

  @override
  _RenderCenteredOnText createRenderObject(BuildContext context) =>
      _RenderCenteredOnText(
        _glyphCenterAboveBaseline(MediaQuery.textScalerOf(context)),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCenteredOnText renderObject,
  ) {
    renderObject.centerAboveBaseline = _glyphCenterAboveBaseline(
      MediaQuery.textScalerOf(context),
    );
  }
}

class _RenderCenteredOnText extends RenderProxyBox {
  _RenderCenteredOnText(this._centerAboveBaseline);

  double _centerAboveBaseline;
  set centerAboveBaseline(double value) {
    if (value == _centerAboveBaseline) return;
    _centerAboveBaseline = value;
    markNeedsLayout();
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      size.height / 2 + _centerAboveBaseline;

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) =>
      getDryLayout(constraints).height / 2 + _centerAboveBaseline;
}

/// Over the bottom of a collapsed message, where its text fades out: an
/// expand icon.
class _CollapsedOverlay extends StatelessWidget {
  const _CollapsedOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 18,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

/// Shows [content] in full up to [collapseAbove]; beyond that, only its top
/// [collapsedHeight], fading out through its alpha at the bottom, with
/// [overlay] over the fade. Decided in layout, so
/// a long message never shows a frame at full height first.
class _Collapsed extends MultiChildRenderObjectWidget {
  _Collapsed({
    required this.shrinkWrap,
    required this.collapsedHeight,
    required this.collapseAbove,
    required Widget content,
    required Widget overlay,
  }) : super(children: [content, overlay]);

  /// As wide as the text, rather than as the room it has.
  final bool shrinkWrap;
  final double collapsedHeight;
  final double collapseAbove;

  @override
  _RenderCollapsed createRenderObject(BuildContext context) =>
      _RenderCollapsed(shrinkWrap, collapsedHeight, collapseAbove);

  @override
  void updateRenderObject(BuildContext context, _RenderCollapsed renderObject) {
    renderObject
      ..shrinkWrap = shrinkWrap
      ..collapsedHeight = collapsedHeight
      ..collapseAbove = collapseAbove;
  }
}

class _CollapsedParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderCollapsed extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CollapsedParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CollapsedParentData> {
  _RenderCollapsed(
    this._shrinkWrap,
    this._collapsedHeight,
    this._collapseAbove,
  );

  bool _shrinkWrap;
  set shrinkWrap(bool value) {
    if (value == _shrinkWrap) return;
    _shrinkWrap = value;
    markNeedsLayout();
  }

  double _collapsedHeight;
  set collapsedHeight(double value) {
    if (value == _collapsedHeight) return;
    _collapsedHeight = value;
    markNeedsLayout();
  }

  double _collapseAbove;
  set collapseAbove(double value) {
    if (value == _collapseAbove) return;
    _collapseAbove = value;
    markNeedsLayout();
  }

  /// Height of the overlay, at the bottom of the shown part, over which the
  /// text fades out.
  static const _overlayHeight = 44.0;

  /// How far the overlay (its icon) and the mask reach past the clipped
  /// text, into the bubble's bottom padding: on screen the clip edge can
  /// fall mid-pixel, and the clip keeps that whole row of pixels while a mask
  /// ending at the edge only partly covers it, leaving a row of glyphs at
  /// close to full strength (seen on the web, at some scroll offsets).
  static const _overlayOvershoot = 2.0;

  /// How far above the clip edge the text is faded out completely: the fade
  /// over the overlay is shifted up by this much, text below it hidden. The
  /// eased end of a fade is faint but not zero, and on the last line that
  /// faint trace shows as the tops of its glyphs.
  static const _fadeOffset = 10.0;

  bool _collapsed = false;

  final _maskLayer = LayerHandle<ShaderMaskLayer>();

  @override
  bool get alwaysNeedsCompositing => _collapsed;

  @override
  void dispose() {
    _maskLayer.layer = null;
    super.dispose();
  }

  RenderBox get _content => firstChild!;
  RenderBox get _overlay => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CollapsedParentData) {
      child.parentData = _CollapsedParentData();
    }
  }

  @override
  void performLayout() {
    _content.layout(
      BoxConstraints(maxWidth: constraints.maxWidth),
      parentUsesSize: true,
    );
    final full = _content.size.height;
    final collapsed = full > _collapseAbove;
    if (collapsed != _collapsed) {
      _collapsed = collapsed;
      markNeedsCompositingBitsUpdate();
    }
    size = constraints.constrain(
      Size(
        _shrinkWrap ? _content.size.width : constraints.maxWidth,
        _collapsed ? _collapsedHeight : full,
      ),
    );
    final overlayHeight = _overlayHeight.clamp(0.0, size.height);
    _overlay.layout(
      BoxConstraints.tight(Size(size.width, overlayHeight + _overlayOvershoot)),
    );
    (_overlay.parentData! as _CollapsedParentData).offset = Offset(
      0,
      size.height - overlayHeight,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_collapsed) {
      _maskLayer.layer = null;
      context.paintChild(_content, offset);
      return;
    }
    final overlayOffset = (_overlay.parentData! as _CollapsedParentData).offset;
    // Over the overlay, shifted up by [_fadeOffset]; below it the gradient
    // clamps to hidden, down through the overshoot.
    final fade = Rect.fromLTRB(
      0,
      overlayOffset.dy - _fadeOffset,
      size.width,
      size.height - _fadeOffset,
    );
    final samples = easedFade().toList().reversed;
    _maskLayer.layer = (_maskLayer.layer ?? ShaderMaskLayer())
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          for (final (_, opacity) in samples)
            Color.fromRGBO(255, 255, 255, opacity),
        ],
        stops: [for (final (t, _) in samples) 1 - t],
      ).createShader(fade)
      ..maskRect = offset & Size(size.width, size.height + _overlayOvershoot)
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(
      _maskLayer.layer!,
      (context, offset) => context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        (context, offset) => context.paintChild(_content, offset),
      ),
      offset,
    );
    context.paintChild(_overlay, offset + overlayOffset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    // Hidden text is not hit; the overlay itself takes no pointers.
    if (!size.contains(position)) return false;
    return _content.hitTest(result, position: position);
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _collapsed ? Offset.zero & size : null;

  @override
  double computeMinIntrinsicWidth(double height) =>
      _content.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _content.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) {
    final full = _content.getMinIntrinsicHeight(width);
    return full > _collapseAbove ? _collapsedHeight : full;
  }

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);
}

/// Lets its child be at most [maxWidthFactor] of the width it is given.
class _WidthFactor extends SingleChildRenderObjectWidget {
  const _WidthFactor({required this.maxWidthFactor, super.child});

  final double maxWidthFactor;

  @override
  _RenderWidthFactor createRenderObject(BuildContext context) =>
      _RenderWidthFactor(maxWidthFactor);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderWidthFactor renderObject,
  ) {
    renderObject.maxWidthFactor = maxWidthFactor;
  }
}

class _RenderWidthFactor extends RenderProxyBox {
  _RenderWidthFactor(this._maxWidthFactor);

  double _maxWidthFactor;
  set maxWidthFactor(double value) {
    if (value == _maxWidthFactor) return;
    _maxWidthFactor = value;
    markNeedsLayout();
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) {
    if (_maxWidthFactor == 1 || !constraints.hasBoundedWidth) {
      return constraints;
    }
    final maxWidth = constraints.maxWidth * _maxWidthFactor;
    return constraints.copyWith(
      minWidth: math.min(constraints.minWidth, maxWidth),
      maxWidth: maxWidth,
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(child.size);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return constraints.constrain(
      child.getDryLayout(_childConstraints(constraints)),
    );
  }
}

/// A [UserMessageStyle.bubble] bubble's outline: rounded corners, and a
/// tail hooked out of its bottom right, toward its sender, as a chat's.
/// The tail takes a strip at the right ([dimensions]), the body the rest.
class _MessageShape extends OutlinedBorder {
  const _MessageShape({super.side});

  static const radius = 10.0;
  static const tailWidth = 7.0;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.only(right: tailWidth);

  @override
  _MessageShape copyWith({BorderSide? side}) =>
      _MessageShape(side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => _MessageShape(side: side.scale(t));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.strokeInset));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  /// The outline in [rect], with [tail] of the tail (0: none, a rounded
  /// rectangle's corner in its place) and corners of [radius].
  static Path _path(Rect rect, {double tail = 1, double radius = radius}) {
    final r = radius;
    final Rect(:left, :top, :right, :bottom) = rect;
    final body = right - tailWidth * tail;
    // The bottom right corner, from the body's side, as three curves: the
    // tail's (down the body's side and out to its tip, back under it, up
    // into the body and round the rest of the corner)...
    final p0 = Offset(body - 3.5, bottom - 2.5);
    final q = Offset(body - 6, bottom);
    final p1 = Offset(body - r, bottom);
    final hooked = [
      Offset(body, bottom - 6),
      Offset(body + 2, bottom - 1),
      Offset(body + tailWidth, bottom),
      Offset(body + tailWidth - 4, bottom + 0.5),
      Offset(body - 1, bottom - 0.5),
      p0,
      p0 + (q - p0) * (2 / 3),
      p1 + (q - p1) * (2 / 3),
      p1,
    ];
    // ...or a plain corner's: on down the side, and its arc in two halves.
    final center = Offset(body - r, bottom - r);
    final h = 0.26521 * r;
    const s = math.sqrt1_2;
    final middle = center + Offset(r * s, r * s);
    final end = Offset(body - r, bottom);
    final plain = [
      Offset(body, bottom - 16 + (16 - r) / 3),
      Offset(body, bottom - 16 + (16 - r) * 2 / 3),
      Offset(body, bottom - r),
      Offset(body, bottom - r + h),
      middle + Offset(h * s, -h * s),
      middle,
      middle + Offset(-h * s, h * s),
      end + Offset(h, 0),
      end,
    ];
    final corner = [
      for (var i = 0; i < hooked.length; i++)
        Offset.lerp(plain[i], hooked[i], tail)!,
    ];
    final path = Path()
      ..moveTo(left + r, top)
      ..lineTo(body - r, top)
      ..arcToPoint(Offset(body, top + r), radius: Radius.circular(r))
      ..lineTo(body, bottom - 16);
    for (var i = 0; i < corner.length; i += 3) {
      path.cubicTo(
        corner[i].dx,
        corner[i].dy,
        corner[i + 1].dx,
        corner[i + 1].dy,
        corner[i + 2].dx,
        corner[i + 2].dy,
      );
    }
    return path
      ..lineTo(left + r, bottom)
      ..arcToPoint(Offset(left, bottom - r), radius: Radius.circular(r))
      ..lineTo(left, top + r)
      ..arcToPoint(Offset(left + r, top), radius: Radius.circular(r))
      ..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(_path(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  bool operator ==(Object other) =>
      other is _MessageShape && other.side == side;

  @override
  int get hashCode => side.hashCode;
}
