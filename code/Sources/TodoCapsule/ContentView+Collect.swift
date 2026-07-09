import SwiftUI
import AppKit

// MARK: 收藏夹 tab —— 写进去、随时取（点一条即复制）。从 ContentView.swift 拆出。
extension ContentView {

    var collectPanelBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            panelListTabs
            collectInputRow
            if state.collects.isEmpty {
                collectEmptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 1) { ForEach(state.collects) { collectRow($0) } }
                }
            }
        }
    }

    var collectInputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.tc(15))
                .foregroundStyle(collectInputActive ? accent : txt3)
            ZStack(alignment: .leading) {
                if state.collectDraft.isEmpty {
                    Text("记一条…")
                        .font(.tc(13))
                        .foregroundStyle(txt3)
                }
                TextField("", text: $state.collectDraft)
                    .textFieldStyle(.plain)
                    .font(.tc(13))
                    .foregroundStyle(txt)
                    .tint(accent)
                    .focused($collectInputFocused)
                    .onSubmit { doCollectSubmit() }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(collectInputActive ? accent.opacity(0.08) : subtleFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(collectInputActive ? accent.opacity(0.6) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            collectInputFocused = true
            state.onRequestKey?()
        }
    }

    private var collectInputActive: Bool {
        collectInputFocused && state.panelTab == .collect
    }

    var collectEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bookmark").font(.tc(20)).foregroundStyle(txt3)
            Text("还没有收藏").font(.tc(13, weight: .semibold)).foregroundStyle(txt)
            Text("写点要存的 · 划词复制部分，或用复制按钮整条复制").font(.tc(11.5)).foregroundStyle(txt3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, 18)
    }

    func smallCollectRow(_ item: CollectItem) -> some View {
        let revealed = revealedId == item.id
        let masked = item.sensitive && !revealed
        let display = masked ? "••••••••" : item.text
        let links = detectedLinks(in: item.text)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.sensitive ? "lock.fill" : "bookmark")
                .font(.tc(11))
                .foregroundStyle(item.sensitive ? accent.opacity(0.85) : txt3)
                .frame(width: 18, height: 22)
            Text(linkedText(display))
                .font(.tc(13))
                .foregroundStyle(masked ? txt2 : txt)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.001)))
        .onTapGesture { copy(item) }
        .contextMenu {
            collectJumpMenuItems(links)
            Button("复制整条") { copy(item) }
            if item.sensitive {
                Button(revealed ? "隐藏" : "显示") {
                    withAnimation(anim) { revealedId = revealed ? nil : item.id }
                }
            }
            Button("删除", role: .destructive) {
                withAnimation(anim) { state.deleteCollect(item.id) }
            }
        }
    }

    private func collectRow(_ item: CollectItem) -> some View {
        let hovered = (hoveredRow == item.id) || (Self.forceHover && item.id == state.collects.first?.id)
        let revealed = revealedId == item.id
        let masked = item.sensitive && !revealed
        let display = masked ? "••••••••" : item.text
        let links = detectedLinks(in: item.text)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.sensitive ? "lock.fill" : "doc.text")
                .font(.tc(11)).foregroundStyle(item.sensitive ? accent.opacity(0.85) : txt3)
                .frame(width: 16, height: 19)
            if editingCollectId == item.id {
                // 编辑也用独立 NSTextView：多行可见、Return=换行、⌘Return=存、失焦落定、Esc 取消
                GrowingTextView(text: $editCollectText, height: $collectEditHeight,
                                focusTick: collectEditFocusTick, maxLines: 8,
                                onSubmit: { commitCollectEdit(item) },
                                onEndEditing: { commitCollectEdit(item) },
                                onCancel: { cancelCollectEdit() })
                    .frame(height: collectEditHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(linkedText(display))
                    .font(.tc(13))
                    .foregroundStyle(masked ? txt2 : txt)
                    .lineLimit(masked ? 1 : nil)                 // 收藏内容看全：非打码项自动换行显示全文
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)                     // 划词选中部分文本 → ⌘C 复制（整条用复制按钮）
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if hovered && editingCollectId != item.id {       // 编辑中不显 hover 控件，避免与编辑框挤一行
                if item.sensitive {
                    Button { withAnimation(anim) { revealedId = revealed ? nil : item.id } } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .font(.tc(11)).foregroundStyle(txt3)
                            .frame(width: 20, height: 22).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(revealed ? "隐藏" : "显示")
                }
                collectJumpControl(links)
                Button { copy(item) } label: {
                    Image(systemName: "doc.on.doc").font(.tc(11)).foregroundStyle(txt3)
                        .frame(width: 20, height: 22).contentShape(Rectangle())
                }.buttonStyle(.plain).help("复制整条")
                Button { withAnimation(anim) { state.deleteCollect(item.id) } } label: {
                    Image(systemName: "xmark").font(.tc(11)).foregroundStyle(txt3)
                        .frame(width: 20, height: 22).contentShape(Rectangle())
                }.buttonStyle(.plain).help("删除")
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(hovered ? Color.white.opacity(0.05) : Color.white.opacity(0.001)))
        .onHover { h in hoveredRow = h ? item.id : (hoveredRow == item.id ? nil : hoveredRow) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { startCollectEdit(item) })
        .contextMenu {
            collectJumpMenuItems(links)
            Button("复制整条") { copy(item) }
            if item.sensitive {
                Button(revealed ? "隐藏" : "显示") {
                    withAnimation(anim) { revealedId = revealed ? nil : item.id }
                }
            }
            Button("删除", role: .destructive) {
                withAnimation(anim) { state.deleteCollect(item.id) }
            }
        }
    }

    var copiedToast: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(accent).font(.tc(12))
            Text("已复制到剪贴板").font(.tc(12)).foregroundStyle(txt2)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x2C2C30)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.1)))
        .padding(6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    func copy(_ item: CollectItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        withAnimation(anim) { copiedFlash = item.id }
        let id = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            if copiedFlash == id { withAnimation(anim) { copiedFlash = nil } }
        }
    }

    @ViewBuilder
    private func collectJumpControl(_ links: [URL]) -> some View {
        if links.count == 1, let url = links.first {
            Button { openLink(url) } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.tc(11)).foregroundStyle(txt3)
                    .frame(width: 20, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("跳转")
        } else if links.count > 1 {
            Menu {
                ForEach(Array(links.enumerated()), id: \.offset) { _, url in
                    Button(linkTitle(url)) { openLink(url) }
                }
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.tc(11)).foregroundStyle(txt3)
                    .frame(width: 20, height: 22).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("选择链接跳转")
        }
    }

    @ViewBuilder
    private func collectJumpMenuItems(_ links: [URL]) -> some View {
        if links.count == 1, let url = links.first {
            Button { openLink(url) } label: {
                Label("跳转", systemImage: "arrow.up.forward.app")
            }
        } else if links.count > 1 {
            Menu {
                ForEach(Array(links.enumerated()), id: \.offset) { _, url in
                    Button(linkTitle(url)) { openLink(url) }
                }
            } label: {
                Label("跳转", systemImage: "arrow.up.forward.app")
            }
        }
    }

    private func openLink(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func linkTitle(_ url: URL) -> String {
        let value = url.absoluteString
        return value.count > 64 ? String(value.prefix(61)) + "..." : value
    }

    private func startCollectEdit(_ item: CollectItem) {
        state.isEditing = true
        editCollectText = item.text
        editingCollectId = item.id
        revealedId = item.id                                 // 编辑期间显形，避免改打码内容
        collectEditHeight = 18
        collectEditFocusTick &+= 1                            // 请求聚焦编辑框
    }
    private func commitCollectEdit(_ item: CollectItem) {
        guard editingCollectId == item.id else { return }
        state.updateCollectText(item.id, editCollectText)
        editingCollectId = nil
        state.isEditing = false
    }
    private func cancelCollectEdit() {
        editingCollectId = nil
        state.isEditing = false
    }
    private func doCollectSubmit() {
        guard !state.collectDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(anim) { state.submitCollect() }
        DispatchQueue.main.async {
            collectInputFocused = true
            state.onRequestKey?()
        }
    }
}
