// Property check: every account signs the hash the EntryPoint will verify.
//
// For each account × EntryPoint version below, the account's real
// `signUserOperation` / `signUserOperationV06` runs with a recording owner,
// and the digest it hands the owner is compared with an independent
// reference built byte by byte from the EntryPoint contracts
// (UserOperationLib.encode + getUserOpHash for v0.6/v0.7, the EIP-712
// PackedUserOperation hash for v0.8, Eip7702Support for the 0x7702 marker).
// The reference uses no SDK encoder (no Hex, AbiEncoder, TypedData).
//
// Bound: USEROP_HASH_RUNS ops per account (default 300), seeded by
// USEROP_HASH_SEED (default 0x4337). Domain: every field in its Solidity
// range (uint128 for packed gas fields, uint256 otherwise), byte fields
// 0..300 bytes, optional factory / paymaster / gas limits / data.
//
// Maintained by the workspace skill `verify-userop-hash-formal`.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';
import 'package:web3dart/web3dart.dart' show keccak256;

void main() {
  final runs =
      int.tryParse(Platform.environment['USEROP_HASH_RUNS'] ?? '') ?? 300;
  final seed =
      int.tryParse(Platform.environment['USEROP_HASH_SEED'] ?? '') ?? 0x4337;

  group('userOp hash property (seed $seed, $runs runs per account)', () {
    for (final target in _targets) {
      test('${target.name} signs the EntryPoint ${target.ep.name} hash',
          () async {
        final rng = Random(seed ^ target.name.hashCode);
        for (var i = 0; i < runs; i++) {
          // The first runs use small values and short bytes so the first
          // counterexample found is a readable one.
          final op = _Op.random(rng, simple: i < runs ~/ 8, target: target);
          final chainId = _uint(rng, 64, simple: i < runs ~/ 8) + BigInt.one;
          await _expectSignsEntryPointHash(
            target,
            op,
            chainId,
            'run $i (seed $seed)',
          );
        }
      });
    }
  });

  group('getPackedUserOperation property (seed $seed, $runs runs)', () {
    test('packs v0.7 fields exactly as the EntryPoint unpacks them', () {
      final rng = Random(seed);
      for (var i = 0; i < runs; i++) {
        final op = _Op.random(rng, simple: i < runs ~/ 8, target: null);
        final packed = getPackedUserOperation(op.toV07());
        final where = 'run $i (seed $seed)\n${op.describe(_Ep.v07)}';
        expect(packed.initCode, _hex(op.initCodeV07()), reason: where);
        expect(
          packed.accountGasLimits,
          _hex(_word(op.packedAccountGasLimits())),
          reason: where,
        );
        expect(packed.gasFees, _hex(_word(op.packedGasFees())), reason: where);
        expect(
          packed.paymasterAndData,
          _hex(op.paymasterAndDataV07()),
          reason: where,
        );
        final back = unpackUserOperation(packed);
        expect(
          back.verificationGasLimit,
          op.verificationGasLimit,
          reason: where,
        );
        expect(back.callGasLimit, op.callGasLimit, reason: where);
        expect(
          back.maxPriorityFeePerGas,
          op.maxPriorityFeePerGas,
          reason: where,
        );
        expect(back.maxFeePerGas, op.maxFeePerGas, reason: where);
      }
    });
  });

  // Known findings (see the skill). Each test states the promise and pins
  // the smallest counterexample; it is skipped so the quick preset stays
  // green. `dart test --run-skipped` shows them failing.
  group('known findings', () {
    test(
      'Etherspot signs the v0.7 hash when factory is set and factoryData is '
      'null',
      () async {
        final etherspot = _targets.singleWhere((t) => t.name == 'Etherspot');
        final op = _Op.zero(factory: _bytes(Random(1), 20));
        await _expectSignsEntryPointHash(
          etherspot,
          op,
          BigInt.one,
          'factory set, factoryData null',
        );
      },
    );
  });

  // Packed v0.7/v0.8 gas fields are uint128 on-chain. A value outside that
  // range has no EntryPoint encoding, so signing must refuse it rather than
  // sign a widened word that shifts the next field.
  group('packed gas fields outside uint128', () {
    final packedTargets = _targets.where((t) => t.ep != _Ep.v06);
    for (final target in packedTargets) {
      for (final field in _packedGasFields) {
        for (final bad in [BigInt.one << 128, BigInt.from(-1)]) {
          test('${target.name} ${target.ep.name} rejects $field = $bad',
              () async {
            await expectLater(
              target.sign(_Op.gasEdge({field: bad}), BigInt.one),
              throwsA(
                isA<ArgumentError>()
                    .having((e) => e.name, 'name', field)
                    .having((e) => e.invalidValue, 'value', bad),
              ),
            );
          });
        }
      }

      test('${target.name} ${target.ep.name} signs every field at 2^128 - 1',
          () async {
        await _expectSignsEntryPointHash(
          target,
          _Op.gasEdge({for (final f in _packedGasFields) f: _u128}),
          BigInt.one,
          'all packed gas fields at 2^128 - 1',
        );
      });
    }

    test('Safe v0.7 rejects verificationGasLimit = 2^128', () async {
      final account = createSafeSmartAccount(
        owners: [_RecordingOwner()],
        chainId: BigInt.one,
        address: _addr(1),
      );
      final op = _Op.gasEdge({'verificationGasLimit': BigInt.one << 128});
      await expectLater(
        account.signUserOperation(op.toV07()),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.name, 'name', 'verificationGasLimit'),
        ),
      );
    });
  });
}

