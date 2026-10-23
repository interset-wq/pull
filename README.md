# Reader

把 GitHub / Gitee / GitCode 上的笔记仓库克隆到手机，提供原生阅读器体验的**只读**应用——替代"为了看笔记搭一个博客"的方案：零部署、零构建托管，笔记仓库本身即数据源。

## 功能

**克隆与同步**
- 通过统一抽象层（`RepositoryAdapter`）接入 GitHub / Gitee / GitCode，业务代码不绑定任何平台 API
- 整仓克隆；启动时静默 pull（离线时保持本地内容可用），仓库页支持手动刷新
- 只读定位：不含任何编辑 / commit / push 功能；当前仅支持公开仓库

**目录浏览**
- 按原目录结构浏览（目录树不扁平化），支持子目录逐级进入、快速回到仓库根
- 非 Markdown 文件用语法高亮只读查看，代码行号同步滚动、右侧贴边滚动条

**阅读体验（第一优先级）**
- Markdown 渲染对标博客：GFM 告警框（`> [!NOTE]` 等）、代码高亮（可一键复制）、表格、HTML 内联/块级标签自动转换
- Jupyter Notebook（`.ipynb`）转 Markdown 渲染
- 数学公式（KaTeX）：行内 `$...$` 与块级 `$$...$$`，金额（`$100`）等场景不误判
- 文章目录（TOC）浮动按钮 + 回顶/回底按钮
- 文首面包屑：`仓库 / 目录 / 子目录` 逐级可点，直接落到对应目录页
- 底部常驻翻页条：上一篇/下一篇不必滚到文末；文末另有「上级目录 / 仓库首页」按钮
- 阅读进度记忆：按文件保存滚动位置，重新打开自动恢复
- 收藏文章 / 最近阅读：首页横滑条目，点击直达（跨仓库）
- 屏幕常亮：设置中开关，阅读页内生效，离开自动释放

**外观**
- 深色模式：跟随系统 + 手动切换
- 代码字体可选（JetBrains Mono / Consolas），默认关闭连字
- 移动端优先的界面布局

## 平台

| 平台 | 状态 |
|------|------|
| Android | ✅ 主要目标（release APK 见 [Releases](https://gitcode.com/interset-wq/reader/releases)） |
| iOS | ✅ 已支持（真机验证进行中） |
| Windows | ✅ 用于本机预览/调试 |

## 技术栈

- **框架**：Flutter（Dart 3 / Flutter 3.47+），iOS + Android + Windows
- **git 层**：libgit2 FFI（git2dart），仅使用克隆 / pull 只读能力
  - git 操作在后台 isolate 执行，避免大仓库卡 UI
- **Markdown**：markdown_widget + flutter_math_fork（KaTeX 公式）
- **存储**：shared_preferences（偏好设置）；阅读进度/收藏/最近阅读以 JSON 存于仓库旁 `.meta/` 目录，随仓库走

## 快速开始

```bash
flutter pub get
flutter run                 # 运行（连接设备/模拟器）
flutter analyze             # 静态检查
flutter test                # 测试
flutter build apk --release # 构建 release APK
```

> 首次运行需在手机浏览器完成应用权限（存储路径在系统默认目录下的 `reader/` 仓库根）。

## 目录结构

```
lib/
├── main.dart               # 入口（libgit2/SSL 初始化顺序见 AGENTS.md）
└── src/
    ├── git/                # git 同步服务、仓库元数据（.meta/）
    ├── platforms/          # RepositoryAdapter 抽象层 + GitHub/Gitee/GitCode 适配器
    ├── notes/              # 笔记扫描、TOC、GFM 告警、ipynb 转换、数学公式
    ├── ui/                 # 首页、仓库页、阅读页、代码查看、设置页
    ├── theme/              # 主题、偏好设置（AppPrefs）
    └── utils/              # 自然排序等工具
```

## 路线图

- 全文搜索
- Mermaid 图表渲染
- 目录树折叠记忆
- 大屏行宽限制
- 音量键翻页 + 滑动手势切文章
- 护眼主题
- 图片缩略图
- 导出 PDF
- 私有仓库（token 本地存储，不做云端）

## 许可证

[MIT](LICENSE)
