# todo-capsule · Phase 1 调研报告

> 日期：2026-06-25 ｜ 方法：26 个并行 Agent（9 个竞品深研 + 6 个技术可行性 + 8 个对抗验证 + 2 个综合）｜ 原始数据：`2026-06-25-todo-capsule-research-raw.json`
> 目标产品：桌面右侧常驻"胶囊"、hover 展开看/快速写待办、最小化后仍常驻；核心约束 = **简单、轻量、不打扰、动效好、美观，绝不臃肿**。

## Executive Summary（5 条）

1. **"简单"= 这个 MVP**：全局热键唤出捕获浮窗 → 单文本框、唯一必填=标题 → 回车即存到单一默认桶 → 胶囊 hover 展开看今日流 → 勾选完成带动画。其余一切（项目层级/看板日历/协作/游戏化/番茄钟/提醒系统）**明确不做**。
2. **最该抄**：单字段自然语言捕获 + 实时 token 高亮可撤销 + 全局热键召唤 + Inbox 兜底（捕获零决策）+ 愉悦勾选微反馈 + hover 揭示 + ~120ms 形变动效。
3. **最该躲**：GTD 全功能 IA、深层项目层级、游戏化、多视图范式、协作层、符号全家桶 NLP、重主题化、语音/AI 转写。
4. **胶囊可行性**：在 macOS 上**有条件可行**，非开箱即得。贴边常驻/跨普通 Space/不抢焦点/idle 穿透/热区展开都能做；但"无条件悬浮于他人全屏之上"**没有受支持的稳定保证**——必须作为产品决策点拍板（建议降级为 best-effort）。
5. **架构推荐（Stage 2）**：**原生 SwiftUI + AppKit（NSPanel）> webview（Tauri/Electron）**——因为胶囊所需的关键窗口行为（non-activating 可输入、浮于全屏、透明毛玻璃、分区穿透）在 webview 上每条最终都要原生逃生口，且 native 在"轻量/美观/动效"三项完胜（单平台 macOS 前提下）。唯一代价：需要 Swift 能力。

---

# Part 1 · 竞品设计研究综合（9 个顶级极简待办/胶囊应用）

> 核心锚点：**工作中秒速写待办 → 胶囊 hover 看/写 → 勾完成**。一切以"简单、不打扰、不臃肿"为最高约束。

## 1. 该采纳（Adopt）— 按"出现频次 × 对胶囊契合度"排序

- **A. 单字段 NLP 捕获（一行话=结构化待办）— 最高共识**（Todoist/TickTick/Superlist/Things3）。胶囊空间极小绝不能放日期选择器，NLP 是唯一能在一行内承载元数据的方式。**边界：只抄自然语言日期（today/tomorrow/+3d）+ 极小符号集（`#`标签、`p1-p3`），不抄 `@/+/!/、` 全家桶。**
- **B. 实时 token 高亮 + 点击撤销**（Todoist/TickTick）。性价比最高的信任机制：识别词高亮成药丸，错了点一下还原；零额外 UI 却给足控制感。
- **C. 全局热键召唤捕获面（零上下文切换）**（Things3 Ctrl+Space / Todoist / Notion Calendar / Superlist 四家一致）。这正是边缘胶囊的产品定义：**不是用户切到 app，而是捕获面浮到用户面前**；`invoke → type → Enter → gone` 闭环必须 1:1 复刻。
- **D. Inbox/默认桶兜底（捕获即存、整理延后或永不）**（全部如此）。写入路径必须一键，捕获时绝不强制选清单/项目/日期。
- **E. 勾选完成=愉悦微反馈（带撤销）**（Superlist tick 音+动画 / Things3 触感 / TickTick 可恢复）。除写入外最高频动作，干脆动画+易撤销是"feels good"里最便宜的一笔。
- **F. Hover 揭示插入线（静止干净、悬停才显影）**（Superlist）。与"hover 展开胶囊"天然同构。
- **G. ~100ms 缓动"让位"动效 + 形态 morph（而非硬切换）**（Superlist/Things3）。"轻量但高级"靠的就是 morph 动效——动效是身份不是装饰。
- **H. 捕获与排期解耦（先随手扔、后拖到时间轴）— 可选进阶/v2**（Amie/Things3）。MVP 只继承"写入零时间决策"原则。

## 2. 该规避（Avoid）— 破坏"简单轻量"的复杂度陷阱

