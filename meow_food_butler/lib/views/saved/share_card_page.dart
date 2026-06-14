import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class RestaurantCardData {
  final String name;
  final String address;
  final double personalRating;
  final String personalNote;
  final String? photoUrl;
  final String? photoPath;
  final String date;

  RestaurantCardData({
    required this.name,
    required this.address,
    required this.personalRating,
    required this.personalNote,
    required this.photoUrl,
    required this.photoPath,
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
  bool _isSharing = false;

  Future<void> _shareToInstagramStory() async {
    setState(() {
      _isSharing = true;
    });

    File? imageFile;
    try {
      imageFile = await _captureCardImage();
      if (imageFile == null) {
        throw Exception('Unable to capture share card image.');
      }

      final result = await _platform.invokeMethod<bool>('shareInstagramStory', {
        'imagePath': imageFile.path,
        'backgroundTopColor': '#FAFAF8',
        'backgroundBottomColor': '#F0EDE6',
      });

      if (result == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opened Instagram Story share.')),
        );
      } else if (imageFile != null) {
        await _shareFallback(imageFile);
      }
    } on PlatformException catch (_) {
      if (imageFile != null) {
        await _shareFallback(imageFile);
      } else if (!mounted) {
        return;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('分享失敗：無法生成分享圖片。')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失敗：${error.toString()}')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isSharing = false;
      });
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
    final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      return null;
    }

    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      return null;
    }

    final Uint8List pngBytes = byteData.buffer.asUint8List();
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/meow_food_butler_share_card.png');

    await file.writeAsBytes(pngBytes);
    return file;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F2ED),
      appBar: AppBar(
        title: const Text('Share Review Card'),
        backgroundColor: const Color(0xFFF5F2ED),
        foregroundColor: const Color(0xFF1A1A18),
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              RepaintBoundary(
                key: _cardKey,
                child: _RestaurantShareCard(data: widget.data),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1D9E75),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isSharing ? null : _shareToInstagramStory,
                  child: _isSharing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFFFFF)),
                            strokeWidth: 2.4,
                          ),
                        )
                      : const Text(
                          '分享到 IG Story',
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RestaurantShareCard extends StatelessWidget {
  final RestaurantCardData data;

  const _RestaurantShareCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAF8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE0DDD5),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPhotoSection(),
          _buildTextSection(),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF).withOpacity(0.92),
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
    if (data.photoUrl != null && data.photoUrl!.isNotEmpty) {
      return Image.network(
        data.photoUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          if (data.photoPath != null && data.photoPath!.isNotEmpty) {
            return _StoragePathImage(
              path: data.photoPath!,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              fallback: _buildPhotoPlaceholder(),
            );
          }
          return _buildPhotoPlaceholder();
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          return _buildPhotoPlaceholder();
        },
      );
    }

    if (data.photoPath != null && data.photoPath!.isNotEmpty) {
      return _StoragePathImage(
        path: data.photoPath!,
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
        child: Icon(
          Icons.camera_alt,
          size: 44,
          color: Color(0xFF8B8B84),
        ),
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
            '“${data.personalNote}”',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF444441),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFF1D9E75),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.pets,
                  size: 14,
                  color: Color(0xFFFFFFFF),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Meow Food Butler',
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
