#if os(macOS)
import CompanionAgent
import CompanionIPC
import CompanionLocalXPCPlatform

/// Adapts only the read capability issued by the complete Agent local-service
/// root. It has no caller identity or method selector: those decisions have
/// already been made by the signed XPC profile before this value is invoked.
public struct MacLocalXPCStatusReaderV1:
    MacLocalXPCStatusReadingV1,
    Sendable
{
    private let statusReader: any AgentLocalStatusReadingV1

    public init(statusReader: any AgentLocalStatusReadingV1) {
        self.statusReader = statusReader
    }

    public func readStatus() async
        -> Result<LocalAgentStatusSnapshot, MacLocalXPCStatusReadErrorV1>
    {
        do {
            return .success(try await statusReader.read())
        } catch {
            return .failure(.sourceUnavailable)
        }
    }
}
#endif