const _packedGasFields = [
  'verificationGasLimit',
  'callGasLimit',
  'maxPriorityFeePerGas',
  'maxFeePerGas',
  'paymasterVerificationGasLimit',
  'paymasterPostOpGasLimit',
];

Future<void> _expectSignsEntryPointHash(
  _Target target,
  _Op op,
  BigInt chainId,
  String label,
) async {
  final recorded = await target.sign(op, chainId);
  final expected = target.expectedDigest(op, chainId);
  if (recorded.digest != expected) {
    fail(
      '${target.name}: $label signed the wrong hash.\n'
      '  signed via ${recorded.via}: ${recorded.digest}\n'
      '  EntryPoint ${target.ep.name} hash:  $expected\n'
      '  chainId: $chainId\n'
      '${op.describe(target.ep)}',
    );
  }
}

// ---------------------------------------------------------------------------
// Targets: one per account × EntryPoint version.
// ---------------------------------------------------------------------------

enum _Ep { v06, v07, v08 }

final _entryPoints = {
  _Ep.v06: _fromHex('5FF137D4b0FDCD49DcA30c7CF57E578a026d2789'),
  _Ep.v07: _fromHex('0000000071727De22E5E9d8BAf0edAc6f37da032'),
  _Ep.v08: _fromHex('4337084d9e255ff0702461cf8895ce9e3b5ff108'),
};

class _Recorded {
  _Recorded(this.via, this.digest);
  final String via;
  final String digest;
}

/// How the account hands the hash to its owner.
enum _Delivery {
  /// owner.signPersonalMessage(userOpHash); the owner adds EIP-191.
  personal,

  /// owner.signHash(keccak("\x19Ethereum Signed Message:\n32" ‖ hash)).
  prefixedHash,

  /// owner.signTypedData(typedData); the owner hashes with hashTypedData.
  typedData,
}

class _Target {
  _Target(
    this.name,
    this.ep,
    this.delivery,
    this.signWith, {
    this.eip7702Delegate,
  });

  final String name;
  final _Ep ep;
  final _Delivery delivery;
  final Future<void> Function(_RecordingOwner owner, _Op op, BigInt chainId)
      signWith;

  /// EIP-7702 delegate of the sender, for accounts that may send the
  /// 0x7702 initCode marker.
  final Uint8List? eip7702Delegate;

  Future<_Recorded> sign(_Op op, BigInt chainId) async {
    final owner = _RecordingOwner();
    await signWith(owner, op, chainId);
    if (owner.calls.length != 1) {
      fail('$name: expected one owner signing call, got ${owner.calls}');
    }
    final call = owner.calls.single;
    final digest = switch (call.kind) {
      'signTypedData' => hashTypedData(call.payload as TypedData),
      _ => call.payload as String,
    };
    return _Recorded(call.kind, digest.toLowerCase());
  }

