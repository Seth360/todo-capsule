# Design Brief：todo-capsule（桌面边缘常驻胶囊待办）

**生成时间**：2026-06-25，由 `design-brief` skill 生成（紧凑版 · 继承 ux-brainstorm）
**场景**：A（新功能/全新产品）
**模式**：traceable_delivery（下游进原型 + Stage 2 工程）
**上游**：`docs/decisions/2026-06-25-todo-capsule-ux-brainstorm.md` + `...-interaction-architecture.md`
**状态**：DRAFT

> **品牌锁声明（重要偏离，已声明非静默）**：本产品是**消费级独立桌面工具，非纷享 CRM**。design-system-contract 的 FxUI #FF8000 品牌锁 / framework CRM 母版 / shadcn-CRM 规范 **不适用本项目**（SF-001/SF-002 限定纷享场景）。视觉自成体系：深色 Granola 式，用户已用真实截图确认形态。此偏离在 ux-brainstorm handoff 已记录，理由：跨产品上下文污染防护——给 CRM 的橙色品牌锁套到消费级待办胶囊上是错误继承。
> **AI/Agent 节声明**：AI Native 判定 = not_suitable（继承自 ux-brainstorm，不重算）。四层思考 Layer C/D、品味信任/代理维度、12 状态中 AI 专有 7 态 → 全部 N/A，理由：纯 GUI 操作型产品，无 AI/Agent。

---

## 1. 设计坐标系

| 维度 | 取值 |
|------|------|
| **产品本质** | 桌面边缘常驻"胶囊"待办，零摩擦记一条、随手瞄/勾，绝不臃肿 |
| **AI 方向** | 无 AI（GUI 可供性优化产品）。胶囊去掉"开 app/找窗/选清单+日期"执行步，但靠交互形态而非 AI |
| **被允许做** | 记一条（热键）、看清单（hover/点击）、勾完成、改/排序、跨 app 常驻 |
| **绝对不做** | 日期/标签/优先级/项目层级、提醒通知、协作、游戏化、AI 自动化、富文本、多语言解析 |
| **设计自由度** | 高（全新产品，无遗留约束）；唯一硬锚 = 用户的深色 Granola 药丸形态参照 |
| **反指标** | 任何把"随手记→勾掉"推向"管理任务系统"的复杂度；任何让静止态泄漏信息/打扰的设计 |

后续所有决策引用此坐标系。

## 2. 原生AI深度思考小结

**继承模式**（上游 ux-brainstorm 已判，本 Phase 仅交互层复核）：
- **产品层**：决策路径 = 记一条 1 次执行（打字+回车），无判断步。N→N' 压缩 = N/A（无 AI）。胶囊在 GUI 层移除"开 app/找窗/选清单+日期"≈3 个执行步。
- **交互层**：传统路径（切到 app→找输入→选清单→输入→保存→切回）≈6 步 → 本产品路径（热键→打字→回车）= **3 步**，M<N 成立。Fallback：菜单栏图标/单击兜底（hover 不可靠时）。
- **信任层**：N/A（无 AI 输出需信任）。用户对"自己刚记的一条"天然可判断。
- **代理层**：N/A（无 Agent）。
- **对当前决策的影响**：采纳"双入口形变胶囊"；预留 v3 AI 拆解的数据结构空间；AI 自动化在 v1 不可行（not_suitable）。
- **交互层复核结论**：承接判定（not_suitable + 3 步路径）在本规格的组件/交互粒度**仍成立**，无冲突，不触发回退。

## 3. 假设挑战结论

**checkpoint 模式**（继承 ux-brainstorm「假设前提」5 条 + 「被否定方向」3 条，仅核对不复活）：

- 5 条已验证假设（双入口热键主写 / 纯扁平无日期 / 深色药丸 / 单形变编排 / 勾掉即清）在本规格下**仍成立**。
- 被否定方向 D1 时间维度 / D2 临时召唤 / D3 AI 自动化 **不复活**。
- **最脆弱假设**（带到 Stage 2 验证）：「单元素就地形变出可输入面板 + non-activating 焦点交接，在打包态/多 macOS 版本下足够可靠」。验证节点 = Stage 2 NSPanel spike（见研究报告 Part 2 §5）。
- 结论：方案继续，无需调整；fallback 已备（Approach A 独立捕获窗）。

