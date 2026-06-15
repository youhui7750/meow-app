import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

class RestaurantCardData {
  final String name;
  final String address;
  final double personalRating;
  final String personalNote;
  final List<String> photoUrls;
  final List<String> photoPaths;
  final String date;

  RestaurantCardData({
    required this.name,
    required this.address,
    required this.personalRating,
    required this.personalNote,
    this.photoUrls = const [],
    this.photoPaths = const [],
    required this.date,
  });
}

class ShareCardPage extends StatefulWidget {
  final RestaurantCardData data;

  const ShareCardPage({super.key, required this.data});

  @override
  State<ShareCardPage> createState() => _ShareCardPageState();
}

class _ShareCardPageState extends State<ShareCardPage> {
  static const _platform = MethodChannel('meow_food_butler/shared_text');
  final GlobalKey _cardKey = GlobalKey();
  final PageController _cardController = PageController();
  bool _isSharing = false;
  bool _isSaving = false;
  int _currentIndex = 0;

  int get _photoCount {
    final n = widget.data.photoUrls.length > widget.data.photoPaths.length
        ? widget.data.photoUrls.length
        : widget.data.photoPaths.length;
    return n == 0 ? 1 : n;
  }

  @override
  void dispose() {
    _cardController.dispose();
    super.dispose();
  }

