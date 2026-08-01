// hdrheic — HDR JPEG → 10-bit adaptive-HDR HEIC converter
//
// Reproduces macOS Preview's "Export → HEIF, 10-bit, Maximum" output:
// a 10-bit Display P3 HEIC that keeps the original ISO gain map (the `tmap`
// adaptive-HDR structure), using only native Apple frameworks and the
// hardware HEVC encoder. Light on the machine, ~1.5 s per image.
//
// Sub-commands:
//   hdrheic scan                 one pass over the configured folder (on demand)
//   hdrheic watch                stay resident, convert new HDR JPEGs (debounced)
//   hdrheic get   <key>          print a config value
//   hdrheic set   <key> <value>  change a config value
//   hdrheic config-path          print the config file path
//   hdrheic version              print version

import Foundation
import CoreImage
import CoreGraphics
import ImageIO

let kVersion = "1.0"

// MARK: - Paths

func expandTilde(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
}

let appSupportDir = expandTilde("~/Library/Application Support/HDRHeic")
let configPath = "\(appSupportDir)/config.json"
let logPath = expandTilde("~/Library/Logs/HDRHeic.log")

// MARK: - Logging

func logLine(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(stamp)] \(message)\n"
    FileHandle.standardOutput.write(line.data(using: .utf8)!)
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        try? handle.close()
    } else {
        try? line.data(using: .utf8)!.write(to: URL(fileURLWithPath: logPath))
    }
}

// MARK: - Config

struct Config {
    var watchFolder: String = "~/Pictures/Exported"
    var debounceSeconds: Double = 5
    var recursive: Bool = true
    // Regeneration policy when a HEIC already exists next to the JPEG:
    //   "never"  — keep it (never overwrite)
    //   "newer"  — re-convert only when the JPEG is newer than the HEIC (default)
    //   "always" — always re-convert, overwriting the HEIC
    var regenerate: String = "newer"
}

func loadConfig() -> Config {
    var config = Config()
    guard let data = FileManager.default.contents(atPath: configPath),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return config
    }
    if let folder = object["watchFolder"] as? String { config.watchFolder = folder }
    if let delay = object["debounceSeconds"] as? Double { config.debounceSeconds = delay }
    if let delay = object["debounceSeconds"] as? Int { config.debounceSeconds = Double(delay) }
    if let recursive = object["recursive"] as? Bool { config.recursive = recursive }
    if let regenerate = object["regenerate"] as? String,
       ["never", "newer", "always"].contains(regenerate) { config.regenerate = regenerate }
    return config
}

func saveConfig(_ config: Config) {
    try? FileManager.default.createDirectory(atPath: appSupportDir,
                                             withIntermediateDirectories: true)
    let object: [String: Any] = [
        "watchFolder": config.watchFolder,
        "debounceSeconds": config.debounceSeconds,
        "recursive": config.recursive,
        "regenerate": config.regenerate,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: object,
                                              options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: URL(fileURLWithPath: configPath))
    }
}

// MARK: - HDR detection

/// True when the JPEG carries a gain map (ISO 21496-1 or Apple HDR) — i.e. it is
/// a real HDR photo. Plain JPEGs have neither and are skipped.
func hasGainMap(_ url: URL) -> Bool {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
    if CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil {
        return true
    }
    if CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil {
        return true
    }
    return false
}

// MARK: - Conversion

enum ConversionError: Error { case cannotLoad }

let sharedContext = CIContext()
let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!

/// Writes a 10-bit Display P3 adaptive-HDR HEIC (SDR base + original gain map).
/// The write is atomic: a temp file is finalised then moved into place.
func convert(_ source: URL, to destination: URL) throws {
    guard let sdrImage = CIImage(contentsOf: source),
          let hdrImage = CIImage(contentsOf: source, options: [.expandToHDR: true]) else {
        throw ConversionError.cannotLoad
    }
    let options: [CIImageRepresentationOption: Any] = [
        CIImageRepresentationOption.hdrImage: hdrImage,
        CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 1.0,
    ]
    let tempURL = destination.deletingLastPathComponent()
        .appendingPathComponent(".\(destination.lastPathComponent).tmp")
    try? FileManager.default.removeItem(at: tempURL)
    try sharedContext.writeHEIF10Representation(of: sdrImage, to: tempURL,
                                                colorSpace: displayP3, options: options)
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.moveItem(at: tempURL, to: destination)
}

// MARK: - Scanning

struct ScanResult {
    var converted = 0
    var regenerated = 0
    var skippedExisting = 0
    var skippedNonHDR = 0
    var failed = 0

    var summary: String {
        "Converted: \(converted)"
            + (regenerated > 0 ? ", regenerated: \(regenerated)" : "")
            + ", skipped (up to date): \(skippedExisting)"
            + ", skipped (not HDR): \(skippedNonHDR)"
            + (failed > 0 ? ", failed: \(failed)" : "")
    }
}

func modificationDate(_ url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
}

func jpegURLs(in folder: URL, recursive: Bool) -> [URL] {
    let manager = FileManager.default
    var results: [URL] = []
    let keys: [URLResourceKey] = [.isRegularFileKey]
    if recursive {
        guard let enumerator = manager.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                  options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in enumerator where isJPEG(url) { results.append(url) }
    } else {
        let contents = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles])) ?? []
        results = contents.filter(isJPEG)
    }
    return results
}

func isJPEG(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    return ext == "jpg" || ext == "jpeg"
}

