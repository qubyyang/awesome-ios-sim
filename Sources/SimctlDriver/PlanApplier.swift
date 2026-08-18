import Foundation
import SimulatorStateCore

public struct OperationReceipt: Codable, Equatable, Sendable {
    public let operationID: String
    public let action: SimulatorOperationAction
    public let targetUDID: String
    public let command: [String]
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let startedAt: String
    public let finishedAt: String

    public init(
        operationID: String,
        action: SimulatorOperationAction,
        targetUDID: String,
        command: [String],
        exitCode: Int32,
        standardOutput: String,
        standardError: String,
        startedAt: String,
        finishedAt: String
    ) {
        self.operationID = operationID
        self.action = action
        self.targetUDID = targetUDID
        self.command = command
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public var succeeded: Bool { exitCode == 0 }
}

public enum ApplyStatus: String, Codable, Sendable {
    case dryRun
    case succeeded
    case failed
}

public struct PlanExecutionReport: Codable, Equatable, Sendable {
    public let plan: SimulatorStatePlan
    public let status: ApplyStatus
    public let receipts: [OperationReceipt]
    public let failure: String?

    public init(
        plan: SimulatorStatePlan,
        status: ApplyStatus,
        receipts: [OperationReceipt] = [],
        failure: String? = nil
    ) {
        self.plan = plan
        self.status = status
        self.receipts = receipts
        self.failure = failure
    }
}

public protocol PlanApplying: Sendable {
    func apply(_ plan: SimulatorStatePlan, confirmed: Bool) throws -> PlanExecutionReport
}

/// Serializes operations for a plan and stops at the first failure. A caller
/// must pass `confirmed: true`; otherwise the method returns a dry-run report.
public final class SimulatorPlanApplier: PlanApplying, @unchecked Sendable {
    private let controller: any SimulatorControlling
    private let lock = NSLock()

    public init(controller: any SimulatorControlling) {
        self.controller = controller
    }

    public func apply(_ plan: SimulatorStatePlan, confirmed: Bool) throws -> PlanExecutionReport {
        guard confirmed else {
            return PlanExecutionReport(plan: plan, status: .dryRun)
        }

        lock.lock()
        defer { lock.unlock() }

        var receipts: [OperationReceipt] = []
        for operation in plan.operations {
            do {
                let receipt = try controller.execute(operation)
                receipts.append(receipt)
                if !receipt.succeeded {
                    return PlanExecutionReport(
                        plan: plan,
                        status: .failed,
                        receipts: receipts,
                        failure: receipt.standardError.isEmpty
                            ? "Operation \(operation.id) exited with \(receipt.exitCode)"
                            : receipt.standardError
                    )
                }
            } catch {
                return PlanExecutionReport(
                    plan: plan,
                    status: .failed,
                    receipts: receipts,
                    failure: error.localizedDescription
                )
            }
        }
        return PlanExecutionReport(plan: plan, status: .succeeded, receipts: receipts)
    }
}

