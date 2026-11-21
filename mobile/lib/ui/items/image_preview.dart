import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/chat_models.dart';
import 'l10n.dart';

/// Shows [image] whole over everything, a tap or the back button closing
/// it: the phone's [showImageGallery], one picture and no menu.
void showImagePreview(BuildContext context, ImageAttachment image) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      pageBuilder: (context, _, _) => _ImagePreviewPage(image: image),
    ),
  );
}

class _ImagePreviewPage extends StatelessWidget {
  const _ImagePreviewPage({required this.image});

  final ImageAttachment image;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 8,
                child: Image.memory(image.bytes, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 12,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                tooltip: context.l10n.commonClose,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [child], which a click shows [image] whole from (see [showImagePreview]).
class ImagePreviewClick extends StatelessWidget {
  const ImagePreviewClick({
    super.key,
    required this.image,
    required this.child,
  });

  final ImageAttachment image;
  final Widget child;

  @override
  Widget build(BuildContext context) => PreviewClick(
    onOpen: () => showImagePreview(context, image),
    child: child,
  );
}

/// [child], a tag for something shown shortened (an image, a long paste),
/// which a click opens whole ([onOpen]). Hears the click itself rather
/// than through a gesture, so a selection of the text around it (in an
/// editor, a message) goes on as it would.
class PreviewClick extends StatefulWidget {
  const PreviewClick({super.key, required this.onOpen, required this.child});

  final VoidCallback onOpen;
  final Widget child;

  @override
  State<PreviewClick> createState() => _PreviewClickState();
}

class _PreviewClickState extends State<PreviewClick> {
  /// Where a primary press went down; null for other presses.
  Offset? _pressedAt;

  void _handleDown(PointerDownEvent event) {
    final primary =
        event.kind != PointerDeviceKind.mouse ||
        event.buttons == kPrimaryMouseButton;
    // Shift extends a selection.
    if (!primary || HardwareKeyboard.instance.isShiftPressed) return;
    _pressedAt = event.position;
    PreviewPressScope._press(context);
  }

  void _handleUp(PointerUpEvent event) {
    final pressedAt = _pressedAt;
    _pressedAt = null;
    // A click, not the end of a drag selection.
    if (pressedAt == null ||
        (event.position - pressedAt).distance > kTouchSlop) {
      return;
    }
    widget.onOpen();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: Listener(
      onPointerDown: _handleDown,
      onPointerUp: _handleUp,
      onPointerCancel: (_) => _pressedAt = null,
      child: widget.child,
    ),
  );
}

/// Tells what is around images and tags a press on one of them (which opens
/// it whole, see [PreviewClick]) from a press on the rest of it: [onPress]
/// hears it first.
class PreviewPressScope extends InheritedWidget {
  const PreviewPressScope({
    super.key,
    required this.onPress,
    required super.child,
  });

  final VoidCallback onPress;

  static void _press(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PreviewPressScope>()?.onPress();

  @override
  bool updateShouldNotify(PreviewPressScope oldWidget) => false;
}
