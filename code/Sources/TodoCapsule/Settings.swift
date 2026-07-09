import Foundation
import AppKit
import Carbon.HIToolbox

/// 自定义热键：预设若干组合，持久化到 UserDefaults，运行时可切换并重注册。
struct HotkeyOption: Codable, Equatable, Hashable {
    let name: String
    let keyCode: UInt32
    let modifiers: UInt32

    var isEmpty: Bool { keyCode == 0 && modifiers == 0 }

    var menuKeyEquivalent: String {
        switch Int(keyCode) {
        case kVK_Space: return " "
        case kVK_ANSI_A: return "a"
        case kVK_ANSI_B: return "b"
        case kVK_ANSI_C: return "c"
        case kVK_ANSI_D: return "d"
        case kVK_ANSI_E: return "e"
        case kVK_ANSI_F: return "f"
        case kVK_ANSI_G: return "g"
        case kVK_ANSI_H: return "h"
        case kVK_ANSI_I: return "i"
        case kVK_ANSI_J: return "j"
        case kVK_ANSI_K: return "k"
        case kVK_ANSI_L: return "l"
        case kVK_ANSI_M: return "m"
        case kVK_ANSI_N: return "n"
        case kVK_ANSI_O: return "o"
        case kVK_ANSI_P: return "p"
        case kVK_ANSI_Q: return "q"
        case kVK_ANSI_R: return "r"
        case kVK_ANSI_S: return "s"
        case kVK_ANSI_T: return "t"
        case kVK_ANSI_U: return "u"
        case kVK_ANSI_V: return "v"
        case kVK_ANSI_W: return "w"
        case kVK_ANSI_X: return "x"
        case kVK_ANSI_Y: return "y"
        case kVK_ANSI_Z: return "z"
        case kVK_Return: return "\r"
        case kVK_Tab: return "\t"
        case kVK_Escape: return "\u{1b}"
        default: return ""
        }
    }
}

enum Settings {
    static let noHotkey = HotkeyOption(name: "无", keyCode: 0, modifiers: 0)

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

    static func displayName(keyCode: UInt32, modifiers: UInt32) -> String {
        guard keyCode != 0 || modifiers != 0 else { return "无" }
        return modifierDisplayName(modifiers) + keyDisplayName(keyCode)
    }

    static func modifierDisplayName(_ modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        return parts.joined()
    }

    static func keyDisplayName(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Delete"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            let map: [Int: String] = [
                kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
                kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
                kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
                kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
                kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
                kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
                kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z"
            ]
            return map[Int(keyCode)] ?? "Key \(keyCode)"
        }
    }

    static func carbonModifiers(from eventModifiers: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if eventModifiers.contains(.command) { value |= UInt32(cmdKey) }
        if eventModifiers.contains(.option) { value |= UInt32(optionKey) }
        if eventModifiers.contains(.control) { value |= UInt32(controlKey) }
        if eventModifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    static func eventModifierFlags(from carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }
}
