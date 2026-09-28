import Foundation

// MARK: - Logging

enum Log {
    private static let queue = DispatchQueue(label: "dshpet.log")
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ message: String) {
        let line = fmt.string(from: Date()) + " " + message + "\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            let url = PetPaths.logURL
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}

// MARK: - Paths

enum PetPaths {
    static let support: URL = {
        let fm = FileManager.default
        // DSHPET_HOME makes the pet self-contained (portable mode, and how the
        // build's own end-to-end test keeps its state out of the real profile).
        if let override = ProcessInfo.processInfo.environment["DSHPET_HOME"], !override.isEmpty {
            let dir = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let dir = base.appendingPathComponent("DSHBalancePet", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var logURL: URL { support.appendingPathComponent("pet.log") }
    static var stateURL: URL { support.appendingPathComponent("state.json") }
    /// Liveness/geometry snapshot, rewritten about once a second while running.
    static var statusURL: URL { support.appendingPathComponent("status.json") }
    static var userKeyURL: URL { support.appendingPathComponent("apikey.txt") }

    /// apikey.txt shipped next to the executable (inside the .app, or next to the raw binary).
    static var sidecarKeyURL: URL {
        executableDir.appendingPathComponent("apikey.txt")
    }

    static var executableDir: URL {
        URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
    }

    static var soundURL: URL? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "hit", withExtension: "wav"),
            support.appendingPathComponent("hit.wav"),
            executableDir.appendingPathComponent("hit.wav"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static let dshCredentials = URL(fileURLWithPath: NSHomeDirectory() + "/.dsh/.credentials.yaml")
}

// MARK: - Credentials

enum AuthMode {
    case apiKey    // sk-... -> https://api.deepseek.com/user/balance  (Authorization: Bearer)
    case account   // DSH platform grant -> <issuer>/api/v0/users/get_user_summary  (x-dsh-auth-token)
}

struct Credential {
    let mode: AuthMode
    let token: String
    let endpoint: URL
    let source: String

    var shortDescription: String {
        switch mode {
        case .apiKey:  return "API Key · " + source
        case .account: return "DSH 账号凭证 · " + source
        }
    }
}

enum CredentialStore {
    static let apiKeyEndpoint = "https://api.deepseek.com/user/balance"

    /// Resolution order:
    ///   1. DSHPET_KEY environment variable
    ///   2. apikey.txt next to the executable
    ///   3. apikey.txt in Application Support
    ///   4. DEEPSEEK_API_KEY inside ~/.dsh/.credentials.yaml
    ///   5. the DSH account-platform grant in ~/.dsh/.credentials.yaml
    static func resolve() -> Credential? {
        let env = ProcessInfo.processInfo.environment

        if let v = env["DSHPET_KEY"], !v.trimmingCharacters(in: .whitespaces).isEmpty {
            return apiKey(v, source: "环境变量 DSHPET_KEY")
        }
        if let v = readKeyFile(PetPaths.sidecarKeyURL) {
            return apiKey(v, source: "apikey.txt（应用目录）")
        }
        if let v = readKeyFile(PetPaths.userKeyURL) {
            return apiKey(v, source: "apikey.txt（配置目录）")
        }

        let yaml = (try? String(contentsOf: PetPaths.dshCredentials, encoding: .utf8)) ?? ""

        if let key = firstGroup(in: yaml, pattern: "DEEPSEEK_API_KEY\\s*:\\s*[\"']?([A-Za-z0-9_\\-]{8,})") {
            return apiKey(key, source: "~/.dsh/.credentials.yaml")
        }
        if let grant = accountGrant(from: yaml) {
            let base = grant.issuer.hasSuffix("/") ? String(grant.issuer.dropLast()) : grant.issuer
            let path = env["DSHPET_API_PATH"] ?? "/api/v0/users/get_user_summary"
            if let url = URL(string: base + path) {
                return Credential(mode: .account, token: grant.token, endpoint: url,
                                  source: "DSH 账号（\(URL(string: base)?.host ?? base)）")
            }
        }
        return nil
    }

    private static func apiKey(_ raw: String, source: String) -> Credential? {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty, let url = URL(string: apiKeyEndpoint) else { return nil }
        return Credential(mode: .apiKey, token: v, endpoint: url, source: source)
    }

    private static func readKeyFile(_ url: URL) -> String? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    private static func firstGroup(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// Pull the token/issuer out of the block-style YAML record
    /// `deepseek-account-platform/default:` in ~/.dsh/.credentials.yaml.
    static func accountGrant(from yaml: String) -> (token: String, issuer: String)? {
        let lines = yaml.components(separatedBy: .newlines)
        for (i, line) in lines.enumerated() {
            guard line.trimmingCharacters(in: .whitespaces).hasPrefix("deepseek-account-platform/default:") else { continue }
            let baseIndent = indentWidth(line)
            var token: String?
            var issuer: String?
            var j = i + 1
            while j < lines.count {
                let l = lines[j]
                let t = l.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty && indentWidth(l) <= baseIndent { break }
                if t.hasPrefix("token:")  { token  = scalar(t, key: "token:") }
                if t.hasPrefix("issuer:") { issuer = scalar(t, key: "issuer:") }
                j += 1
            }
            if let tk = token, let isr = issuer, !tk.isEmpty, !isr.isEmpty {
                return (tk, isr)
            }
        }
        return nil
    }

    private static func indentWidth(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    private static func scalar(_ line: String, key: String) -> String? {
        var v = String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
        v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return v.isEmpty ? nil : v
    }
}

// MARK: - Persisted state

struct PetState {
    var sizeIndex: Int = 1          // index into PetController.sizePresets
    var snapOnRelease: Bool = true
    var soundOn: Bool = true
    var pollSeconds: Double = 30
    var windowOrigin: CGPoint?

    static func load() -> PetState {
        var s = PetState()
        guard let data = try? Data(contentsOf: PetPaths.stateURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return s }
        if let v = obj["sizeIndex"] as? Int { s.sizeIndex = v }
        if let v = obj["snapOnRelease"] as? Bool { s.snapOnRelease = v }
        if let v = obj["soundOn"] as? Bool { s.soundOn = v }
        if let v = obj["pollSeconds"] as? Double { s.pollSeconds = v }
        if let x = obj["originX"] as? Double, let y = obj["originY"] as? Double {
            s.windowOrigin = CGPoint(x: x, y: y)
        }
        return s
    }

    func save() {
        var obj: [String: Any] = [
            "sizeIndex": sizeIndex,
            "snapOnRelease": snapOnRelease,
            "soundOn": soundOn,
            "pollSeconds": pollSeconds,
        ]
        if let o = windowOrigin {
            obj["originX"] = Double(o.x)
            obj["originY"] = Double(o.y)
        }
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: PetPaths.stateURL)
        }
    }
}
