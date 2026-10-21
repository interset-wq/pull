import 'package:flutter/material.dart';

import 'repo_image.dart';

/// 图片阅读器：左右滑动多图浏览、双指缩放、页码指示。
class ImageGalleryPage extends StatefulWidget {
  const ImageGalleryPage({
    required this.sources,
    required this.repoRoot,
    this.initialIndex = 0,
    super.key,
  });

  final List<String> sources;
  final String repoRoot;
  final int initialIndex;

  @override
  State<ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends State<ImageGalleryPage> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _currentPage {
    final page = _controller.hasClients ? _controller.page : null;
    return page?.round() ?? widget.initialIndex;
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
        itemBuilder: (context, index) => InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: buildRepoImage(
              widget.sources[index],
              repoRoot: widget.repoRoot,
            ),
          ),
        ),
      ),
    );
  }
}
