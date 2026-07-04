import AppKit
import Foundation

public actor TranscriptActionPasteboardClipboard: TranscriptClipboardWriting {
    public init() {}

    public func writeTranscript(_ content: String) async {
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(content, forType: .string)
        }
    }
}

public actor TranscriptActionSavePanelDestinationSelector: TranscriptExportDestinationSelecting {
    private let defaultDirectoryURL: URL?

    public init(defaultDirectoryURL: URL? = nil) {
        self.defaultDirectoryURL = defaultDirectoryURL
    }

    public func destination(for request: TranscriptExportDestinationRequest) async -> String? {
        let defaultDirectoryURL = defaultDirectoryURL
        return await MainActor.run {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.directoryURL = defaultDirectoryURL
            panel.nameFieldStringValue = Self.suggestedFilename(for: request)
            panel.title = "Export Transcript"
            panel.prompt = "Export"
            return panel.runModal() == .OK ? panel.url?.path : nil
        }
    }

    public static func suggestedFilename(for request: TranscriptExportDestinationRequest) -> String {
        let rawName = request.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = rawName
            .unicodeScalars
            .map { scalar -> Character in
                if CharacterSet.alphanumerics.contains(scalar)
                    || scalar == "-"
                    || scalar == "_"
                    || scalar == "." {
                    return Character(scalar)
                }
                return "-"
            }
            .reduce(into: "") { result, character in
                if character == "-", result.last == "-" {
                    return
                }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))

        let baseName = sanitized.isEmpty ? "meeting-transcript" : sanitized
        switch request.exportType {
        case .markdown:
            return "\(baseName).md"
        case .plainText:
            return "\(baseName).txt"
        case .json:
            return "\(baseName).json"
        }
    }
}
