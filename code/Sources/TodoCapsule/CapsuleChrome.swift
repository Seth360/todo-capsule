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

/// 内容尺寸（控制器与视图共用同一套公式，保证窗口 / 命中矩形 / 视图一致）。
enum CapsuleMetrics {
    static let idleW: CGFloat = 32
    static let idleH: CGFloat = 78
    static let expandedW: CGFloat = 400      // peek / capture
    static let panelW: CGFloat = 600         // 大面板更宽、更沉浸

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
            let h = tab == .collect ? panelHCollect(count: collect)
                                    : panelH(active: active, completed: completed)
            return CGSize(width: panelW, height: h)
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
            // 柔和圆角阴影：弥散且明显；药丸距屏右缘 ~32(见 contentInsetRight)，右阴影完整落屏内，不被屏幕物理边缘裁出竖直棱角
            .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 7)
    }
}
