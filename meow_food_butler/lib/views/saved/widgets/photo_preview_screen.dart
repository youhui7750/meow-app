import 'dart:ui' as ui;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

/// A photo source — either a resolved network [url] or a Firebase Storage [path].
/// At least one must be non-null.
class PhotoSource {
  final String? url;
  final String? path;

  const PhotoSource({this.url, this.path});
}

/// Full-screen lightbox with swipe-down-to-dismiss, pinch-to-zoom, prev/next
/// navigation, and support for both network URLs and Firebase Storage paths.
class PhotoPreviewScreen extends StatefulWidget {
  final List<PhotoSource> sources;
  final int initialIndex;

  const PhotoPreviewScreen({
    super.key,
    required this.sources,
    required this.initialIndex,
  });

  /// Convenience helper that pushes the preview as a fade-in transparent route.
  static void show(
    BuildContext context, {
    required List<PhotoSource> sources,
    int initialIndex = 0,
  }) {
    if (sources.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.20),
        pageBuilder: (_, animation, _) => PhotoPreviewScreen(
          sources: sources,
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<PhotoPreviewScreen> createState() => _PhotoPreviewScreenState();
}

class _PhotoPreviewScreenState extends State<PhotoPreviewScreen> {
  late final PageController _pageController;
  late int _currentIndex;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex =
        widget.initialIndex.clamp(0, widget.sources.length - 1).toInt();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _moveBy(int delta) {
    final next =
        (_currentIndex + delta).clamp(0, widget.sources.length - 1).toInt();
    if (next == _currentIndex) return;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (delta <= 0 && _dragOffset <= 0) return;
    setState(() => _dragOffset = (_dragOffset + delta).clamp(0.0, 240.0));
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 90 || velocity > 700) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = _currentIndex > 0;
    final canGoForward = _currentIndex < widget.sources.length - 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.36),
          child: SafeArea(
            child: Stack(
              children: [
                // ---- Photo swipe area ----
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: _handleDragUpdate,
                  onVerticalDragEnd: _handleDragEnd,
                  child: AnimatedSlide(
                    offset: Offset(0, _dragOffset / 520),
                    duration: _dragOffset == 0
                        ? const Duration(milliseconds: 180)
                        : Duration.zero,
                    curve: Curves.easeOutCubic,
                    child: LayoutBuilder(
                      builder: (context, constraints) => Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: SizedBox(
                            width: constraints.maxWidth * 0.88,
                            height: constraints.maxHeight * 0.78,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.28),
                              ),
                              child: PageView.builder(
                                controller: _pageController,
                                itemCount: widget.sources.length,
                                onPageChanged: (i) =>
                                    setState(() => _currentIndex = i),
                                itemBuilder: (context, index) => Center(
                                  child: InteractiveViewer(
                                    minScale: 1,
                                    maxScale: 4,
                                    child: _PhotoSourceView(
                                      source: widget.sources[index],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ---- Close button ----
                Positioned(
                  top: 12,
                  left: 12,
                  child: IconButton.filled(
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.55),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ),

                // ---- Page counter ----
                Positioned(
                  top: 18,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          '${_currentIndex + 1} / ${widget.sources.length}',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ---- Prev/Next arrows ----
                if (widget.sources.length > 1) ...[
                  Positioned(
                    left: 16,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton.filled(
                        onPressed: canGoBack ? () => _moveBy(-1) : null,
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Colors.black.withValues(alpha: 0.55),
                          disabledBackgroundColor:
                              Colors.black.withValues(alpha: 0.18),
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white38,
                        ),
                        icon: const Icon(Icons.chevron_left),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton.filled(
                        onPressed: canGoForward ? () => _moveBy(1) : null,
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Colors.black.withValues(alpha: 0.55),
                          disabledBackgroundColor:
                              Colors.black.withValues(alpha: 0.18),
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white38,
                        ),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal: renders one photo from either a URL or a Storage path.
// ---------------------------------------------------------------------------

class _PhotoSourceView extends StatefulWidget {
  final PhotoSource source;

  const _PhotoSourceView({required this.source});

  @override
  State<_PhotoSourceView> createState() => _PhotoSourceViewState();
}

class _PhotoSourceViewState extends State<_PhotoSourceView> {
  Future<String>? _pathFuture;

  @override
  void initState() {
    super.initState();
    if (widget.source.url == null && widget.source.path != null) {
      _pathFuture = FirebaseStorage.instance
          .ref(widget.source.path!)
          .getDownloadURL();
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.source.url;
    if (url != null) return _networkImage(url);

    return FutureBuilder<String>(
      future: _pathFuture,
      builder: (context, snap) {
        if (snap.hasData) return _networkImage(snap.data!);
        if (snap.hasError) {
          return const Icon(
            Icons.broken_image_outlined,
            color: Colors.white70,
            size: 48,
          );
        }
        return const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white54,
          ),
        );
      },
    );
  }

  Widget _networkImage(String url) => Image.network(
        url,
        fit: BoxFit.contain,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (_, _, _) => const Icon(
          Icons.broken_image_outlined,
          color: Colors.white70,
          size: 48,
        ),
      );
}
