import XCTest

@testable import MoviePilot_TV

private enum CoalescingCacheTestError: Error, Equatable {
  case stale
  case latest
  case rejected
}

@MainActor
private final class LoadGate {
  private var isOpen = false
  private var arrivals = 0
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    arrivals += 1
    let pendingArrivalWaiters = arrivalWaiters
    arrivalWaiters.removeAll()
    pendingArrivalWaiters.forEach { $0.resume() }
    guard !isOpen else { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func waitForArrival() async {
    guard arrivals == 0 else { return }
    await withCheckedContinuation { continuation in
      arrivalWaiters.append(continuation)
    }
  }

  func open() {
    isOpen = true
    let pendingWaiters = waiters
    waiters.removeAll()
    pendingWaiters.forEach { $0.resume() }
  }
}

@MainActor
private final class LoadProbe {
  var loadCount = 0
  var joinedWaiterStarted = false
  var rejectsCaller = false
}

private final class TestClock {
  var date = Date(timeIntervalSince1970: 1_000)
}

@MainActor
final class CoalescingCacheTests: XCTestCase {
  private func countingLoad(
    _ value: String,
    probe: LoadProbe
  ) -> @MainActor () async throws -> String {
    {
      probe.loadCount += 1
      return value
    }
  }

  func testConcurrentReadsShareOneInFlightLoad() async throws {
    let cache = CoalescingCache<String, String>(ttl: 60, capacity: 10)
    let gate = LoadGate()
    let probe = LoadProbe()

    let first = Task {
      try await cache.value(for: "key", validate: {}) {
        probe.loadCount += 1
        await gate.wait()
        return "shared"
      }
    }
    await gate.waitForArrival()

    let second = Task {
      probe.joinedWaiterStarted = true
      return try await cache.value(
        for: "key",
        validate: {},
        load: countingLoad("unexpected", probe: probe)
      )
    }
    await Task.yield()
    XCTAssertTrue(probe.joinedWaiterStarted)
    gate.open()

    let firstValue = try await first.value
    let secondValue = try await second.value
    XCTAssertEqual(firstValue, "shared")
    XCTAssertEqual(secondValue, "shared")
    XCTAssertEqual(probe.loadCount, 1)
  }

  func testFreshEntryIsReusedAndAccessRenewsExpiry() async throws {
    let clock = TestClock()
    let cache = CoalescingCache<String, Int>(ttl: 10, capacity: 10, now: { clock.date })
    let probe = LoadProbe()
    let load: @MainActor () async throws -> Int = {
      probe.loadCount += 1
      return probe.loadCount
    }

    let initial = try await cache.value(for: "key", validate: {}, load: load)
    clock.date += 8
    let renewed = try await cache.value(for: "key", validate: {}, load: load)
    clock.date += 8
    let stillCached = try await cache.value(for: "key", validate: {}, load: load)
    clock.date += 11
    let reloaded = try await cache.value(for: "key", validate: {}, load: load)

    XCTAssertEqual([initial, renewed, stillCached, reloaded], [1, 1, 1, 2])
  }

  func testNonRenewingEntryExpiresFromStoreTime() async throws {
    let clock = TestClock()
    let cache = CoalescingCache<String, Int>(
      ttl: 10,
      capacity: 10,
      renewsTTLOnAccess: false,
      now: { clock.date }
    )
    let probe = LoadProbe()
    let load: @MainActor () async throws -> Int = {
      probe.loadCount += 1
      return probe.loadCount
    }

    let initial = try await cache.value(for: "key", validate: {}, load: load)
    clock.date += 8
    let cached = try await cache.value(for: "key", validate: {}, load: load)
    clock.date += 3
    let reloaded = try await cache.value(for: "key", validate: {}, load: load)

    XCTAssertEqual([initial, cached, reloaded], [1, 1, 2])
  }

  func testForcedRefreshSupersedesInFlightLoadAndOlderWaiterFollowsLatest() async throws {
    let cache = CoalescingCache<String, String>(ttl: 60, capacity: 10)
    let staleGate = LoadGate()
    let probe = LoadProbe()

    let staleRead = Task {
      try await cache.value(for: "key", validate: {}) {
        probe.loadCount += 1
        await staleGate.wait()
        return "stale"
      }
    }
    await staleGate.waitForArrival()

    let refreshed = try await cache.value(
      for: "key",
      forceRefresh: true,
      validate: {},
      load: countingLoad("latest", probe: probe)
    )
    staleGate.open()
    let staleCallerValue = try await staleRead.value
    let cachedValue = try await cache.value(
      for: "key",
      validate: {},
      load: countingLoad("unexpected", probe: probe)
    )

    XCTAssertEqual(refreshed, "latest")
    XCTAssertEqual(staleCallerValue, "latest")
    XCTAssertEqual(cachedValue, "latest")
    XCTAssertEqual(probe.loadCount, 2)
  }

