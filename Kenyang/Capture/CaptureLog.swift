import Foundation

enum CaptureLog {
    static var isEnabled = true

    static func line(_ text: String) {
        guard isEnabled else { return }
        print("[CAPTURE] \(text)")
        fflush(stdout)
    }

    static func rule(_ title: String) {
        line(String(repeating: "─", count: 66))
        line(title)
        line(String(repeating: "─", count: 66))
    }

    static func numbered(_ text: String, limit: Int = 200) {
        guard isEnabled else { return }
        let lines = text.components(separatedBy: .newlines)
        for (index, raw) in lines.prefix(limit).enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            line(String(format: "  %3d │ %@", index + 1, trimmed))
        }
        if lines.count > limit {
            line("  … \(lines.count - limit) more lines not shown")
        }
    }
}
