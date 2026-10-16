#if (os(iOS) || os(macOS) || os(visionOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Observation
import StoreKit
import SwiftUI
#if os(iOS) || os(visionOS)
import UIKit
#endif

#if os(visionOS)
typealias DirectPurchaseScene = UIWindowScene
#else
struct DirectPurchaseScene {}
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

struct DirectProSnapshot {
    var lifetime = false
    var trial: DirectProTrial?
    var historyUnavailable = false
}

@MainActor @Observable final class DirectProAccess {
    #if os(visionOS)
    static let shared = DirectProAccess(defaults: VisionDevelopmentQA.defaults)
    #else
    static let shared = DirectProAccess()
    #endif
    static let productID = "media.jenny.maccompanion.pro.lifetime"
    static let trialProductID = "media.jenny.maccompanion.pro.trial14"
    private(set) var hasLifetimePro = false
    private(set) var trial: DirectProTrial?
    private(set) var trialHistoryUnavailable = false
    private(set) var ready = false
    private(set) var product: Product?
    private(set) var trialProduct: Product?
    enum Operation {
        case loadingProducts, purchasing, startingTrial, restoring
        var title: String {
            switch self {
            case .loadingProducts: "Checking App Store availability…"
            case .purchasing: "Completing purchase…"
            case .startingTrial: "Starting your trial…"
            case .restoring: "Restoring purchases…"
            }
        }
    }
    private(set) var operation: Operation?
    var busy: Bool { operation != nil }
    var message: String?
    var recovery: DirectRecoveryNotice?
    private var updates: Task<Void, Never>?
    private var expiry: Task<Void, Never>?
    private var refreshRevision = 0
    private var evaluatedAt: Date
    private let now: () -> Date
    private let defaults: UserDefaults
    private let readEntitlements: @MainActor () async -> DirectProSnapshot
    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         readEntitlements: @escaping @MainActor () async -> DirectProSnapshot = { await DirectProAccess.storeSnapshot() }) {
        self.defaults = defaults; self.now = now; evaluatedAt = now(); self.readEntitlements = readEntitlements
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
        let snapshot = await readEntitlements()
        guard revision == refreshRevision else { return }
        hasLifetimePro = snapshot.lifetime; trial = snapshot.trial
        trialHistoryUnavailable = snapshot.historyUnavailable
        ready = true; reevaluateTrial()
    }
    private static func storeSnapshot() async -> DirectProSnapshot {
        var snapshot = DirectProSnapshot()
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                snapshot.lifetime = snapshot.lifetime || Self.admits(transaction, productID: Self.productID)
            }
        }
        // History includes revoked trials so refund/restore cannot restart them.
        let history = await StoreKit.Transaction.latest(for: Self.trialProductID)
        switch history {
        case .verified(let transaction):
            if transaction.productID == Self.trialProductID && transaction.productType == .nonConsumable {
                snapshot.trial = DirectProTrial(entitlement: Self.entitlement(transaction, productID: Self.trialProductID),
                                               originalPurchaseDate: transaction.originalPurchaseDate)
            } else { snapshot.historyUnavailable = true }
        case .unverified: snapshot.historyUnavailable = true
        case nil: break
        }
        return snapshot
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
        operation = .loadingProducts; message = nil; recovery = nil; defer { operation = nil }
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
    func purchase(scene: DirectPurchaseScene? = nil) async {
        guard let product, !hasLifetimePro else { return }
        await purchase(product, trialPurchase: false, scene: scene)
    }
    func startTrial(scene: DirectPurchaseScene? = nil) async {
        guard !busy else { return }
        await refresh()
        guard canStartTrial, let trialProduct else { return }
        await purchase(trialProduct, trialPurchase: true, scene: scene)
    }
    private func purchase(_ selected: Product, trialPurchase: Bool, scene: DirectPurchaseScene?) async {
        guard !busy, !trialPurchase || selected.price == 0 else { return }
        operation = trialPurchase ? .startingTrial : .purchasing; message = nil; recovery = nil; defer { operation = nil }
        do {
            #if os(visionOS)
            guard let scene, scene.activationState == .foregroundActive else { recovery = .make(.storeUnavailable); return }
            let result = try await selected.purchase(confirmIn: scene)
            #else
            let result = try await selected.purchase()
            #endif
            switch result {
            case .success(let result):
                guard case .verified(let transaction) = result, Self.admits(transaction, productID: selected.id) else {
                    recovery = .make(.purchaseUnconfirmed); return
                }
                await transaction.finish(); await refresh()
                if trialPurchase {
                    message = trialIsActive ? "Your 14-day Pro trial has started. There is no automatic charge."
                                           : "This trial cannot unlock Pro. Restore Purchases and check your device date."
                } else if hasLifetimePro { message = "Lifetime Pro unlocked." }
            case .pending: recovery = .make(.purchasePending)
            case .userCancelled: break
            @unknown default: recovery = .make(.purchaseUnconfirmed)
            }
        } catch { if !Self.isStoreCancellation(error) { recovery = .make(.purchaseUnconfirmed) } }
    }
    func restore() async {
        guard !busy else { return }; operation = .restoring; message = nil; recovery = nil; defer { operation = nil }
        do {
            try await AppStore.sync(); await refresh()
            if hasLifetimePro { message = "Lifetime Pro restored." }
            else if trialIsActive { message = "Your Pro trial is restored with its original end date." }
            else if trial != nil { recovery = .make(.trialEnded) }
            else { recovery = .make(.noPurchase) }
        } catch { if !Self.isStoreCancellation(error) { recovery = .make(.restoreFailed) } }
    }
    static func isStoreCancellation(_ error: Error) -> Bool {
        if case StoreKitError.userCancelled = error { return true }
        let value = error as NSError
        return DirectCancellation.isCancellation(error) || (value.domain == SKErrorDomain && value.code == SKError.paymentCancelled.rawValue)
    }
    func canAddMac(count: Int) -> Bool { hasPro || count < 1 }
    func canAddKey(count: Int) -> Bool { hasPro || count < 1 }
    func canUseMac(_ id: UUID, among ids: [UUID]) -> Bool { ids.contains(id) && (hasPro || freeID("mac", ids: ids) == id) }
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
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .title2) private var benefitIconWidth = 32.0
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSize
    #endif
    @State private var access: DirectProAccess
    @State private var purchaseScene: DirectPurchaseScene?
    init(access: DirectProAccess = .shared) { _access = State(initialValue: access) }
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
                content.accessibilityIdentifier("mac-pro-content")
                purchaseArea
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }.padding(16)
            }.frame(width: 600, height: 700)
            #else
            NavigationStack {
                content
                    .navigationTitle("Mac Companion Pro").directInlineNavigationTitle()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                    .safeAreaInset(edge: .bottom, spacing: 0) { if !purchaseInScroll { purchaseArea } }
            }
            #endif
        }
        .background(.background).directAppearance()
        .task { await access.loadProduct() }
        #if os(visionOS)
        .background(VisionSceneCapture { purchaseScene = $0 })
        .onDisappear { purchaseScene = nil }
        #endif
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await access.refresh() } } }
    }
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                status
                if let notice = access.recovery {
                    if notice.reason == .storeUnavailable {
                        DirectStoreRecoveryBanner(retry: { Task { await access.loadProduct() } }, busy: access.busy)
                    } else { DirectRecoveryCard(notice: notice, primary: recoveryAction, secondary: historyAction) }
                }
                VStack(alignment: .leading, spacing: 20) {
                    Text("More ways to work with your Macs").font(.title2.bold())
                    benefit("More Macs and SSH keys", detail: "Save multiple connections and named keys.", symbol: "desktopcomputer")
                    benefit("Easier SSH setup", detail: "Install a public key from your Mac’s settings.", symbol: "key")
                    benefit("Your own quick actions", detail: "Customize keys, shortcuts and saved text.", symbol: "keyboard")
                }.accessibilityIdentifier("pro-benefits")
                Divider()
                DirectInformationGroup(title: "Free Version", symbol: "checkmark.circle", items: freeFeatures)
                    .accessibilityIdentifier("pro-free-features")
                if !access.hasLifetimePro {
                    DisclosureGroup("After the trial") {
                        Text("There is no automatic charge. After 14 days, Pro features require a lifetime purchase. Your saved Macs and keys are kept; free-version limits apply.")
                            .font(.footnote).foregroundStyle(.secondary).padding(.top, 6)
                    }
                }
                if access.trialHistoryUnavailable {
                    Text("Restore Purchases to check your trial history. Free features remain available.").font(.footnote).foregroundStyle(.secondary)
                }
                if purchaseInScroll { purchaseArea }
            }.padding(24).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("pro-scroll-content")
    }
    @ViewBuilder private var status: some View {
            if access.hasLifetimePro {
                Label("Lifetime Pro is unlocked", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else if access.trialIsActive, let trial = access.trial {
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(access.trialDaysRemaining) days left in your trial", systemImage: "clock").font(.headline).foregroundStyle(.tint)
                    Text("Ends \(trial.endDate.formatted(date: .abbreviated, time: .omitted)).").font(.footnote).foregroundStyle(.secondary)
                }
            } else if access.trial != nil {
                Label("Your trial has ended", systemImage: "clock").foregroundStyle(.secondary)
            }
    }
    private var purchaseArea: some View {
        VStack(spacing: 10) {
            if !access.hasLifetimePro {
                Button {
                    Task { await access.purchase(scene: purchaseScene) }
                } label: {
                    Text(access.product.map { "Unlock Lifetime Pro · " + $0.displayPrice } ?? "Purchase Unavailable")
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(access.product == nil || access.busy).accessibilityIdentifier("pro-purchase")
                Text("One-time purchase. No subscription.").font(.footnote).foregroundStyle(.secondary)
                if access.trial == nil {
                    Button("Try Pro Free for 14 Days") { Task { await access.startTrial(scene: purchaseScene) } }
                        .disabled(!access.canStartTrial || access.busy).accessibilityIdentifier("pro-start-trial")
                    Text("No automatic charge.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 16) {
                Button("Restore Purchases") { Task { await access.restore() } }.disabled(access.busy).accessibilityIdentifier("pro-restore")
                if (access.product == nil || access.trialProduct == nil) && access.recovery?.reason != .storeUnavailable {
                    Button("Reload Store") { Task { await access.loadProduct() } }.disabled(access.busy)
                }
            }.font(.footnote)
            ZStack {
                Text(" ").font(.footnote).accessibilityHidden(true)
                if let operation = access.operation {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(operation.title).font(.footnote).foregroundStyle(.secondary) }
                        .accessibilityElement(children: .combine).accessibilityIdentifier("pro-operation")
                }
                else if let message = access.message { Text(message).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("pro-result") }
            }.frame(minHeight: 24)
        }.padding(16).frame(maxWidth: .infinity).background(.bar)
    }
    private func benefit(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tint).frame(width: benefitIconWidth).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var freeFeatures: [String] {
        #if os(iOS)
        let modes = "Screen Sharing, Trackpad & Keyboard, and basic Terminal"
        #else
        let modes = "Screen Sharing and basic Terminal"
        #endif
        return ["One saved Mac and one SSH key", modes, "Standard keyboard controls, display selection and zoom",
            "Local and private VPN connections", "Security, accessibility and SSH key import/export"]
    }
    private var purchaseInScroll: Bool {
        #if os(iOS)
        textSize.isAccessibilitySize || verticalSize == .compact
        #else
        false
        #endif
    }
}
#endif
