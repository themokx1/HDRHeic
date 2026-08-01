// HDRHeic — SwiftUI control panel.
// One window: settings, a green/red watcher status light, and a log viewer.
// The heavy lifting stays in the embedded `hdrheic` engine (scan / watch).

import SwiftUI
import AppKit

// MARK: - Paths & constants

let kAgentLabel = "com.zoltanpalotai.hdrheic"
let kConfigDir  = NSHomeDirectory() + "/Library/Application Support/HDRHeic"
let kConfigPath = kConfigDir + "/config.json"
let kLogPath    = NSHomeDirectory() + "/Library/Logs/HDRHeic.log"
let kPlistPath  = NSHomeDirectory() + "/Library/LaunchAgents/\(kAgentLabel).plist"

func engineURL() -> URL? { Bundle.main.url(forResource: "hdrheic", withExtension: nil) }

func expandTilde(_ path: String) -> String { (path as NSString).expandingTildeInPath }

/// Runs a tool and returns (exitCode, trimmed stdout+stderr).
@discardableResult
func run(_ launchPath: String, _ arguments: [String]) -> (Int32, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return (process.terminationStatus, text)
}

// MARK: - Config

final class ConfigStore: ObservableObject {
    @Published var watchFolder: String = expandTilde("~/Pictures/Exported")
    @Published var debounceSeconds: Int = 5
    @Published var recursive: Bool = true

    init() { load() }

    func load() {
        guard let data = FileManager.default.contents(atPath: kConfigPath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let folder = object["watchFolder"] as? String { watchFolder = expandTilde(folder) }
        if let delay = object["debounceSeconds"] as? Double { debounceSeconds = Int(delay) }
        if let delay = object["debounceSeconds"] as? Int { debounceSeconds = delay }
        if let recursiveValue = object["recursive"] as? Bool { recursive = recursiveValue }
    }

    func save() {
        try? FileManager.default.createDirectory(atPath: kConfigDir, withIntermediateDirectories: true)
        let object: [String: Any] = [
            "watchFolder": watchFolder,
            "debounceSeconds": Double(debounceSeconds),
            "recursive": recursive,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: object,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: kConfigPath))
        }
    }
}

// MARK: - Watcher (launchd agent)

final class Watcher: ObservableObject {
    @Published var isRunning = false

    private var uid: String { "\(getuid())" }

    func refresh() {
        let (code, _) = run("/bin/launchctl", ["print", "gui/\(uid)/\(kAgentLabel)"])
        isRunning = (code == 0)
    }

