import SwiftUI
import AppKit

/// 触觉反馈（拖拽抓起/跨行/落定）。仅 Force Touch 触控板有效，无则系统静默 → fail-soft。
enum Haptic {
    static func bump() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}

extension Font {
    static func tc(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: size).weight(weight)
    }
}

extension NSFont {
    static func tc(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont(name: "Inter", size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}

/// Todo Capsule 的界面基础令牌。新界面只从这里取颜色、圆角和间距，避免重新引入蓝色主操作。
enum CapsuleDesign {
    static let primary = Color(hex: 0x0B9153)
    static let primaryPressed = Color(hex: 0x087A46)
    static let canvasDark = Color(hex: 0x1C1C1C)
    static let sidebarDark = Color(hex: 0x191919)
    static let surfaceDark = Color(hex: 0x24272B)
    static let fieldDark = Color(hex: 0x24272B)
    static let textStrong = Color(hex: 0xF2F3F5)
    static let textSecondary = Color(hex: 0xAAAFB7)
    static let textMuted = Color(hex: 0x727780)
    static let borderDark = Color.white.opacity(0.10)

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 28
    }

    enum Radius {
        static let control: CGFloat = 8
        static let field: CGFloat = 10
        static let modal: CGFloat = 16
    }
}

extension CapsuleMetrics {
    static let panelMinSize = CGSize(width: 820, height: 620)
    static let panelMaxSize = CGSize(width: 1440, height: 1000)
}

struct CapsulePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, CapsuleDesign.Space.sm)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: CapsuleDesign.Radius.control, style: .continuous)
                    .fill(isEnabled ? (configuration.isPressed ? CapsuleDesign.primaryPressed : CapsuleDesign.primary) : CapsuleDesign.primary.opacity(0.35))
            )
            .opacity(isEnabled ? 1 : 0.7)
    }
}

struct CapsuleSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(CapsuleDesign.textSecondary)
            .padding(.horizontal, CapsuleDesign.Space.sm)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: CapsuleDesign.Radius.control, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CapsuleDesign.Radius.control, style: .continuous)
                    .strokeBorder(CapsuleDesign.borderDark, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// 全局下拉入口：深灰填充、紧凑高度、双向箭头，避免各页面出现不同的菜单外观。
struct CapsuleDropdownLabel: View {
    let title: String
    var minWidth: CGFloat = 144

    var body: some View {
        HStack(spacing: CapsuleDesign.Space.sm) {
            Text(title)
                .font(.tc(13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: CapsuleDesign.Space.md)
            Image(systemName: "chevron.up.chevron.down")
                .font(.tc(10, weight: .semibold))
        }
        .foregroundStyle(CapsuleDesign.textStrong)
        .padding(.horizontal, CapsuleDesign.Space.sm)
        .frame(minWidth: minWidth, minHeight: 36)
        .background(
            RoundedRectangle(cornerRadius: CapsuleDesign.Radius.control, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
    }
}

/// 内容尺寸（控制器与视图共用同一套公式，保证窗口 / 命中矩形 / 视图一致）。
enum CapsuleMetrics {
    static let idleW: CGFloat = 32
    static let idleH: CGFloat = 78
    static let expandedW: CGFloat = 400      // peek / capture
    static let panelW: CGFloat = 1000        // 大窗模式固定 1000×800
    static let panelHValue: CGFloat = 800

    static func expandedH(count: Int) -> CGFloat {
        // 小窗默认高度 300；条目较多时继续按内容适度增高。
        min(452, max(300, 104 + CGFloat(count) * 38))
    }
    static func panelH(active: Int, completed: Int) -> CGFloat {
        let base = 158 + CGFloat(active) * 40                       // 顶栏+tab+输入框+活跃行，减少底部留白
        let comp = completed > 0 ? 44 + CGFloat(completed) * 34 : 0 // 已完成区
        return min(720, max(animMin, base + comp))
    }
    static func panelHCollect(count: Int) -> CGFloat {
        let rows = max(count, 1)
        return min(720, max(animMin, 166 + CGFloat(rows) * 40))     // 减少底部留白
    }
    static let animMin: CGFloat = 360

    static func size(mode: CapsuleMode, active: Int, completed: Int,
                     collect: Int = 0, tab: PanelTab = .today) -> CGSize {
        switch mode {
        case .idle: return CGSize(width: idleW, height: idleH)
        case .peek, .capture: return CGSize(width: expandedW, height: expandedH(count: active))
        case .panel:
            return CGSize(width: panelW, height: panelHValue)
        }
    }
}

struct CapsuleSurface: ViewModifier {
    let radius: CGFloat
    let fill: Color
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
