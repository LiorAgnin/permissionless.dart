@Tags(['integration', 'funded'])
library;

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../config/test_config.dart';
import '../config/test_utils.dart';

/// Live Pimlico Sepolia coverage for EntryPoint v0.9 + Simple7702Account.
///
/// Required base environment:
/// - PIMLICO_API_KEY
/// - TEST_PRIVATE_KEY
/// - SEPOLIA_RPC_URL
///
/// Sponsored path additionally requires:
/// - PIMLICO_SPONSORSHIP_POLICY_ID
void main() {
  group('Pimlico Sepolia Simple7702 v0.9 live flow', () {
    test(
      'self-funded prepare/sign/submit/receipt succeeds',
      () async {
        if (!TestConfig.hasLiveV09BaseEnv) {
          requireLiveV09BaseEnv();
          return;
        }

        final clients = _createClients();
        try {
          await _runLiveV09Flow(
            clients: clients,
            paymasterContext: null,
            requiresNativeBalance: true,
          );
        } finally {
          clients.close();
        }
      },
      timeout: const Timeout(TestTimeouts.e2eFlow),
    );

    test(
      'sponsored prepare/sign/submit/receipt succeeds',
      () async {
        if (!TestConfig.hasLiveV09SponsoredEnv) {
          requireLiveV09SponsoredEnv();
          return;
        }

        final clients = _createClients(withPaymaster: true);
        try {
          await _runLiveV09Flow(
            clients: clients,
            paymasterContext: PaymasterContext(
              sponsorshipPolicyId: TestConfig.pimlicoSponsorshipPolicyId!,
            ),
            requiresNativeBalance: false,
          );
        } finally {
          clients.close();
        }
      },
      timeout: const Timeout(TestTimeouts.e2eFlow),
    );
  });
}

_LiveV09Clients _createClients({bool withPaymaster = false}) {
  const chain = TestChain.sepolia;
  final owner = PrivateKeyEip7702Owner(TestConfig.testPrivateKey!);
  final publicClient = createPublicClient(
    url: TestConfig.sepoliaRpcUrl!,
    timeout: TestTimeouts.longNetwork,
  );
  final bundler = createPimlicoClient(
    url: chain.pimlicoUrl,
    entryPoint: EntryPointAddresses.v09,
    timeout: TestTimeouts.longNetwork,
  );
  final paymaster = withPaymaster
      ? createPaymasterClient(
          url: chain.pimlicoUrl,
          timeout: TestTimeouts.longNetwork,
        )
      : null;
  final account = createEip7702SimpleSmartAccount(
    owner: owner,
    chainId: chain.chainIdBigInt,
    publicClient: publicClient,
    entryPointVersion: EntryPointVersion.v09,
  );

  return _LiveV09Clients(
    owner: owner,
    publicClient: publicClient,
    bundler: bundler,
    paymaster: paymaster,
    account: account,
  );
}

