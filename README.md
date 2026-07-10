# Todo Capsule

Todo Capsule 是一个 macOS 桌面边缘待办胶囊。它用 SwiftUI + AppKit `NSPanel` 实现，常驻屏幕边缘，无 Dock 图标，适合工作时快速记一条、扫一眼、勾掉。

## 下载安装

下载最新版 DMG：

[todo-capsule-v1.0.6.dmg](https://github.com/Seth360/todo-capsule/releases/download/v1.0.6/todo-capsule-v1.0.6.dmg)

所有版本见 [GitHub Releases](https://github.com/Seth360/todo-capsule/releases)。

提示：当前安装包未做 Apple Developer ID 公证。首次打开如果被 macOS 拦截，请右键 App 选择“打开”。

从 `v0.1.1` 开始，应用内已接入 Sparkle 自动更新。菜单栏图标中可选择“检查更新…”。

发布新版本和自动更新源维护流程见 [docs/RELEASE_PROCESS.md](docs/RELEASE_PROCESS.md)。换账号或换 Agent 工具时，先读这份文档，尤其注意不要提交 Sparkle 私钥，也不要在验证自动更新时覆盖 `/Applications/TodoCapsule.app`。

## 功能

- 全局热键快速记录待办
- 小窗一瞥、输入态、大窗面板三种主要工作形态
- 清单、标签、收藏夹、回收箱
- 行内编辑、拖拽排序、置顶、撤销
- 亮色/暗色/跟随系统主题
- AI 总结配置与导出设置
- 本地 JSON 持久化

## 运行

```bash
cd code
swift run
```

要求 macOS 14+，并安装 Xcode 或 Command Line Tools。

## 打包

```bash
cd code
./build-app.sh
open ./TodoCapsule.app
```

生成 DMG：

```bash
cd code
./package-dmg.sh
```

## 数据位置

运行数据保存在：

```text
~/Library/Application Support/todo-capsule/
```

## 项目结构

```text
code/
  Package.swift
  Sources/TodoCapsule/   # SwiftUI + AppKit app
  Resources/             # Info.plist, icon
docs/                    # 产品、研究和工程文档
vercel-proxy/            # 内置预设模型的 Vercel 服务端代理模板
```

更多开发细节见 `code/README.md`。

## 预设模型代理

App 内置的“预设”模型会请求 `https://fuxc.team/api/summary`，真实模型 Key 不会打包进 App。代理函数模板在 `vercel-proxy/`，部署前需要在 Vercel 项目里配置 `AI_PROXY_API_KEY` 等环境变量。