  func testSupersededFailureDoesNotReachWaitersOrReplaceLatestValue() async throws {
    let cache = CoalescingCache<String, String>(ttl: 60, capacity: 10)
    let staleGate = LoadGate()
    let probe = LoadProbe()

    let staleRead = Task {
      try await cache.value(for: "key", validate: {}) {
        probe.loadCount += 1
        await staleGate.wait()
        throw CoalescingCacheTestError.stale
      }
    }
    await staleGate.waitForArrival()

    let refreshed = try await cache.value(
      for: "key",
      forceRefresh: true,
      validate: {},
      load: countingLoad("latest", probe: probe)
    )
    staleGate.open()
    let staleCallerValue = try await staleRead.value

    XCTAssertEqual(refreshed, "latest")
    XCTAssertEqual(staleCallerValue, "latest")
    XCTAssertEqual(probe.loadCount, 2)
  }

  func testLatestFailureReachesAllWaitersWithoutRetryOrCaching() async throws {
    let cache = CoalescingCache<String, String>(ttl: 60, capacity: 10)
    let gate = LoadGate()
    let probe = LoadProbe()

    let first = Task { () -> CoalescingCacheTestError? in
      do {
        _ = try await cache.value(for: "key", validate: {}) {
          probe.loadCount += 1
          await gate.wait()
          throw CoalescingCacheTestError.latest
        }
        return nil
      } catch {
        return error as? CoalescingCacheTestError
      }
    }
    await gate.waitForArrival()

    let second = Task { () -> CoalescingCacheTestError? in
      probe.joinedWaiterStarted = true
      do {
        _ = try await cache.value(
          for: "key",
          validate: {},
          load: countingLoad("unexpected", probe: probe)
        )
        return nil
      } catch {
        return error as? CoalescingCacheTestError
      }
    }
    await Task.yield()
    XCTAssertTrue(probe.joinedWaiterStarted)
    gate.open()

    let firstError = await first.value
    let secondError = await second.value
    XCTAssertEqual(firstError, .latest)
    XCTAssertEqual(secondError, .latest)
    XCTAssertEqual(probe.loadCount, 1)

    let nextValue = try await cache.value(
      for: "key",
      validate: {},
      load: countingLoad("fresh", probe: probe)
    )
    XCTAssertEqual(nextValue, "fresh")
    XCTAssertEqual(probe.loadCount, 2)
  }

  func testInvalidateAllDiscardsInFlightSuccessAndWaiterReloads() async throws {
    let cache = CoalescingCache<String, String>(ttl: 60, capacity: 10)
    let gate = LoadGate()
    let probe = LoadProbe()

    let read = Task {
      try await cache.value(for: "key", validate: {}) {
        probe.loadCount += 1
        guard probe.loadCount == 1 else { return "after-invalidation" }
        await gate.wait()
        return "before-invalidation"
      }
    }
    await gate.waitForArrival()

    cache.invalidateAll()
    gate.open()
    let value = try await read.value
    let cachedValue = try await cache.value(
      for: "key",
      validate: {},
      load: countingLoad("unexpected", probe: probe)
    )

    XCTAssertEqual(value, "after-invalidation")
    XCTAssertEqual(cachedValue, "after-invalidation")
    XCTAssertEqual(probe.loadCount, 2)
  }

  func testFailureOfInvalidatedLoadStillReachesWaiterWithoutReload() async throws {
    let cache = CoalescingCache<String, String>(ttl: 60, capacity: 10)
    let probe = LoadProbe()

    // 例如权限探测在加载内部刷新了会话：缓存随之失效，但这次加载的业务错误仍要交给调用方。
    do {
      _ = try await cache.value(for: "key", validate: {}) {
        probe.loadCount += 1
        guard probe.loadCount == 1 else { return "unexpected-reload" }
        cache.invalidateAll()
        throw CoalescingCacheTestError.latest
      }
      XCTFail("The failure of the invalidated load must reach its waiter.")
    } catch {
      XCTAssertEqual(error as? CoalescingCacheTestError, .latest)
    }
    XCTAssertEqual(probe.loadCount, 1)
  }

  func testCancelledWaiterReceivesCancellationInsteadOfSharedFailure() async throws {
    let cache = CoalescingCache<String, String>(ttl: 60, capacity: 10)
    let gate = LoadGate()

    let read = Task { () -> Error? in
      do {
        _ = try await cache.value(for: "key", validate: {}) {
          await gate.wait()
          throw CoalescingCacheTestError.latest
        }
        return nil
      } catch {
        return error
      }
    }
    await gate.waitForArrival()
    read.cancel()
    gate.open()

    let error = await read.value
    XCTAssertTrue(error is CancellationError)
  }