  String expectedDigest(_Op op, BigInt chainId) {
    final entryPoint = _entryPoints[ep]!;
    final hash = switch (ep) {
      _Ep.v06 => _userOpHashV06(op, entryPoint, chainId),
      _Ep.v07 => _userOpHashV07(op, entryPoint, chainId),
      _Ep.v08 => _userOpHashV08(op, entryPoint, chainId, eip7702Delegate),
    };
    final digest = switch (delivery) {
      _Delivery.personal || _Delivery.typedData => hash,
      _Delivery.prefixedHash => keccak256(
          _cat([
            Uint8List.fromList('\x19Ethereum Signed Message:\n32'.codeUnits),
            hash,
          ]),
        ),
    };
    return _hex(digest);
  }
}

final _delegate7702 = _bytes(Random(7702), 20);

final List<_Target> _targets = [
  _Target(
    'Simple',
    _Ep.v06,
    _Delivery.personal,
    (o, op, c) => createSimpleSmartAccount(
      owner: o,
      chainId: c,
      entryPointVersion: EntryPointVersion.v06,
      address: _addr(1),
    ).signUserOperationV06(op.toV06()),
  ),
  _Target(
    'Simple',
    _Ep.v07,
    _Delivery.personal,
    (o, op, c) =>
        createSimpleSmartAccount(owner: o, chainId: c, address: _addr(1))
            .signUserOperation(op.toV07()),
  ),
  _Target(
    'Simple',
    _Ep.v08,
    _Delivery.typedData,
    (o, op, c) => createSimpleSmartAccount(
      owner: o,
      chainId: c,
      entryPointVersion: EntryPointVersion.v08,
      address: _addr(1),
    ).signUserOperation(op.toV07()),
  ),
  _Target(
    'Light v1.1.0',
    _Ep.v06,
    _Delivery.personal,
    (o, op, c) => createLightSmartAccount(
      owner: o,
      chainId: c,
      entryPointVersion: EntryPointVersion.v06,
      address: _addr(1),
    ).signUserOperationV06(op.toV06()),
  ),
  _Target(
    'Light v2.0.0',
    _Ep.v07,
    _Delivery.personal,
    (o, op, c) =>
        createLightSmartAccount(owner: o, chainId: c, address: _addr(1))
            .signUserOperation(op.toV07()),
  ),
  _Target(
    'Trust',
    _Ep.v06,
    _Delivery.personal,
    (o, op, c) =>
        createTrustSmartAccount(owner: o, chainId: c, address: _addr(1))
            .signUserOperationV06(op.toV06()),
  ),
  _Target(
    'Thirdweb',
    _Ep.v06,
    _Delivery.personal,
    (o, op, c) => createThirdwebSmartAccount(
      owner: o,
      chainId: c,
      entryPointVersion: EntryPointVersion.v06,
      address: _addr(1),
    ).signUserOperationV06(op.toV06()),
  ),
  _Target(
    'Thirdweb',
    _Ep.v07,
    _Delivery.personal,
    (o, op, c) =>
        createThirdwebSmartAccount(owner: o, chainId: c, address: _addr(1))
            .signUserOperation(op.toV07()),
  ),
  _Target(
    'Biconomy',
    _Ep.v06,
    _Delivery.personal,
    (o, op, c) =>
        createBiconomySmartAccount(owner: o, chainId: c, address: _addr(1))
            .signUserOperationV06(op.toV06()),
  ),
  _Target(
    'Nexus',
    _Ep.v07,
    _Delivery.personal,
    (o, op, c) =>
        createNexusSmartAccount(owner: o, chainId: c, address: _addr(1))
            .signUserOperation(op.toV07()),
  ),
  _Target(
    'Etherspot',
    _Ep.v07,
    _Delivery.personal,
    (o, op, c) => createEtherspotSmartAccount(
      owner: o,
      chainId: c,
      address: _addr(1),
    ).signUserOperation(op.toV07()),
  ),
  _Target(
    'Kernel v0.2.2',
    _Ep.v06,
    _Delivery.personal,
    (o, op, c) => createKernelSmartAccount(
      owner: o,
      chainId: c,
      version: KernelVersion.v0_2_2,
      address: _addr(1),
    ).signUserOperationV06(op.toV06()),
  ),
  _Target(
    'Kernel v0.3.1',
    _Ep.v07,
    _Delivery.personal,
    (o, op, c) => createKernelSmartAccount(
      owner: o,
      chainId: c,
      version: KernelVersion.v0_3_1,
      address: _addr(1),
    ).signUserOperation(op.toV07()),
  ),
  _Target(
    'EIP-7702 Kernel',
    _Ep.v07,
    _Delivery.prefixedHash,
    (o, op, c) => createEip7702KernelSmartAccount(owner: o, chainId: c)
        .signUserOperation(op.toV07()),
  ),
  _Target(
    'EIP-7702 Simple',
    _Ep.v08,
    _Delivery.typedData,
    (o, op, c) => createEip7702SimpleSmartAccount(
      owner: o,
      chainId: c,
      accountLogicAddress: EthereumAddress.fromHex(_hex(_delegate7702)),
    ).signUserOperation(op.toV07()),
    eip7702Delegate: _delegate7702,
  ),
];

