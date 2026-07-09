import SwiftUI
import AppKit

struct ArchiveWeekGroup: Identifiable {
    let start: Date
    let items: [Todo]

    var id: Date { start }
}

enum ArchiveDateGrouper {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }

    static var currentWeekInterval: DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: Date()) ?? DateInterval(start: Date(), duration: 7 * 24 * 60 * 60)
    }

    static func weekStart(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    static func groups(for items: [Todo]) -> [ArchiveWeekGroup] {
        let grouped = Dictionary(grouping: items) { item in
            weekStart(for: item.completedAt ?? item.createdAt)
        }
        return grouped
            .map { start, items in
                ArchiveWeekGroup(
                    start: start,
                    items: items.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
                )
            }
            .sorted { $0.start > $1.start }
    }

    static func weekTitle(_ start: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start)
    }

    static func itemDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

struct ArchiveHistoryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var hoveredId: UUID?
    @State private var dragWindowOrigin: NSPoint?

    private var usesLightTheme: Bool {
        switch state.settings.theme {
        case .light: return true
        case .dark: return false
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        }
    }
    private var txt: Color { usesLightTheme ? Color(hex: 0x1D1D1F) : Color(hex: 0xF2F2F4) }
    private var txt2: Color { usesLightTheme ? Color(hex: 0x5C5C62) : Color(hex: 0x9B9BA1) }
    private var txt3: Color { usesLightTheme ? Color(hex: 0x85858B) : Color(hex: 0x6E6E74) }
    private var accent: Color { Color(hex: 0x32D158) }
    private var subtleFill: Color { usesLightTheme ? Color.black.opacity(0.045) : Color.white.opacity(0.04) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("回收箱", systemImage: "arrow.3.trianglepath")
                    .font(.tc(22, weight: .semibold))
                    .foregroundStyle(txt)
                Text("\(state.completedArchive.count)")
                    .font(.tc(12, weight: .semibold))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(accent.opacity(0.16)))
                Spacer()
                Button {
                    state.showingArchive = false
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.tc(13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(txt3)
                .pointingHandCursor()
            }
            .contentShape(Rectangle())
            .gesture(windowDragGesture)

            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.tc(12, weight: .semibold))
                        .foregroundStyle(txt3)
                    TextField("搜索完成项", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.tc(13))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(subtleFill))

                tagFilterBar
            }

            if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.tc(24))
                        .foregroundStyle(txt3)
                    Text("没有匹配的完成项")
                        .font(.tc(13, weight: .semibold))
                        .foregroundStyle(txt2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(ArchiveDateGrouper.groups(for: filteredItems)) { group in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(ArchiveDateGrouper.weekTitle(group.start))
                                    .font(.tc(12, weight: .semibold))
                                    .foregroundStyle(txt3)
                                    .padding(.horizontal, 2)
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(group.items) { item in
                                        archiveHistoryRow(item)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(22)
        .frame(width: 720, height: 620)
    }

    private var tagFilterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "number")
                .font(.tc(12, weight: .semibold))
                .foregroundStyle(txt3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    archiveTagButton(title: "全部", selected: selectedTag == nil) {
                        selectedTag = nil
                    }
                    ForEach(availableTags, id: \.self) { tag in
                        archiveTagButton(title: "#\(tag)", selected: selectedTag == tag) {
                            selectedTag = tag
                        }
                    }
                }
            }
        }
        .frame(width: 280, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func archiveTagButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.tc(11.5, weight: .semibold))
                .foregroundStyle(selected ? accent : txt2)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill((selected ? accent : txt3).opacity(selected ? 0.16 : 0.10)))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func archiveHistoryRow(_ item: Todo) -> some View {
        let hovered = hoveredId == item.id
        return HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    state.restoreFromArchive(item)
                }
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.tc(13, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("恢复到待办")
            .pointingHandCursor()

            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.tc(13))
                    .foregroundStyle(txt)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Text(ArchiveDateGrouper.itemDate(item.completedAt ?? item.createdAt))
                        .font(.tc(11))
                        .foregroundStyle(txt3)
                    tagPills(item.tags)
                }
            }

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    state.deleteFromArchive(item)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.tc(11, weight: .semibold))
                    .foregroundStyle(txt3)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)
            .help("永久删除")
            .pointingHandCursor()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hovered ? Color.white.opacity(0.07) : subtleFill))
        .contentShape(Rectangle())
        .onHover { h in hoveredId = h ? item.id : (hoveredId == item.id ? nil : hoveredId) }
        .contextMenu {
            Button { state.restoreFromArchive(item) } label: {
                Label("恢复到待办", systemImage: "arrow.uturn.backward.circle")
            }
            Button(role: .destructive) { state.deleteFromArchive(item) } label: {
                Label("永久删除", systemImage: "trash")
            }
        }
    }

    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else { return }
                let origin = dragWindowOrigin ?? window.frame.origin
                dragWindowOrigin = origin
                window.setFrameOrigin(NSPoint(x: origin.x + value.translation.width, y: origin.y - value.translation.height))
            }
            .onEnded { _ in dragWindowOrigin = nil }
    }

    private func tagPills(_ tags: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(3), id: \.self) { tag in
                let color = tagColor(tag)
                Text("#\(tag)")
                    .font(.tc(10, weight: .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(color.opacity(0.16)))
            }
        }
    }

    private func tagColor(_ tag: String) -> Color {
        let palette: [UInt32] = [0x32D158, 0x64D2FF, 0xBF8CFF, 0xFF9F0A, 0xFF5E7E, 0x5DE4C7]
        let sum = tag.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(hex: palette[sum % palette.count])
    }

    private var availableTags: [String] {
        Array(Set(state.completedArchive.flatMap(\.tags))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var filteredItems: [Todo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return state.completedArchive.filter { item in
            let matchesSearch = query.isEmpty || item.text.localizedCaseInsensitiveContains(query)
            let matchesTag = selectedTag.map { item.tags.contains($0) } ?? true
            return matchesSearch && matchesTag
        }
    }
}
