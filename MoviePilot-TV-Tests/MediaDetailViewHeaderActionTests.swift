import XCTest

@testable import MoviePilot_TV

final class MediaDetailViewHeaderActionTests: XCTestCase {
  func testSubscribedHeaderActionShowsUnsubscribeConfirmation() {
    var didShowUnsubscribeConfirm = false
    var didStartSubscribe = false

    MediaDetailView.performHeaderSubscribeAction(
      isSubscribed: true,
      showUnsubscribeConfirm: {
        didShowUnsubscribeConfirm = true
      },
      startSubscribe: {
        didStartSubscribe = true
      }
    )

    XCTAssertTrue(didShowUnsubscribeConfirm)
    XCTAssertFalse(didStartSubscribe)
  }

  func testUnsubscribedHeaderActionStartsSubscribeFlow() {
    var didShowUnsubscribeConfirm = false
    var didStartSubscribe = false

    MediaDetailView.performHeaderSubscribeAction(
      isSubscribed: false,
      showUnsubscribeConfirm: {
        didShowUnsubscribeConfirm = true
      },
      startSubscribe: {
        didStartSubscribe = true
      }
    )

    XCTAssertFalse(didShowUnsubscribeConfirm)
    XCTAssertTrue(didStartSubscribe)
  }
}
