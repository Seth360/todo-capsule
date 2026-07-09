# Todo Capsule 开发说明

这是 Todo Capsule 的 Swift Package。应用主体是一个无 Dock 图标的 macOS accessory app，使用 AppKit 管理 `NSPanel`，SwiftUI 绘制胶囊界面。

## 本地运行

```bash
swift run
```

## 构建检查

```bash
swift build
```

## 打包 app

```bash
./build-app.sh
open ./TodoCapsule.app
```

`build-app.sh` 会生成 `TodoCapsule.app`，复制 `Info.plist` 和图标，并尝试签名。若本机没有 `Mandarin Dictation Local` 证书，会回退到 ad-hoc 签名。

## 生成 DMG

```bash
./package-dmg.sh
```

## 自动更新

应用通过 Sparkle 检查 `https://raw.githubusercontent.com/Seth360/todo-capsule/main/appcast.xml`。完整发布流程、签名命令、GitHub Release 上传步骤和自动更新测试注意事项见 `../docs/RELEASE_PROCESS.md`。

特别注意：验证自动更新时不要覆盖 `/Applications/TodoCapsule.app`，应保留旧版本，让 Sparkle 从 GitHub Release 下载新版本。

## 主要源码

- `CapsuleController.swift`: NSPanel 生命周期、布局、热键和菜单栏入口
- `CapsulePanel.swift`: 自定义面板事件处理，包括拖拽和头部双击
- `ContentView.swift`: 胶囊壳、输入框、待办行、标签渲染
- `ContentView+Panel.swift`: 大窗面板和小窗一瞥
- `ContentView+Collect.swift`: 收藏夹界面
- `AppState.swift`: 待办、清单、标签、收藏、设置和总结状态
- `TodoStore.swift` / `CollectStore.swift`: 本地持久化
- `SettingsView.swift`: 设置窗口

## 本地数据

数据默认写入：

```text
~/Library/Application Support/todo-capsule/
```

调试时可设置 `TC_DEBUG_MODE` 进入预置窗口状态，方便截图核对 UI。
