import CompanionPersistence
import Foundation

public actor OperationStartupReconcilerV0 {
    private let store: SQLiteSecurityStore
    private var completed: DurableOperationStartupReconciliation?

    public init(store: SQLiteSecurityStore) {
        self.store = store
    }

    public func reconcileBeforeOpeningIngress(
        wallNowUnixMilliseconds: Int64
    ) async throws -> DurableOperationStartupReconciliation {
        if let completed { return completed }
        let result = try await store.reconcileOperationsAtStartup(
            atUnixMilliseconds: wallNowUnixMilliseconds
        )
        completed = result
        return result
    }

    public func requireReconciled() throws -> DurableOperationStartupReconciliation {
        guard let completed else {
            throw OperationStartupError.reconciliationRequired
        }
        return completed
    }
}

public enum OperationStartupError: Error, Equatable, Sendable {
    case reconciliationRequired
}
