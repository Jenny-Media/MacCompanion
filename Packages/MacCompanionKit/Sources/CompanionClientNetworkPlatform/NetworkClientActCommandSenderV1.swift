import CompanionClient

/// The authenticated primary pump is only a byte sender at this boundary. The
/// Act owner retains all catalog, operation, approval, and result authority.
extension NetworkClientPrimaryFramePumpV0:
    ClientAuthenticatedCommandSendingV1 {}