| 陷阱 | 来自 | 为什么对胶囊是毒 |
|---|---|---|
| GTD 全功能 IA（5 列表+Areas+Projects+Headings+双日期语义） | Things3 | 把"快速 jotter"变成"列表管理者" |
| 深层项目/子项目/Section 嵌套 | Todoist/TickTick/Superlist | 组织开销与快速捕获直接对立 |
| 游戏化（Karma/连击/成就/统计报表） | Todoist/TickTick | 动机剧场，纯膨胀 |
| 多视图（Kanban/Timeline-Gantt/日历/四象限） | TickTick/Todoist | 互相竞争的视觉范式，每加一个加重量 |
| 协作层（assignee/评论/共享/@人） | Todoist/TickTick/Superlist/Amie | 团队工具重量，个人胶囊用不上 |
| 附属子 app（习惯/番茄钟/专注统计/日历同步） | TickTick | scope creep 成第二套心智模型 |
| 多目的地导航（Inbox+Today+Updates+Tasks+Lists） | Superlist | 单用户胶囊只要一条流 |
| 布尔查询/Filter 语言+保存查询 | Todoist/TickTick | 95% 用户碰不到的 power-user 表面积 |
| 符号全家桶 NLP + 8 语言解析器 | Todoist/Things3 | 工程无底洞 |
| 重主题化（自定义壁纸/自然背景/富文档） | Superlist/TickTick | 与"绝不臃肿"对冲 |
| 语音/AI 转写管线 | Superlist/Amie | 独立模态+高基建，对"hover 打字"胶囊是膨胀 |

**一句话原则：** 凡是把工具从"随手记→勾掉"推向"管理你的任务系统"的，一律不要。

## 3. 推荐的最小功能集（MVP）

**MUST（必做）：**
1. 全局热键召唤浮窗——任何 app 之上弹捕获框，`invoke→type→Enter→gone`，焦点回原处。
2. 单文本框捕获，唯一必填=标题——无表单、无必选清单/项目/日期，回车即存。
3. 极小 NLP 解析：自然语言日期（today/tomorrow/明天/`+3d`）+ `#标签` + `p1-p3`，**仅作用于捕获不作用于行内编辑**。
4. 实时 token 高亮 + 点击撤销。
5. 单一默认桶（Inbox/今日流）——一条扁平、可拖拽排序的流。
6. 胶囊 hover 展开看列表——收起=极简、悬停/点击=展开。
7. 勾选完成 + 动画 + 易撤销。
8. Esc 取消 / Enter 提交并收起——写入态只有这两个出口。

**明确不做（守边界）：** ❌项目/子项目/文件夹层级 ❌看板/日历/Gantt/象限 ❌协作 ❌游戏化/统计/习惯/番茄钟 ❌符号全家桶 ❌语音/AI 转写/富文本/自定义壁纸 ❌多语言 NLP（先中英 today-tomorrow-+Nd 子集）❌提醒/通知系统（MVP 不引入后台调度）⏸️拖拽排期到时间轴（留 v2）。

## 4. 胶囊交互范式建议

- **常驻形态**：静止态=笔尖（屏幕边缘小药丸/小条，零信息泄漏）；展开态=一张纸（干净白面、大量留白、今日流+顶部单输入框）。
- **触发三入口**：① 全局热键召唤纯写入浮窗（主入口，对标 Things3/Todoist）② hover 边缘热区 ~150ms 缓动展开看/勾（次入口）③ 单击=钉住展开（多笔操作，再点/Esc 收起）。
- **动效**：胶囊→面板 ~120-150ms 缓动 morph（宽高+圆角+透明度联动）；hover 磁吸放大；勾选 ~100ms 干脆动画+可选轻音（默认关）+让位动画；hover 行间灰色插入线点击即长出可编辑行。
- **不打扰原则**：静止零信息泄漏；捕获后即隐退（用一闪 toast/音代替"已捕获"，绝不停留确认）；悬停才显影、移开就收；零阻塞表单（无必填、无模态对话框）；解析不抢手（错了点一下还原，绝不自动弹日期选择器打断打字流）。

**单一北极星：** 让"一个念头"在一次击键+一行字内被记下并消失在视野外，让"勾掉"成为愉悦瞬间——其余一切都是可被砍掉的重量。

---

# Part 2 · 桌面边缘常驻胶囊 — 架构决策报告

## 1. 胶囊可行性结论（对抗验证后修正版）

