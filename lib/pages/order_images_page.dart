import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../services/database_service.dart';
import 'fabric_page.dart' show detectImageType;

class OrderImagesPage extends StatelessWidget {
  final String orderId;
  final String orderLabel;

  const OrderImagesPage({
    super.key,
    required this.orderId,
    required this.orderLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Order Photos',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(orderLabel, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
      body: _OrderImagesBody(orderId: orderId),
    );
  }
}

class _OrderImagesBody extends StatefulWidget {
  final String orderId;

  const _OrderImagesBody({required this.orderId});

  @override
  State<_OrderImagesBody> createState() => _OrderImagesBodyState();
}

class _OrderImagesBodyState extends State<_OrderImagesBody> {
  final DatabaseService _dbService = DatabaseService();
  bool _isUploading = false;
  double _uploadProgress = 0;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(
      maxWidth: 2048,
      imageQuality: 85,
    );
    if (picked.isEmpty || !mounted) return;
    await _uploadFiles(picked);
  }

  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2048,
      imageQuality: 85,
    );
    if (photo == null || !mounted) return;
    await _uploadFiles([photo]);
  }

  Future<void> _uploadFiles(List<XFile> picked) async {
    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      for (var i = 0; i < picked.length; i++) {
        final file = picked[i];
        final Uint8List bytes = await file.readAsBytes();
        final type = detectImageType(bytes);
        if (type == null) {
          throw '${file.name}: unsupported format (use JPEG, PNG or WebP)';
        }
        final fileName =
            'order_${widget.orderId}_${DateTime.now().millisecondsSinceEpoch}_$i.${type.ext}';
        final ref = FirebaseStorage.instance
            .ref()
            .child('order_images')
            .child(widget.orderId)
            .child(fileName);

        final task = ref.putData(
          bytes,
          SettableMetadata(contentType: type.contentType),
        );

        task.snapshotEvents.listen((snapshot) {
          if (!mounted || snapshot.totalBytes == 0) return;
          setState(() {
            _uploadProgress =
                (i + snapshot.bytesTransferred / snapshot.totalBytes) /
                picked.length;
          });
        });

        final snapshot = await task;
        final downloadUrl = await snapshot.ref.getDownloadURL();

        await _dbService.addOrderImage(
          orderId: widget.orderId,
          imageUrl: downloadUrl,
          fileName: fileName,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            picked.length == 1
                ? 'Photo uploaded successfully'
                : '${picked.length} photos uploaded successfully',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    String docId,
    String imageUrl,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Photo'),
        content: const Text(
          'Are you sure you want to delete this photo? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await _dbService.deleteOrderImage(docId: docId, storageUrl: imageUrl);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Photo deleted')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openLightbox(
    BuildContext context,
    List<Map<String, dynamic>> images,
    int initialIndex,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _ImageLightbox(images: images, initialIndex: initialIndex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _dbService.getOrderImagesStream(widget.orderId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final images = snapshot.data ?? [];
        final isInitialLoading =
            snapshot.connectionState == ConnectionState.waiting &&
            images.isEmpty;

        return Stack(
          children: [
            if (images.isEmpty && !isInitialLoading)
              _EmptyOrderImages(
                onCamera: _pickFromCamera,
                onGallery: _pickAndUpload,
              )
            else
              GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: isInitialLoading ? 6 : images.length,
                itemBuilder: (context, index) {
                  if (isInitialLoading) {
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                    );
                  }

                  final image = images[index];
                  final docId = image['docId'] as String;
                  final imageUrl = image['imageUrl'] as String;

                  return _OrderImageTile(
                    imageUrl: imageUrl,
                    onOpen: () => _openLightbox(context, images, index),
                    onDelete: () => _confirmDelete(context, docId, imageUrl),
                  );
                },
              ),
            if (_isUploading)
              Positioned(
                left: 24,
                right: 24,
                bottom: 96,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Uploading... ${(_uploadProgress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: _uploadProgress),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 16,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton(
                    heroTag: 'order-image-camera',
                    onPressed: _isUploading ? null : _pickFromCamera,
                    tooltip: 'Take Photo',
                    child: const Icon(Icons.camera_alt),
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.extended(
                    heroTag: 'order-image-gallery',
                    onPressed: _isUploading ? null : _pickAndUpload,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Photos'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyOrderImages extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  const _EmptyOrderImages({required this.onCamera, required this.onGallery});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No photos yet',
            style: TextStyle(fontSize: 18, color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
          Text(
            'Add photos for this order.',
            style: TextStyle(color: Colors.grey[400]),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: onCamera,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
              ),
              ElevatedButton.icon(
                onPressed: onGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Photos'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrderImageTile extends StatelessWidget {
  final String imageUrl;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _OrderImageTile({
    required this.imageUrl,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      onLongPress: onDelete,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: Colors.grey[200],
                child: const Center(
                  child: Icon(Icons.broken_image_outlined, color: Colors.grey),
                ),
              ),
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: Colors.grey[100],
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onDelete,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageLightbox extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final int initialIndex;

  const _ImageLightbox({required this.images, required this.initialIndex});

  @override
  State<_ImageLightbox> createState() => _ImageLightboxState();
}

class _ImageLightboxState extends State<_ImageLightbox> {
  late PageController _pageController;
  late int _currentIndex;
  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  bool _sharing = false;

  /// 下載目前這張相並叫出系統分享面板。iPhone／iPad 分享面板有「拷貝」「儲存影像」等選項，
  /// 因為 Web 版圖片無法用長按選取或拷貝。
  Future<void> _shareCurrent() async {
    final imageUrl = widget.images[_currentIndex]['imageUrl'] as String;
    setState(() => _sharing = true);
    try {
      final bytes = await FirebaseStorage.instance.refFromURL(imageUrl).getData();
      if (bytes == null) throw 'empty image';
      final type = detectImageType(bytes);
      if (type == null) throw 'unsupported format';
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          mimeType: type.contentType,
          name: 'order_photo_${_currentIndex + 1}.${type.ext}',
        ),
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('無法分享圖片：$e')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.images.length}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: '分享／拷貝／儲存圖片',
            icon: const Icon(Icons.ios_share),
            onPressed: _sharing ? null : _shareCurrent,
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (index) {
          _transformationController.value = Matrix4.identity();
          setState(() => _currentIndex = index);
        },
        itemBuilder: (context, index) {
          final imageUrl = widget.images[index]['imageUrl'] as String;
          return GestureDetector(
            onDoubleTap: () =>
                _transformationController.value = Matrix4.identity(),
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 1,
              maxScale: 6,
              child: Center(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 64,
                      color: Colors.white54,
                    ),
                  ),
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
