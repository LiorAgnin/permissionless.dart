/// Solidity signatures of the Safe, Safe4337Module, MultiSend and Safe7579
/// launchpad functions this package calls.
///
/// Selectors, encoders and decoders all derive from these; not exported.
library;

/// `Safe.setup`.
const safeSetupSignature =
    'setup(address[],uint256,address,bytes,address,address,uint256,address)';

/// `Safe4337Module.executeUserOp`.
const safeExecuteUserOpSignature = 'executeUserOp(address,uint256,bytes,uint8)';

/// `Safe4337Module.executeUserOpWithErrorString`.
const safeExecuteUserOpWithErrorStringSignature =
    'executeUserOpWithErrorString(address,uint256,bytes,uint8)';

/// `SafeProxyFactory.createProxyWithNonce`.
const safeCreateProxyWithNonceSignature =
    'createProxyWithNonce(address,bytes,uint256)';

/// `SafeProxyFactory.proxyCreationCode`.
const safeProxyCreationCodeSignature = 'proxyCreationCode()';

/// `SafeModuleSetup.enableModules`.
const safeEnableModulesSignature = 'enableModules(address[])';

/// `MultiSend.multiSend` (also MultiSendCallOnly).
const safeMultiSendSignature = 'multiSend(bytes)';

/// `Safe7579Launchpad.initSafe7579`; `ModuleInit` is `(address,bytes)`.
const safe7579InitSignature = 'initSafe7579(address,(address,bytes)[],'
    '(address,bytes)[],(address,bytes)[],address[],uint8)';

/// `Safe7579Launchpad.preValidationSetup`.
const safe7579PreValidationSetupSignature =
    'preValidationSetup(bytes32,address,bytes)';

/// `Safe7579Launchpad.setupSafe(InitData)`.
const safe7579SetupSafeSignature = 'setupSafe((address,address[],uint256,'
    'address,bytes,address,(address,bytes)[],bytes))';

/// The `InitData` fields the launchpad hashes into `initHash` (all but
/// `callData`), as a function signature so `AbiEncoder` can encode them.
const safe7579InitHashFieldsSignature = 'initHash(address,address[],uint256,'
    'address,bytes,address,(address,bytes)[])';