## 4. 体验验证结论

核心任务路径：记一条 = 热键→打字→回车 = **3 步**（达 Linear ≤3 锚点）。渐进披露：是（静止=笔尖，展开才显内容）。体验风险：hover 触发脆弱（已加去抖+兜底）；长清单容量（已加 jotter 容量哲学）。设计边界：纯扁平单桶，无组织。

### 状态覆盖声明（12 状态）

| 状态 | 方案处理方式 | 需单独设计 |
|------|-----------|-----------|
| 默认态 | idle 静止药丸（顶部对勾符号 + 未完成数 + 柔影）；展开 = 扁平今日流 | 是 |
| 空态 | 无未完成项：展开/静止显示友好"清零"（"今日清零 ✓，⌥Space 记一条"），不空白 | 是 |
| 加载态 | 本地数据，瞬时；启动时极短淡入。基本 N/A（无网络等待） | 否 |
| 错误态 | 本地写入几乎不失败；落库失败 → 行内轻提示"未保存，重试"，输入内容保留不丢 | 是 |
| 成功态 | 提交一条 = 一闪微确认（toast/微动效）后缩回；勾选 = 愉悦划线/淡出 | 是 |
| ─── AI 专有 ─── | | |
| 思考中态 | N/A — 本功能不涉及 AI | 否 |
| 低置信态 | N/A — 本功能不涉及 AI | 否 |
| 拒答态 | N/A — 本功能不涉及 AI | 否 |
| 部分完成态 | N/A — 非 agent 场景 | 否 |
| 待 Steer 态 | N/A — 本功能不涉及 AI | 否 |
| 幻觉兜底态 | N/A — 本功能不涉及 AI | 否 |
| Agent 执行中态 | N/A — 非 agent 场景 | 否 |

## 5. 品味检查四锚点（效率 5 锚点；信任/代理 N/A）

【效率维度】
- **Ryo Lu**（任务对齐）：✅ 每个元素服务任务——药丸=入口+计数，输入框=记，行=看/勾。无装饰元素。
- **Linear**（路径效率）：✅ 核心路径 3 步（热键→打字→回车），即时反馈（乐观 UI，立即入列）。已达底线，难再少。
- **Attio**（密度层次）：✅ L1 待办文字（13px）/ L2 计数（12px medium accent）/ L3 引导文案（12px secondary）三层可辨。
- **Notion**（入口克制）：✅ 静止态主入口=药丸单一；展开态主操作=输入+勾选，≤3，无重复入口。
- **Raycast**（AI 入口）：N/A — 无 AI。（热键召唤=任务上下文内召唤捕获，路径不变长，精神对齐。）

【信任维度】
- **Perplexity**：N/A — 无 AI 输出需追溯。
- **Granola**（诚实表达）：N/A — 无 AI。（注：用户参照 Granola 是其**视觉形态**药丸，非其 AI 信任语义。）

【代理维度】
- **Cursor**：N/A — 无 Agent。

整体评估：**通过**（无阻断锚点；效率 5 锚点全过）。

## 6. 设计决策清单（每条 8 字段）

> 视觉 token（本节决策共用，深色 Granola 体系）：
> 面：胶囊 `#1E1E20`、面板 `#232326`，描边 `rgba(255,255,255,.08)`，柔影 `0 8px 24px rgba(0,0,0,.35)`。
> 字：Inter；待办 13px/400 `#F2F2F4`、计数 12px/600 accent、次要 12px/400 `#9B9BA1`、占位 13px `#6E6E74`。
> accent（计数/对勾）：默认 `#34C75A`（呼应 Granola 绿，**可微调，deferred**）。
> 圆角：药丸=stadium(全圆)、面板 14px。间距 8pt 栅格，行高 ~32px，面板内距 12–16px。
> 动效：morph 180–220ms spring；reduced-motion=120ms 透明度/尺寸渐变。
> 尺寸：idle 药丸 ~44px 宽 × ~96px 高（对勾+计数竖排）、右缘留 8px；展开面板 ~320px 宽、max-height min(70vh, 内容)、内滚。