    func install() {
        guard let engine = engineURL()?.path else { return }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key><string>\(kAgentLabel)</string>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>\(engine)</string>
        \t\t<string>watch</string>
        \t</array>
        \t<key>RunAtLoad</key><true/>
        \t<key>KeepAlive</key><true/>
        \t<key>ProcessType</key><string>Background</string>
        \t<key>StandardErrorPath</key><string>\(kLogPath)</string>
        </dict>
        </plist>
        """
        let launchAgents = NSHomeDirectory() + "/Library/LaunchAgents"
        try? FileManager.default.createDirectory(atPath: launchAgents, withIntermediateDirectories: true)
        try? plist.write(toFile: kPlistPath, atomically: true, encoding: .utf8)
        run("/bin/launchctl", ["bootout", "gui/\(uid)", kPlistPath])
        run("/bin/launchctl", ["bootstrap", "gui/\(uid)", kPlistPath])
        refresh()
    }

    func remove() {
        run("/bin/launchctl", ["bootout", "gui/\(uid)", kPlistPath])
        try? FileManager.default.removeItem(atPath: kPlistPath)
        refresh()
    }

    func restartIfRunning() {
        if isRunning { install() }
    }
}

// MARK: - Log

struct LogEntry: Identifiable {
    let id = UUID()
    let time: String
    let text: String
    let ok: Bool
}

final class LogStore: ObservableObject {
    @Published var entries: [LogEntry] = []

    private let inputFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()
    private let outputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    func refresh() {
        guard let content = try? String(contentsOfFile: kLogPath, encoding: .utf8) else {
            entries = []; return
        }
        var result: [LogEntry] = []
        for line in content.split(separator: "\n") {
            let string = String(line)
            let isConverted = string.contains("] Converted: ")
            let isFailed = string.contains("] FAILED: ")
            guard isConverted || isFailed else { continue }
            guard let close = string.firstIndex(of: "]") else { continue }
            let stamp = String(string[string.index(string.startIndex, offsetBy: 1)..<close])
            let time = inputFormatter.date(from: stamp).map { outputFormatter.string(from: $0) } ?? stamp
            let marker = isConverted ? "] Converted: " : "] FAILED: "
            if let range = string.range(of: marker) {
                let body = String(string[range.upperBound...])
                result.append(LogEntry(time: time, text: body, ok: isConverted))
            }
        }
        entries = result.reversed()   // newest first
    }
}

// MARK: - View

struct ContentView: View {
    @StateObject private var config = ConfigStore()
    @StateObject private var watcher = Watcher()
    @StateObject private var log = LogStore()

    @State private var converting = false
    @State private var lastResult = ""

    private let tick = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            settingsBox
            watcherBox
            logBox
        }
        .padding(20)
        .frame(width: 580, height: 660)
        .onAppear { watcher.refresh(); log.refresh() }
        .onReceive(tick) { _ in watcher.refresh(); log.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("HDRHeic").font(.system(size: 22, weight: .bold))
            Text("HDR JPEG → 10-bit HDR HEIC")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var settingsBox: some View {
        GroupBox("Settings") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Folder").frame(width: 70, alignment: .leading)
                    Text(config.watchFolder)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…") { chooseFolder() }
                }
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("Delay").frame(width: 70, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Stepper(value: $config.debounceSeconds, in: 1...120) {
                            Text("\(config.debounceSeconds) seconds")
                        }
                        Text("Wait for the folder to settle before converting.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .onChange(of: config.debounceSeconds) { saveAndReload() }
                Divider()
                HStack {
                    Text("Scope").frame(width: 70, alignment: .leading)
                    Toggle("Include subfolders", isOn: $config.recursive)
                        .onChange(of: config.recursive) { saveAndReload() }
                    Spacer()
                }
            }
            .padding(6)
        }
    }

    private var watcherBox: some View {
        GroupBox("Background watcher") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(watcher.isRunning ? Color.green : Color.red)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 0.5))
                    Text(watcher.isRunning ? "Running — new HDR photos convert automatically"
                                           : "Off — nothing converts automatically")
                        .foregroundStyle(watcher.isRunning ? .primary : .secondary)
                    Spacer()
                    if watcher.isRunning {
                        Button("Turn Off") { watcher.remove() }
                    } else {
                        Button("Turn On") { watcher.install() }.keyboardShortcut(.defaultAction)
                    }
                }
                Divider()
                HStack(spacing: 10) {
                    Button {
                        convertNow()
                    } label: {
                        Label("Convert now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(converting)
                    if converting { ProgressView().scaleEffect(0.6).frame(width: 16, height: 16) }
                    Text(lastResult).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer()
                }
            }
            .padding(6)
        }
    }

    private var logBox: some View {
        GroupBox("Recent conversions") {
            VStack(spacing: 6) {
                if log.entries.isEmpty {
                    Text("Nothing converted yet.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(log.entries) { entry in
                                HStack(spacing: 8) {
                                    Image(systemName: entry.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(entry.ok ? .green : .red)
                                        .font(.caption)
                                    Text(entry.time)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(entry.text)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                }
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
            .padding(6)
        }
    }

    // MARK: Actions

    private func saveAndReload() {
        config.save()
        watcher.restartIfRunning()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: config.watchFolder)
        if panel.runModal() == .OK, let path = panel.url?.path {
            config.watchFolder = path
            saveAndReload()
        }
    }

    private func convertNow() {
        guard let engine = engineURL()?.path else {
            lastResult = "engine not found"; return
        }
        converting = true
        lastResult = "Converting…"
        DispatchQueue.global(qos: .userInitiated).async {
            let (_, output) = run(engine, ["scan"])
            let summary = output.split(separator: "\n").last.map(String.init) ?? "done"
            DispatchQueue.main.async {
                converting = false
                lastResult = summary
                log.refresh()
            }
        }
    }
}

@main
struct HDRHeicApp: App {
    var body: some Scene {
        WindowGroup("HDRHeic") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
