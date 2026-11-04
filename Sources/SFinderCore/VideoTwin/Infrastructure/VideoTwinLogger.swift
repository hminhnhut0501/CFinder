import OSLog

public enum VideoTwinLogger {
    public static let scanner    = Logger(subsystem: "com.sfinder.videotwin", category: "scanner")
    public static let probe      = Logger(subsystem: "com.sfinder.videotwin", category: "probe")
    public static let decoder    = Logger(subsystem: "com.sfinder.videotwin", category: "decoder")
    public static let fingerprint = Logger(subsystem: "com.sfinder.videotwin", category: "fingerprint")
    public static let matcher    = Logger(subsystem: "com.sfinder.videotwin", category: "matcher")
    public static let database   = Logger(subsystem: "com.sfinder.videotwin", category: "database")
    public static let quality    = Logger(subsystem: "com.sfinder.videotwin", category: "quality")
    public static let ui         = Logger(subsystem: "com.sfinder.videotwin", category: "UI")
}