**D-001 · 静止药丸（idle capsule）**
- 组件：自绘 CapsulePill
- 决策：右缘竖向深色 stadium 药丸，顶部明确**对勾/清单符号**（非抽象 logo，消歧义），下方 accent 色未完成数；柔影；零任务文字泄漏。
- 理由：用户 Granola 截图确认形态；对勾符号解决 Oracle F1 语义歧义（不被误读为通知/录音）。
- 排除备选：①几乎隐形细条（发现性差）②纯圆点/logo（语义更弱）。
- tradeoff：略比"隐形细条"显眼（接受——换可发现性 + 语义清晰）。
- 状态覆盖：默认/空（计数 0 或全清标识）。
- 来源：UXB-D4（药丸）+ Oracle F1。

**D-002 · 全局热键捕获（capture flow）**
- 组件：自绘 CaptureInput（含 shadcn Input 行为）
- 决策：全局热键（默认 ⌥Space，可改）从任意 app/任意态触发 → 胶囊就地形变出聚焦输入框（边框+光标+占位"记一条…"）→ 打字 → Enter 落库+一闪确认+缩回+焦点归还 / Esc 取消。唯一必填=标题。
- 理由：研究最强共识（capture 来找你，3 步零摩擦）；占位+边框=Oracle F6 态自解释。
- 排除备选：①独立捕获窗（Approach A，割裂）②hover 才能写（摩擦）。
- tradeoff：需建立热键肌肉记忆（接受——首次引导 + 菜单栏兜底）。
- 状态覆盖：默认/成功/错误（落库失败保留输入）。
- 来源：UXB-D1/D3 + Oracle F6。

**D-003 · hover 瞄看 + 去抖 + 兜底（peek）**
- 组件：自绘 PeekList
- 决策：光标进右缘热区**驻留 150–250ms 且低速**才展开成清单（去抖防误触/防漏检）；移开自动收；**单击药丸/菜单栏图标 = 等价兜底入口**，看列表不 100% 依赖 hover。
- 理由：研究判 hover 为 best-effort（光标轮询）；去抖+兜底化解 Oracle F3。
- 排除备选：①裸 hover 即展开（误触+漏检）②只靠 hover 无兜底（脆弱）。
- tradeoff：展开有 ~200ms 驻留延迟（接受——换不误触）。
- 状态覆盖：默认/空。
- 来源：UXB-D3 + Oracle F3。

**D-004 · 单元素形变编排 + 态信号（morph choreography）**
- 组件：自绘 MorphContainer
- 决策：idle→peek→capture→confirm 全程一个连续形变元素（灵动岛式），每态有肉眼可辨信号：capture=输入框边框+光标+占位；peek=行 hover 高亮无输入光标；confirm=一闪即收。180–220ms spring。
- 理由：用户选定 Approach B；态信号化解 Oracle F6 过载。
- 排除备选：①独立窗口切换（割裂，Approach A）②无态信号纯形变（F6 过载）。
- tradeoff：实现精细度高（接受——native SwiftUI 形变是强项）。
- 状态覆盖：默认/成功。
- 来源：UXB-D1 + Oracle F6。

**D-005 · 勾选完成 → 几秒自动清走（complete lifecycle）**
- 组件：自绘 TodoRow + shadcn Checkbox 行为
- 决策：点勾选框 → 愉悦划线/淡出（完成快感）→ 撤销窗口 ~4s 内可一键还原 → 超时/下次展开自动移出活跃流；静止计数 -1；v1 无已完成历史。
- 理由：用户选定（纯 jotter 不堆积）；化解 Oracle F8 + F4 容量。
- 排除备选：①划线保留当天可见（堆积）②移到已完成分区（引入结构）。
- tradeoff：超 4s 不可找回（接受——jotter 定位，换永远只看活跃负担）。
- 状态覆盖：成功（勾选动效）/ 默认。
- 来源：用户 Phase 5 选择 + Oracle F8/F4。