  func testCancelledLoadAfterInvalidationReloadsForWaiter() async throws {
    let cache = CoalescingCache<String, String>(ttl: 60, capacity: 10)
    let probe = LoadProbe()

    let value = try await cache.value(for: "key", validate: {}) {
      probe.loadCount += 1
      guard probe.loadCount == 1 else { return "reloaded" }
      cache.invalidateAll()
      throw CancellationError()
    }

    XCTAssertEqual(value, "reloaded")
    XCTAssertEqual(probe.loadCount, 2)
  }

  func testInvalidateAllDropsCachedEntries() async throws {
    let cache = CoalescingCache<String, String>(ttl: 60, capacity: 10)
    let probe = LoadProbe()

    let initial = try await cache.value(
      for: "key",
      validate: {},
      load: countingLoad("old", probe: probe)
    )
    cache.invalidateAll()
    let reloaded = try await cache.value(
      for: "key",
      validate: {},
      load: countingLoad("new", probe: probe)
    )

    XCTAssertEqual(initial, "old")
    XCTAssertEqual(reloaded, "new")
    XCTAssertEqual(probe.loadCount, 2)
  }

  func testCachedReadDuringForcedRefreshKeepsCachedValueAndRefreshCompletes() async throws {
    let cache = CoalescingCache<String, String>(ttl: 60, capacity: 10)
    let gate = LoadGate()
    let probe = LoadProbe()

    _ = try await cache.value(for: "key", validate: {}) { "cached" }
    let refresh = Task {
      try await cache.value(for: "key", forceRefresh: true, validate: {}) {
        await gate.wait()
        return "refreshed"
      }
    }
    await gate.waitForArrival()

    let duringRefresh = try await cache.value(
      for: "key",
      validate: {},
      load: countingLoad("unexpected", probe: probe)
    )
    gate.open()
    let refreshed = try await refresh.value
    let afterRefresh = try await cache.value(
      for: "key",
      validate: {},
      load: countingLoad("unexpected", probe: probe)
    )

    XCTAssertEqual(duringRefresh, "cached")
    XCTAssertEqual(refreshed, "refreshed")
    XCTAssertEqual(afterRefresh, "refreshed")
    XCTAssertEqual(probe.loadCount, 0)
  }

  func testValidationFailureStopsCallerWithoutStartingOrReturningLoad() async throws {
    let cache = CoalescingCache<String, String>(ttl: 60, capacity: 10)
    let gate = LoadGate()
    let probe = LoadProbe()

    do {
      _ = try await cache.value(
        for: "rejected-before-load",
        validate: { throw CoalescingCacheTestError.rejected },
        load: countingLoad("unexpected", probe: probe)
      )
      XCTFail("Validation failure must stop the caller before loading.")
    } catch {
      XCTAssertEqual(error as? CoalescingCacheTestError, .rejected)
    }
    XCTAssertEqual(probe.loadCount, 0)

    let read = Task {
      try await cache.value(
        for: "rejected-after-load",
        validate: {
          if probe.rejectsCaller { throw CoalescingCacheTestError.rejected }
        }
      ) {
        await gate.wait()
        return "loaded"
      }
    }
    await gate.waitForArrival()
    probe.rejectsCaller = true
    gate.open()

    do {
      _ = try await read.value
      XCTFail("Validation failure after loading must not return the loaded value.")
    } catch {
      XCTAssertEqual(error as? CoalescingCacheTestError, .rejected)
    }
  }

  func testCapacityEvictsEntryClosestToExpiry() async throws {
    let clock = TestClock()
    let cache = CoalescingCache<String, String>(ttl: 10, capacity: 2, now: { clock.date })
    let probe = LoadProbe()

    _ = try await cache.value(for: "a", validate: {}, load: countingLoad("a1", probe: probe))
    clock.date += 1
    _ = try await cache.value(for: "b", validate: {}, load: countingLoad("b1", probe: probe))
    clock.date += 1
    // 访问续期后 a 比 b 更晚过期，容量满时应淘汰 b。
    _ = try await cache.value(for: "a", validate: {}, load: countingLoad("unexpected", probe: probe))
    _ = try await cache.value(for: "c", validate: {}, load: countingLoad("c1", probe: probe))

    let a = try await cache.value(for: "a", validate: {}, load: countingLoad("a2", probe: probe))
    let b = try await cache.value(for: "b", validate: {}, load: countingLoad("b2", probe: probe))

    XCTAssertEqual(a, "a1")
    XCTAssertEqual(b, "b2")
    XCTAssertEqual(probe.loadCount, 4)
  }
}
