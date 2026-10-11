import StoreKit
import StoreKitTest
import XCTest
#if os(iOS)
@testable import Mac_Companion
#else
@testable import MacCompanion
#endif

@MainActor final class StoreCancellationTests: XCTestCase {
    func testTerminalDraftSaveRequiresProWhileFreeSettingsRemainSaveable() {
        let draft = [VNCQuickAction(title: "Synthetic interrupt", kind: .shortcut, key: 0x63, modifiers: [0xffe3])]
        XCTAssertTrue(DirectQuickActionEditing.canSave(draft, mode: .terminal, hasPro: true))
        XCTAssertFalse(DirectQuickActionEditing.canSave(draft, mode: .terminal, hasPro: false))
        XCTAssertFalse(DirectQuickActionEditing.canSave([], mode: .terminal, hasPro: false))
        XCTAssertTrue(DirectQuickActionEditing.canSave(DirectControlMode.desktop.defaults, mode: .desktop, hasPro: false))
        XCTAssertTrue(DirectQuickActionEditing.canSave(DirectControlMode.trackpad.defaults, mode: .trackpad, hasPro: false))
        XCTAssertFalse(DirectQuickActionEditing.canSave([.init(title: "Invalid", kind: .shortcut)], mode: .terminal, hasPro: true))
    }

    #if os(iOS)
    // The Simulator QA lane enables StoreKit transactions. Mac hosted QA has no
    // StoreKit purchase entitlement; the shared save policy is tested above.
    func testTerminalDraftSaveStopsAfterStoreKitRefundOrTrialExpiry() async throws {
        let config = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: config)
        store.disableDialogs = true; store.clearTransactions()
        defer { store.clearTransactions() }
        let draft = [VNCQuickAction(title: "Synthetic interrupt", kind: .shortcut, key: 0x63, modifiers: [0xffe3])]
        let access = DirectProAccess()
        await access.loadProduct(); await access.purchase()
        XCTAssertTrue(access.hasPro)
        XCTAssertTrue(DirectQuickActionEditing.canSave(draft, mode: .terminal, hasPro: access.hasPro))
        let purchase = try XCTUnwrap(store.allTransactions().first { $0.productIdentifier == DirectProAccess.productID })
        try store.refundTransaction(identifier: purchase.identifier)
        for _ in 0..<200 {
            if !access.hasPro { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await access.refresh()
        XCTAssertFalse(access.hasPro)
        XCTAssertFalse(DirectQuickActionEditing.canSave(draft, mode: .terminal, hasPro: access.hasPro))

        var clock = Date()
        let trialAccess = DirectProAccess(now: { clock })
        await trialAccess.loadProduct(); await trialAccess.startTrial()
        clock = Date(); trialAccess.reevaluateTrial()
        XCTAssertTrue(trialAccess.hasPro)
        XCTAssertTrue(DirectQuickActionEditing.canSave(draft, mode: .terminal, hasPro: trialAccess.hasPro))
        clock = try XCTUnwrap(trialAccess.trial).endDate
        trialAccess.reevaluateTrial()
        XCTAssertFalse(trialAccess.hasPro)
        XCTAssertFalse(DirectQuickActionEditing.canSave(draft, mode: .terminal, hasPro: trialAccess.hasPro))
    }
    #endif

    func testCancellingSystemPurchaseOrRestoreDoesNotBecomeAnErrorButOtherFailuresDo() {
        XCTAssertTrue(DirectProAccess.isStoreCancellation(StoreKitError.userCancelled))
        XCTAssertTrue(DirectProAccess.isStoreCancellation(NSError(domain: SKErrorDomain, code: SKError.paymentCancelled.rawValue)))
        XCTAssertTrue(DirectProAccess.isStoreCancellation(CancellationError()))
        XCTAssertFalse(DirectProAccess.isStoreCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)))
        XCTAssertFalse(DirectProAccess.isStoreCancellation(StoreKitError.notAvailableInStorefront))
    }
}
