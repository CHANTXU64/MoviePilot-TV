import XCTest

@testable import MoviePilot_TV

private struct TestItem: Identifiable, Equatable {
  let id: Int
}

private enum TestFailure: Error, LocalizedError {
  case expected
  case requestTimedOut
  case timedOut(String)

  var errorDescription: String? {
    switch self {
    case .expected:
      return "Expected test failure"
    case .requestTimedOut:
      return "Request timed out"
    case .timedOut(let description):
      return "Timed out waiting for \(description)"
    }
  }
}

private actor AsyncGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func open() {
    guard !isOpen else { return }
    isOpen = true
    let continuations = waiters
    waiters.removeAll()
    continuations.forEach { $0.resume() }
  }
}

private actor PageProbe {
  private var pages: [Int] = []
  private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

  func record(_ page: Int) {
    pages.append(page)
    resumeSatisfiedWaiters()
  }

  func snapshot() -> [Int] {
    pages
  }

  func waitForPageCount(_ count: Int) async {
    guard pages.count < count else { return }
    await withCheckedContinuation { continuation in
      waiters.append((count, continuation))
    }
  }

  private func resumeSatisfiedWaiters() {
    var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    for waiter in waiters {
      if pages.count >= waiter.count {
        waiter.continuation.resume()
      } else {
        remaining.append(waiter)
      }
    }

    waiters = remaining
  }
}

private func withTimeout<T: Sendable>(
  _ description: String,
  seconds: TimeInterval = 2,
  operation: @escaping @Sendable () async -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask {
      await operation()
    }
    group.addTask {
      try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      throw TestFailure.timedOut(description)
    }

    let result = try await group.next()!
    group.cancelAll()
    return result
  }
}

final class PaginatorTests: XCTestCase {
  
  // MARK: - 生命周期与任务取消测试

  /// 验证 `cancel` 能够使正在进行（In-Flight）的请求结果失效。
  /// 模拟：请求发起后卡住 -> 调用 cancel -> 请求最终完成并返回数据。
  /// 期望：返回的过时数据应被静默丢弃，不污染 items，并且加载状态应归位。
  @MainActor
  func testCancelInvalidatesInFlightResult() async throws {
    let probe = PageProbe()
    let gate = AsyncGate()
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in
        await probe.record(page)
        await gate.wait()
        return [TestItem(id: page)]
      },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    let refreshTask = Task { @MainActor in
      await paginator.refresh()
    }

    try await withTimeout("first fetch to start") {
      await probe.waitForPageCount(1)
    }

    paginator.cancel()
    await gate.open()
    await refreshTask.value

