# LangshenAgent 手机版（开源复刻）

LangshenAgent 桌面端的独立手机客户端，按官方 APK（`dev.langshenagent.mobile`）的行为复刻实现。
桌面端仓库在上一级目录 `../`，连接协议复用 `../packages/bao_link` 与 `../packages/bao_iroh`。

- **applicationId**: `com.langshenagent.mobileoss`（与官方版不冲突，可共存）
- **应用名**: 宝码
- **入口**: `lib/main.dart` → `lib/ui/app.dart` → `lib/ui/home_page.dart`（对话/Bot/文件/设置四栏）

## 构建

⚠️ FlyEnv 的 x86_64 rustc 在 PATH 里会抢在 rustup proxy 前面，导致 `bao_iroh` Rust hook
编译失败。构建必须前置 rustup 工具链路径：

```bash
cd mobile
PATH="$HOME/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin:$PATH" flutter pub get
PATH="$HOME/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin:$PATH" flutter build apk --debug
```

产物：`build/app/outputs/flutter-apk/app-debug.apk`（debug 约 215MB）。
**发版必须用 release**：`flutter build apk --release --target-platform android-arm64`
→ `app-release.apk` 约 50MB（与官方同量级；debug 含 3 个 ABI 的未优化引擎 +
85MB kernel 快照，不能发布）。

检查：`dart analyze`（应无 error，info 级 lint 可忽略）；测试 `flutter test`
（只跑相关测试，勿无脑全量）。

## 自更新（dl.langshen.shop）

走本机 Caddy 静态服务（LaunchDaemon `dev.langshen.dl-caddy`，IPv6 公网，
文档见 `../../Terraria ModLoader/langshen-dl-mirror/README.md`）。

### 机制

1. App 启动（HomePage）和设置页「检查更新」→ `GET https://dl.langshen.shop/reports/langshenagent-latest.json`
2. `build` 大于本机 `versionCode`（pubspec `version: x.y.z+N` 的 `N`）→ 弹窗（版本号+notes）
3. 用户确认 → 下载 APK（进度条）→ `langshenagent/update` 通道 → `PackageInstaller` 覆盖安装
4. 未授予「安装未知应用」会先引导去系统设置页

⚠️ manifest 放在 `/reports/` 而不是 `/apk/`：`/apk/*`、`/releases/*` 路由带
`Cache-Control: immutable` 一年缓存，`/reports/*` 没有，版本清单必须放后者。

### 服务端文件（本机 `/Users/xiaolang/langshen-dl-mirror/data/`）

```
data/
  apk/langshenagent-<version>.apk        安装包（文件名必须带版本号，immutable 缓存才不会错发旧包）
  reports/langshenagent-latest.json      版本清单
```

### latest.json 格式

```json
{
  "version": "1.0.1",                       // 展示用版本号
  "build": 2,                               // int，必须递增，和 versionCode 比较
  "apk": "/apk/langshenagent-1.0.1.apk",          // 站内路径或完整 URL
  "size": 50448412,                         // APK 字节数：进度计算 + 完整性校验 + 包复用
  "notes": "更新说明，可为空字符串"            // 显示在更新弹窗
}
```

### 发版流程

```bash
# 1. pubspec.yaml: version: 1.0.2+3（build 号 +N 必须递增）
# 2. 构建 release 并上传（size 用实际字节数）
PATH="$HOME/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin:$PATH" \
  flutter build apk --release --target-platform android-arm64
cp build/app/outputs/flutter-apk/app-release.apk /Users/xiaolang/langshen-dl-mirror/data/apk/langshenagent-1.0.2.apk
# 3. 编辑 /Users/xiaolang/langshen-dl-mirror/data/reports/langshenagent-latest.json
#    （version/build/apk/size/notes 全改）
# 4. 验证
curl -sS https://dl.langshen.shop/reports/langshenagent-latest.json
curl -sSI https://dl.langshen.shop/apk/langshenagent-1.0.2.apk
```

代码位置：`lib/update.dart`（检查/下载/完整性校验/包复用）、`lib/ui/update_dialog.dart`
（弹窗/进度）、`android/.../MainActivity.kt`（`install` 走 FileProvider + ACTION_VIEW
系统安装器，`res/xml/file_paths.xml` 限定 `cache/update/`）。

## 关键目录

- `lib/link/` — 协议客户端：`phone_link.dart`（连接/配对/全部 RPC）、`chat_codec.dart`（消息+bot 标签编解码）、`link_store.dart`（配对信息持久化）
- `lib/chat/` — 消息模型（与桌面端 `lib/chat/chat_models.dart` 同构）
- `lib/ui/` — 页面：home_page（四栏骨架）、chat_page、sessions_page、files_page、file_viewer、group_page、pair_page、settings_page
- `lib/ui/items/` — 聊天条目渲染（移植自桌面 `lib/chat/widgets/`）
- `lib/ui/md/` — markdown 渲染（移植自桌面：markdown_view/cjk/math/tags + inline_code + md_theme 配色 shim）
- `lib/app_state.dart` — 多电脑连接管理、局域网发现
- `lib/phone_platform.dart` — Android 通道封装（保活/haptics/更新/通知）

## 已实现 / 未实现

✅ 配对（扫码/链接/局域网）、安全码、多电脑切换、工作区→会话两级列表、聊天流式渲染
（markdown/代码块/数学公式/折叠标签）、bot 气泡与建议、工具/计划/终端/diff 条目、
交互卡片（问题/审批）、会话管理（重命名/置顶/归档/删除）、新建对话、项目/文件浏览、
图片预览、`bao_editor` 文件查看器+diff、命令输出订阅、keep/undo、选择模型/模式/权限、
自更新、前台保活、本地通知。

❌ 语音听写、ElevenLabs 语音回复、贴纸、离线 bot、@文件 提及、自定义主题、
`<bot_show_chat>` 会话卡片、文件写回（协议无写方法）。
