import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.healthlens.app"

    static let healthKit = Logger(subsystem: subsystem, category: "HealthKit")
    static let ai = Logger(subsystem: subsystem, category: "AI")
    static let keychain = Logger(subsystem: subsystem, category: "Keychain")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let network = Logger(subsystem: subsystem, category: "Network")
}