    let requestedPages = await probe.snapshot()
    XCTAssertEqual(requestedPages, [1])
    XCTAssertEqual(paginator.items, [])
    XCTAssertFalse(paginator.isLoading)
    XCTAssertFalse(paginator.isFirstLoading)
    XCTAssertFalse(paginator.isLoadingMore)
  }

  // MARK: - 游标控制测试

  /// 验证在进行加载时调用 `advancePageCursor` 能正确取消当前卡住的请求，
  /// 并使用位移后的新游标重新发起下一次加载。
  @MainActor
  func testAdvancePageCursorRestartsCancelledInFlightLoadWithShiftedPage() async throws {
    let probe = PageProbe()
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in
        await probe.record(page)

        if page == 1 {
          while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 1_000_000)
          }
          throw CancellationError()
        }

        return [TestItem(id: page)]
      },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    let refreshTask = Task { @MainActor in
      await paginator.refresh()
    }

    try await withTimeout("initial page request") {
      await probe.waitForPageCount(1)
    }

    paginator.advancePageCursor(by: 1)

    try await withTimeout("restart page request") {
      await probe.waitForPageCount(2)
    }

    await refreshTask.value

    let requestedPages = await probe.snapshot()
    XCTAssertEqual(requestedPages, [1, 2])
    XCTAssertEqual(paginator.items, [TestItem(id: 2)])
    XCTAssertFalse(paginator.isLoading)
  }

  /// 验证在加载中调用 `rewindPageCursor` 会重启请求，且遇到之前已有的重复页面时
  /// 能够借助去重逻辑跳过，并自动继续拉取到新的有效页面。
  @MainActor
  func testRewindPageCursorRestartsAndScansPastDuplicatePage() async throws {
    let probe = PageProbe()
    var hasBlockedPageTwo = false
    var seenIds = Set<Int>()

    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in
        await probe.record(page)

        if page == 2, !hasBlockedPageTwo {
          hasBlockedPageTwo = true
          while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 1_000_000)
          }
          throw CancellationError()
        }

        return [TestItem(id: page)]
      },
      processor: { items, newItems in
        let uniqueItems = newItems.filter { seenIds.insert($0.id).inserted }
        items.append(contentsOf: uniqueItems)
        return !uniqueItems.isEmpty
      }
    )

    await paginator.refresh()
    XCTAssertEqual(paginator.items, [TestItem(id: 1)])

    let loadMoreTask = Task { @MainActor in
      await paginator.loadMore()
    }

    try await withTimeout("blocked page 2 request") {
      await probe.waitForPageCount(2)
    }

    paginator.rewindPageCursor(by: 1)

    try await withTimeout("rewound duplicate page and replacement page") {
      await probe.waitForPageCount(4)
    }

    await loadMoreTask.value

    let requestedPages = await probe.snapshot()
    XCTAssertEqual(requestedPages, [1, 2, 1, 2])
    XCTAssertEqual(paginator.items, [TestItem(id: 1), TestItem(id: 2)])
    XCTAssertTrue(paginator.hasMore)
    XCTAssertFalse(paginator.isLoading)
  }

  // MARK: - 错误状态记录与恢复测试

  /// 验证正常业务错误被触发时能正确拦截并在随后的成功重试中清空状态。
  @MainActor
  func testErrorStateClearsAfterSuccessfulRetry() async {
    var shouldFail = true
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in
        if shouldFail {
          shouldFail = false
          throw TestFailure.expected
        }
        return [TestItem(id: page)]
      },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    await paginator.refresh()

    XCTAssertTrue(paginator.hasError)
    XCTAssertNotNil(paginator.lastError)
    XCTAssertTrue(paginator.hasMore)

    await paginator.loadMore()

    XCTAssertFalse(paginator.hasError)
    XCTAssertNil(paginator.lastError)
    XCTAssertEqual(paginator.items, [TestItem(id: 1)])
    XCTAssertTrue(paginator.hasMore)
  }

  /// 验证网络超时错误被捕获并在随后的成功重试中清空状态。
  @MainActor
  func testTimeoutErrorIsRecordedAndClearsAfterSuccessfulRetry() async {
    var shouldTimeout = true
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in
        if shouldTimeout {
          shouldTimeout = false
          throw TestFailure.requestTimedOut
        }
        return [TestItem(id: page)]
      },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    await paginator.refresh()

    XCTAssertTrue(paginator.hasError)
    XCTAssertNotNil(paginator.lastError)
    XCTAssertTrue(paginator.hasMore)
    XCTAssertEqual(paginator.items, [])

    await paginator.loadMore()

    XCTAssertFalse(paginator.hasError)
    XCTAssertNil(paginator.lastError)
    XCTAssertEqual(paginator.items, [TestItem(id: 1)])
  }

  /// 验证在发生3次连续错误后，分页器会自动停止并锁定 `hasMore = false`。
  @MainActor
  func testStopsAfterThreeConsecutiveErrors() async {
    var requestCount = 0
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { _ in
        requestCount += 1
        throw TestFailure.expected
      },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    await paginator.refresh()
    await paginator.loadMore()
    await paginator.loadMore()
    await paginator.loadMore()

    XCTAssertEqual(requestCount, 3)
    XCTAssertTrue(paginator.hasError)
    XCTAssertNotNil(paginator.lastError)
    XCTAssertFalse(paginator.hasMore)
    XCTAssertEqual(paginator.items, [])
  }

  // MARK: - 数据去重与并发隔离测试

  /// 验证在反复拉取到仅含重复数据的页面时，分页器扫描达到次数限制后会主动停止。
  @MainActor
  func testDuplicateOnlyPagesDoNotAppendAndStopAfterScanLimit() async {
    let probe = PageProbe()
    var seenIds = Set<Int>()
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in
        await probe.record(page)
        return [TestItem(id: 1)]
      },
      processor: { items, newItems in
        let uniqueItems = newItems.filter { seenIds.insert($0.id).inserted }
        items.append(contentsOf: uniqueItems)
        return !uniqueItems.isEmpty
      }
    )

    await paginator.refresh()
    await paginator.loadMore()

    let requestedPages = await probe.snapshot()
    XCTAssertEqual(requestedPages, [1, 2, 3])
    XCTAssertEqual(paginator.items, [TestItem(id: 1)])
    XCTAssertFalse(paginator.hasMore)
    XCTAssertFalse(paginator.hasError)
    XCTAssertNil(paginator.lastError)
  }

  /// 验证并发情况下，如果旧的 refresh 请求延迟返回，新的 refresh 结果不会被污染。
  /// (依靠 generation 世代隔离策略)
  @MainActor
  func testRefreshInvalidatesOlderRefreshThatCompletesLater() async throws {
    let probe = PageProbe()
    let oldRefreshGate = AsyncGate()
    var fetchCount = 0

    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in
        await probe.record(page)
        fetchCount += 1

        if fetchCount == 1 {
          await oldRefreshGate.wait()
          return [TestItem(id: 100)]
        }

        return [TestItem(id: 200)]
      },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    let oldRefreshTask = Task { @MainActor in
      await paginator.refresh()
    }

    try await withTimeout("old refresh fetch to start") {
      await probe.waitForPageCount(1)
    }

    let newRefreshTask = Task { @MainActor in
      await paginator.refresh()
    }

    try await withTimeout("new refresh fetch to start") {
      await probe.waitForPageCount(2)
    }

    await oldRefreshGate.open()
    await oldRefreshTask.value
    await newRefreshTask.value

    let requestedPages = await probe.snapshot()
    XCTAssertEqual(requestedPages, [1, 1])
    XCTAssertEqual(paginator.items, [TestItem(id: 200)])
    XCTAssertFalse(paginator.isLoading)
  }

  /// 验证释放 `Paginator` 时，正在进行的异步加载任务会被正确取消。
  @MainActor
  func testDeinitCancelsInFlightTask() async throws {
    let probe = PageProbe()
    let gate = AsyncGate()
    var paginator: Paginator<TestItem>? = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in
        await probe.record(page)
        await gate.wait()
        return [TestItem(id: page)]
      },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    let refreshTask = Task { @MainActor in
      await paginator?.refresh()
    }

    try await withTimeout("fetch to start") {
      await probe.waitForPageCount(1)
    }

    // 释放 paginator，deinit 应取消 in-flight task
    paginator = nil

    // 打开 gate 让 fetcher 可以完成（如果未被取消的话）
    await gate.open()
    // refreshTask 中的 await paginator?.refresh() 在 paginator 为 nil 后
    // 可选链返回 Void，不会崩溃
    await refreshTask.value

    let requestedPages = await probe.snapshot()
    XCTAssertEqual(requestedPages, [1], "deinit 应取消 in-flight 加载，不应请求额外页面")
  }

  /// 验证在快速的 `cancel` 和 `refresh` 循环调用下，不会崩溃或产生异常状态。
  @MainActor
  func testRapidCancelRefreshCycleDoesNotCrash() async {
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in
        try await Task.sleep(nanoseconds: 10_000_000)
        return [TestItem(id: page)]
      },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    for _ in 0..<10 {
      paginator.cancel()
      await paginator.refresh()
    }

    XCTAssertFalse(paginator.isLoading)
    XCTAssertFalse(paginator.hasError)
    XCTAssertNotNil(paginator.items.first)
  }

  /// 验证在空闲状态下调用 `cancel()` 是无副作用的操作 (no-op)。
  @MainActor
  func testCancelWhenIdleIsNoOp() async {
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in [TestItem(id: page)] },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    await paginator.refresh()
    XCTAssertEqual(paginator.items, [TestItem(id: 1)])
    XCTAssertFalse(paginator.isLoading)

    paginator.cancel()

    XCTAssertFalse(paginator.isLoading)
    XCTAssertFalse(paginator.isFirstLoading)
    XCTAssertFalse(paginator.isLoadingMore)
  }

  /// 验证调用 `cancel()` 不会清空已经加载的 items 列表。
  @MainActor
  func testCancelPreservesExistingItems() async {
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in [TestItem(id: page)] },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    await paginator.refresh()
    await paginator.loadMore()
    XCTAssertEqual(paginator.items, [TestItem(id: 1), TestItem(id: 2)])

    paginator.cancel()

    XCTAssertEqual(paginator.items, [TestItem(id: 1), TestItem(id: 2)], "cancel 不应清空 items")
  }

  /// 验证在 `refresh` 中，如果 API 返回重复的数据，能够被正确去重。
  @MainActor
  func testRefreshDeduplicatesItems() async {
    var seenIds = Set<Int>()
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { _ in
        // 总是返回相同内容
        return [TestItem(id: 1), TestItem(id: 2)]
      },
      processor: { items, newItems in
        let uniqueItems = newItems.filter { seenIds.insert($0.id).inserted }
        items.append(contentsOf: uniqueItems)
        return !uniqueItems.isEmpty
      }
    )

    await paginator.refresh()
    XCTAssertEqual(paginator.items, [TestItem(id: 1), TestItem(id: 2)])

    await paginator.loadMore()
    // 第二页返回相同内容，processor 去重后返回 false，扫描后停止
    XCTAssertEqual(paginator.items, [TestItem(id: 1), TestItem(id: 2)], "重复内容不应追加")
    XCTAssertFalse(paginator.hasMore)
  }

  /// 验证当 fetcher 抛出网络超时错误时，错误状态会被正确记录。
  @MainActor
  func testNetworkTimeoutErrorRecorded() async {
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { _ in
        throw TestFailure.requestTimedOut
      },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    await paginator.refresh()

    XCTAssertTrue(paginator.hasError)
    XCTAssertTrue(paginator.lastError is TestFailure, "lastError 应记录超时错误")
    if case .requestTimedOut = paginator.lastError as? TestFailure {
      // 正确
    } else {
      XCTFail("lastError 应为 .requestTimedOut 类型")
    }
  }

  /// 验证通过 `refresh()` 触发重置时，会正确清除所有之前的错误状态。
  @MainActor
  func testRefreshClearsPreviousErrorState() async {
    var failCount = 0
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in
        if failCount < 3 {
          failCount += 1
          throw TestFailure.expected
        }
        return [TestItem(id: page)]
      },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    // 触发连续错误
    await paginator.refresh()
    await paginator.loadMore()
    await paginator.loadMore()
    XCTAssertTrue(paginator.hasError)
    XCTAssertFalse(paginator.hasMore)

    // refresh 会调用 reset()，应清除所有状态
    await paginator.refresh()

    XCTAssertFalse(paginator.hasError, "refresh (reset) 后应清除 hasError")
    XCTAssertNil(paginator.lastError, "refresh (reset) 后应清除 lastError")
    XCTAssertTrue(paginator.hasMore, "refresh (reset) 后应重置 hasMore")
    XCTAssertEqual(paginator.items, [TestItem(id: 1)], "refresh 后应成功加载")
  }

  /// 验证当 fetcher 返回空数组时，`hasMore` 会被正确置为 false，并停止后续加载。
  @MainActor
  func testEmptyResponseStopsLoading() async {
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { _ in [] },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    await paginator.refresh()

    XCTAssertEqual(paginator.items, [])
    XCTAssertFalse(paginator.hasMore, "空响应后 hasMore 应为 false")
    XCTAssertFalse(paginator.isLoading)
    XCTAssertFalse(paginator.hasError)
  }

  /// 验证在进行多次加载时，请求的页码是严格按顺序递增的。
  @MainActor
  func testPageNumbersIncrementSequentially() async {
    let probe = PageProbe()
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in
        await probe.record(page)
        return [TestItem(id: page)]
      },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    await paginator.refresh()
    await paginator.loadMore()
    await paginator.loadMore()

    let pages = await probe.snapshot()
    XCTAssertEqual(pages, [1, 2, 3])
    XCTAssertEqual(paginator.items, [TestItem(id: 1), TestItem(id: 2), TestItem(id: 3)])
  }

  /// 验证在成功加载后，连续错误计数器会被重置，防止与历史错误累加。
  @MainActor
  func testConsecutiveErrorCountResetsAfterSuccess() async {
    var failCount = 0
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in
        if failCount > 0 && failCount < 3 {
          failCount += 1
          throw TestFailure.expected
        }
        failCount += 1
        return [TestItem(id: page)]
      },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    // 第1次 refresh 成功（failCount 从 0→1，不抛错）
    await paginator.refresh()
    XCTAssertEqual(paginator.items, [TestItem(id: 1)])
    XCTAssertFalse(paginator.hasError)

    // 第2次 loadMore 失败（failCount 从 1→2），但只有1次连续错误
    await paginator.loadMore()
    XCTAssertTrue(paginator.hasError)
    XCTAssertTrue(paginator.hasMore, "仅1次连续错误不应停止加载")

    // 第3次 loadMore 失败（failCount 从 2→3），2次连续错误
    await paginator.loadMore()
    XCTAssertTrue(paginator.hasError)
    XCTAssertTrue(paginator.hasMore, "2次连续错误不应停止加载")

    // 第4次 loadMore 成功（failCount 从 3→4，不抛错），错误计数应重置
    await paginator.loadMore()
    XCTAssertFalse(paginator.hasError, "成功后错误状态应清除")
    XCTAssertEqual(paginator.items, [TestItem(id: 1), TestItem(id: 2)])
  }

  /// 验证在空闲状态下调用 `advancePageCursor` 只会移动页码游标，不触发实际的网络请求。
  @MainActor
  func testAdvancePageCursorWhenIdleOnlyShiftsCursor() async {
    let probe = PageProbe()
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in
        await probe.record(page)
        return [TestItem(id: page)]
      },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    await paginator.refresh()
    let pagesAfterRefresh = await probe.snapshot()
    XCTAssertEqual(pagesAfterRefresh, [1])

    // 空闲时推进2页
    paginator.advancePageCursor(by: 2)

    // 没有触发新请求
    let pagesAfterAdvance = await probe.snapshot()
    XCTAssertEqual(pagesAfterAdvance, [1], "空闲时 advancePageCursor 不应触发请求")

    // 后续 loadMore 应从第4页开始（refresh 加了第1页 → page=2，advance +2 → page=4）
    await paginator.loadMore()
    let pagesAfterLoadMore = await probe.snapshot()
    XCTAssertEqual(pagesAfterLoadMore, [1, 4], "loadMore 应从推进后的页码开始")
  }

  /// 验证在空闲状态下调用 `rewindPageCursor` 只会回退页码游标并重置 `hasMore`，不触发请求。
  @MainActor
  func testRewindPageCursorWhenIdleOnlyShiftsCursor() async {
    var page = 0
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { _ in
        page += 1
        return [TestItem(id: page)]
      },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    await paginator.refresh()
    await paginator.loadMore()
    XCTAssertEqual(paginator.items.count, 2)

    // 空闲时回退1页
    paginator.rewindPageCursor(by: 1)

    // 没有崩溃或异常状态
    XCTAssertFalse(paginator.isLoading)
    XCTAssertTrue(paginator.hasMore, "rewindPageCursor 应重置 hasMore")
  }

  /// 验证在分页器发生重置操作时，传入的 `onReset` 闭包会被正确回调。
  @MainActor
  func testOnResetCallbackInvokedOnRefresh() async {
    var resetCount = 0
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in [TestItem(id: page)] },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      },
      onReset: { resetCount += 1 }
    )

    await paginator.refresh()
    XCTAssertEqual(resetCount, 1, "首次 refresh 应触发 onReset")

    await paginator.refresh()
    XCTAssertEqual(resetCount, 2, "第二次 refresh 应再次触发 onReset")
  }

  /// 验证调用 `loadMore(itemId)` 时，如果目标项未达到预设的加载阈值，会自动跳过加载。
  @MainActor
  func testLoadMoreSkipsWhenItemBelowThreshold() async {
    let probe = PageProbe()
    let paginator = Paginator<TestItem>(
      threshold: 5,
      fetcher: { page in
        await probe.record(page)
        return (1...10).map { TestItem(id: page * 100 + $0) }
      },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    await paginator.refresh()
    let pagesAfterRefresh = await probe.snapshot()
    XCTAssertEqual(pagesAfterRefresh, [1])

    // 传入列表第一个 item 的 id，远未到达阈值位置
    let firstItemId = paginator.items.first!.id
    await paginator.loadMore(firstItemId)

    let pagesAfterLoadMore = await probe.snapshot()
    XCTAssertEqual(pagesAfterLoadMore, [1], "未到阈值位置时 loadMore 不应触发请求")
  }

  /// 验证调用 `advancePageCursor` 并传入 0 或负数值时，该无效操作会被忽略。
  @MainActor
  func testAdvancePageCursorWithZeroOrNegativeIsNoOp() async {
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in [TestItem(id: page)] },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    await paginator.refresh()
    let itemCountBefore = paginator.items.count

    paginator.advancePageCursor(by: 0)
    paginator.advancePageCursor(by: -1)

    await paginator.loadMore()
    XCTAssertEqual(paginator.items.count, itemCountBefore + 1, "无效 advance 不应影响页码")
  }

  /// 验证调用 `rewindPageCursor` 并传入 0 或负数值时，该无效操作会被忽略。
  @MainActor
  func testRewindPageCursorWithZeroOrNegativeIsNoOp() async {
    let paginator = Paginator<TestItem>(
      threshold: 1,
      fetcher: { page in [TestItem(id: page)] },
      processor: { items, newItems in
        items.append(contentsOf: newItems)
        return !newItems.isEmpty
      }
    )

    await paginator.refresh()

    paginator.rewindPageCursor(by: 0)
    paginator.rewindPageCursor(by: -1)

    XCTAssertFalse(paginator.isLoading)
  }
}
