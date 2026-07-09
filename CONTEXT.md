# CONTEXT.md — Todo Capsule

Todo Capsule 是一个 macOS 桌面边缘待办工具。当前主线是原生 SwiftUI + AppKit 应用，不包含旧实验运行时。

## 当前边界

- App 代码位于 `code/Sources/TodoCapsule/`
- Swift Package 位于 `code/Package.swift`
- 运行数据写入 `~/Library/Application Support/todo-capsule/`
- 打包脚本位于 `code/build-app.sh`

## 开发约束

- 修改 UI 后至少运行 `swift build`
- 本地生成物如 `.build/`、`TodoCapsule.app`、`.dmg` 不入库
- 用户说“发布”时，先读 `docs/RELEASE_PROCESS.md`，按完整 Sparkle + GitHub Release 流程发布，不要只 `git push`
- 旧实验运行时、`.luca` 工作流状态和交接文档已从公开仓库清理
- 大窗/小窗交互依赖 `CapsulePanel` 的 AppKit 事件处理，标题栏拖拽和双击逻辑需要一起验证
