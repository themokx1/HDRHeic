// HDRHeic — SwiftUI control panel (menu-bar app).
// One window: settings, a green/red watcher status light, batch progress,
// recent conversions and failures. The heavy lifting stays in the embedded
// `hdrheic` engine (scan / watch).

import SwiftUI
import AppKit

// MARK: - Paths & constants

let kAgentLabel = "com.zoltanpalotai.hdrheic"
let kConfigDir  = NSHomeDirectory() + "/Library/Application Support/HDRHeic"
let kConfigPath = kConfigDir + "/config.json"
let kLogPath    = NSHomeDirectory() + "/Library/Logs/HDRHeic.log"
let kPlistPath  = NSHomeDirectory() + "/Library/LaunchAgents/\(kAgentLabel).plist"
let kRepo       = "themokx1/HDRHeic"

func engineURL() -> URL? { Bundle.main.url(forResource: "hdrheic", withExtension: nil) }

func expandTilde(_ path: String) -> String { (path as NSString).expandingTildeInPath }

func appVersion() -> String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
}

// MARK: - Localization (English source strings, Hungarian overrides)

private let hungarian: [String: String] = [
    "HDR JPEG → 10-bit HDR HEIC": "HDR JPEG → 10 bites HDR HEIC",
    "Settings": "Beállítások",
    "Folder": "Mappa",
    "Choose…": "Tallózás…",
    "Delay": "Késleltetés",
    "%@ seconds": "%@ másodperc",
    "Wait for the folder to settle before converting.":
        "Várakozás, amíg a mappa megnyugszik, csak utána konvertál.",
    "Scope": "Hatókör",
    "Include subfolders": "Almappákkal együtt",
    "Redo": "Újra",
    "Never": "Soha",
    "Newer": "Ha újabb",
    "Always": "Mindig",
    "Keep existing HEICs — never overwrite.":
        "A meglévő HEIC marad — sosem írja felül.",
    "Always re-convert, overwriting the HEIC.":
        "Mindig újrakonvertál, felülírja a HEIC-et.",
    "Re-convert when the JPEG is newer than its HEIC.":
        "Újrakonvertál, ha a JPEG frissebb a HEIC-nél.",
    "Original": "Eredeti",
    "Move the JPEG to the Trash after converting":
        "A JPEG a Kukába kerül konvertálás után",
    "Recoverable from the Trash. Turn off to keep both files.":
        "A Kukából visszaállítható. Kikapcsolva mindkét fájl megmarad.",
    "Terminal": "Terminál",
    "Install the `hdrheic` command-line tool": "A `hdrheic` parancssori eszköz telepítése",
    "Adds a `hdrheic` command to ~/.local/bin.":
        "Létrehoz egy `hdrheic` parancsot a ~/.local/bin mappában.",
    "Background watcher": "Háttérfigyelő",
    "Running — new HDR photos convert automatically":
        "Fut — az új HDR képek automatikusan konvertálódnak",
    "Off — nothing converts automatically":
        "Kikapcsolva — semmi nem konvertálódik magától",
    "Turn On": "Bekapcsolás",
    "Turn Off": "Kikapcsolás",
    "Convert now": "Konvertálás most",
    "Recent conversions": "Legutóbbi konvertálások",
    "Nothing converted yet.": "Még nem történt konvertálás.",
    "Converting…": "Konvertálás…",
    "Problems": "Hibák",
    "Clear": "Törlés",
    "Choose the folder to watch": "Válaszd ki a figyelendő mappát",
    "Welcome to HDRHeic": "Üdv a HDRHeic-ben!",
    "Pick the folder your HDR photos are exported to. You can change it later in Settings.":
        "Válaszd ki a mappát, ahová a HDR képeidet exportálod. Később a Beállításokban módosíthatod.",
    "Choose Folder…": "Mappa kiválasztása…",
    "Later": "Később",
    "The watched folder no longer exists.": "A figyelt mappa már nem létezik.",
    "The background watcher points at an old copy of the app. Repair it to keep converting automatically.":
        "A háttérfigyelő az app egy régi példányára mutat. Javítsd, hogy az automatikus konvertálás működjön.",
    "Repair": "Javítás",
    "A new version is available": "Új verzió érhető el",
    "Download": "Letöltés",
    "engine not found": "a motor nem található",
]