/// Records the single digest each account asks its owner to sign.
class _RecordingOwner extends AccountOwner
    implements Eip7702KernelOwner, Eip7702SimpleAccountOwner {
  final calls = <({String kind, Object payload})>[];

  static final _dummySig = '0x${'11' * 64}1b';

  @override
  EthereumAddress get address => _addr(0xAA);

  @override
  Future<String> signPersonalMessage(String hash) async {
    calls.add((kind: 'signPersonalMessage', payload: hash));
    return _dummySig;
  }

  @override
  Future<String> signRawHash(String hash) async {
    calls.add((kind: 'signRawHash', payload: hash));
    return _dummySig;
  }

  @override
  Future<String> signHash(String messageHash) async {
    calls.add((kind: 'signHash', payload: messageHash));
    return _dummySig;
  }

  @override
  Future<String> signTypedData(TypedData typedData) async {
    calls.add((kind: 'signTypedData', payload: typedData));
    return _dummySig;
  }

  @override
  Future<Eip7702Authorization> createAuthorization({
    required BigInt chainId,
    required EthereumAddress contractAddress,
    required BigInt nonce,
  }) =>
      throw UnimplementedError('not used by signUserOperation');
}

// ---------------------------------------------------------------------------
// The operation model and the reference EntryPoint hashes.
// ---------------------------------------------------------------------------

final _u128 = (BigInt.one << 128) - BigInt.one;
final _marker7702 = _cat([
  Uint8List.fromList([0x77, 0x02]),
  Uint8List(18),
]);

class _Op {
  _Op({
    required this.sender,
    required this.nonce,
    required this.factory,
    required this.factoryData,
    required this.callData,
    required this.callGasLimit,
    required this.verificationGasLimit,
    required this.preVerificationGas,
    required this.maxFeePerGas,
    required this.maxPriorityFeePerGas,
    required this.paymaster,
    required this.paymasterVerificationGasLimit,
    required this.paymasterPostOpGasLimit,
    required this.paymasterData,
    required this.signature,
  });

  /// [target] decides which ranges are legal: the packed v0.7/v0.8 gas
  /// fields are uint128, v0.6 gas fields are uint256.
  factory _Op.random(Random r, {required bool simple, _Target? target}) {
    final packed = target == null || target.ep != _Ep.v06;
    final gasBits = packed ? 128 : 256;
    Uint8List? factory;
    if (r.nextInt(3) > 0) {
      factory = target?.eip7702Delegate != null && r.nextBool()
          ? _marker7702
          : _bytes(r, 20);
    }
    final hasPaymaster = r.nextInt(3) > 0;
    return _Op(
      sender: _bytes(r, 20),
      nonce: _uint(r, 256, simple: simple),
      factory: factory,
      factoryData: r.nextInt(4) == 0 ? null : _blob(r, simple: simple),
      callData: _blob(r, simple: simple),
      callGasLimit: _uint(r, gasBits, simple: simple),
      verificationGasLimit: _uint(r, gasBits, simple: simple),
      preVerificationGas: _uint(r, 256, simple: simple),
      maxFeePerGas: _uint(r, gasBits, simple: simple),
      maxPriorityFeePerGas: _uint(r, gasBits, simple: simple),
      paymaster: hasPaymaster ? _bytes(r, 20) : null,
      paymasterVerificationGasLimit:
          r.nextInt(4) == 0 ? null : _uint(r, 128, simple: simple),
      paymasterPostOpGasLimit:
          r.nextInt(4) == 0 ? null : _uint(r, 128, simple: simple),
      paymasterData: r.nextInt(4) == 0 ? null : _blob(r, simple: simple),
      signature: _blob(r, simple: simple),
    );
  }