| 子能力 | 能不能做 | 约束 / 真相 |
|---|---|---|
| 贴边右侧常驻定位 | ✅ 可靠 | `currentMonitor()`/`workArea` 算右缘 + `setPosition`；须用 **PhysicalPosition × scaleFactor**（Retina/多屏偏移坑 tauri #7890），监听 monitor/resize 重吸附。 |
| 软件最小化后常驻 | ✅ 可靠 | 胶囊是独立 always-on-top 窗口，生命周期与主窗解耦。 |
| 跨所有普通 Space 可见 | ✅ 可靠 | `canJoinAllSpaces` + 高 window level + `Accessory`/LSUIElement。 |
| 不抢焦点（non-activating） | ⚠️ 条件成立 | **纯 config/JS 达不到**。`focusable:false` ≠ non-activating（会导致面板输入框收不到键盘）。必须 native：`NSWindowStyleMaskNonactivatingPanel` + `becomesKeyOnlyIfNeeded`（Tauri 用 `tauri-nspanel`，Electron 用 `BaseWindow type:'panel'`）。 |
| 悬浮于他人全屏之上 | ❌ 不能无条件保证 | **整条断言最脆的承重点。** 别的 app 全屏时 macOS 给它建隔离 Space；需显式 `fullScreenAuxiliary`（仅 canJoinAllSpaces 不够），**且即便配对仍有大量"配了也不显示、要手动 focus 才浮起"的实测缺陷**（Electron #36364 / tauri #11488 均 closed-not-planned）。 |
| idle 点击穿透 | ✅ 可靠 | `setIgnoreCursorEvents(true)` / `setIgnoreMouseEvents(true,{forward})`，整窗级。 |
| hover 进热区"可靠"展开 | ⚠️ 尽力而为非"可靠" | **无 per-region hit-test**。idle=穿透时 DOM `:hover` 根本不触发，热区触发只能靠 **Rust 侧 ~30–60ms 全局光标轮询**比对屏幕矩形再翻 ignore——开环近似，有采样延迟（快速划过漏检）+功耗代价。 |

**一句话结论：** 胶囊在 macOS 上**有条件可行**。在「直装/DMG 分发 + 接受摘掉 Dock 图标（Accessory）+ 放弃 Mac App Store + 逐 macOS 版本实测打包态 .app」前提下，可做到右侧贴边常驻/跨普通 Space/不抢焦点/idle 穿透/热区展开。但**"无条件始终悬浮于任意 app 原生全屏之上"在 macOS 上没有稳定保证**——必须显式拍板（建议降级 best-effort）。

## 2. 架构推荐（唯一推荐）：原生 SwiftUI + AppKit（NSPanel），不用 webview

- **(a) 关键窗口行为 native 是基线、webview 是逃生口堆叠**：每条 webview 路线最终都要 native 逃生口（non-activating→tauri-nspanel/Electron panel；浮于全屏→私有 collectionBehavior；透明→`macOSPrivateApi`→永久失去 MAS）。选 webview 仍在写/依赖 AppKit，只是隔了层不稳定胶水，且打包后行为不一致（tauri #11488/#9556/#13415 透明置顶丢失，必须测 bundled .app）。
- **(b) 轻量 native 完胜**：Electron idle 150–300MB；Tauri 30–110MB（WKWebView Sonoma~66MB / Tahoe~110MB 持续回归）；SwiftUI 胶囊=小 NSPanel+少量视图，常驻内存压到 webview 零头，且 native 可用 `NSTrackingArea`/全局 `NSEvent` 做热区，无需 60fps 轮询烧 CPU。
- **(c) 美观+动效要破直觉**：你是单平台单窗口产品，Electron 的"跨平台渲染一致"优势对你不产生价值。反而 webview 透明窗 `backdrop-filter:blur()` 在透明 Tauri 窗破损、Electron 透明+vibrancy 有长期白底 bug；要 macOS 原生质感必须 `NSVisualEffectView`。SwiftUI `.animation`/`matchedGeometryEffect`/spring + `NSWindow.setFrame(animate:)` 对"小圆点→展开面板"形变是一等支持，原生 60/120fps。
- **唯一代价 / 反选条件**：写 Swift（需团队有 Swift 能力）。仅当①团队完全无 Swift 能力且无法补、②未来明确要跨 Win/Linux 复用同一胶囊——才反选 webview。

## 3. 关键技术机制清单（native 路线，确切 API）

