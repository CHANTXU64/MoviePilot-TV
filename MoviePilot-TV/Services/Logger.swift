import Foundation

// MARK: - 核心协议与实现

/// 定义了日志实现程序的标准接口。
/// 任何日志记录器（例如，基于 print、os.log 或第三方）都必须遵守此协议。
public protocol LogHandler {
  func log(
    level: Logger.Level,
    message: @autoclosure () -> Any,
    metadata: [String: Any]?,
    file: String,
    function: String,
    line: UInt
  )
}

/// 一个默认的日志处理器，在调试构建期间将消息打印到控制台。
///
/// 此实现会格式化消息以包含级别、源文件和行号，
/// 如果提供了元数据，它也会被一并打印出来。
public struct PrintLogHandler: LogHandler {
  public init() {}

  public func log(
    level: Logger.Level,
    message: @autoclosure () -> Any,
    metadata: [String: Any]?,
    file: String,
    function: String,
    line: UInt
  ) {
    #if DEBUG
      let fileName = URL(fileURLWithPath: file).lastPathComponent
      var logMessage = "[\(level.prefix)] [\(fileName):\(line)] -> \(message())"

      if let metadata = metadata, !metadata.isEmpty {
        logMessage += " | metadata: \(metadata)"
      }

      print(logMessage)
    #endif
  }
}

// MARK: - 公开的日志 API

/// 一个集中的、可适配的应用程序日志记录工具。
///
/// 此枚举充当外观（facade），将所有日志调用转发到可配置的 `LogHandler`。
/// 默认情况下，它使用 `PrintLogHandler`，该处理器仅在 `DEBUG` 构建中向控制台打印。
/// 这种架构使得更换底层日志引擎变得容易，而无需更改整个应用程序中的任何日志调用代码。
///
/// **基本用法：**
/// ```
/// Logger.info("用户成功登录。")
/// Logger.error("获取电影失败: \(error.localizedDescription)")
/// ```
///
/// **支持结构化日志：**
/// ```
/// let metadata = ["userId": 123, "context": "ProfileView"]
/// Logger.info("用户数据已加载", metadata: metadata)
/// ```
///
/// ```swift
/// // 在你的 AppDelegate 或 App 结构体的初始化方法中
/// Logger.bootstrap(handler: MyCustomLogHandler())
/// ```
public enum Logger {

  /// 代表日志消息的严重级别。
  public enum Level {
    case verbose
    case debug
    case info
    case warning
    case error

    /// 用于日志消息的简短描述性前缀。
    var prefix: String {
      switch self {
      case .verbose: return "VERBOSE"
      case .debug: return "DEBUG"
      case .info: return "INFO"
      case .warning: return "WARN"
      case .error: return "ERROR"
      }
    }
  }

  /// 当前活动的日志处理器。默认为基于 print 的处理器。
  private static var handler: LogHandler = PrintLogHandler()

  /// 使用特定的处理器来配置日志系统。
  ///
  /// 在应用程序生命周期的早期调用此方法，以设置期望的日志后端。
  ///
  /// - Parameter handler: 一个遵守 `LogHandler` 协议的类型的实例。
  public static func bootstrap(handler: LogHandler) {
    self.handler = handler
  }

  /// 记录一条详细消息。用于比调试更详细的诊断信息。
  public static func verbose(
    _ message: @autoclosure () -> Any,
    metadata: [String: Any]? = nil,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
  ) {
    handler.log(level: .verbose, message: message(), metadata: metadata, file: file, function: function, line: line)
  }

  /// 记录一条调试消息。用于详细的、临时的调试信息。
  public static func debug(
    _ message: @autoclosure () -> Any,
    metadata: [String: Any]? = nil,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
  ) {
    handler.log(level: .debug, message: message(), metadata: metadata, file: file, function: function, line: line)
  }

  /// 记录一条信息性消息。用于常规的操作性消息。
  public static func info(
    _ message: @autoclosure () -> Any,
    metadata: [String: Any]? = nil,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
  ) {
    handler.log(level: .info, message: message(), metadata: metadata, file: file, function: function, line: line)
  }

  /// 记录一条警告消息。用于不需要立即采取行动的潜在问题。
  public static func warning(
    _ message: @autoclosure () -> Any,
    metadata: [String: Any]? = nil,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
  ) {
    handler.log(level: .warning, message: message(), metadata: metadata, file: file, function: function, line: line)
  }

  /// 记录一条错误消息。用于严重的错误和异常。
  public static func error(
    _ message: @autoclosure () -> Any,
    metadata: [String: Any]? = nil,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
  ) {
    handler.log(level: .error, message: message(), metadata: metadata, file: file, function: function, line: line)
  }
}