Future<void> _runLiveV09Flow({
  required _LiveV09Clients clients,
  required PaymasterContext? paymasterContext,
  required bool requiresNativeBalance,
}) async {
  const chain = TestChain.sepolia;
  final accountAddress = await clients.account.getAddress();

  expect(accountAddress, equals(clients.owner.address));
  expect(chain.entryPointV09, equals(EntryPointAddresses.v09));
  expect(clients.account.entryPointVersion, equals(EntryPointVersion.v09));
  expect(clients.account.entryPoint, equals(EntryPointAddresses.v09));
  expect(
    clients.account.accountLogicAddress,
    equals(Simple7702AccountAddresses.v09),
  );
  expect(
    EntryPointAddresses.v09.hex.toLowerCase(),
    equals('0x433709009b8330fda32311df1c2afa402ed8d009'),
  );
  expect(
    Simple7702AccountAddresses.v09.hex.toLowerCase(),
    equals('0xa46cc63ebf4bd77888aa327837d20b23a63a56b5'),
  );

  final delegation = await _assertSupportedDelegation(
    clients.publicClient,
    accountAddress,
  );
  if (delegation == _DelegationState.undelegated) {
    final eoaNonce = await clients.publicClient.getTransactionCount(
      accountAddress,
    );
    final authorization = await clients.account.getAuthorization(
      nonce: eoaNonce,
    );

    expect(authorization.chainId, equals(chain.chainIdBigInt));
    expect(authorization.address, equals(Simple7702AccountAddresses.v09));
    expect(authorization.nonce, equals(eoaNonce));
  }

  if (requiresNativeBalance) {
    final balance = await clients.publicClient.getBalance(accountAddress);
    if (balance == BigInt.zero) {
      fail(
        'Setup error: TEST_PRIVATE_KEY EOA ${accountAddress.checksummed} '
        'has zero Sepolia ETH. Fund it before running the self-funded '
        'EntryPoint v0.9 live flow.',
      );
    }
  }

  final smartAccountClient = createSmartAccountClient(
    account: clients.account,
    bundler: clients.bundler,
    publicClient: clients.publicClient,
    paymaster: clients.paymaster,
  );
  final gasPrices = await clients.bundler.getUserOperationGasPrice();
  final call = Call(to: accountAddress, value: BigInt.zero, data: '0x');

  final prepared = await smartAccountClient.prepareUserOperationWithAuth(
    calls: [call],
    maxFeePerGas: gasPrices.fast.maxFeePerGas,
    maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
    paymasterContext: paymasterContext,
  );

  expect(prepared.userOp.sender, equals(accountAddress));
  expect(prepared.userOp.callData, isNot(equals('0x')));
  expect(prepared.userOp.callGasLimit, greaterThanBigInt(BigInt.zero));
  expect(prepared.userOp.verificationGasLimit, greaterThanBigInt(BigInt.zero));
  expect(prepared.userOp.preVerificationGas, greaterThanBigInt(BigInt.zero));

  if (delegation == _DelegationState.undelegated) {
    expect(prepared.authorization, isNotNull);
    expect(
      prepared.authorization!.address,
      equals(Simple7702AccountAddresses.v09),
    );
  } else {
    expect(prepared.authorization, isNull);
  }

  if (paymasterContext == null) {
    expect(prepared.userOp.paymaster, isNull);
  } else {
    expect(prepared.userOp.paymaster, isNotNull);
    expect(prepared.userOp.paymasterData, isNotNull);
  }

  final signed = await smartAccountClient.signUserOperation(prepared.userOp);
  expect(signed.signature, startsWith('0x'));
  expect(signed.signature, isNot(equals(prepared.userOp.signature)));

  final hash = await smartAccountClient.sendPreparedUserOperationWithAuth(
    signed,
    prepared.authorization,
  );
  expect(hash, startsWith('0x'));
  expect(hash.length, equals(66));

  final receipt = await smartAccountClient.waitForReceipt(
    hash,
    timeout: TestTimeouts.e2eFlow,
  );
  expect(receipt, isNotNull);
  expect(receipt!.success, isTrue);
  expect(receipt.receipt?.transactionHash, startsWith('0x'));
}

Future<_DelegationState> _assertSupportedDelegation(
  PublicClient publicClient,
  EthereumAddress accountAddress,
) async {
  final code = await publicClient.getCode(accountAddress);
  final lowerCode = code.toLowerCase();
  if (lowerCode == '0x') {
    return _DelegationState.undelegated;
  }

  final stripped = Hex.strip0x(lowerCode);
  if (!stripped.startsWith(_eip7702DelegationPrefix)) {
    fail(
      'Setup error: TEST_PRIVATE_KEY EOA ${accountAddress.checksummed} '
      'already has non-EIP-7702 code ${_previewHex(lowerCode)}. Use a fresh '
      'Sepolia EOA or one delegated to Simple7702Account v0.9 '
      '(${Simple7702AccountAddresses.v09.checksummed}).',
    );
  }

  if (stripped.length < _eip7702DelegationPrefix.length + 40) {
    fail(
      'Setup error: TEST_PRIVATE_KEY EOA ${accountAddress.checksummed} '
      'has malformed EIP-7702 delegation code ${_previewHex(lowerCode)}.',
    );
  }

  final delegatedTo = EthereumAddress.fromHex(
    '0x${stripped.substring(_eip7702DelegationPrefix.length, _eip7702DelegationPrefix.length + 40)}',
  );
  if (delegatedTo.hex.toLowerCase() !=
      Simple7702AccountAddresses.v09.hex.toLowerCase()) {
    fail(
      'Setup error: TEST_PRIVATE_KEY EOA ${accountAddress.checksummed} '
      'is already delegated to ${delegatedTo.checksummed}. Expected '
      'Simple7702Account v0.9 '
      '(${Simple7702AccountAddresses.v09.checksummed}). Use a fresh Sepolia '
      'EOA or clear the incompatible delegation before running this test.',
    );
  }

  return _DelegationState.delegatedToSimple7702V09;
}

String _previewHex(String value) =>
    value.length <= 66 ? value : '${value.substring(0, 66)}...';

const _eip7702DelegationPrefix = 'ef0100';

enum _DelegationState { undelegated, delegatedToSimple7702V09 }

class _LiveV09Clients {
  _LiveV09Clients({
    required this.owner,
    required this.publicClient,
    required this.bundler,
    required this.paymaster,
    required this.account,
  });

  final PrivateKeyEip7702Owner owner;
  final PublicClient publicClient;
  final PimlicoClient bundler;
  final PaymasterClient? paymaster;
  final Eip7702SimpleSmartAccount account;

  void close() {
    bundler.close();
    paymaster?.close();
    publicClient.close();
  }
}