func runScan(_ config: Config, verbose: Bool) -> ScanResult {
    var result = ScanResult()
    let folder = URL(fileURLWithPath: expandTilde(config.watchFolder), isDirectory: true)
    guard FileManager.default.fileExists(atPath: folder.path) else {
        logLine("Watch folder does not exist: \(folder.path)")
        return result
    }
    for source in jpegURLs(in: folder, recursive: config.recursive) {
        let heic = source.deletingPathExtension().appendingPathExtension("heic")
        let heif = source.deletingPathExtension().appendingPathExtension("heif")
        let existingOutput: URL? = FileManager.default.fileExists(atPath: heic.path) ? heic
            : (FileManager.default.fileExists(atPath: heif.path) ? heif : nil)

        var isRegenerate = false
        if let output = existingOutput {
            switch config.regenerate {
            case "always":
                isRegenerate = true
            case "newer":
                // Regenerate only when the JPEG is newer than the existing HEIC.
                if let sourceDate = modificationDate(source),
                   let outputDate = modificationDate(output),
                   sourceDate > outputDate {
                    isRegenerate = true
                } else {
                    result.skippedExisting += 1
                    continue
                }
            default: // "never"
                result.skippedExisting += 1
                continue
            }
        }

        if !hasGainMap(source) {
            result.skippedNonHDR += 1
            continue
        }
        do {
            try convert(source, to: heic)
            if isRegenerate {
                result.regenerated += 1
                logLine("Regenerated: \(source.lastPathComponent) → \(heic.lastPathComponent)")
            } else {
                result.converted += 1
                logLine("Converted: \(source.lastPathComponent) → \(heic.lastPathComponent)")
            }
        } catch {
            result.failed += 1
            logLine("FAILED: \(source.lastPathComponent) — \(error)")
        }
    }
    if verbose || result.converted > 0 || result.failed > 0 {
        logLine("Scan complete — \(result.summary)")
    }
    return result
}

// MARK: - Watching (FSEvents + debounce)

final class Watcher {
    let config: Config
    let queue = DispatchQueue(label: "hdrheic.watch")
    var pending: DispatchWorkItem?
    var stream: FSEventStreamRef?

    init(_ config: Config) { self.config = config }

    func start() {
        let folder = expandTilde(config.watchFolder)
        logLine("Watching \(folder) (debounce \(config.debounceSeconds)s, "
            + "recursive: \(config.recursive))")

        // Catch anything that arrived while we were not running.
        scheduleScan(triggeredByEvent: false)

        var context = FSEventStreamContext(version: 0,
                                           info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<Watcher>.fromOpaque(info).takeUnretainedValue()
            watcher.scheduleScan(triggeredByEvent: true)
        }
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context,
                                               [folder] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               1.0, flags) else {
            logLine("Could not create FSEvent stream — exiting")
            exit(1)
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        dispatchMain()
    }

    /// Debounce: every event resets the timer; a scan runs only once the folder
    /// has been quiet for `debounceSeconds`. That quiet period is what guarantees
    /// a file has finished being written before we touch it.
    func scheduleScan(triggeredByEvent: Bool) {
        if triggeredByEvent { logLine("Change detected — waiting for the folder to settle") }
        pending?.cancel()
        let work = DispatchWorkItem {
            let result = runScan(self.config, verbose: false)
            logLine("Settled — \(result.summary)")
        }
        pending = work
        queue.asyncAfter(deadline: .now() + config.debounceSeconds, execute: work)
    }
}

// MARK: - Entry point

let arguments = CommandLine.arguments
let command = arguments.count > 1 ? arguments[1] : "scan"

switch command {
case "version", "--version", "-v":
    print(kVersion)

case "config-path":
    print(configPath)

case "get":
    guard arguments.count > 2 else { FileHandle.standardError.write("usage: hdrheic get <key>\n".data(using: .utf8)!); exit(2) }
    let config = loadConfig()
    switch arguments[2] {
    case "watchFolder": print(expandTilde(config.watchFolder))
    case "debounceSeconds": print(String(format: "%g", config.debounceSeconds))
    case "recursive": print(config.recursive ? "true" : "false")
    case "regenerate": print(config.regenerate)
    default: FileHandle.standardError.write("unknown key\n".data(using: .utf8)!); exit(2)
    }

case "set":
    guard arguments.count > 3 else { FileHandle.standardError.write("usage: hdrheic set <key> <value>\n".data(using: .utf8)!); exit(2) }
    var config = loadConfig()
    let value = arguments[3]
    switch arguments[2] {
    case "watchFolder": config.watchFolder = value
    case "debounceSeconds": config.debounceSeconds = max(1, Double(value) ?? config.debounceSeconds)
    case "recursive": config.recursive = (value == "true" || value == "1" || value == "yes")
    case "regenerate":
        guard ["never", "newer", "always"].contains(value) else {
            FileHandle.standardError.write("regenerate must be never|newer|always\n".data(using: .utf8)!); exit(2)
        }
        config.regenerate = value
    default: FileHandle.standardError.write("unknown key\n".data(using: .utf8)!); exit(2)
    }
    saveConfig(config)
    print("ok")

case "scan":
    let config = loadConfig()
    if !FileManager.default.fileExists(atPath: configPath) { saveConfig(config) }
    let result = runScan(config, verbose: true)
    // Final line without a timestamp so callers (the app) can show it verbatim.
    print(result.summary)

case "watch":
    let config = loadConfig()
    if !FileManager.default.fileExists(atPath: configPath) { saveConfig(config) }
    Watcher(config).start()

default:
    FileHandle.standardError.write("unknown command: \(command)\n".data(using: .utf8)!)
    exit(2)
}
