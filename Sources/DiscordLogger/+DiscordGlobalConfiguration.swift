import DiscordCore

extension DiscordGlobalConfiguration {
    static var _logManager: DiscordLogManager?
    
    /// The manager of logging to Discord.
    /// You must initialize this, if you want to use `DiscordLogHandler`.
    public static var logManager: DiscordLogManager {
        get {
            guard let logManager = _logManager else {
                fatalError("Need to configure the log-manager using 'DiscordGlobalConfiguration.logManager = DiscordLogManager(...)'")
            }
            return logManager
        }
        set(newValue) { _logManager = newValue }
    }
}