- **NSPanel 子类**：`styleMask` 含 `.nonactivatingPanel`；`becomesKeyOnlyIfNeeded=true`（只有点文本框才成 key window，正好匹配 hover 展开后快速写）；`level=.statusBar`（高于普通窗口）；`collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]`（`fullScreenAuxiliary` 是浮于全屏的必需项，漏配=切全屏后消失；`stationary`=Mission Control 切 Space 不被当普通窗平移）；`isOpaque=false`+`backgroundColor=.clear`+`hasShadow`。
- **App 级**：`NSApp.setActivationPolicy(.accessory)`（LSUIElement，不占 Dock/Cmd-Tab，与主窗最小化解耦；**代价=抹掉 Dock 图标**）+ `NSStatusItem`（菜单栏锚点/退出入口）+ 全局快捷键。
- **贴边+多屏**：`NSScreen.visibleFrame` 算右缘；监听 `didChangeScreenParametersNotification` 重吸附；物理坐标避 Retina 偏移。
- **idle 穿透+热区展开**：idle `panel.ignoresMouseEvents=true`；热区用 `NSEvent.addGlobalMonitorForEvents(.mouseMoved)` 或一条始终不穿透的窄边缘 `NSTrackingArea` 捕获 enter（比 webview 60fps 轮询省电更可靠）；展开翻 `ignoresMouseEvents=false`+`setFrame(display:animate:)`+SwiftUI spring。
- **视觉**：`NSVisualEffectView` 毛玻璃（替代失效的 `backdrop-filter`）。
- **若仍选 Tauri**：等价逃生口 `tauri-nspanel`（`PanelBuilder`/`PanelLevel::Floating`/`set_collection_behavior`）+ `macos-private-api` + 光标轮询切 `set_ignore_cursor_events`，并接受打包态实测负担。

## 4. 必须在选型前拍板的产品决策（非技术问题）

1. **全屏悬浮可靠性**：接受"他人全屏场景下可能不浮起/需手动 focus"，还是把"浮于全屏之上"降为非承诺特性？→ 建议 **best-effort，不写进硬需求**。
2. **Dock 图标 vs 始终可见**：`Accessory` 二选一。→ 建议 **Accessory + 菜单栏入口**（胶囊类工具标准形态）。
3. **Mac App Store**：透明胶囊基本与 MAS 无缘 → **直装/DMG/notarized 分发**。

## 5. 第一步技术 Spike（Stage 2 起手，直击最大不确定性）

> 用 SwiftUI/AppKit 起一个最小 NSPanel，验证"全屏悬浮 + non-activating 写入"这条最脆链路。验收（全部在**打包后 .app**、跨 **≥2 个 macOS 版本**、真机多屏）：
> - [ ] 贴右缘，切到另一 app 原生全屏后胶囊**仍可见且浮于其上** → 过不了就把"全屏悬浮"降 best-effort
> - [ ] idle `ignoresMouseEvents=true` 时底层 app 可正常点击穿透
> - [ ] 全局 monitor/TrackingArea 命中右缘热区 → 展开（实测漏触发率与延迟）
> - [ ] 展开后面板内**文本框能收键盘输入**（验证 non-activating 但能输入）
> - [ ] 主窗最小化/关闭后胶囊常驻不受影响
> - [ ] 折叠态常驻内存+CPU 实测（坐实"轻量"）

---

# Part 3 · 对抗验证矩阵（8 个 skeptic Agent 审 4 条承重结论）

| # | 待验证结论 | 成立? | 修正 |
|---|---|---|---|
| 1 | 胶囊能始终可见（含跨 Space + 悬浮于全屏之上）且不抢焦点 | ❌ 不成立 | 跨普通 Space+不进 Dock+不抢焦点 ✅；但"悬浮于他人全屏之上"需 `fullScreenAuxiliary` 且仍有已记录的不稳定缺陷 → 降级为有条件/best-effort |
| 2 | idle 点击穿透 + hover 可靠展开 | ❌ 不成立 | idle 整窗穿透 ✅；hover 展开**不能用 CSS :hover**（穿透态 DOM hover 不触发），须全局光标轮询/native TrackingArea 模拟 → "尽力而为"非"可靠" |
| 3 | webview 框架本身即可满足全部需求，无需原生逃生口 | ❌ 不成立 | 覆盖绝大多数，但跨全屏可见+non-activating+透明都需原生逃生口；`macos-private-api` 失去 MAS；打包态 ≠ dev 态 |
| 4 | 存在比 webview 更契合"轻量+美观+动效"的更优架构（原生 NSPanel） | ✅ 成立 | 限定：在 **macOS 单平台、按运行时质量评分**时 native 更优；webview 在**开发成本/跨平台**轴占优。此结论由外部核验支撑（可行性 JSON 只覆盖 Tauri/Electron） |

---

*附：每个竞品/可行性问题的完整结构化发现与来源 URL 见 `2026-06-25-todo-capsule-research-raw.json`。*