**D-006 · 三态焦点机（focus model）**
- 组件：窗口行为契约（Stage 2 NSPanel）
- 决策：idle/peek 绝不抢焦点（idle 穿透）；仅"主动写"临时夺 key；**热键任意态强制进 capture 接管键盘**；结束归还来源 app（最低承诺=回原 app 不激活胶囊；尽力=回原插入点 best-effort）。
- 理由：化解 Oracle F2 焦点悖论；NSPanel `.nonactivatingPanel`+`becomesKeyOnlyIfNeeded`。
- 排除备选：①`focusable:false`（输入框收不到键盘）②整窗常 key（抢焦点打扰）。
- tradeoff：原插入点精确回归 best-effort（接受——Stage 2 spike 实测）。
- 状态覆盖：默认/成功。
- 来源：Oracle F2/F11 + 交互架构 §3。

**D-007 · 深色视觉系统（Granola 体系）**
- 组件：design tokens（见本节顶部）
- 决策：深色 Granola 体系（#1E1E20 药丸 / #232326 面板 / Inter / accent #34C75A），展开面板**默认深色系与药丸一致**（深 vs 浅纸 deferred 到原型实测）。
- 理由：用户 Granola 截图确认；Inter = 高端 productivity dark UI 标准（ui-ux-pro-max）。
- 排除备选：①FxUI 橙色品牌（非 CRM 产品，不适用）②浅色纸面板（与药丸不一致，deferred 待验）。
- tradeoff：深色面板看长清单对比度需调校（接受——deferred 原型实测）。
- 状态覆盖：全部（视觉底座）。
- 来源：UXB-D4/D8 + ui-ux-pro-max typography。

**D-008 · reduced-motion + 全屏/多屏退化（degradation）**
- 组件：响应式行为契约
- 决策：`prefers-reduced-motion` → 形变降级为 120ms 透明度/尺寸渐变（保留"从哪长出/缩回哪"因果，去位移弹性），确认降级静态 checkmark+自动收。他人全屏 → 胶囊 best-effort 浮起/否则隐退，**热键写入永远可用**；多屏跟随光标所在屏右缘。
- 理由：化解 Oracle F7/F5；ui-ux-pro-max 标 reduced-motion High。
- 排除备选：①忽略 reduced-motion（无障碍违规）②全屏强浮（无稳定保证）。
- tradeoff：他人全屏时"看/管理"可能不可用（接受——北极星=记一条，热键保住）。
- 状态覆盖：默认（双套规格）。
- 来源：Oracle F5/F7 + 研究 Part 2。

**D-009 · 空态（empty state）**
- 组件：自绘 EmptyState
- 决策：无未完成项 → 展开显示友好"清零"态 + 引导（"今日清零 ✓ · ⌥Space 记一条 · 移到这儿看清单"），首次启动一次性出现含热键提示；静止计数显 0 或轻量全清标识。
- 理由：ui-ux-pro-max 空态 = 给引导非空白；兼任 F1 首次可发现性。
- 排除备选：①空白面板（无引导）②持续教学提示（打扰）。
- tradeoff：首次引导占一次注意力（接受——只一次）。
- 状态覆盖：空态。
- 来源：交互架构 S5 + ui-ux-pro-max。

## 7. shadcn 组件映射表

> 承载方式：**局部改动/独立组件 — 不使用 framework 整页母版**（消费级桌面胶囊，5 个 CRM 母版均不适用）。下游原型：HTML（open-design 首选）。组件以**自绘**为主，少量 shadcn 行为参照。