  /// All-zero operation, for pinning a counterexample by hand.
  factory _Op.zero({Uint8List? factory}) => _Op(
        sender: Uint8List(20),
        nonce: BigInt.zero,
        factory: factory,
        factoryData: null,
        callData: Uint8List(0),
        callGasLimit: BigInt.zero,
        verificationGasLimit: BigInt.zero,
        preVerificationGas: BigInt.zero,
        maxFeePerGas: BigInt.zero,
        maxPriorityFeePerGas: BigInt.zero,
        paymaster: null,
        paymasterVerificationGasLimit: null,
        paymasterPostOpGasLimit: null,
        paymasterData: null,
        signature: Uint8List(0),
      );

  /// All-zero operation with a paymaster, every packed gas field zero
  /// except those in [gas] (keyed by field name).
  factory _Op.gasEdge(Map<String, BigInt> gas) {
    BigInt g(String field) => gas[field] ?? BigInt.zero;
    return _Op(
      sender: Uint8List(20),
      nonce: BigInt.zero,
      factory: null,
      factoryData: null,
      callData: Uint8List(0),
      callGasLimit: g('callGasLimit'),
      verificationGasLimit: g('verificationGasLimit'),
      preVerificationGas: BigInt.zero,
      maxFeePerGas: g('maxFeePerGas'),
      maxPriorityFeePerGas: g('maxPriorityFeePerGas'),
      paymaster: Uint8List(20)..[19] = 1,
      paymasterVerificationGasLimit: g('paymasterVerificationGasLimit'),
      paymasterPostOpGasLimit: g('paymasterPostOpGasLimit'),
      paymasterData: null,
      signature: Uint8List(0),
    );
  }

  final Uint8List sender;
  final BigInt nonce;
  final Uint8List? factory;
  final Uint8List? factoryData;
  final Uint8List callData;
  final BigInt callGasLimit;
  final BigInt verificationGasLimit;
  final BigInt preVerificationGas;
  final BigInt maxFeePerGas;
  final BigInt maxPriorityFeePerGas;
  final Uint8List? paymaster;
  final BigInt? paymasterVerificationGasLimit;
  final BigInt? paymasterPostOpGasLimit;
  final Uint8List? paymasterData;
  final Uint8List signature;

  // v0.6 carries initCode / paymasterAndData as opaque bytes; reuse the
  // same parts so one generator feeds every version.
  Uint8List initCodeV06() => initCodeV07();
  Uint8List paymasterAndDataV06() => paymaster == null
      ? Uint8List(0)
      : _cat([paymaster!, paymasterData ?? Uint8List(0)]);

  /// viem getInitCode / EntryPoint v0.7: factory ‖ factoryData, or empty.
  Uint8List initCodeV07() => factory == null
      ? Uint8List(0)
      : _cat([factory!, factoryData ?? Uint8List(0)]);

  /// paymaster ‖ uint128 pmVerificationGas ‖ uint128 pmPostOpGas ‖ data.
  Uint8List paymasterAndDataV07() => paymaster == null
      ? Uint8List(0)
      : _cat([
          paymaster!,
          _uintBytes(paymasterVerificationGasLimit ?? BigInt.zero, 16),
          _uintBytes(paymasterPostOpGasLimit ?? BigInt.zero, 16),
          paymasterData ?? Uint8List(0),
        ]);

  BigInt packedAccountGasLimits() =>
      (verificationGasLimit << 128) | callGasLimit;
  BigInt packedGasFees() => (maxPriorityFeePerGas << 128) | maxFeePerGas;

  UserOperationV06 toV06() => UserOperationV06(
        sender: EthereumAddress.fromHex(_hex(sender)),
        nonce: nonce,
        initCode: _hex(initCodeV06()),
        callData: _hex(callData),
        callGasLimit: callGasLimit,
        verificationGasLimit: verificationGasLimit,
        preVerificationGas: preVerificationGas,
        maxFeePerGas: maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
        paymasterAndData: _hex(paymasterAndDataV06()),
        signature: _hex(signature),
      );

