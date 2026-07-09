import SwiftUI
import AppKit

struct UpdateDialogView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.tc(22, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x32D158))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.tc(18, weight: .semibold))
                    Text(status)
                        .font(.tc(12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let info = state.updateInfo, info.phase == .downloading {
                ProgressView(value: info.progress)
                    .progressViewStyle(.linear)
                Text("\(Int(info.progress * 100))%")
                    .font(.tc(12, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else if state.updateInfo?.phase == .readyToRestart {
                Text("新版已就绪，重启后生效。")
                    .font(.tc(14, weight: .medium))
                    .foregroundStyle(Color(hex: 0x32D158))
            } else if state.updateInfo?.phase == .checking {
                ProgressView()
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("更新说明")
                    .font(.tc(13, weight: .semibold))
                ScrollView {
                    Text(notes)
                        .font(.tc(13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 110)
            }

            Spacer(minLength: 0)

            HStack {
                Button("取消") {
                    state.dismissUpdate()
                    NSApp.keyWindow?.close()
                }
                .disabled(isBusy)

                Button("跳过这个版本") {
                    state.skipUpdate()
                    NSApp.keyWindow?.close()
                }
                .disabled(isBusy || state.updateInfo?.phase == .readyToRestart)

                Spacer()

                Button(primaryTitle) {
                    if state.updateInfo?.phase == .readyToRestart {
                        state.restartForUpdate()
                    } else {
                        state.installUpdate()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canPrimaryAction)
            }
        }
        .padding(22)
        .frame(width: 480, height: 360)
    }

    private var title: String {
        state.updateInfo?.title ?? "检查更新"
    }

    private var status: String {
        state.updateInfo?.statusText ?? "正在获取更新信息..."
    }

    private var notes: String {
        guard let text = state.updateInfo?.notes, !text.isEmpty else {
            return "暂无更新说明。"
        }
        return text
    }

    private var icon: String {
        switch state.updateInfo?.phase {
        case .readyToRestart: return "checkmark.circle.fill"
        case .downloading: return "arrow.down.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        default: return "sparkles"
        }
    }

    private var isBusy: Bool {
        state.updateInfo?.phase == .downloading || state.updateInfo?.phase == .installing || state.updateInfo?.phase == .checking
    }

    private var primaryTitle: String {
        state.updateInfo?.phase == .readyToRestart ? "重启应用" : "立即更新"
    }

    private var canPrimaryAction: Bool {
        guard let phase = state.updateInfo?.phase else { return false }
        return phase == .available || phase == .readyToRestart
    }
}

extension ContentView {
    var updateNoticeBanner: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
            Text(updateNoticeText)
                .font(.tc(12, weight: .semibold))
                .foregroundStyle(txt)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button {
                state.dismissUpdateBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.tc(10, weight: .bold))
                    .foregroundStyle(txt3)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(accent.opacity(usesLightTheme ? 0.13 : 0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(accent.opacity(0.34), lineWidth: 1)
        )
        .padding(.horizontal, state.mode == .panel ? 68 : 10)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            state.openUpdateDialog()
        }
    }

    private var updateNoticeText: String {
        guard let info = state.updateInfo else { return "发现新版本" }
        switch info.phase {
        case .downloading:
            return "正在下载 \(Int(info.progress * 100))%"
        case .readyToRestart:
            return "新版已就绪，重启后生效"
        default:
            return "发现新版本 \(info.version)"
        }
    }
}