  Future<void> _saveToAlbum() async {
    setState(() => _isSaving = true);
    try {
      final imageFile = await _captureCardImage();
      if (imageFile == null) throw Exception('無法產生圖片');

      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要相簿存取權限才能儲存圖片')),
          );
          return;
        }
      }

      await Gal.putImage(imageFile.path, album: 'Meow Butler');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已儲存到相簿')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('儲存失敗：${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _shareToInstagramStory() async {
    setState(() => _isSharing = true);

    File? imageFile;
    try {
      imageFile = await _captureStoryImage();
      if (imageFile == null) throw Exception('Unable to capture share card image.');

      final result = await _platform.invokeMethod<bool>('shareInstagramStory', {
        'backgroundImage': imageFile.path,
        'backgroundTopColor': '#FAFAF8',
        'backgroundBottomColor': '#F0EDE6',
      });

      if (result == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opened Instagram Story share.')),
        );
      } else {
        await _shareFallback(imageFile);
      }
    } on PlatformException catch (_) {
      await _shareFallback(imageFile!);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失敗：${error.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _shareFallback(File imageFile) async {
    try {
      await Share.shareXFiles(
        [XFile(imageFile.path)],
        text: '分享我的 Meow Food Butler 食評卡片',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shared using available share sheet.')),
      );
    } catch (shareError) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失敗：${shareError.toString()}')),
      );
    }
  }

  Future<File?> _captureCardImage() async {
    final boundary =
        _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;

    final Uint8List pngBytes = byteData.buffer.asUint8List();
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/meow_food_butler_share_card.png');
    await file.writeAsBytes(pngBytes);
    return file;
  }

  /// Composes a 1080×1920 IG Story: blurred photo bg + centred scaled card.
  Future<File?> _captureStoryImage() async {
    final cardBoundary =
        _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (cardBoundary == null) return null;

    const pixelRatio = 3.0;
    // Expected canvas pixels for the 320×470 card
    const cardW = 320.0 * pixelRatio; // 960
    const cardH = 470.0 * pixelRatio; // 1410

    final rawImage = await cardBoundary.toImage(pixelRatio: pixelRatio);

    // Crop to exact card dimensions in case PageView painted adjacent pages.
    final ui.Image cardImage;
    if (rawImage.width != cardW.toInt() || rawImage.height != cardH.toInt()) {
      final cropRecorder = ui.PictureRecorder();
      final cropCanvas = Canvas(cropRecorder);
      cropCanvas.drawImageRect(
        rawImage,
        Rect.fromLTWH(0, 0, cardW, cardH),
        Rect.fromLTWH(0, 0, cardW, cardH),
        Paint(),
      );
      cardImage = await cropRecorder
          .endRecording()
          .toImage(cardW.toInt(), cardH.toInt());
    } else {
      cardImage = rawImage;
    }

    // Fixed IG Story canvas (1080×1920)
    const storyW = 1080.0;
    const storyH = 1920.0;
    final storyRect = Rect.fromLTWH(0, 0, storyW, storyH);

    // Scale card to 80% of story width and centre it
    const scale = (storyW * 0.80) / cardW;
    const scaledW = cardW * scale;
    const scaledH = cardH * scale;
    const cardX = (storyW - scaledW) / 2;
    const cardY = (storyH - scaledH) / 2;

    // Resolve background photo URL
    final photoUrl = _currentIndex < widget.data.photoUrls.length
        ? widget.data.photoUrls[_currentIndex]
        : null;
    final photoPath = _currentIndex < widget.data.photoPaths.length
        ? widget.data.photoPaths[_currentIndex]
        : null;

    String? bgUrl =
        (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : null;
    if (bgUrl == null && photoPath != null && photoPath.isNotEmpty) {
      try {
        bgUrl =
            await FirebaseStorage.instance.ref(photoPath).getDownloadURL();
      } catch (_) {}
    }

    final ui.Image? bgImage =
        bgUrl != null ? await _loadNetworkImage(bgUrl) : null;

    // Compose
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    if (bgImage != null) {
      // Cover-crop bg to fill 1080×1920
      final bgW = bgImage.width.toDouble();
      final bgH = bgImage.height.toDouble();
      final bgAspect = bgW / bgH;
      const storyAspect = storyW / storyH;
      final Rect srcRect;
      if (bgAspect > storyAspect) {
        final cropW = bgH * storyAspect;
        srcRect = Rect.fromLTWH((bgW - cropW) / 2, 0, cropW, bgH);
      } else {
        final cropH = bgW / storyAspect;
        srcRect = Rect.fromLTWH(0, (bgH - cropH) / 2, bgW, cropH);
      }

      // Blurred background layer
      canvas.saveLayer(
        storyRect,
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
      );
      canvas.drawImageRect(bgImage, srcRect, storyRect, Paint());
      canvas.restore();

      // Dark overlay so card pops
      canvas.drawRect(storyRect, Paint()..color = const Color(0x55000000));
    } else {
      // Fallback gradient
      canvas.drawRect(
        storyRect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(0, storyH),
            [const Color(0xFFFAFAF8), const Color(0xFFF0EDE6)],
          ),
      );
    }

    // Card image (scaled into dstRect)
    canvas.drawImageRect(
      cardImage,
      Rect.fromLTWH(0, 0, cardW, cardH),
      Rect.fromLTWH(cardX, cardY, scaledW, scaledH),
      Paint(),
    );

    final picture = recorder.endRecording();
    final storyUiImage =
        await picture.toImage(storyW.toInt(), storyH.toInt());
    final byteData =
        await storyUiImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;

    final pngBytes = byteData.buffer.asUint8List();
    final directory = await getTemporaryDirectory();
    final file =
        File('${directory.path}/meow_food_butler_story_export.png');
    await file.writeAsBytes(pngBytes);
    return file;
  }

  Future<ui.Image?> _loadNetworkImage(String url) async {
    final completer = Completer<ui.Image?>();
    NetworkImage(url).resolve(const ImageConfiguration()).addListener(
      ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info.image);
        },
        onError: (_, _) {
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Share Review Card'),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The RepaintBoundary wraps the entire card area (including PageView).
                    // toImage() captures whatever page is currently visible.
                    RepaintBoundary(
                      key: _cardKey,
                      child: ClipRect(
                        child: SizedBox(
                          width: 320,
                          height: 470,
                          child: PageView.builder(
                            controller: _cardController,
                            itemCount: _photoCount,
                            onPageChanged: (i) =>
                                setState(() => _currentIndex = i),
                            itemBuilder: (context, index) {
                              final url = index < widget.data.photoUrls.length
                                  ? widget.data.photoUrls[index]
                                  : null;
                              final path =
                                  index < widget.data.photoPaths.length
                                      ? widget.data.photoPaths[index]
                                      : null;
                              return _RestaurantShareCard(
                                data: widget.data,
                                photoUrl: url,
                                photoPath: path,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    // Dots are outside the RepaintBoundary — not captured in the exported image
                    if (_photoCount > 1) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_photoCount, (i) {
                          final selected = i == _currentIndex;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: selected ? 14 : 5,
                            height: 5,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: colorScheme.onSurface
                                  .withValues(alpha: selected ? 0.6 : 0.2),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          );
                        }),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: colorScheme.outline),
                      ),
                      onPressed: _isSaving ? null : _saveToAlbum,
                      icon: _isSaving
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.primary,
                              ),
                            )
                          : const Icon(Icons.download_outlined),
                      label: const Text(
                        '儲存到相簿',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.primaryContainer,
                        foregroundColor: colorScheme.onPrimaryContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isSharing ? null : _shareToInstagramStory,
                      icon: _isSharing
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    colorScheme.onPrimaryContainer),
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.send_outlined),
                      label: const Text(
                        '分享到 IG Story',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestaurantShareCard extends StatelessWidget {
  final RestaurantCardData data;
  final String? photoUrl;
  final String? photoPath;

  const _RestaurantShareCard({
    required this.data,
    this.photoUrl,
    this.photoPath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAF8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0DDD5), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPhotoSection(),
          Expanded(child: _buildTextSection()),
        ],
      ),
    );
  }

  Widget _buildPhotoSection() {
    return SizedBox(
      height: 260,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildPhotoContent(),
            Positioned(
              bottom: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StarRating(rating: data.personalRating),
                    const SizedBox(width: 8),
                    Text(
                      data.personalRating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Color(0xFF1A1A18),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoContent() {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return Image.network(
        photoUrl!,
        key: ValueKey(photoUrl),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (context, error, stackTrace) {
          if (photoPath != null && photoPath!.isNotEmpty) {
            return _StoragePathImage(
              path: photoPath!,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              fallback: _buildPhotoPlaceholder(),
            );
          }
          return _buildPhotoPlaceholder();
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildPhotoPlaceholder();
        },
      );
    }

    if (photoPath != null && photoPath!.isNotEmpty) {
      return _StoragePathImage(
        path: photoPath!,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        fallback: _buildPhotoPlaceholder(),
      );
    }

    return _buildPhotoPlaceholder();
  }

  Widget _buildPhotoPlaceholder() {
    return Container(
      color: const Color(0xFFD9D9D4),
      child: const Center(
        child: Icon(Icons.camera_alt, size: 44, color: Color(0xFF8B8B84)),
      ),
    );
  }

  Widget _buildTextSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A18),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 14,
                color: Color(0xFF888780),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  data.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF888780),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFE0DDD5)),
          const SizedBox(height: 14),
          Text(
            '"${data.personalNote}"',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF444441),
              height: 1.6,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 22,
                  height: 22,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Meow Butler',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A18),
                ),
              ),
              const Spacer(),
              Text(
                data.date,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF888780),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StoragePathImage extends StatelessWidget {
  final String path;
  final double width;
  final double height;
  final BoxFit fit;
  final Widget fallback;

  const _StoragePathImage({
    required this.path,
    required this.width,
    required this.height,
    required this.fit,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: FirebaseStorage.instance.ref(path).getDownloadURL(),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            width: width,
            height: height,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (url == null) {
          return fallback;
        }
        return Image.network(
          key: ValueKey(url),
          url,
          width: width,
          height: height,
          fit: fit,
          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
          errorBuilder: (context, error, stackTrace) => fallback,
        );
      },
    );
  }
}

class _StarRating extends StatelessWidget {
  final double rating;

  const _StarRating({required this.rating});

  @override
  Widget build(BuildContext context) {
    final stars = List<Widget>.generate(
      5,
      (index) {
        final value = index + 1;
        if (rating >= value) {
          return const Icon(
            Icons.star_rounded,
            size: 14,
            color: Color(0xFFE8A020),
          );
        }

        if (rating >= value - 0.5) {
          return const Icon(
            Icons.star_half_rounded,
            size: 14,
            color: Color(0xFFE8A020),
          );
        }

        return const Icon(
          Icons.star_outline_rounded,
          size: 14,
          color: Color(0xFFE8A020),
        );
      },
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: stars
          .expand((widget) => [widget, const SizedBox(width: 2)])
          .toList()
        ..removeLast(),
    );
  }
}