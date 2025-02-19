#if DEBUG
@testable import Logging
#else
import Logging
#endif
import DiscordModels

extension LoggingSystem {
    /// Bootstraps the logging system to use `DiscordLogHandler`.
    /// After calling this function, all your `Logger`s will start using `DiscordLogHandler`.
    ///
    /// - NOTE: Be careful because `LoggingSystem.bootstrap` can only be called once.
    /// If you use libraries like Vapor, you would want to remove such lines where you call `LoggingSystem...` and replace it with this function.
    public static func bootstrapWithDiscordLogger(
        address: WebhookAddress,
        level: Logger.Level = .info,
        metadataProvider: Logger.MetadataProvider? = nil,
        makeMainLogHandler: @escaping (String, Logger.MetadataProvider?) -> LogHandler
    ) async {
        LoggingSystem._bootstrap({ label, metadataProvider in
            var otherHandler = makeMainLogHandler(label, metadataProvider)
            otherHandler.logLevel = level
            let handler = MultiplexLogHandler([
                otherHandler,
                DiscordLogHandler(
                    label: label,
                    address: address,
                    level: level,
                    metadataProvider: metadataProvider
                )
            ])
            return handler
        }, metadataProvider: metadataProvider)
        /// If the log-manager is not yet set, then when it's set it'll use this new logger anyway.
        await DiscordGlobalConfiguration._logManager?.renewFallbackLogger()
    }
    
    private static func _bootstrap(
        _ factory: @escaping (String, Logger.MetadataProvider?) -> LogHandler,
        metadataProvider: Logger.MetadataProvider?
    ) {
#if DEBUG
        LoggingSystem.bootstrapInternal(factory, metadataProvider: metadataProvider)
#else
        LoggingSystem.bootstrap(factory, metadataProvider: metadataProvider)
#endif
    }
}