| 区域 | 组件来源 | 组件名 | variant | 对应决策 | 备注 |
|------|---------|--------|---------|---------|------|
| 静止药丸 | 自绘 | CapsulePill | — | D-001 | stadium 深色 + 对勾符号 + accent 计数 + 柔影 |
| 捕获输入框 | 自绘(参照 shadcn) | Input | ghost/borderless→focus 边框 | D-002 | 透明底，focus 出边框+光标+占位 |
| 待办行 | 自绘 | TodoRow | — | D-005 | hover 高亮；行内可编辑 |
| 勾选框 | 自绘(参照 shadcn) | Checkbox | — | D-005 | 勾选触发划线/淡出动效 |
| 清单容器 | 自绘 | PeekList | — | D-003 | max-height 内滚 |
| 形变容器 | 自绘 | MorphContainer | — | D-004 | spring 180–220ms / reduced-motion 分支 |
| 空态 | 自绘 | EmptyState | — | D-009 | 引导文案 + 热键提示 |
| 撤销提示 | 自绘(参照 shadcn) | Toast/Inline | — | D-005 | ~4s 撤销窗口 |

> 无 AI 区域，故无思考中/低置信/拒答态组件。

## 8. 可追踪完整矩阵

| Source Claim ID | 来源 | 诉求摘要 | 映射决策 | 映射状态 | 下游去向 | 结果 |
|----------------|------|---------|---------|---------|---------|------|
| UXB-D1 | ux-brainstorm | 单形变胶囊编排 | D-004/D-002 | 默认/成功 | HTML+Stage2 | MAPPED |
| UXB-D2 | ux-brainstorm | 纯扁平无日期 | D-005/D-007 | 默认 | HTML+Stage2 | MAPPED |
| UXB-D3 | ux-brainstorm | 双入口(热键写/hover看) | D-002/D-003 | 默认 | HTML+Stage2 | MAPPED |
| UXB-D4 | ux-brainstorm | 深色 Granola 药丸+计数 | D-001/D-007 | 默认/空 | HTML+Stage2 | MAPPED |
| UXB-D5 | ux-brainstorm | 勾掉即清 | D-005 | 成功 | HTML+Stage2 | MAPPED |
| UXB-D6 | ux-brainstorm | 三态焦点机 | D-006 | 默认/成功 | Stage2 | MAPPED |
| UXB-D7 | ux-brainstorm | AI not_suitable | （全局）| AI 7 态 N/A | — | MAPPED |
| UXB-D8 | ux-brainstorm | 视觉非 FxUI 自成体系 | D-007 | 全部 | HTML+Stage2 | MAPPED |
| OR-F1 | Oracle | 药丸语义歧义 | D-001 | 默认 | HTML | MAPPED |
| OR-F2 | Oracle | 焦点交接 | D-006 | — | Stage2 | MAPPED |
| OR-F3 | Oracle | hover 脆弱+兜底 | D-003 | 默认 | HTML+Stage2 | MAPPED |
| OR-F4 | Oracle | 长清单容量 | D-005/D-003 | 默认 | HTML | MAPPED |
| OR-F5 | Oracle | 全屏/多屏退化 | D-008 | 默认 | Stage2 | DEFERRED（最终承诺级 Stage2 spike） |
| OR-F6 | Oracle | 态自解释信号 | D-004 | 默认/成功 | HTML | MAPPED |
| OR-F7 | Oracle | reduced-motion 双规格 | D-008 | 默认 | HTML | MAPPED |
| OR-F8 | Oracle | 完成态归宿 | D-005 | 成功 | HTML | MAPPED |
| OR-F11 | Oracle | 焦点回归分级 | D-006 | — | Stage2 | DEFERRED（Stage2 spike 实测） |
| OR-F10 | Oracle | v3 AI 拆解重开维度 | （演进） | — | v3 | DEFERRED |

✅ **TRACEABILITY GATE PASS**：ux-brainstorm 核心决策 8/8 MAPPED；Oracle 补丁 11/11 有去向（9 MAPPED / 2 DEFERRED 带原因）；每个 D-series 至少出现在一个组件映射行；非 N/A 状态均有 HTML 指示。

## 9. Design Generation Packet

> 给 open-design / html-prototype 的**唯一主输入**。只含本文件已有事实。

**产品**：todo-capsule —— macOS 桌面右缘常驻"胶囊"待办。北极星：一次击键+一行字记下念头并离开视野；勾掉=愉悦瞬间。**纯 GUI，无 AI**。

