// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The Services menu's Clean Links, which replaces selected text with its cleaned version, keeping
/// rich text's formatting. It gets the text from the service's own pasteboard, not the clipboard.
final class ServiceProvider: NSObject {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    @objc func cleanLinks(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        // Failing leaves the selection exactly as it was.
        let nothingToClean = "There are no links to clean in the selection." as NSString

        if let rtf = pasteboard.data(forType: .rtf) {
            let formattingLost = "Preen couldn’t clean the selection without losing its formatting." as NSString
            guard let text = try? NSMutableAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) else {
                error.pointee = formattingLost
                return
            }
            guard cleanLinks(in: text) else {
                error.pointee = nothingToClean
                return
            }
            guard let cleaned = try? text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) else {
                error.pointee = formattingLost
                return
            }
            pasteboard.clearContents()
            pasteboard.setData(cleaned, forType: .rtf)
            pasteboard.setString(text.string, forType: .string)
            return
        }

        guard let text = pasteboard.string(forType: .string) else {
            error.pointee = nothingToClean
            return
        }
        let result = model.cleanText(text)
        guard result.changed else {
            error.pointee = nothingToClean
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(result.text, forType: .string)
    }

    /// Cleans the links behind linked words and the links written out in the text. Returns whether
    /// anything changed.
    private func cleanLinks(in text: NSMutableAttributedString) -> Bool {
        var changed = false
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let link = (value as? URL)?.absoluteString ?? (value as? String),
                  let cleaned = model.cleanLink(link)
            else { return }
            text.addAttribute(.link, value: URL(string: cleaned) ?? cleaned, range: range)
            changed = true
        }

        // Replaced from the end, so the ranges still to come stay where they were.
        for link in model.cleanText(text.string).links.reversed() {
            text.replaceCharacters(in: link.range, with: link.cleaned)
            changed = true
        }
        return changed
    }
}