  UserOperationV07 toV07() => UserOperationV07(
        sender: EthereumAddress.fromHex(_hex(sender)),
        nonce: nonce,
        factory:
            factory == null ? null : EthereumAddress.fromHex(_hex(factory!)),
        factoryData: factoryData == null ? null : _hex(factoryData!),
        callData: _hex(callData),
        callGasLimit: callGasLimit,
        verificationGasLimit: verificationGasLimit,
        preVerificationGas: preVerificationGas,
        maxFeePerGas: maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
        paymaster: paymaster == null
            ? null
            : EthereumAddress.fromHex(_hex(paymaster!)),
        paymasterVerificationGasLimit: paymasterVerificationGasLimit,
        paymasterPostOpGasLimit: paymasterPostOpGasLimit,
        paymasterData: paymasterData == null ? null : _hex(paymasterData!),
        signature: _hex(signature),
      );

  String describe(_Ep ep) {
    String b(Uint8List? v) => v == null ? 'null' : _hex(v);
    return [
      '  sender: ${b(sender)}',
      '  nonce: $nonce',
      if (ep == _Ep.v06) ...[
        '  initCode: ${b(initCodeV06())}',
        '  paymasterAndData: ${b(paymasterAndDataV06())}',
      ] else ...[
        '  factory: ${b(factory)}',
        '  factoryData: ${b(factoryData)}',
        '  paymaster: ${b(paymaster)}',
        '  paymasterVerificationGasLimit: $paymasterVerificationGasLimit',
        '  paymasterPostOpGasLimit: $paymasterPostOpGasLimit',
        '  paymasterData: ${b(paymasterData)}',
      ],
      '  callData: ${b(callData)}',
      '  callGasLimit: $callGasLimit',
      '  verificationGasLimit: $verificationGasLimit',
      '  preVerificationGas: $preVerificationGas',
      '  maxFeePerGas: $maxFeePerGas',
      '  maxPriorityFeePerGas: $maxPriorityFeePerGas',
    ].join('\n');
  }
}

/// EntryPoint v0.6 getUserOpHash:
/// keccak(abi.encode(keccak(pack(op)), entryPoint, chainId)).
Uint8List _userOpHashV06(_Op op, Uint8List ep, BigInt chainId) {
  final inner = keccak256(
    _cat([
      _addrWord(op.sender),
      _word(op.nonce),
      keccak256(op.initCodeV06()),
      keccak256(op.callData),
      _word(op.callGasLimit),
      _word(op.verificationGasLimit),
      _word(op.preVerificationGas),
      _word(op.maxFeePerGas),
      _word(op.maxPriorityFeePerGas),
      keccak256(op.paymasterAndDataV06()),
    ]),
  );
  return keccak256(_cat([inner, _addrWord(ep), _word(chainId)]));
}

/// The v0.7/v0.8 field encoding shared by UserOperationLib.encode.
List<Uint8List> _packedFields(_Op op, Uint8List initCodeHash) => [
      _addrWord(op.sender),
      _word(op.nonce),
      initCodeHash,
      keccak256(op.callData),
      _word(op.packedAccountGasLimits()),
      _word(op.preVerificationGas),
      _word(op.packedGasFees()),
      keccak256(op.paymasterAndDataV07()),
    ];

/// EntryPoint v0.7 getUserOpHash.
Uint8List _userOpHashV07(_Op op, Uint8List ep, BigInt chainId) {
  final inner = keccak256(_cat(_packedFields(op, keccak256(op.initCodeV07()))));
  return keccak256(_cat([inner, _addrWord(ep), _word(chainId)]));
}

