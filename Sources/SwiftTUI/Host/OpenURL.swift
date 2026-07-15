import Foundation

/// Opens a URL / file path with the platform default handler.
@MainActor
public enum OpenURL {
    public static func open(_ url: URL) {
        let target = url.isFileURL
            ? url.path(percentEncoded: false)
            : url.absoluteString
        open(target)
    }

    public static func open(_ target: String) {
        guard !target.isEmpty else { return }
        let process = Process()
        #if os(macOS)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [target]
        #elseif os(Windows)
        process.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\cmd.exe")
        process.arguments = ["/c", "start", "", target]
        #elseif os(Linux)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
        process.arguments = [target]
        #else
        return
        #endif
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