**承载/产出**：独立组件 HTML 高保真可交互原型（**非** framework CRM 母版；目标平台=macOS 桌面浮层，原型在浏览器演示形变与交互）。

**视觉 token**：深色 Granola 体系——胶囊 `#1E1E20` / 面板 `#232326` / 描边 `rgba(255,255,255,.08)` / 柔影 `0 8px 24px rgba(0,0,0,.35)`；字体 **Inter**（待办 13/400 `#F2F2F4`、计数 12/600 `#34C75A`、次要 12/400 `#9B9BA1`、占位 13 `#6E6E74`）；accent `#34C75A`（可微调）；圆角 药丸 stadium / 面板 14px；8pt 栅格，行高 32px。

**四态形变规格（核心，必须逐态实现并可演示切换）**：
1. **idle**：右缘竖向深色药丸，顶部对勾符号 + 下方 accent 未完成数，柔影，零任务文字。
2. **peek**（hover 驻留 150–250ms 触发）：形变成清单面板，行 hover 高亮，无输入光标，可勾/拖/行内"+"。
3. **capture**（热键触发，任意态强制进入）：形变出聚焦输入框（边框+光标+占位"记一条…"），打字→Enter 落库→一闪确认→缩回。
4. **confirm**：一闪微反馈即缩回 idle。
形变 180–220ms spring；**reduced-motion 版**=120ms 透明度/尺寸渐变保留因果。

**交互流**：热键写（3 步：热键→打字→回车）；hover 看（驻留去抖）+ 单击兜底；勾选→划线/淡出→~4s 可撤销→自动清走（计数 -1）；行内编辑/拖拽排序；空态友好引导 + 热键提示。

**MUST 决策**：D-001..D-009（见 §6）。**状态**：默认/空/错误/成功（AI 7 态 N/A）。

**Do-not**：❌ 日期/标签/优先级/项目层级 ❌ 看板/日历 ❌ 协作/游戏化/统计 ❌ AI/智能化任何元素 ❌ FxUI 橙色品牌 ❌ 装饰性无限动画 ❌ 静止态泄漏任务文字 ❌ 任何必填项/模态对话框。

## 10. Tool Consumption Contract

| 下游工具 | 主输入 | 可读校验源 | 不允许做 |
|---------|--------|-----------|---------|
| open-design（首选） | §9 Generation Packet + §6 决策 + §7 组件映射 | 本 design-brief 正文 | 不复活 REMOVED/否定方向；不引入 AI 元素；不套 FxUI/CRM 母版；不发散新方案 |
| /html-prototype（fallback） | §9 Generation Packet + 承载方式(独立组件) + §7 | 本 design-brief 正文 | 不绕过 brief 重设计交互；不调用 framework CRM 母版 |
| Stage 2 工程（tech-spec/task-plan） | 本 brief 正文 + §8 矩阵 + 交互架构文档 | ux-brainstorm/research | 不编造需求；DEFERRED 项(F5/F11)须先 spike |

> MagicPath（React canvas）**非本项目主路径**——产物是桌面浮层非 Web 组件库，HTML/open-design 更合适。

## 11. REMOVED 记录
- （场景 A，无 prd-constraints 围栏，无 OUT-OF-SCOPE 删除项；被否定方向见 ux-brainstorm D1/D2/D3，不在此重复。）

## 12. 交接块（下游恢复索引，仅索引非第二事实源）

- **场景**：A ｜ **AI Native**：not_suitable（无 AI） ｜ **承载**：独立组件 HTML 原型（非母版）
- **核心产出**：`docs/decisions/2026-06-25-todo-capsule-design-brief.md`（本文件，§9 Generation Packet 为下游主输入）
- **下游主路径**：open-design（首选）/ html-prototype（fallback）→ 高保真可交互原型，演示四态形变 + 双套动效规格
- **DEFERRED（带到 Stage 2）**：F5 全屏悬浮最终承诺级、F11 焦点回归精度 → NSPanel spike 实测
- **不得**：复活 D1/D2/D3、引入 AI、套 FxUI 品牌/CRM 母版

<!-- FILE_END: todo-capsule-design-brief.md -->
