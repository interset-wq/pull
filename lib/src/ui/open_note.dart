import 'package:flutter/material.dart';

import '../git/repo_meta.dart';
import '../notes/note_scanner.dart';
import 'code_viewer.dart';
import 'image_gallery.dart';
import 'markdown_viewer.dart';

/// 打开仓库/本地镜像里的一个文件：阅读页 / 图库 / 代码查看。
///
/// 打开即清除该文件的「新增/更新」标记并记录最近打开。返回的 Future 在
/// 目标页面退出后完成，调用方可据此刷新自己的列表。
Future<void> openNoteFile(
  BuildContext context, {
  required String repoRoot,
  required NoteFile note,
  String? findQuery,
}) {
  RepoMeta.touchLastOpened(repoRoot, note.relativePath);
  RepoMeta.clearRecentChange(repoRoot, note.relativePath);
  if (note.isMarkdown || note.isPlainText) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MarkdownViewerPage(
          note: note,
          repoRoot: repoRoot,
          initialFindQuery: findQuery,
        ),
      ),
    );
  }
  if (note.isImage) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ImageGalleryPage(
          sources: [note.absolutePath],
          baseDir: repoRoot,
        ),
      ),
    );
  }
  return Navigator.push<void>(
    context,
    MaterialPageRoute<void>(
      builder: (_) => CodeViewerPage(
        path: note.absolutePath,
        fileName: note.fileName + note.extension,
      ),
    ),
  );
}
