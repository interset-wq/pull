import 'package:flutter/material.dart';

import 'repo_image.dart';

/// 图片阅读器：左右滑动多图浏览、双指缩放、页码指示。
class ImageGalleryPage extends StatefulWidget {
  const ImageGalleryPage({
    required this.sources,
    required this.baseDir,
    this.initialIndex = 0,
    super.key,
  });

  final List<String> sources;
  final String baseDir;
  final int initialIndex;

  @override
  State<ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends State<ImageGalleryPage> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  final TransformationController _transformer = TransformationController();
  TapDownDetails _lastTapDown = TapDownDetails();

  @override
  void dispose() {
    _controller.dispose();
    _transformer.dispose();
    super.dispose();
  }

  int get _currentPage {
    final page = _controller.hasClients ? _controller.page : null;
    return page?.round() ?? widget.initialIndex;
  }

  /// 双击：已放大则还原，否则以点击位置为中心放大 2.5 倍。
  void _handleDoubleTap() {
    final current = _transformer.value;
    if (current != Matrix4.identity()) {
      setState(() => _transformer.value = Matrix4.identity());
      return;
    }
    final position = _lastTapDown.localPosition;
    const scale = 2.5;
    _transformer.value = Matrix4.identity()
      ..translateByDouble(
        -position.dx * (scale - 1),
        -position.dy * (scale - 1),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentPage + 1} / ${widget.sources.length}'
          '  ${widget.sources[_currentPage].split('/').last}',
          style: const TextStyle(fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.sources.length,
        onPageChanged: (_) => setState(() {}),
        itemBuilder: (context, index) => GestureDetector(
          onDoubleTapDown: (d) => _lastTapDown = d,
          onDoubleTap: _handleDoubleTap,
          child: InteractiveViewer(
            transformationController: _transformer,
            maxScale: 5,
            child: Center(
              child: buildRepoImage(
                widget.sources[index],
                baseDir: widget.baseDir,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