/// Localized string. English text is the key; Hungarian comes from the table.
func L(_ key: String) -> String {
    let language = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
    guard language == "hu" else { return key }
    return hungarian[key] ?? key
}

// MARK: - Process helpers

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

/// Runs a tool and delivers stdout line by line (used for scan progress).
func runStreaming(_ launchPath: String, _ arguments: [String],
                  onLine: @escaping (String) -> Void,
                  onFinish: @escaping (String) -> Void) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()   // keep log noise out of the parsed stream

    var buffer = ""
    var lastLine = ""
    pipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
        buffer += text
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newline])
            buffer = String(buffer[buffer.index(after: newline)...])
            if !line.isEmpty {
                lastLine = line
                DispatchQueue.main.async { onLine(line) }
            }
        }
    }
    process.terminationHandler = { _ in
        pipe.fileHandleForReading.readabilityHandler = nil
        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = tail.isEmpty ? lastLine : tail
        DispatchQueue.main.async { onFinish(summary) }
    }
    do { try process.run() } catch {
        DispatchQueue.main.async { onFinish("\(error)") }
    }
}

// MARK: - Config

final class ConfigStore: ObservableObject {
    @Published var watchFolder: String = expandTilde("~/Pictures/Exported")
    @Published var debounceSeconds: Int = 5
    @Published var recursive: Bool = true
    @Published var regenerate: String = "newer"   // never | newer | always
    @Published var deleteSource: Bool = true

    init() { load() }

    func load() {
        guard let data = FileManager.default.contents(atPath: kConfigPath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let folder = object["watchFolder"] as? String { watchFolder = expandTilde(folder) }
        if let delay = object["debounceSeconds"] as? Double { debounceSeconds = Int(delay) }
        if let delay = object["debounceSeconds"] as? Int { debounceSeconds = delay }
        if let recursiveValue = object["recursive"] as? Bool { recursive = recursiveValue }
        if let policy = object["regenerate"] as? String,
           ["never", "newer", "always"].contains(policy) { regenerate = policy }
        if let delete = object["deleteSource"] as? Bool { deleteSource = delete }
    }

    func save() {
        try? FileManager.default.createDirectory(atPath: kConfigDir, withIntermediateDirectories: true)
        let object: [String: Any] = [
            "watchFolder": watchFolder,
            "debounceSeconds": Double(debounceSeconds),
            "recursive": recursive,
            "regenerate": regenerate,
            "deleteSource": deleteSource,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: object,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: kConfigPath))
        }
    }

    var folderExists: Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: watchFolder, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}

// MARK: - Watcher (launchd agent)

final class Watcher: ObservableObject {
    @Published var isRunning = false
    /// True when the installed agent points at a different app copy than this one
    /// (e.g. the app was moved or replaced) — the watcher would run stale code.
    @Published var isStale = false

    private var uid: String { "\(getuid())" }

    func refresh() {
        let (code, _) = run("/bin/launchctl", ["print", "gui/\(uid)/\(kAgentLabel)"])
        isRunning = (code == 0)
        isStale = isRunning && installedEnginePath() != engineURL()?.path
    }

    /// The engine path recorded in the installed LaunchAgent, if any.
    private func installedEnginePath() -> String? {
        guard let data = FileManager.default.contents(atPath: kPlistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String] else { return nil }
        return arguments.first
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

// MARK: - Command-line tool

/// Manages a `~/.local/bin/hdrheic` symlink to the app's embedded engine, so the
/// CLI works from Terminal. Auto-installed once on first launch; toggleable after.
final class CLIInstaller: ObservableObject {
    @Published var installed = false
    let linkPath = NSHomeDirectory() + "/.local/bin/hdrheic"

    func refresh() {
        let manager = FileManager.default
        if let destination = try? manager.destinationOfSymbolicLink(atPath: linkPath),
           manager.fileExists(atPath: destination) {
            installed = true
        } else {
            installed = false
        }
    }

    func install() {
        guard let engine = engineURL()?.path else { return }
        let manager = FileManager.default
        let directory = (linkPath as NSString).deletingLastPathComponent
        try? manager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? manager.removeItem(atPath: linkPath)
        try? manager.createSymbolicLink(atPath: linkPath, withDestinationPath: engine)
        refresh()
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: linkPath)
        refresh()
    }

    /// Install the symlink once, the first time the app is ever launched. Also
    /// re-point it if it still targets a different (moved/old) app copy.
    func installOnceIfFirstLaunch() {
        let key = "didAutoInstallCLI"
        if !UserDefaults.standard.bool(forKey: key) {
            install()
            UserDefaults.standard.set(true, forKey: key)
        } else if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath),
                  destination != engineURL()?.path {
            install()
        }
        refresh()
    }
}

