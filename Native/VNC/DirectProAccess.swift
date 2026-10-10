#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Observation
import StoreKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct DirectProEntitlement {
    let verified: Bool
    let matchingProduct: Bool
    let nonConsumable: Bool
    let revoked: Bool
    var unlocked: Bool { verified && matchingProduct && nonConsumable && !revoked }
}

struct DirectProTrial {
    static let duration: TimeInterval = 14 * 24 * 60 * 60
    let entitlement: DirectProEntitlement
    let originalPurchaseDate: Date
    var endDate: Date { originalPurchaseDate.addingTimeInterval(Self.duration) }
    func active(at date: Date) -> Bool {
        entitlement.unlocked && originalPurchaseDate <= date && date < endDate
    }
}

@MainActor @Observable final class DirectProAccess {
    static let shared = DirectProAccess()
    static let productID = "media.jenny.maccompanion.pro.lifetime"
    static let trialProductID = "media.jenny.maccompanion.pro.trial14"
    private(set) var hasLifetimePro = false
    private(set) var trial: DirectProTrial?
    private(set) var trialHistoryUnavailable = false
    private(set) var ready = false
    private(set) var product: Product?
    private(set) var trialProduct: Product?
    private(set) var busy = false
    var message: String?
    var recovery: DirectRecoveryNotice?
    private var updates: Task<Void, Never>?
    private var expiry: Task<Void, Never>?
    private var refreshRevision = 0
    private var evaluatedAt: Date
    private let now: () -> Date
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults; self.now = now; evaluatedAt = now()
    }
    isolated deinit { updates?.cancel(); expiry?.cancel() }

    // Clock rollback within this process cannot extend the trial. Offline expiry
    // otherwise uses device time, without introducing an account or time server.
    private var effectiveNow: Date { max(now(), evaluatedAt) }
    var trialIsActive: Bool { trial?.active(at: effectiveNow) == true }
    var hasPro: Bool { hasLifetimePro || trialIsActive }
    var trialDaysRemaining: Int {
        guard trialIsActive, let trial else { return 0 }
        return max(1, Int(ceil(trial.endDate.timeIntervalSince(effectiveNow) / 86400)))
    }
    var canStartTrial: Bool {
        ready && !hasLifetimePro && trial == nil && !trialHistoryUnavailable && trialProduct != nil && product != nil
    }
    var accessTitle: String {
        if hasLifetimePro { return "Lifetime Pro · Unlocked" }
        if trialIsActive { return "Pro Trial · \(trialDaysRemaining) days left" }
        return "Mac Companion Pro"
    }
    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self, !Task.isCancelled else { return }
                if case .verified(let transaction) = result,
                   [Self.productID, Self.trialProductID].contains(transaction.productID) {
                    await self.refresh()
                    await transaction.finish()
                }
            }
        }
        Task { await refresh() }
    }
    func refresh() async {
        refreshRevision += 1; let revision = refreshRevision
        var lifetime = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                lifetime = lifetime || Self.admits(transaction, productID: Self.productID)
            }
        }
        // History includes a revoked trial. A refund/restore must not make the
        // Start Trial button reappear or reset the original purchase date.
        let history = await StoreKit.Transaction.latest(for: Self.trialProductID)
        guard revision == refreshRevision else { return }
        hasLifetimePro = lifetime; trial = nil; trialHistoryUnavailable = false
        switch history {
        case .verified(let transaction):
            if transaction.productID == Self.trialProductID && transaction.productType == .nonConsumable {
                trial = DirectProTrial(entitlement: Self.entitlement(transaction, productID: Self.trialProductID),
                                       originalPurchaseDate: transaction.originalPurchaseDate)
            } else { trialHistoryUnavailable = true }
        case .unverified: trialHistoryUnavailable = true
        case nil: break
        }
        ready = true; reevaluateTrial()
    }
    private static func entitlement(_ transaction: StoreKit.Transaction, productID: String) -> DirectProEntitlement {
        DirectProEntitlement(verified: true, matchingProduct: transaction.productID == productID,
                             nonConsumable: transaction.productType == .nonConsumable, revoked: transaction.revocationDate != nil)
    }
    private static func admits(_ transaction: StoreKit.Transaction, productID: String) -> Bool {
        entitlement(transaction, productID: productID).unlocked
    }
    func reevaluateTrial() {
        evaluatedAt = effectiveNow; expiry?.cancel(); expiry = nil
        guard trialIsActive, !hasLifetimePro, let trial else { return }
        // A bounded check also refreshes the displayed days after a time change.
        let seconds = min(60, max(0.01, trial.endDate.timeIntervalSince(effectiveNow)))
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.reevaluateTrial()
        }
    }
    func loadProduct() async {
        start()
        guard !busy else { return }
        busy = true; message = nil; recovery = nil; defer { busy = false }
        do {
            let products = try await Product.products(for: [Self.productID, Self.trialProductID])
            product = products.first { $0.id == Self.productID && $0.type == .nonConsumable }
            trialProduct = products.first { $0.id == Self.trialProductID && $0.type == .nonConsumable && $0.price == 0 }
            if product == nil || trialProduct == nil {
                recovery = .make(.storeUnavailable)
            }
            await refresh()
        } catch { recovery = .make(.storeUnavailable) }
    }
    func purchase() async {
        guard let product, !hasLifetimePro else { return }
        await purchase(product, trialPurchase: false)
    }
    func startTrial() async {
        guard !busy else { return }
        await refresh()
        guard canStartTrial, let trialProduct else { return }
        await purchase(trialProduct, trialPurchase: true)
    }
    private func purchase(_ selected: Product, trialPurchase: Bool) async {
        guard !busy, !trialPurchase || selected.price == 0 else { return }
        busy = true; message = nil; recovery = nil; defer { busy = false }
        do {
            switch try await selected.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result, Self.admits(transaction, productID: selected.id) else {
                    recovery = .make(.purchaseUnconfirmed); return
                }
                await transaction.finish(); await refresh()
                if trialPurchase {
                    message = trialIsActive ? "Your 14-day Pro trial has started. There is no automatic charge."
                                           : "This trial cannot unlock Pro. Restore Purchases and check your device date."
                }
            case .pending: recovery = .make(.purchasePending)
            case .userCancelled: break
            @unknown default: recovery = .make(.purchaseUnconfirmed)
            }
        } catch { if !DirectCancellation.isCancellation(error) { recovery = .make(.purchaseUnconfirmed) } }
    }
    func restore() async {
        guard !busy else { return }; busy = true; message = nil; recovery = nil; defer { busy = false }
        do {
            try await AppStore.sync(); await refresh()
            if hasLifetimePro { message = "Lifetime Pro restored." }
            else if trialIsActive { message = "Your Pro trial is restored with its original end date." }
            else if trial != nil { recovery = .make(.trialEnded) }
            else { recovery = .make(.noPurchase) }
        } catch { if !DirectCancellation.isCancellation(error) { recovery = .make(.restoreFailed) } }
    }
    func canAddMac(count: Int) -> Bool { hasPro || count < 1 }
    func canAddKey(count: Int) -> Bool { hasPro || count < 1 }
    func canUseMac(_ id: UUID, among ids: [UUID]) -> Bool { hasPro || freeID("mac", ids: ids) == id }
    func canUseKey(_ id: UUID, among ids: [UUID]) -> Bool { hasPro || freeID("key", ids: ids) == id }
    func chooseFreeMac(_ id: UUID) { defaults.set(id.uuidString, forKey: "direct-free-mac-v1") }
    func chooseFreeKey(_ id: UUID) { defaults.set(id.uuidString, forKey: "direct-free-key-v1") }
    private func freeID(_ kind: String, ids: [UUID]) -> UUID? {
        let key = "direct-free-\(kind)-v1"
        if let value = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)), ids.contains(value) { return value }
        guard let first = ids.first else { return nil }
        defaults.set(first.uuidString, forKey: key); return first
    }
}

