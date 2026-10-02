import Combine
import Foundation

@MainActor
final class LogViewerViewModel: ObservableObject {
  nonisolated deinit {}

  enum LevelFilter: String, CaseIterable, Identifiable {
    case debug
    case info
    case warning
    case error

    var id: String { rawValue }

    var title: String {
      switch self {
      case .debug: return "DEBUG"
      case .info: return "INFO"
      case .warning: return "WARN"
      case .error: return "ERROR"
      }
    }

    var levels: Set<Logger.Level> {
      Set(Logger.Level.allCases.filter { $0 >= minimumLevel })
    }

    var minimumLevel: Logger.Level {
      switch self {
      case .debug: return .debug
      case .info: return .info
      case .warning: return .warning
      case .error: return .error
      }
    }
  }

  enum TimeFilter: String, CaseIterable, Identifiable {
    case lastHour
    case today
    case last24Hours
    case last3Days
    case last7Days

    var id: String { rawValue }

    var title: String {
      switch self {
      case .lastHour: return "近 1 小时"
      case .today: return "今天"
      case .last24Hours: return "近 24 小时"
      case .last3Days: return "近 3 天"
      case .last7Days: return "近 7 天"
      }
    }

    func interval(now: Date, calendar: Calendar) -> (start: Date, end: Date) {
      switch self {
      case .lastHour:
        return (now.addingTimeInterval(-60 * 60), now)
      case .today:
        return (calendar.startOfDay(for: now), now)
      case .last24Hours:
        return (now.addingTimeInterval(-24 * 60 * 60), now)
      case .last3Days:
        return (now.addingTimeInterval(-3 * 24 * 60 * 60), now)
      case .last7Days:
        return (now.addingTimeInterval(-7 * 24 * 60 * 60), now)
      }
    }
  }

  @Published var isRecordingEnabled: Bool {
    didSet {
      guard oldValue != isRecordingEnabled else { return }
      store.setRecordingEnabled(isRecordingEnabled)
    }
  }
  @Published var levelFilter: LevelFilter = .warning
  @Published var timeFilter: TimeFilter = .today
  @Published private(set) var records: [LogRecord] = []
  @Published private(set) var isTruncated = false
  @Published private(set) var isLoading = false
  @Published private(set) var storageIssues: Set<LogStorageIssue> = []

  private let store: PersistentLogStore
  private let now: () -> Date
  private let calendar: Calendar
  private var reloadGeneration: UInt64 = 0

  init(
    store: PersistentLogStore = .shared,
    now: @escaping () -> Date = { Date() },
    calendar: Calendar = PersistentLogStore.defaultCalendar
  ) {
    self.store = store
    self.now = now
    self.calendar = calendar
    self.isRecordingEnabled = store.isRecordingEnabled
  }

  var summaryText: String {
    if isTruncated {
      return "显示最近 \(records.count) 条"
    }
    return "共 \(records.count) 条"
  }

  var storageErrorMessage: String? {
    let messages = LogStorageIssue.allCases.filter { storageIssues.contains($0) }.map(\.message)
    return messages.isEmpty ? nil : messages.joined(separator: "\n")
  }

  var showsEmptyState: Bool {
    records.isEmpty && !isLoading && !storageIssues.contains(.readFailed)
  }

  func makeQuery() -> LogQuery {
    let current = now()
    let interval = timeFilter.interval(now: current, calendar: calendar)
    return LogQuery(
      levels: levelFilter.levels,
      startDate: interval.start,
      endDate: interval.end
    )
  }

  func reloadRecords() async {
    reloadGeneration &+= 1
    let generation = reloadGeneration
    let query = makeQuery()
    if records.isEmpty {
      isLoading = true
    }
    let result = await store.records(matching: query)
    guard generation == reloadGeneration else { return }
    records = result.records
    isTruncated = result.isTruncated
    storageIssues = result.storageIssues
    isLoading = false
  }
}

enum LogDisplayFormatting {
  static let timestamp: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
  }()
}