// MARK: - Update check

final class UpdateChecker: ObservableObject {
    @Published var latestVersion: String?
    @Published var updateAvailable = false

    var releaseURL: URL { URL(string: "https://github.com/\(kRepo)/releases/latest")! }

    func check() {
        guard let url = URL(string: "https://api.github.com/repos/\(kRepo)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = object["tag_name"] as? String else { return }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            DispatchQueue.main.async {
                self?.latestVersion = latest
                self?.updateAvailable = isVersion(latest, newerThan: appVersion())
            }
        }.resume()
    }
}

/// Numeric, component-wise version comparison ("1.10" > "1.9").
func isVersion(_ candidate: String, newerThan current: String) -> Bool {
    let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
    let right = current.split(separator: ".").map { Int($0) ?? 0 }
    for index in 0..<max(left.count, right.count) {
        let a = index < left.count ? left[index] : 0
        let b = index < right.count ? right[index] : 0
        if a != b { return a > b }
    }
    return false
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
    @Published var failures: [LogEntry] = []

    private let inputFormatter = ISO8601DateFormatter()
    private let outputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    func refresh() {
        guard let content = try? String(contentsOfFile: kLogPath, encoding: .utf8) else {
            entries = []; failures = []; return
        }
        var converted: [LogEntry] = []
        var failed: [LogEntry] = []
        for line in content.split(separator: "\n") {
            let string = String(line)
            let marker: String
            let ok: Bool
            if string.contains("] Converted: ") { marker = "] Converted: "; ok = true }
            else if string.contains("] Regenerated: ") { marker = "] Regenerated: "; ok = true }
            else if string.contains("] FAILED: ") { marker = "] FAILED: "; ok = false }
            else if string.contains("] Kept JPEG (could not move to Trash): ") {
                marker = "] Kept JPEG (could not move to Trash): "; ok = false
            }
            else { continue }
            guard let close = string.firstIndex(of: "]") else { continue }
            let stamp = String(string[string.index(string.startIndex, offsetBy: 1)..<close])
            let time = inputFormatter.date(from: stamp).map { outputFormatter.string(from: $0) } ?? stamp
            guard let range = string.range(of: marker) else { continue }
            let prefix = marker.contains("Regenerated") ? "↻ " : ""
            let entry = LogEntry(time: time, text: prefix + String(string[range.upperBound...]), ok: ok)
            if ok { converted.append(entry) } else { failed.append(entry) }
        }
        entries = converted.reversed()
        failures = failed.reversed()
    }

    /// Truncates the log file (also clears the failure list).
    func clear() {
        try? "".write(toFile: kLogPath, atomically: true, encoding: .utf8)
        refresh()
    }
}

// MARK: - View

struct ContentView: View {
    @StateObject private var config = ConfigStore()
    @StateObject private var watcher = Watcher()
    @StateObject private var log = LogStore()
    @StateObject private var cli = CLIInstaller()
    @StateObject private var updates = UpdateChecker()

    @State private var converting = false
    @State private var lastResult = ""
    @State private var progressCurrent = 0
    @State private var progressTotal = 0
    @State private var showOnboarding = false