struct DirectProView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var access = DirectProAccess.shared
    private var recoveryAction: DirectRecoveryAction? {
        guard let reason = access.recovery?.reason else { return nil }
        switch reason {
        case .storeUnavailable: return .init(title: "Reload Store", perform: { Task { await access.loadProduct() } })
        case .purchaseUnconfirmed, .restoreFailed, .noPurchase: return .init(title: "Restore Purchases", perform: { Task { await access.restore() } })
        default: return nil
        }
    }
    private var historyAction: DirectRecoveryAction? {
        guard access.recovery?.reason == .purchaseUnconfirmed || access.recovery?.reason == .noPurchase else { return nil }
        return .init(title: "Apple Purchase History", perform: { DirectClientPlatformV1.open(URL(string: "https://reportaproblem.apple.com/")!) })
    }
    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                HStack {
                    Text("Mac Companion Pro").font(.headline)
                    Spacer()
                }.padding(20)
                Divider()
                Form { sections }.formStyle(.grouped)
                    .accessibilityIdentifier("mac-pro-content")
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }.padding(16)
            }.frame(width: 560, height: 640)
            #else
            NavigationStack {
                List { sections }
                    .navigationTitle("Mac Companion Pro").directInlineNavigationTitle()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
            #endif
        }
        .task { await access.loadProduct() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await access.refresh() } } }
    }
    @ViewBuilder private var sections: some View {
        Section {
            #if os(iOS)
            Label("Mac Companion Pro", systemImage: "sparkles").font(.title2.bold())
            #endif
            Text("Try Pro free for 14 days, or unlock it for life. No subscription.").foregroundStyle(.secondary)
            if access.hasLifetimePro {
                Label("Lifetime Pro is unlocked", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else if access.trialIsActive, let trial = access.trial {
                Label("\(access.trialDaysRemaining) days left in your trial", systemImage: "clock").foregroundStyle(.tint)
                Text("Pro access ends \(trial.endDate.formatted(date: .abbreviated, time: .shortened)).").font(.footnote)
            } else if access.trial != nil {
                Text("Your Pro trial has ended. Basic features remain free.").foregroundStyle(.secondary)
            }
        }
        if let notice = access.recovery {
            Section { DirectRecoveryCard(notice: notice, primary: recoveryAction, secondary: historyAction) }
        }
        Section("Pro features") {
            Label("Multiple saved Macs and named SSH keys", systemImage: "desktopcomputer")
            Label("Install SSH keys from each Mac’s settings", systemImage: "key")
            Label("Custom terminal keys, shortcuts and snippets", systemImage: "keyboard")
        }
        if !access.hasLifetimePro && access.trial == nil {
            Section {
                Button("Start 14-day Free Trial") { Task { await access.startTrial() } }
                    .disabled(!access.canStartTrial || access.busy).accessibilityIdentifier("pro-start-trial")
            } header: { Text("14-day Trial") } footer: {
                Text("All Pro features for 14 days from today. Then multiple Macs/keys, key setup and custom controls require Lifetime Pro. Basic features stay free and your data is preserved. No automatic charge. \(access.product.map { "Lifetime Pro costs " + $0.displayPrice + " once, as a separate purchase." } ?? "The lifetime upgrade price appears when the store is available.")")
            }
        }
        Section {
            if !access.hasLifetimePro {
                Button(access.product.map { "Unlock Lifetime Pro · " + $0.displayPrice } ?? "Purchase Unavailable") {
                    Task { await access.purchase() }
                }.disabled(access.product == nil || access.busy).accessibilityIdentifier("pro-purchase")
            }
            Button("Restore Purchases") { Task { await access.restore() } }.disabled(access.busy).accessibilityIdentifier("pro-restore")
            if access.product == nil || access.trialProduct == nil { Button("Reload Store") { Task { await access.loadProduct() } }.disabled(access.busy) }
            if access.trialHistoryUnavailable { Text("Trial history couldn’t be verified. Restore Purchases before starting a trial; free features remain available.").font(.footnote).foregroundStyle(.secondary) }
            if access.busy { ProgressView("Contacting the App Store…") }
            if let message = access.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        } footer: { Text("Lifetime Pro is a one-time purchase. No renewal or subscription.") }
        Section("Free, without a time limit") {
            #if os(macOS)
            Text("One saved Mac and one SSH key. Desktop, basic Terminal, all standard keyboard controls, local/VPN addresses, display selection and zoom.")
            #else
            Text("One saved Mac and one SSH key. Desktop, Trackpad & Keyboard, basic Terminal, all standard keyboard controls, local/VPN addresses, display selection and zoom.")
            #endif
            Text("Security, accessibility and SSH key import/export stay free. Existing extra Macs and keys are preserved.").foregroundStyle(.secondary)
        }
    }
}
#endif
