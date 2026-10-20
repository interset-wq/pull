# AGENTS.md

基于 git 仓库的笔记阅读 App：把 GitHub / Gitee / GitCode 上的 Markdown 笔记仓库克隆到手机，提供原生阅读器体验（代码高亮、图片相对路径、front-matter 元数据、目录/标签/最近更新三种查找方式），支持轻量编辑后 commit + push 回仓库。零部署、零构建托管。

## 技术栈与选型（已定，勿擅自更换）

- **框架**：Flutter（iOS + Android 双端），Dart 3 / Flutter 3.47+
- **git 层**：libgit2 FFI（git2dart）优先，备选平台 API 拉取 + 本地缓存；这是本项目最大技术风险点，改动同步层前先做小验证
- **Markdown 渲染**：markdown_widget / flutter_markdown + 代码高亮
- **平台适配**：GitHub / Gitee / GitCode 必须通过统一抽象层（`RepositoryAdapter` 之类的接口）接入，禁止在业务代码里直接写某家平台的 API 调用
- **鉴权**：各平台 PAT token 登录，token 只存本地安全存储，禁止硬编码或写入日志

## 第一版范围（反目标即边界）

- 只做：整仓克隆 → 舒服地读（第一优先级是渲染体验）→ 轻量编辑提交
- 不做：完整编辑器、双链/图谱、协作功能、任何形式的部署/CI/静态站生成
- 底线：渲染效果不能差于博客；同步冲突/丢内容不可接受——涉及 git 操作的改动必须重点自查这两条

## 开发约定

- 提交：英文 Conventional Commit（feat/fix/chore…），原子化提交；push 必须先经用户同意
- 临时文件放 `temp/`（已加入 .gitignore），不放系统 temp
- 不使用 TDD/SDD 流程；仅当改动触及已有测试覆盖的行为时才同步调整测试
- Windows 环境：Python 读文件必须显式 `encoding="utf-8"`

## 常用命令

```bash
flutter create .            # 项目尚未初始化时先执行
flutter pub get
flutter run                 # 运行（连接设备/模拟器）
flutter analyze             # 静态检查
flutter test
flutter build apk --release
```

## 维护规则

项目结构、构建/测试命令、架构边界、开发约定或本文件记录的其他事实发生变化时，必须在同一次改动中同步更新本文件。