    private let tick = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if updates.updateAvailable { updateBanner }
            if !config.folderExists { missingFolderBanner }
            if watcher.isStale { staleWatcherBanner }
            settingsBox
            watcherBox
            logBox
            if !log.failures.isEmpty { failureBox }
        }
        .padding(20)
        .frame(width: 580, height: 880)
        .onAppear {
            watcher.refresh(); log.refresh(); cli.installOnceIfFirstLaunch(); updates.check()
            showOnboarding = !UserDefaults.standard.bool(forKey: "didOnboard") && !config.folderExists
        }
        .onReceive(tick) { _ in watcher.refresh(); log.refresh() }
        .sheet(isPresented: $showOnboarding) { onboardingSheet }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HDRHeic").font(.system(size: 22, weight: .bold))
                Text(L("HDR JPEG → 10-bit HDR HEIC"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text("v\(appVersion())").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Banners

    private var updateBanner: some View {
        banner(color: .accentColor, icon: "arrow.down.circle.fill",
               text: "\(L("A new version is available")) — v\(updates.latestVersion ?? "")") {
            Button(L("Download")) { NSWorkspace.shared.open(updates.releaseURL) }
        }
    }

    private var missingFolderBanner: some View {
        banner(color: .orange, icon: "exclamationmark.triangle.fill",
               text: L("The watched folder no longer exists.")) {
            Button(L("Choose…")) { chooseFolder() }
        }
    }

    private var staleWatcherBanner: some View {
        banner(color: .orange, icon: "wrench.and.screwdriver.fill",
               text: L("The background watcher points at an old copy of the app. Repair it to keep converting automatically.")) {
            Button(L("Repair")) { watcher.install() }
        }
    }

    private func banner<Content: View>(color: Color, icon: String, text: String,
                                       @ViewBuilder action: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            action()
        }
        .padding(10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Onboarding

    private var onboardingSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.max.fill").font(.system(size: 40)).foregroundStyle(.orange)
            Text(L("Welcome to HDRHeic")).font(.title2).bold()
            Text(L("Pick the folder your HDR photos are exported to. You can change it later in Settings."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("Later")) { finishOnboarding() }
                Button(L("Choose Folder…")) {
                    chooseFolder()
                    finishOnboarding()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 400)
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "didOnboard")
        showOnboarding = false
    }

    // MARK: Settings

    private var settingsBox: some View {
        GroupBox(L("Settings")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L("Folder")).frame(width: 74, alignment: .leading)
                    Text(config.watchFolder)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(L("Choose…")) { chooseFolder() }
                }
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Delay")).frame(width: 74, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Stepper(value: $config.debounceSeconds, in: 1...120) {
                            Text(String(format: L("%@ seconds"), "\(config.debounceSeconds)"))
                        }
                        Text(L("Wait for the folder to settle before converting."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .onChange(of: config.debounceSeconds) { saveAndReload() }
                Divider()
                HStack {
                    Text(L("Scope")).frame(width: 74, alignment: .leading)
                    Toggle(L("Include subfolders"), isOn: $config.recursive)
                        .onChange(of: config.recursive) { saveAndReload() }
                    Spacer()
                }
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Redo")).frame(width: 74, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Picker("", selection: $config.regenerate) {
                            Text(L("Never")).tag("never")
                            Text(L("Newer")).tag("newer")
                            Text(L("Always")).tag("always")
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        .onChange(of: config.regenerate) { saveAndReload() }
                        Text(regenerateHint).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Original")).frame(width: 74, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(L("Move the JPEG to the Trash after converting"), isOn: $config.deleteSource)
                            .onChange(of: config.deleteSource) { saveAndReload() }
                        Text(L("Recoverable from the Trash. Turn off to keep both files."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Terminal")).frame(width: 74, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(L("Install the `hdrheic` command-line tool"), isOn: Binding(
                            get: { cli.installed },
                            set: { $0 ? cli.install() : cli.remove() }
                        ))
                        Text(L("Adds a `hdrheic` command to ~/.local/bin."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(6)
        }
    }

    private var regenerateHint: String {
        switch config.regenerate {
        case "never":  return L("Keep existing HEICs — never overwrite.")
        case "always": return L("Always re-convert, overwriting the HEIC.")
        default:       return L("Re-convert when the JPEG is newer than its HEIC.")
        }
    }

    // MARK: Watcher + convert

    private var watcherBox: some View {
        GroupBox(L("Background watcher")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(watcher.isRunning ? Color.green : Color.red)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 0.5))
                    Text(watcher.isRunning ? L("Running — new HDR photos convert automatically")
                                           : L("Off — nothing converts automatically"))
                        .foregroundStyle(watcher.isRunning ? .primary : .secondary)
                    Spacer()
                    if watcher.isRunning {
                        Button(L("Turn Off")) { watcher.remove() }
                    } else {
                        Button(L("Turn On")) { watcher.install() }.keyboardShortcut(.defaultAction)
                    }
                }
                Divider()
                HStack(spacing: 10) {
                    Button {
                        convertNow()
                    } label: {
                        Label(L("Convert now"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(converting)
                    Text(lastResult).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer()
                }
                if converting {
                    if progressTotal > 0 {
                        ProgressView(value: Double(progressCurrent), total: Double(progressTotal)) {
                            Text("\(progressCurrent) / \(progressTotal)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
            }
            .padding(6)
        }
    }

    // MARK: Log + failures

    private var logBox: some View {
        GroupBox(L("Recent conversions")) {
            VStack(spacing: 6) {
                if log.entries.isEmpty {
                    Text(L("Nothing converted yet."))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    entryList(log.entries)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
            .padding(6)
        }
    }

    private var failureBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("\(L("Problems")) (\(log.failures.count))", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.callout)
                    Spacer()
                    Button(L("Clear")) { log.clear() }.controlSize(.small)
                }
                entryList(Array(log.failures.prefix(20)))
            }
            .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 110)
            .padding(6)
        }
    }

    private func entryList(_ items: [LogEntry]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(items) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: entry.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(entry.ok ? .green : .red).font(.caption)
                        Text(entry.time)
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
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
        panel.prompt = L("Choose…")
        panel.message = L("Choose the folder to watch")
        if config.folderExists {
            panel.directoryURL = URL(fileURLWithPath: config.watchFolder)
        }
        if panel.runModal() == .OK, let path = panel.url?.path {
            config.watchFolder = path
            saveAndReload()
        }
    }

    private func convertNow() {
        guard let engine = engineURL()?.path else {
            lastResult = L("engine not found"); return
        }
        converting = true
        progressCurrent = 0
        progressTotal = 0
        lastResult = L("Converting…")
        runStreaming(engine, ["scan", "--progress"], onLine: { line in
            let parts = line.split(separator: " ")
            if line.hasPrefix("TOTAL "), parts.count >= 2 {
                progressTotal = Int(parts[1]) ?? 0
            } else if line.hasPrefix("PROGRESS "), parts.count >= 3 {
                progressCurrent = Int(parts[1]) ?? 0
                progressTotal = Int(parts[2]) ?? progressTotal
            }
        }, onFinish: { summary in
            converting = false
            lastResult = summary
            log.refresh()
        })
    }
}

// MARK: - App shell

func appLog(_ message: String) {
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    if let handle = FileHandle(forWritingAtPath: kLogPath) {
        handle.seekToEndOfFile(); handle.write(line.data(using: .utf8)!); try? handle.close()
    } else {
        try? line.data(using: .utf8)!.write(to: URL(fileURLWithPath: kLogPath))
    }
}

/// AppKit-driven menu-bar app: a real NSStatusItem (reliable), plus one window
/// hosting the SwiftUI ContentView, opened from the menu or on launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "HDRHeic")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L("Convert now"), action: #selector(convertNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "HDRHeic…", action: #selector(openWindow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit HDRHeic",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        let hosting = NSHostingController(rootView: ContentView())
        window = NSWindow(contentViewController: hosting)
        window.title = "HDRHeic"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()

        appLog("GUI launched — menu-bar status item installed: \(statusItem.button != nil)")
        openWindow() // show the window on first launch
    }

    @objc func openWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Menu-bar shortcut: run one conversion pass without opening the window.
    @objc func convertNow() {
        guard let engine = engineURL()?.path else { return }
        DispatchQueue.global(qos: .userInitiated).async { run(engine, ["scan"]) }
    }

    /// Re-opening the app (double-click in Finder/Launchpad, or `open`) shows the
    /// window again — a reliable way in even if the menu-bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWindow()
        return true
    }
}

@main
struct HDRHeicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        // No primary window scene — the AppDelegate owns the window. `Settings`
        // is a harmless minimal scene so the App type has a body.
        Settings { EmptyView() }
    }
}
