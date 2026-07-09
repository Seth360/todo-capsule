import Foundation
import Carbon.HIToolbox

/// 自定义热键：预设若干组合，持久化到 UserDefaults，运行时可切换并重注册。
struct HotkeyOption: Equatable {
    let name: String
    let keyCode: UInt32
    let modifiers: UInt32
}

enum Settings {
    static let hotkeyOptions: [HotkeyOption] = [
        HotkeyOption(name: "⌥Space",  keyCode: UInt32(kVK_Space),  modifiers: UInt32(optionKey)),
        HotkeyOption(name: "⌃Space",  keyCode: UInt32(kVK_Space),  modifiers: UInt32(controlKey)),
        HotkeyOption(name: "⌥T",      keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(optionKey)),
        HotkeyOption(name: "⌘⌥Space", keyCode: UInt32(kVK_Space),  modifiers: UInt32(cmdKey | optionKey)),
        HotkeyOption(name: "⌥N",      keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(optionKey)),
    ]

    static let quickRecordHotkeyOptions: [HotkeyOption] = [
        HotkeyOption(name: "⌘⌥C", keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | optionKey)),
        HotkeyOption(name: "⌘⌥R", keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | optionKey)),
        HotkeyOption(name: "⌃⌥C", keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey)),
    ]

    private static let hotkeyKey = "hotkeyIndex"

    static var hotkeyIndex: Int {
        get {
            let i = UserDefaults.standard.integer(forKey: hotkeyKey)
            return min(max(0, i), hotkeyOptions.count - 1)
        }
        set { UserDefaults.standard.set(newValue, forKey: hotkeyKey) }
    }

    static var hotkey: HotkeyOption { hotkeyOptions[hotkeyIndex] }
}
