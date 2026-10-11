import StoreKit
import XCTest
#if os(iOS)
@testable import Mac_Companion
#else
@testable import MacCompanion
#endif

@MainActor final class StoreCancellationTests: XCTestCase {
    func testCancellingSystemPurchaseOrRestoreDoesNotBecomeAnErrorButOtherFailuresDo() {
        XCTAssertTrue(DirectProAccess.isStoreCancellation(StoreKitError.userCancelled))
        XCTAssertTrue(DirectProAccess.isStoreCancellation(NSError(domain: SKErrorDomain, code: SKError.paymentCancelled.rawValue)))
        XCTAssertTrue(DirectProAccess.isStoreCancellation(CancellationError()))
        XCTAssertFalse(DirectProAccess.isStoreCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)))
        XCTAssertFalse(DirectProAccess.isStoreCancellation(StoreKitError.notAvailableInStorefront))
    }
}