/// EntryPoint v0.8 getUserOpHash: EIP-712 over PackedUserOperation, domain
/// ("ERC4337", "1", chainId, entryPoint). With the 0x7702 initCode marker,
/// Eip7702Support replaces the marker with the sender's delegate.
Uint8List _userOpHashV08(
  _Op op,
  Uint8List ep,
  BigInt chainId,
  Uint8List? delegate,
) {
  final initCode = op.initCodeV07();
  final isMarker =
      initCode.length >= 20 && _sameBytes(initCode.sublist(0, 20), _marker7702);
  final initCodeHash = isMarker
      ? keccak256(_cat([delegate!, initCode.sublist(20)]))
      : keccak256(initCode);
  final typeHash = keccak256(
    _utf8(
      _eip712Type('PackedUserOperation', [
        'address sender',
        'uint256 nonce',
        'bytes initCode',
        'bytes callData',
        'bytes32 accountGasLimits',
        'uint256 preVerificationGas',
        'bytes32 gasFees',
        'bytes paymasterAndData',
      ]),
    ),
  );
  final structHash =
      keccak256(_cat([typeHash, ..._packedFields(op, initCodeHash)]));
  final domainSeparator = keccak256(
    _cat([
      keccak256(
        _utf8(
          _eip712Type('EIP712Domain', [
            'string name',
            'string version',
            'uint256 chainId',
            'address verifyingContract',
          ]),
        ),
      ),
      keccak256(_utf8('ERC4337')),
      keccak256(_utf8('1')),
      _word(chainId),
      _addrWord(ep),
    ]),
  );
  return keccak256(
    _cat([
      Uint8List.fromList([0x19, 0x01]),
      domainSeparator,
      structHash,
    ]),
  );
}

// ---------------------------------------------------------------------------
// Generators and byte helpers (independent of the SDK's Hex / AbiEncoder).
// ---------------------------------------------------------------------------

BigInt _uint(Random r, int bits, {required bool simple}) {
  final max = (BigInt.one << bits) - BigInt.one;
  if (simple) return BigInt.from(r.nextInt(1 << 16));
  switch (r.nextInt(8)) {
    case 0:
      final edges = [
        BigInt.zero,
        BigInt.one,
        max,
        BigInt.one << (bits - 1),
        (BigInt.one << 64) - BigInt.one,
        BigInt.one << 64,
        if (bits > 128) _u128,
        if (bits > 128) _u128 + BigInt.one,
      ];
      return edges[r.nextInt(edges.length)];
    case 1:
      return BigInt.from(r.nextInt(1 << 32));
    default:
      // Random magnitude: a random bit length, then random bits.
      final len = 1 + r.nextInt(bits);
      final bytes = _bytes(r, (len + 7) ~/ 8);
      return _toBigInt(bytes) & ((BigInt.one << len) - BigInt.one);
  }
}

Uint8List _blob(Random r, {required bool simple}) {
  const lengths = [0, 1, 4, 20, 31, 32, 33, 64];
  final len = simple
      ? r.nextInt(5)
      : (r.nextBool() ? lengths[r.nextInt(lengths.length)] : r.nextInt(301));
  return _bytes(r, len);
}

Uint8List _bytes(Random r, int n) =>
    Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));

Uint8List _cat(List<Uint8List> parts) {
  final b = BytesBuilder(copy: false);
  parts.forEach(b.add);
  return b.toBytes();
}

Uint8List _uintBytes(BigInt v, int width) {
  if (v.isNegative || v.bitLength > width * 8) {
    throw ArgumentError('$v does not fit in uint${width * 8}');
  }
  final out = Uint8List(width);
  var x = v;
  for (var i = width - 1; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x >>= 8;
  }
  return out;
}

Uint8List _word(BigInt v) => _uintBytes(v, 32);

Uint8List _addrWord(Uint8List address) => _cat([Uint8List(12), address]);

BigInt _toBigInt(Uint8List bytes) =>
    bytes.fold(BigInt.zero, (acc, b) => (acc << 8) | BigInt.from(b));

Uint8List _utf8(String s) => Uint8List.fromList(s.codeUnits);

/// EIP-712 encodeType for a struct with no nested types.
String _eip712Type(String name, List<String> fields) =>
    '$name(${fields.join(',')})';

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

const _hexDigits = '0123456789abcdef';

String _hex(Uint8List bytes) {
  final sb = StringBuffer('0x');
  for (final b in bytes) {
    sb
      ..write(_hexDigits[b >> 4])
      ..write(_hexDigits[b & 0xf]);
  }
  return sb.toString();
}

Uint8List _fromHex(String h) => Uint8List.fromList([
      for (var i = 0; i < h.length; i += 2)
        int.parse(h.substring(i, i + 2), radix: 16),
    ]);

EthereumAddress _addr(int n) => EthereumAddress.fromHex(
      _hex(
        _cat([
          Uint8List(19),
          Uint8List.fromList([n]),
        ]),
      ),
    );
