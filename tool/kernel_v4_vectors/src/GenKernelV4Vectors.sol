// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Kernel} from "@kernel/Kernel.sol";
import {KernelUUPS} from "@kernel/KernelUUPS.sol";
import {KernelImmutableECDSA} from "@kernel/KernelImmutableECDSA.sol";
import {KernelFactory} from "@kernel/KernelFactory.sol";
import {Install} from "@kernel/types/Structs.sol";
import {
    INSTALL_PACKAGES_STRUCT_HASH,
    INSTALL_STRUCT_HASH,
    DOMAIN_TYPEHASH_SANS_CHAIN_ID
} from "@kernel/types/Constants.sol";
import {Lib4337} from "@kernel/lib/Lib4337.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {UserOperationLib} from "account-abstraction/core/UserOperationLib.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {EfficientHashLib} from "solady/utils/EfficientHashLib.sol";

/// Minimal subset of the Foundry cheatcode interface, declared inline so this
/// generator needs no `forge install` step.
interface Vm {
    function toString(bytes32 value) external pure returns (string memory);
    function toString(bytes memory value) external pure returns (string memory);
    function toString(uint256 value) external pure returns (string memory);
    function toString(address value) external pure returns (string memory);
    function writeFile(string calldata path, string calldata data) external;
    function sign(uint256 privateKey, bytes32 digest) external pure returns (uint8 v, bytes32 r, bytes32 s);
    function prank(address msgSender) external;
    function deal(address who, uint256 newBalance) external;
    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

/// The Staker forwarding entry point, restated here for calldata encoding only
/// (kernel/src/Staker.sol is the source of truth for the selector).
interface IStaker {
    function deployWithFactory(address factory, bytes calldata createData) external payable returns (address);
}

/// Thin external wrapper over the pinned EntryPoint v0.9 hashing internals
/// (same pattern as tool/entry_point_v09_vectors), deployed so the script
/// contract itself never relies on `address(this)`.
contract HashOracle {
    using UserOperationLib for PackedUserOperation;

    /// Mirrors `EntryPoint.getUserOpHash` for a non-7702 operation: EIP-712
    /// digest over the `ERC4337` / `1` domain. (Restated from the EntryPoint's
    /// OpenZeppelin EIP712 base; `UserOperationLib` supplies the struct hash.)
    function userOpHash(PackedUserOperation calldata op, uint256 chainId, address entryPoint)
        external
        pure
        returns (bytes32)
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ERC4337")),
                keccak256(bytes("1")),
                chainId,
                entryPoint
            )
        );
        return keccak256(abi.encodePacked(hex"1901", domainSeparator, op.hash(bytes32(0))));
    }

    /// Mirrors `Lib4337.chainAgnosticUserOpHash` (nonce mode `0x40`) with the
    /// EntryPoint v0.9 domain constants inlined: the same struct hash under an
    /// `EIP712Domain(string name,string version,address verifyingContract)`
    /// domain — no chainId. The generator cross-checks this restatement
    /// against the pinned `Lib4337` via [ChainAgnosticOracle].
    function chainAgnosticUserOpHash(PackedUserOperation calldata op, address entryPoint)
        external
        pure
        returns (bytes32)
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,address verifyingContract)"),
                keccak256(bytes("ERC4337")),
                keccak256(bytes("1")),
                entryPoint
            )
        );
        return keccak256(abi.encodePacked(hex"1901", domainSeparator, op.hash(bytes32(0))));
    }
}

/// Thin external wrapper over the pinned `Lib4337.chainAgnosticUserOpHash`
/// (calldata plumbing only). It reads `name` / `version` live from the
/// EntryPoint's `eip712Domain()`, so the canonical address must carry the real
/// EntryPoint v0.9 code (etched in `run`) when this is called.
contract ChainAgnosticOracle {
    function hash(address ep, PackedUserOperation calldata op) external view returns (bytes32) {
        return Lib4337.chainAgnosticUserOpHash(ep, op);
    }
}

/// Minimal root ECDSA validator, restated from the pinned repo's own test
/// mock (`kernel/test/mock/ECDSAValidator.sol`, not importable across the
/// checkout symlink): `onInstall` stores the 20-byte owner, `validateUserOp`
/// recovers the raw digest — the same semantics ticket 11 established for the
/// v3 drop-in validator. The Kernel install path only low-level-calls
/// `onInstall`, and root validation only calls `validateUserOp`, so no other
/// module surface is needed.
contract RootEcdsaValidator {
    mapping(address => address) public owners;

    function onInstall(bytes calldata data) external payable {
        owners[msg.sender] = address(bytes20(data[0:20]));
    }

    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        payable
        returns (uint256)
    {
        if (owners[msg.sender] == ECDSA.tryRecoverCalldata(userOpHash, userOp.signature)) {
            return 0;
        }
        return 1;
    }

    /// The enable-mode digest check for accounts whose *root* is a validator
    /// module (`_verifySignature` routes non-fallback roots here): raw-digest
    /// recovery, same semantics as `validateUserOp`.
    function isValidSignatureWithSender(address, bytes32 hash, bytes calldata sig) external view returns (bytes4) {
        return owners[msg.sender] == ECDSA.tryRecoverCalldata(hash, sig) ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }
}

/// Minimal permission policy, restated in the spirit of the pinned repo's
/// test mocks: passes only when its `PermissionSignature` chunk equals the
/// fixed proof bytes. This makes the fixture prove the SDK routes the right
/// element of the signatures array to the right module — a policy that
/// accepted anything could not distinguish correct framing from garbage.
contract ProofPolicy {
    bytes internal constant PROOF = hex"c0ffee";

    function onInstall(bytes calldata) external payable {}

    function checkUserOpPolicy(bytes32, PackedUserOperation calldata userOp) external payable returns (uint256) {
        return keccak256(userOp.signature) == keccak256(PROOF) ? 0 : 1;
    }

    function checkSignaturePolicy(bytes32, address, bytes32, bytes calldata sig) external view returns (uint256) {
        return keccak256(sig) == keccak256(PROOF) ? 0 : 1;
    }
}

/// Minimal ECDSA permission signer (the permission's finalizing module):
/// recovers the raw digest from its chunk — the same semantics as
/// [RootEcdsaValidator], but on the `ISigner` interface.
contract EcdsaSigner {
    mapping(address => address) public owners;

    function onInstall(bytes calldata data) external payable {
        owners[msg.sender] = address(bytes20(data[0:20]));
    }

    function checkUserOpSignature(bytes32, PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        payable
        returns (uint256)
    {
        return owners[msg.sender] == ECDSA.tryRecoverCalldata(userOpHash, userOp.signature) ? 0 : 1;
    }

    function checkSignature(bytes32, address, bytes32 hash, bytes calldata sig) external view returns (bytes4) {
        return owners[msg.sender] == ECDSA.tryRecoverCalldata(hash, sig) ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }
}

/// A trivial side-effect target for the execute round-trip cases.
contract Target {
    uint256 public x;
    uint256 public y;

    function setX(uint256 value) external payable {
        x = value;
    }

    function setY(uint256 value) external payable {
        y = value;
    }
}

/// @notice Generates the committed Kernel v4.0 fixture consumed by the Dart
/// Kernel v4 tests, from the pinned `kernel-v4.0` contracts.
///
/// Run with `./generate.sh` from this directory (or
/// `forge script src/GenKernelV4Vectors.sol:GenKernelV4Vectors` after
/// symlinking `kernel` to the checkout). See README.md.
contract GenKernelV4Vectors {
    using UserOperationLib for PackedUserOperation;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant OUT_PATH = "../../packages/permissionless/test/fixtures/kernel_v4_vectors.json";

    /// Canonical EntryPoint v0.9 (eth-infinitism release; also the constructor
    /// argument pinned in `releases/v0.4.0.json`).
    address internal constant ENTRY_POINT = 0x433709009B8330FDa32311DF1C2AFA402eD8D009;

    // CREATE2-predicted release addresses from `releases/v0.4.0.json`.
    address internal constant CANON_STAKER = 0x58E2fD56990250b0eE784d15905C9856209226aE;
    address internal constant CANON_UUPS = 0xC842fE2aC44046AE3cEf033A16c67a9BC287cbD2;
    address internal constant CANON_IMMUTABLE_ECDSA = 0x6F0999265B6E1dFbe875F104548b875a99A65d37;
    address internal constant CANON_FACTORY = 0xA299A4eFee7BBFb2Ea5668b30218C45fff78356c;

    /// Hardhat account #0 — fixed offline unit-test key, never used on live
    /// networks (see the repo test conventions).
    uint256 internal constant SIGNER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address internal constant SIGNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    /// Hardhat account #1 — the wrong-signer negative case.
    uint256 internal constant WRONG_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    address internal constant OTHER_SIGNER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    /// The v3-era ECDSA validator, used as a realistic module address in
    /// package vectors (drop-in for basic v4 root flows).
    address internal constant ECDSA_VALIDATOR = 0x845ADb2C711129d4f3966735eD98a9F09fC4cE57;

    /// The library's stub signature (`kernelDummyEcdsaSignature`): validation
    /// must fail cleanly (return 1), not revert, for gas estimation to work.
    bytes internal constant STUB_SIGNATURE =
        hex"fffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c";

    /// The 4-byte PermissionId of the permission userOp case (left-aligned in
    /// the 20-byte vId field of the nonce).
    bytes4 internal constant PERMISSION_ID = 0xdeadbeef;

    KernelFactory internal factory;
    HashOracle internal hashOracle;
    ChainAgnosticOracle internal chainAgnosticOracle;
    address internal localUups;
    address internal localImmutableEcdsa;
    string internal buf;

    // Scratch for the UUPS root case (split across two frames for stack room).
    address internal uupsValidator;
    address internal uupsSender;
    address internal uupsCanonicalSender;

    // Scratch for the non-root userOp cases (same stack-room pattern).
    address internal validatorModule;
    address internal validatorSender;
    address internal policyModule;
    address internal signerModule;
    address internal permissionSender;

    // Scratch for the enable-mode cases (ticket 05).
    address internal enableValidator;
    address internal enableSender;
    address internal enableTarget;
    bytes32 internal enableChainDigest;
    bytes32 internal enableSansDigest;
    bytes32 internal enableOpHash;
    bytes internal enableRootSig;
    bytes internal enableInnerSig;
    bytes internal enableBlob;
    bytes internal enableStubBlob;
    uint256 internal enableValidationData;
    uint256 internal enableWrongSignerVD;
    uint256 internal enableWrongDomainVD;
    uint256 internal enableStubVD;
    address internal enableReplaySender;
    bytes32 internal enableReplayChainDigest;
    bytes32 internal enableReplaySansDigest;
    bytes32 internal enableReplayOpHash;
    bytes internal enableReplayRootSig;
    bytes internal enableReplayInnerSig;
    bytes internal enableReplayBlob;
    uint256 internal enableReplayValidationData;
    uint256 internal enableReplayWrongDomainVD;
    address internal uupsEnableSender;
    address internal uupsEnableRootValidator;
    bytes32 internal uupsEnableDigest;
    bytes32 internal uupsEnableOpHash;
    bytes internal uupsEnableRootSig;
    bytes internal uupsEnableInnerSig;
    bytes internal uupsEnableBlob;
    uint256 internal uupsEnableValidationData;

    function run() external {
        hashOracle = new HashOracle();
        localUups = address(new KernelUUPS(IEntryPoint(ENTRY_POINT)));
        localImmutableEcdsa = address(new KernelImmutableECDSA(IEntryPoint(ENTRY_POINT)));
        factory = new KernelFactory(KernelUUPS(payable(localUups)), KernelImmutableECDSA(payable(localImmutableEcdsa)));

        buf = "{\n";
        _kv("_generator", "tool/kernel_v4_vectors -- regenerate, do not hand-edit");
        buf = string.concat(buf, ',\n  "entryPoint": "', vm.toString(ENTRY_POINT), '"');
        buf = string.concat(buf, ',\n  "chainId": ', vm.toString(block.chainid));
        buf = string.concat(buf, ',\n  "canonical": {');
        buf = string.concat(buf, '"staker": "', vm.toString(CANON_STAKER), '"');
        buf = string.concat(buf, ', "kernelUUPS": "', vm.toString(CANON_UUPS), '"');
        buf = string.concat(buf, ', "kernelImmutableECDSA": "', vm.toString(CANON_IMMUTABLE_ECDSA), '"');
        buf = string.concat(buf, ', "factory": "', vm.toString(CANON_FACTORY), '"');
        buf = string.concat(buf, "}");
        buf = string.concat(buf, ',\n  "localFactory": "', vm.toString(address(factory)), '"');
        buf = string.concat(buf, ',\n  "localKernelUUPS": "', vm.toString(localUups), '"');
        buf = string.concat(buf, ',\n  "localKernelImmutableECDSA": "', vm.toString(localImmutableEcdsa), '"');

        buf = string.concat(buf, ',\n  "addressCases": [\n');
        _addressCase("emptyNonce0", SIGNER, _noPackages(), 0, true);
        buf = string.concat(buf, ",\n");
        _addressCase("emptyNonce1", SIGNER, _noPackages(), 1, false);
        buf = string.concat(buf, ",\n");
        _addressCase("emptyNonceLarge", SIGNER, _noPackages(), 0xdeadbeefcafe, false);
        buf = string.concat(buf, ",\n");
        _addressCase("otherSigner", OTHER_SIGNER, _noPackages(), 0, false);
        buf = string.concat(buf, ",\n");
        _addressCase("oneValidatorPackage", SIGNER, _validatorPackage(), 0, false);
        buf = string.concat(buf, ",\n");
        _addressCase("twoPackages", SIGNER, _twoPackages(), 42, false);
        buf = string.concat(buf, ",\n");
        _addressCase("rootValidatorNonce1", SIGNER, _validatorPackage(), 1, false);
        buf = string.concat(buf, ",\n");
        _addressCase("rootValidatorOtherOwner", OTHER_SIGNER, _validatorPackageFor(OTHER_SIGNER), 0, false);
        buf = string.concat(buf, "\n  ]");

        _rootUserOpCase();
        _uupsRootUserOpCase();
        _executeCases();

        // Ticket-04 vectors. Deployed after the cases above so the extra
        // CREATE nonces do not shift the earlier local fixture addresses.
        chainAgnosticOracle = new ChainAgnosticOracle();
        // The chain-agnostic hash and its on-EVM acceptance need real
        // EntryPoint v0.9 code at the canonical address (`eip712Domain()` is
        // read live). Etch the vendored release bytecode there.
        vm.etch(ENTRY_POINT, address(new EntryPoint()).code);
        _nonceKeyCases();
        _validatorUserOpCase();
        _permissionUserOpCase();
        _replayableUserOpCase();

        // Ticket-05 vectors: enable-mode UserOperations.
        _enableUserOpCase();
        _enableReplayableUserOpCase();
        _uupsEnableUserOpCase();

        buf = string.concat(buf, "\n}\n");
        vm.writeFile(OUT_PATH, buf);
    }

    // ------------------------------------------------------------------
    // Address vectors
    // ------------------------------------------------------------------

    function _noPackages() internal pure returns (Install[] memory pkgs) {
        pkgs = new Install[](0);
    }

    /// A realistic root-validator install package (type 1, owner-packed data).
    function _validatorPackage() internal pure returns (Install[] memory pkgs) {
        return _validatorPackageFor(SIGNER);
    }

    function _validatorPackageFor(address owner) internal pure returns (Install[] memory pkgs) {
        pkgs = new Install[](1);
        pkgs[0] = Install({
            moduleType: 1,
            module: ECDSA_VALIDATOR,
            moduleData: abi.encodePacked(owner),
            internalData: hex""
        });
    }

    function _twoPackages() internal pure returns (Install[] memory pkgs) {
        pkgs = new Install[](2);
        pkgs[0] = Install({
            moduleType: 1,
            module: ECDSA_VALIDATOR,
            moduleData: abi.encodePacked(SIGNER),
            internalData: hex""
        });
        pkgs[1] = Install({
            moduleType: 2,
            module: 0x00000000000000000000000000000000DeaDBeef,
            moduleData: hex"deadbeef",
            internalData: hex"cafe"
        });
    }

    /// Byte-for-byte restatement of `KernelFactory._calculateSalt` using the
    /// same `EfficientHashLib` the factory compiles against. The public
    /// `getECDSAAddress` cross-check below keeps this honest.
    function _salt(Install[] memory packages, uint256 nonce) internal pure returns (bytes32) {
        bytes32[] memory buffer = EfficientHashLib.malloc(packages.length + 1);
        EfficientHashLib.set(buffer, 0, nonce);
        for (uint256 i = 1; i < buffer.length; i++) {
            Install memory pkg = packages[i - 1];
            EfficientHashLib.set(
                buffer,
                i,
                EfficientHashLib.hash(
                    bytes32(pkg.moduleType),
                    bytes32(uint256(uint160(pkg.module))),
                    keccak256(pkg.moduleData),
                    keccak256(pkg.internalData)
                )
            );
        }
        return EfficientHashLib.hash(buffer);
    }

    function _addressCase(
        string memory name,
        address signer,
        Install[] memory packages,
        uint256 nonce,
        bool deployAndCheck
    ) internal {
        bytes32 salt = _salt(packages, nonce);
        bytes memory args = abi.encodePacked(signer);

        address localAddress = factory.getECDSAAddress(signer, packages, nonce);
        address canonicalAddress =
            LibClone.predictDeterministicAddressERC1967(CANON_IMMUTABLE_ECDSA, args, salt, CANON_FACTORY);
        address localUupsAddress = factory.getAddress(packages, nonce);
        address canonicalUupsAddress = LibClone.predictDeterministicAddressERC1967(CANON_UUPS, salt, CANON_FACTORY);

        // Cross-check the restated salt/initcode math against the factory view.
        require(
            localAddress == LibClone.predictDeterministicAddressERC1967(localImmutableEcdsa, args, salt, address(factory)),
            "salt restatement drifted from factory.getECDSAAddress"
        );

        if (deployAndCheck) {
            address deployed = address(factory.deployECDSA(signer, packages, nonce));
            require(deployed == localAddress, "deployECDSA landed off the predicted address");
            require(deployed.code.length > 0, "deployECDSA produced no code");
        }

        bytes memory deployCalldata = abi.encodeCall(KernelFactory.deployECDSA, (signer, packages, nonce));
        bytes memory stakerCalldata = abi.encodeCall(IStaker.deployWithFactory, (CANON_FACTORY, deployCalldata));

        buf = string.concat(buf, '    {"name": "', name, '"');
        buf = string.concat(buf, ', "signer": "', vm.toString(signer), '"');
        buf = string.concat(buf, ', "nonce": "', vm.toString(nonce), '"');
        buf = string.concat(buf, ', "packages": [');
        for (uint256 i = 0; i < packages.length; i++) {
            if (i > 0) buf = string.concat(buf, ", ");
            buf = string.concat(buf, '{"moduleType": ', vm.toString(packages[i].moduleType));
            buf = string.concat(buf, ', "module": "', vm.toString(packages[i].module), '"');
            buf = string.concat(buf, ', "moduleData": "', vm.toString(packages[i].moduleData), '"');
            buf = string.concat(buf, ', "internalData": "', vm.toString(packages[i].internalData), '"}');
        }
        buf = string.concat(buf, "]");
        buf = string.concat(buf, ', "salt": "', vm.toString(salt), '"');
        buf = string.concat(
            buf,
            ', "canonicalInitCodeHash": "',
            vm.toString(LibClone.initCodeHashERC1967(CANON_IMMUTABLE_ECDSA, args)),
            '"'
        );
        buf = string.concat(
            buf, ', "canonicalInitCode": "', vm.toString(LibClone.initCodeERC1967(CANON_IMMUTABLE_ECDSA, args)), '"'
        );
        buf = string.concat(buf, ', "canonicalAddress": "', vm.toString(canonicalAddress), '"');
        buf = string.concat(buf, ', "canonicalUupsAddress": "', vm.toString(canonicalUupsAddress), '"');
        buf = string.concat(buf, ', "localAddress": "', vm.toString(localAddress), '"');
        buf = string.concat(buf, ', "localUupsAddress": "', vm.toString(localUupsAddress), '"');
        buf = string.concat(buf, ', "deployEcdsaCalldata": "', vm.toString(deployCalldata), '"');
        buf = string.concat(buf, ', "deployWithFactoryCalldata": "', vm.toString(stakerCalldata), '"');
        _appendUupsDeployCalldata(packages, nonce);
        buf = string.concat(buf, "}");
    }

    /// Emits the UUPS `deploy` / staker-wrapped calldata fields for a case
    /// (split out of `_addressCase` to stay within the stack limit).
    function _appendUupsDeployCalldata(Install[] memory packages, uint256 nonce) internal {
        bytes memory deployCalldata = abi.encodeCall(KernelFactory.deploy, (packages, nonce));
        bytes memory stakerCalldata = abi.encodeCall(IStaker.deployWithFactory, (CANON_FACTORY, deployCalldata));
        buf = string.concat(buf, ', "deployUupsCalldata": "', vm.toString(deployCalldata), '"');
        buf = string.concat(buf, ', "deployUupsWithFactoryCalldata": "', vm.toString(stakerCalldata), '"');
    }

    // ------------------------------------------------------------------
    // Root userOp acceptance
    // ------------------------------------------------------------------

    function _userOpHash(PackedUserOperation memory op) internal view returns (bytes32) {
        return hashOracle.userOpHash(op, block.chainid, ENTRY_POINT);
    }

    function _rootUserOpCase() internal {
        // The account deployed by the `emptyNonce0` case above.
        address account = factory.getECDSAAddress(SIGNER, _noPackages(), 0);
        Target target = new Target();

        bytes memory execData = abi.encodePacked(address(target), uint256(0), abi.encodeCall(Target.setX, (42)));
        bytes memory callData = abi.encodeCall(Kernel.execute, (bytes32(0), execData));

        PackedUserOperation memory op = PackedUserOperation({
            sender: account,
            nonce: 0, // vMode 0x00 (standard), vType 0x00 (root), vId 0, key 0, seq 0
            initCode: hex"",
            callData: callData,
            accountGasLimits: bytes32((uint256(200000) << 128) | uint256(100000)),
            preVerificationGas: 50000,
            gasFees: bytes32((uint256(1 gwei) << 128) | uint256(2 gwei)),
            paymasterAndData: hex"",
            signature: hex""
        });

        bytes32 opHash = _userOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, opHash);
        // Struct assignment in memory aliases, so keep the good signature in
        // its own variable and restore it before emitting the fixture.
        bytes memory goodSignature = abi.encodePacked(r, s, v);

        op.signature = goodSignature;
        vm.prank(ENTRY_POINT);
        uint256 validationData = Kernel(payable(account)).validateUserOp(op, opHash, 0);
        require(validationData == 0, "root ECDSA signature was not accepted");

        (v, r, s) = vm.sign(WRONG_KEY, opHash);
        op.signature = abi.encodePacked(r, s, v);
        vm.prank(ENTRY_POINT);
        uint256 wrongSignerValidationData = Kernel(payable(account)).validateUserOp(op, opHash, 0);
        require(wrongSignerValidationData == 1, "wrong-signer signature unexpectedly accepted");

        op.signature = STUB_SIGNATURE;
        vm.prank(ENTRY_POINT);
        uint256 stubValidationData = Kernel(payable(account)).validateUserOp(op, opHash, 0);
        require(stubValidationData == 1, "stub signature must fail cleanly, not revert");

        op.signature = goodSignature;

        buf = string.concat(buf, ',\n  "rootUserOp": {');
        buf = string.concat(buf, '"sender": "', vm.toString(op.sender), '"');
        buf = string.concat(buf, ', "signer": "', vm.toString(SIGNER), '"');
        buf = string.concat(buf, ', "nonce": "', vm.toString(op.nonce), '"');
        buf = string.concat(buf, ', "callData": "', vm.toString(op.callData), '"');
        buf = string.concat(buf, ', "callGasLimit": 100000');
        buf = string.concat(buf, ', "verificationGasLimit": 200000');
        buf = string.concat(buf, ', "preVerificationGas": 50000');
        buf = string.concat(buf, ', "maxFeePerGas": ', vm.toString(uint256(2 gwei)));
        buf = string.concat(buf, ', "maxPriorityFeePerGas": ', vm.toString(uint256(1 gwei)));
        buf = string.concat(buf, ', "userOpHash": "', vm.toString(opHash), '"');
        buf = string.concat(buf, ', "signature": "', vm.toString(op.signature), '"');
        buf = string.concat(buf, ', "validationData": ', vm.toString(validationData));
        buf = string.concat(buf, ', "wrongSignerValidationData": ', vm.toString(wrongSignerValidationData));
        buf = string.concat(buf, ', "stubSignatureValidationData": ', vm.toString(stubValidationData));
        buf = string.concat(buf, "}");
    }

    /// UUPS variant of the root case: the root validator is packages[0] of
    /// `factory.deploy` (a [RootEcdsaValidator] with raw-digest recovery), and
    /// root-type UserOperations still carry the raw 65-byte signature.
    function _uupsRootUserOpCase() internal {
        RootEcdsaValidator validator = new RootEcdsaValidator();
        Install[] memory pkgs = new Install[](1);
        pkgs[0] =
            Install({moduleType: 1, module: address(validator), moduleData: abi.encodePacked(SIGNER), internalData: hex""});

        uupsValidator = address(validator);
        uupsSender = address(factory.deploy(pkgs, 0));
        require(uupsSender == factory.getAddress(pkgs, 0), "deploy landed off factory.getAddress");
        require(uupsSender.code.length > 0, "deploy produced no code");
        uupsCanonicalSender = LibClone.predictDeterministicAddressERC1967(CANON_UUPS, _salt(pkgs, 0), CANON_FACTORY);

        _uupsRootUserOpValidateAndEmit();
    }

    function _uupsRootUserOpValidateAndEmit() internal {
        address account = uupsSender;
        Target target = new Target();
        bytes memory execData = abi.encodePacked(address(target), uint256(0), abi.encodeCall(Target.setX, (42)));
        bytes memory callData = abi.encodeCall(Kernel.execute, (bytes32(0), execData));

        PackedUserOperation memory op = PackedUserOperation({
            sender: account,
            nonce: 0, // vMode 0x00 (standard), vType 0x00 (root), vId 0, key 0, seq 0
            initCode: hex"",
            callData: callData,
            accountGasLimits: bytes32((uint256(200000) << 128) | uint256(100000)),
            preVerificationGas: 50000,
            gasFees: bytes32((uint256(1 gwei) << 128) | uint256(2 gwei)),
            paymasterAndData: hex"",
            signature: hex""
        });

        bytes32 opHash = _userOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, opHash);
        bytes memory goodSignature = abi.encodePacked(r, s, v);

        op.signature = goodSignature;
        vm.prank(ENTRY_POINT);
        uint256 validationData = Kernel(payable(account)).validateUserOp(op, opHash, 0);
        require(validationData == 0, "UUPS root ECDSA signature was not accepted");

        (v, r, s) = vm.sign(WRONG_KEY, opHash);
        op.signature = abi.encodePacked(r, s, v);
        vm.prank(ENTRY_POINT);
        uint256 wrongSignerValidationData = Kernel(payable(account)).validateUserOp(op, opHash, 0);
        require(wrongSignerValidationData == 1, "UUPS wrong-signer signature unexpectedly accepted");

        op.signature = STUB_SIGNATURE;
        vm.prank(ENTRY_POINT);
        uint256 stubValidationData = Kernel(payable(account)).validateUserOp(op, opHash, 0);
        require(stubValidationData == 1, "UUPS stub signature must fail cleanly, not revert");

        op.signature = goodSignature;

        buf = string.concat(buf, ',\n  "uupsRootUserOp": {');
        buf = string.concat(buf, '"sender": "', vm.toString(op.sender), '"');
        buf = string.concat(buf, ', "canonicalSender": "', vm.toString(uupsCanonicalSender), '"');
        buf = string.concat(buf, ', "rootValidator": "', vm.toString(uupsValidator), '"');
        buf = string.concat(buf, ', "signer": "', vm.toString(SIGNER), '"');
        buf = string.concat(buf, ', "nonce": "', vm.toString(op.nonce), '"');
        buf = string.concat(buf, ', "callData": "', vm.toString(op.callData), '"');
        buf = string.concat(buf, ', "callGasLimit": 100000');
        buf = string.concat(buf, ', "verificationGasLimit": 200000');
        buf = string.concat(buf, ', "preVerificationGas": 50000');
        buf = string.concat(buf, ', "maxFeePerGas": ', vm.toString(uint256(2 gwei)));
        buf = string.concat(buf, ', "maxPriorityFeePerGas": ', vm.toString(uint256(1 gwei)));
        buf = string.concat(buf, ', "userOpHash": "', vm.toString(opHash), '"');
        buf = string.concat(buf, ', "signature": "', vm.toString(op.signature), '"');
        buf = string.concat(buf, ', "validationData": ', vm.toString(validationData));
        buf = string.concat(buf, ', "wrongSignerValidationData": ', vm.toString(wrongSignerValidationData));
        buf = string.concat(buf, ', "stubSignatureValidationData": ', vm.toString(stubValidationData));
        buf = string.concat(buf, "}");
    }

    // ------------------------------------------------------------------
    // ERC-7579 execute round-trips
    // ------------------------------------------------------------------

    function _executeCases() internal {
        address account = factory.getECDSAAddress(SIGNER, _noPackages(), 0);
        vm.deal(account, 1 ether);
        Target target = new Target();

        // Single: execute(bytes32(0), to ‖ value ‖ data).
        bytes memory singleExec = abi.encodePacked(address(target), uint256(7), abi.encodeCall(Target.setX, (7)));
        bytes memory singleCallData = abi.encodeCall(Kernel.execute, (bytes32(0), singleExec));
        vm.prank(ENTRY_POINT);
        (bool ok,) = account.call{value: 0}(singleCallData);
        require(ok && target.x() == 7, "single execute round-trip failed");

        // Batch: execute(0x01 << 248, abi.encode(Execution[])).
        Execution[] memory execs = new Execution[](2);
        execs[0] = Execution({target: address(target), value: 0, callData: abi.encodeCall(Target.setX, (11))});
        execs[1] = Execution({target: address(target), value: 0, callData: abi.encodeCall(Target.setY, (12))});
        bytes32 batchMode = bytes32(uint256(0x01) << 248);
        bytes memory batchCallData = abi.encodeCall(Kernel.execute, (batchMode, abi.encode(execs)));
        vm.prank(ENTRY_POINT);
        (ok,) = account.call(batchCallData);
        require(ok && target.x() == 11 && target.y() == 12, "batch execute round-trip failed");

        buf = string.concat(buf, ',\n  "execute": {');
        buf = string.concat(buf, '"target": "', vm.toString(address(target)), '"');
        buf = string.concat(buf, ', "single": {"to": "', vm.toString(address(target)), '"');
        buf = string.concat(buf, ', "value": 7');
        buf = string.concat(buf, ', "data": "', vm.toString(abi.encodeCall(Target.setX, (7))), '"');
        buf = string.concat(buf, ', "callData": "', vm.toString(singleCallData), '"}');
        buf = string.concat(buf, ', "batch": {"calls": [');
        buf = string.concat(
            buf,
            '{"to": "',
            vm.toString(address(target)),
            '", "value": 0, "data": "',
            vm.toString(abi.encodeCall(Target.setX, (11))),
            '"}'
        );
        buf = string.concat(
            buf,
            ', {"to": "',
            vm.toString(address(target)),
            '", "value": 0, "data": "',
            vm.toString(abi.encodeCall(Target.setY, (12))),
            '"}'
        );
        buf = string.concat(buf, '], "callData": "', vm.toString(batchCallData), '"}');
        buf = string.concat(buf, "}");
    }

    // ------------------------------------------------------------------
    // Nonce key packing (ticket 04)
    // ------------------------------------------------------------------

    /// Byte-for-byte restatement of the pinned repo's own test-side encoder
    /// (`KernelTestBase.encodeNonce`): the 24-byte EntryPoint nonce key is
    /// `[1B vMode | 1B vType | 20B vId | 2B nonceKey]`, and `parseNonce`
    /// (src/lib/Utils.sol) reads exactly these positions. The non-root userOp
    /// cases below feed keys packed this way through the real Kernel, which
    /// keeps the restatement honest.
    function _packNonceKey(uint8 vMode, uint8 vType, bytes20 vId, uint16 nonceKey) internal pure returns (uint192) {
        return uint192(bytes24(abi.encodePacked(vMode, vType, vId, nonceKey)));
    }

    function _nonceKeyCases() internal {
        buf = string.concat(buf, ',\n  "nonceKeys": [\n');
        _nonceKeyCase("rootDefault", 0x00, 0x00, bytes20(0), 0, 0);
        buf = string.concat(buf, ",\n");
        _nonceKeyCase("rootParallelKey", 0x00, 0x00, bytes20(0), 0x0102, 7);
        buf = string.concat(buf, ",\n");
        _nonceKeyCase(
            "validator", 0x00, 0x01, bytes20(0x1111111111111111111111111111111111111111), 0, 1
        );
        buf = string.concat(buf, ",\n");
        _nonceKeyCase("permissionMaxKey", 0x00, 0x02, bytes20(PERMISSION_ID), 0xffff, 42);
        buf = string.concat(buf, ",\n");
        _nonceKeyCase("replayableRoot", 0x40, 0x00, bytes20(0), 0, 0);
        buf = string.concat(buf, ",\n");
        _nonceKeyCase(
            "replayableValidator", 0x40, 0x01, bytes20(0x2222222222222222222222222222222222222222), 1, 3
        );
        buf = string.concat(buf, ",\n");
        _nonceKeyCase(
            "enableValidator", 0x08, 0x01, bytes20(0x3333333333333333333333333333333333333333), 0, 0
        );
        buf = string.concat(buf, ",\n");
        _nonceKeyCase(
            "enableReplayableEnable", 0x0C, 0x01, bytes20(0x4444444444444444444444444444444444444444), 2, 5
        );
        buf = string.concat(buf, ",\n");
        _nonceKeyCase(
            "enableWithReplayableUserOp", 0x48, 0x01, bytes20(0x5555555555555555555555555555555555555555), 0, 1
        );
        buf = string.concat(buf, ",\n");
        _nonceKeyCase("allModeFlags", 0x4C, 0x02, bytes20(PERMISSION_ID), 3, 9);
        buf = string.concat(buf, "\n  ]");
    }

    function _nonceKeyCase(string memory name, uint8 vMode, uint8 vType, bytes20 vId, uint16 nonceKey, uint64 seq)
        internal
    {
        uint192 key = _packNonceKey(vMode, vType, vId, nonceKey);
        uint256 nonce = (uint256(key) << 64) | seq;
        buf = string.concat(buf, '    {"name": "', name, '"');
        buf = string.concat(buf, ', "vMode": ', vm.toString(uint256(vMode)));
        buf = string.concat(buf, ', "vType": ', vm.toString(uint256(vType)));
        buf = string.concat(buf, ', "vId": "', vm.toString(abi.encodePacked(vId)), '"');
        buf = string.concat(buf, ', "nonceKey": ', vm.toString(uint256(nonceKey)));
        buf = string.concat(buf, ', "sequence": ', vm.toString(uint256(seq)));
        buf = string.concat(buf, ', "key": "', vm.toString(uint256(key)), '"');
        buf = string.concat(buf, ', "nonce": "', vm.toString(nonce), '"}');
    }

    // ------------------------------------------------------------------
    // Non-root userOps (ticket 04)
    // ------------------------------------------------------------------

    /// The shared gas/op shape of every userOp acceptance case.
    function _defaultOp(address sender, uint256 nonce, bytes memory callData)
        internal
        pure
        returns (PackedUserOperation memory op)
    {
        op = PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: hex"",
            callData: callData,
            accountGasLimits: bytes32((uint256(200000) << 128) | uint256(100000)),
            preVerificationGas: 50000,
            gasFees: bytes32((uint256(1 gwei) << 128) | uint256(2 gwei)),
            paymasterAndData: hex"",
            signature: hex""
        });
    }

    function _emitGasFields() internal {
        buf = string.concat(buf, ', "callGasLimit": 100000');
        buf = string.concat(buf, ', "verificationGasLimit": 200000');
        buf = string.concat(buf, ', "preVerificationGas": 50000');
        buf = string.concat(buf, ', "maxFeePerGas": ', vm.toString(uint256(2 gwei)));
        buf = string.concat(buf, ', "maxPriorityFeePerGas": ', vm.toString(uint256(1 gwei)));
    }

    /// `execute(single: target.setX(42))` — the callData every ticket-04 case
    /// uses. Non-root validations only pass `validateUserOp` when the leading
    /// selector is allow-listed for the vId, which the install packages below
    /// grant for `Kernel.execute`.
    function _executeSetXCallData(Target target) internal pure returns (bytes memory) {
        return abi.encodeCall(
            Kernel.execute,
            (bytes32(0), abi.encodePacked(address(target), uint256(0), abi.encodeCall(Target.setX, (42))))
        );
    }

    /// A standard-mode userOp routed to an installed validator module
    /// (vType 0x01, vId = validator address). The validator's owner is
    /// deliberately a *different* key than the account's root fallback signer:
    /// acceptance of the validator owner's signature (and rejection of the
    /// root signer's) proves the nonce routing, not the fallback, validated
    /// the op.
    function _validatorUserOpCase() internal {
        RootEcdsaValidator validator = new RootEcdsaValidator();
        validatorModule = address(validator);
        Install[] memory pkgs = new Install[](1);
        pkgs[0] = Install({
            moduleType: 1,
            module: validatorModule,
            moduleData: abi.encodePacked(OTHER_SIGNER),
            // 20-byte zero hook (=> installed-no-hook sentinel) + allow-listed
            // `execute` selector.
            internalData: abi.encodePacked(address(0), Kernel.execute.selector)
        });
        validatorSender = address(factory.deployECDSA(SIGNER, pkgs, 100));
        _validatorUserOpValidateAndEmit();
    }

    function _validatorUserOpValidateAndEmit() internal {
        Target target = new Target();
        uint256 nonce = uint256(_packNonceKey(0x00, 0x01, bytes20(validatorModule), 0)) << 64;
        PackedUserOperation memory op = _defaultOp(validatorSender, nonce, _executeSetXCallData(target));

        bytes32 opHash = _userOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(WRONG_KEY, opHash); // OTHER_SIGNER owns the validator
        bytes memory goodSignature = abi.encodePacked(r, s, v);

        op.signature = goodSignature;
        vm.prank(ENTRY_POINT);
        uint256 validationData = Kernel(payable(validatorSender)).validateUserOp(op, opHash, 0);
        require(validationData == 0, "validator-routed signature was not accepted");

        (v, r, s) = vm.sign(SIGNER_KEY, opHash); // the root fallback signer must NOT pass here
        op.signature = abi.encodePacked(r, s, v);
        vm.prank(ENTRY_POINT);
        uint256 rootSignerValidationData = Kernel(payable(validatorSender)).validateUserOp(op, opHash, 0);
        require(rootSignerValidationData == 1, "root signer unexpectedly accepted on the validator path");

        op.signature = STUB_SIGNATURE;
        vm.prank(ENTRY_POINT);
        uint256 stubValidationData = Kernel(payable(validatorSender)).validateUserOp(op, opHash, 0);
        require(stubValidationData == 1, "validator stub signature must fail cleanly, not revert");

        op.signature = goodSignature;

        buf = string.concat(buf, ',\n  "validatorUserOp": {');
        buf = string.concat(buf, '"sender": "', vm.toString(op.sender), '"');
        buf = string.concat(buf, ', "validator": "', vm.toString(validatorModule), '"');
        buf = string.concat(buf, ', "signer": "', vm.toString(OTHER_SIGNER), '"');
        buf = string.concat(buf, ', "rootSigner": "', vm.toString(SIGNER), '"');
        buf = string.concat(buf, ', "nonce": "', vm.toString(op.nonce), '"');
        buf = string.concat(buf, ', "callData": "', vm.toString(op.callData), '"');
        _emitGasFields();
        buf = string.concat(buf, ', "userOpHash": "', vm.toString(opHash), '"');
        buf = string.concat(buf, ', "signature": "', vm.toString(op.signature), '"');
        buf = string.concat(buf, ', "validationData": ', vm.toString(validationData));
        buf = string.concat(buf, ', "rootSignerValidationData": ', vm.toString(rootSignerValidationData));
        buf = string.concat(buf, ', "stubSignatureValidationData": ', vm.toString(stubValidationData));
        buf = string.concat(buf, "}");
    }

    /// A standard-mode userOp routed to a permission (vType 0x02, vId =
    /// 4-byte PermissionId left-aligned). The signature is
    /// `abi.encode(bytes[])` — one chunk per policy in install order, the
    /// signer's chunk last (`PermissionSignature`, src/types/Structs.sol).
    /// The policy only passes on its exact proof bytes, so acceptance proves
    /// the chunk routing; the nonce also carries a non-zero 2-byte nonceKey
    /// to pin that byte lane on a real acceptance path.
    function _permissionUserOpCase() internal {
        policyModule = address(new ProofPolicy());
        signerModule = address(new EcdsaSigner());
        Install[] memory pkgs = new Install[](2);
        // All policies must precede the signer for the same PermissionId; the
        // signer install finalizes the permission.
        pkgs[0] = Install({
            moduleType: 5,
            module: policyModule,
            moduleData: hex"",
            internalData: abi.encodePacked(PERMISSION_ID)
        });
        pkgs[1] = Install({
            moduleType: 6,
            module: signerModule,
            moduleData: abi.encodePacked(OTHER_SIGNER),
            internalData: abi.encodePacked(PERMISSION_ID, address(0), Kernel.execute.selector)
        });
        permissionSender = address(factory.deployECDSA(SIGNER, pkgs, 101));
        _permissionUserOpValidateAndEmit();
    }

    function _permissionSignature(bytes memory policyChunk, bytes memory signerChunk)
        internal
        pure
        returns (bytes memory)
    {
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = policyChunk;
        signatures[1] = signerChunk;
        return abi.encode(signatures);
    }

    function _permissionUserOpValidateAndEmit() internal {
        Target target = new Target();
        uint256 nonce = uint256(_packNonceKey(0x00, 0x02, bytes20(PERMISSION_ID), 0x0102)) << 64;
        PackedUserOperation memory op = _defaultOp(permissionSender, nonce, _executeSetXCallData(target));

        bytes32 opHash = _userOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(WRONG_KEY, opHash); // OTHER_SIGNER owns the permission signer
        bytes memory signerChunk = abi.encodePacked(r, s, v);
        bytes memory goodSignature = _permissionSignature(hex"c0ffee", signerChunk);

        op.signature = goodSignature;
        vm.prank(ENTRY_POINT);
        uint256 validationData = Kernel(payable(permissionSender)).validateUserOp(op, opHash, 0);
        require(validationData == 0, "permission signature list was not accepted");

        (v, r, s) = vm.sign(SIGNER_KEY, opHash);
        op.signature = _permissionSignature(hex"c0ffee", abi.encodePacked(r, s, v));
        vm.prank(ENTRY_POINT);
        uint256 wrongSignerValidationData = Kernel(payable(permissionSender)).validateUserOp(op, opHash, 0);
        require(wrongSignerValidationData == 1, "wrong signer unexpectedly accepted on the permission path");

        op.signature = _permissionSignature(hex"baadf00d", signerChunk);
        vm.prank(ENTRY_POINT);
        uint256 wrongPolicyDataValidationData = Kernel(payable(permissionSender)).validateUserOp(op, opHash, 0);
        require(wrongPolicyDataValidationData == 1, "wrong policy chunk unexpectedly accepted");

        bytes memory stubSignature = _permissionSignature(hex"c0ffee", STUB_SIGNATURE);
        op.signature = stubSignature;
        vm.prank(ENTRY_POINT);
        uint256 stubValidationData = Kernel(payable(permissionSender)).validateUserOp(op, opHash, 0);
        require(stubValidationData == 1, "permission stub signature must fail cleanly, not revert");

        op.signature = goodSignature;

        buf = string.concat(buf, ',\n  "permissionUserOp": {');
        buf = string.concat(buf, '"sender": "', vm.toString(op.sender), '"');
        buf = string.concat(buf, ', "permissionId": "', vm.toString(abi.encodePacked(PERMISSION_ID)), '"');
        buf = string.concat(buf, ', "policy": "', vm.toString(policyModule), '"');
        buf = string.concat(buf, ', "signerModule": "', vm.toString(signerModule), '"');
        buf = string.concat(buf, ', "signer": "', vm.toString(OTHER_SIGNER), '"');
        buf = string.concat(buf, ', "policyData": "0xc0ffee"');
        buf = string.concat(buf, ', "nonceKey": 258');
        buf = string.concat(buf, ', "nonce": "', vm.toString(op.nonce), '"');
        buf = string.concat(buf, ', "callData": "', vm.toString(op.callData), '"');
        _emitGasFields();
        buf = string.concat(buf, ', "userOpHash": "', vm.toString(opHash), '"');
        buf = string.concat(buf, ', "signature": "', vm.toString(op.signature), '"');
        buf = string.concat(buf, ', "stubSignature": "', vm.toString(stubSignature), '"');
        buf = string.concat(buf, ', "validationData": ', vm.toString(validationData));
        buf = string.concat(buf, ', "wrongSignerValidationData": ', vm.toString(wrongSignerValidationData));
        buf = string.concat(buf, ', "wrongPolicyDataValidationData": ', vm.toString(wrongPolicyDataValidationData));
        buf = string.concat(buf, ', "stubSignatureValidationData": ', vm.toString(stubValidationData));
        buf = string.concat(buf, "}");
    }

    /// A replayable (nonce mode 0x40) root userOp: Kernel swaps the
    /// EntryPoint-supplied hash for `Lib4337.chainAgnosticUserOpHash` — the
    /// same v0.9 PackedUserOperation struct hash under an EIP-712 domain
    /// without a chainId — so the signature must be over that digest instead.
    /// The restated oracle, the pinned `Lib4337` (against the etched
    /// EntryPoint), and the real Kernel acceptance are all required to agree.
    function _replayableUserOpCase() internal {
        // The account deployed by the `emptyNonce0` case above.
        address account = factory.getECDSAAddress(SIGNER, _noPackages(), 0);
        Target target = new Target();
        uint256 nonce = uint256(_packNonceKey(0x40, 0x00, bytes20(0), 0)) << 64;
        PackedUserOperation memory op = _defaultOp(account, nonce, _executeSetXCallData(target));

        bytes32 standardHash = _userOpHash(op);
        bytes32 agnosticHash = hashOracle.chainAgnosticUserOpHash(op, ENTRY_POINT);
        require(
            agnosticHash == chainAgnosticOracle.hash(ENTRY_POINT, op),
            "restated chain-agnostic hash drifted from the pinned Lib4337"
        );
        require(agnosticHash != standardHash, "chain-agnostic hash should differ from the standard hash");

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, agnosticHash);
        bytes memory goodSignature = abi.encodePacked(r, s, v);

        // The EntryPoint passes the *standard* hash as the userOpHash argument
        // in the real flow; Kernel recomputes the chain-agnostic digest itself.
        op.signature = goodSignature;
        vm.prank(ENTRY_POINT);
        uint256 validationData = Kernel(payable(account)).validateUserOp(op, standardHash, 0);
        require(validationData == 0, "chain-agnostic signature was not accepted");

        (v, r, s) = vm.sign(SIGNER_KEY, standardHash);
        op.signature = abi.encodePacked(r, s, v);
        vm.prank(ENTRY_POINT);
        uint256 standardHashSignatureValidationData = Kernel(payable(account)).validateUserOp(op, standardHash, 0);
        require(
            standardHashSignatureValidationData == 1,
            "signature over the standard hash unexpectedly accepted in replayable mode"
        );

        op.signature = goodSignature;

        buf = string.concat(buf, ',\n  "replayableUserOp": {');
        buf = string.concat(buf, '"sender": "', vm.toString(op.sender), '"');
        buf = string.concat(buf, ', "signer": "', vm.toString(SIGNER), '"');
        buf = string.concat(buf, ', "nonce": "', vm.toString(op.nonce), '"');
        buf = string.concat(buf, ', "callData": "', vm.toString(op.callData), '"');
        _emitGasFields();
        buf = string.concat(buf, ', "standardUserOpHash": "', vm.toString(standardHash), '"');
        buf = string.concat(buf, ', "chainAgnosticUserOpHash": "', vm.toString(agnosticHash), '"');
        buf = string.concat(buf, ', "signature": "', vm.toString(op.signature), '"');
        buf = string.concat(buf, ', "validationData": ', vm.toString(validationData));
        buf = string.concat(
            buf, ', "standardHashSignatureValidationData": ', vm.toString(standardHashSignatureValidationData)
        );
        buf = string.concat(buf, "}");
    }

    // ------------------------------------------------------------------
    // Enable-mode userOps (ticket 05)
    // ------------------------------------------------------------------

    /// The package list every enable case installs: one validator module
    /// owned by OTHER_SIGNER, with a zero hook and the `execute` selector
    /// allow-listed (the same internalData shape as the ticket-04 validator
    /// case — required because non-root validations gate on the leading
    /// selector).
    function _enablePackages() internal view returns (Install[] memory) {
        return _enablePackagesFor(OTHER_SIGNER);
    }

    function _enablePackagesFor(address moduleOwner) internal view returns (Install[] memory pkgs) {
        pkgs = new Install[](1);
        pkgs[0] = Install({
            moduleType: 1,
            module: enableValidator,
            moduleData: abi.encodePacked(moduleOwner),
            internalData: abi.encodePacked(address(0), Kernel.execute.selector)
        });
    }

    /// Restatement of `ModuleManager._installHash` (EIP-712 array-of-structs
    /// hashing: keccak of the concatenated per-package struct hashes).
    function _installHash(Install[] memory packages) internal pure returns (bytes32) {
        bytes memory acc;
        for (uint256 i = 0; i < packages.length; i++) {
            acc = abi.encodePacked(
                acc,
                keccak256(
                    abi.encode(
                        INSTALL_STRUCT_HASH,
                        packages[i].moduleType,
                        packages[i].module,
                        keccak256(packages[i].moduleData),
                        keccak256(packages[i].internalData)
                    )
                )
            );
        }
        return keccak256(acc);
    }

    /// Restatement of the enable digest built by
    /// `ModuleManager._verifyInstallSignatureRaw`: the `InstallPackages`
    /// struct hash under the *account's* EIP-712 domain ("Kernel" / "0.4.0",
    /// verifyingContract = the account) — with the chainId field dropped when
    /// the nonce carries the enable-replayable bit (`0x04`). Kernel-side
    /// acceptance below keeps this honest.
    function _installDigest(address account, uint256 installNonce, Install[] memory packages, bool sansChainId)
        internal
        view
        returns (bytes32)
    {
        // Honesty checks: the pinned constants really are the keccak of the
        // documented type strings the Dart implementation hashes.
        require(
            INSTALL_PACKAGES_STRUCT_HASH
                == keccak256(
                    "InstallPackages(uint256 nonce,Install[] packages)Install(uint256 moduleType,address module,bytes moduleData,bytes internalData)"
                ),
            "InstallPackages typehash drifted"
        );
        require(
            INSTALL_STRUCT_HASH
                == keccak256("Install(uint256 moduleType,address module,bytes moduleData,bytes internalData)"),
            "Install typehash drifted"
        );
        bytes32 structHash =
            keccak256(abi.encode(INSTALL_PACKAGES_STRUCT_HASH, installNonce, _installHash(packages)));
        bytes32 domainSeparator = sansChainId
            ? keccak256(
                abi.encode(DOMAIN_TYPEHASH_SANS_CHAIN_ID, keccak256(bytes("Kernel")), keccak256(bytes("0.4.0")), account)
            )
            : keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes("Kernel")),
                    keccak256(bytes("0.4.0")),
                    block.chainid,
                    account
                )
            );
        return keccak256(abi.encodePacked(hex"1901", domainSeparator, structHash));
    }

    function _sign(uint256 key, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    /// The `EnableModeSignature` blob carried in `userOp.signature`:
    /// `abi.encode(uint256 nonce, Install[] packages, bytes enableSignature,
    /// bytes userOpSignature)` — the tuple encoding Kernel's
    /// `sig := signature.offset` calldata cast expects (no extra wrapper
    /// offset word).
    function _enableModeSignature(
        uint256 installNonce,
        Install[] memory packages,
        bytes memory enableSignature,
        bytes memory userOpSignature
    ) internal pure returns (bytes memory) {
        return abi.encode(installNonce, packages, enableSignature, userOpSignature);
    }

    /// Runs `validateUserOp` for an enable-mode op against [sender] and
    /// returns the validation data. Every call mutates the account (enable
    /// mode installs packages and consumes the install nonce even when the
    /// signature is invalid), so each assertion gets its own account.
    function _validateEnableOp(address sender, uint8 vMode, bytes memory signature)
        internal
        returns (uint256 validationData, bytes32 opHash)
    {
        uint256 nonce = uint256(_packNonceKey(vMode, 0x01, bytes20(enableValidator), 0)) << 64;
        PackedUserOperation memory op = _defaultOp(sender, nonce, _executeSetXCallData(Target(enableTarget)));
        opHash = _userOpHash(op);
        op.signature = signature;
        vm.prank(ENTRY_POINT);
        validationData = Kernel(payable(sender)).validateUserOp(op, opHash, 0);
    }

    /// Builds the full EnableModeSignature blob for [sender]'s enable op:
    /// signs the inner userOp signature with the enabled validator's owner
    /// key and wraps it with the given enable signature.
    function _enableBlobFor(address sender, uint8 vMode, bytes memory enableSignature)
        internal
        view
        returns (bytes memory blob)
    {
        uint256 nonce = uint256(_packNonceKey(vMode, 0x01, bytes20(enableValidator), 0)) << 64;
        PackedUserOperation memory op = _defaultOp(sender, nonce, _executeSetXCallData(Target(enableTarget)));
        bytes memory innerSig = _sign(WRONG_KEY, _userOpHash(op)); // OTHER_SIGNER owns the enabled validator
        blob = _enableModeSignature(0, _enablePackages(), enableSignature, innerSig);
    }

    /// The chain-specific enable case (nonce mode `0x08`): a fresh
    /// `KernelImmutableECDSA` account installs a validator module atomically
    /// with the first (non-deploy) op — the immutable fallback signer signs
    /// the InstallPackages digest, the module owner signs the userOpHash.
    /// Negative assertions each run on their own account (see
    /// [_validateEnableOp]).
    function _enableUserOpCase() internal {
        enableValidator = address(new RootEcdsaValidator());
        enableTarget = address(new Target());
        enableSender = address(factory.deployECDSA(SIGNER, _noPackages(), 200));

        Install[] memory pkgs = _enablePackages();
        enableChainDigest = _installDigest(enableSender, 0, pkgs, false);
        enableSansDigest = _installDigest(enableSender, 0, pkgs, true);
        enableRootSig = _sign(SIGNER_KEY, enableChainDigest);

        _enableUserOpValidate();
        _enableUserOpNegatives();
        _enableUserOpEmit();
    }

    function _enableUserOpValidate() internal {
        uint256 nonce = uint256(_packNonceKey(0x08, 0x01, bytes20(enableValidator), 0)) << 64;
        PackedUserOperation memory op = _defaultOp(enableSender, nonce, _executeSetXCallData(Target(enableTarget)));
        enableOpHash = _userOpHash(op);
        enableInnerSig = _sign(WRONG_KEY, enableOpHash);
        enableBlob = _enableModeSignature(0, _enablePackages(), enableRootSig, enableInnerSig);

        op.signature = enableBlob;
        vm.prank(ENTRY_POINT);
        enableValidationData = Kernel(payable(enableSender)).validateUserOp(op, enableOpHash, 0);
        require(enableValidationData == 0, "enable-mode signature was not accepted");

        // The install nonce was consumed: an identical replay must revert
        // (InvalidNonce), not validate.
        vm.prank(ENTRY_POINT);
        try Kernel(payable(enableSender)).validateUserOp(op, enableOpHash, 0) returns (uint256) {
            revert("install nonce replay unexpectedly accepted");
        } catch {}
    }

    function _enableUserOpNegatives() internal {
        // Wrong enable signer: the module owner cannot authorize its own
        // install; only the root (fallback) signer can.
        address sender = address(factory.deployECDSA(SIGNER, _noPackages(), 201));
        bytes memory enableSig = _sign(WRONG_KEY, _installDigest(sender, 0, _enablePackages(), false));
        (enableWrongSignerVD,) = _validateEnableOp(sender, 0x08, _enableBlobFor(sender, 0x08, enableSig));
        require(enableWrongSignerVD == 1, "non-root enable signature unexpectedly accepted");

        // Chain-agnostic digest under plain enable mode 0x08: the domain
        // must be chain-bound unless the 0x04 bit says otherwise.
        sender = address(factory.deployECDSA(SIGNER, _noPackages(), 202));
        enableSig = _sign(SIGNER_KEY, _installDigest(sender, 0, _enablePackages(), true));
        (enableWrongDomainVD,) = _validateEnableOp(sender, 0x08, _enableBlobFor(sender, 0x08, enableSig));
        require(enableWrongDomainVD == 1, "sans-chainId enable digest unexpectedly accepted in mode 0x08");

        // Estimation stub: both signature slots stubbed must fail cleanly,
        // not revert. When BOTH the enable and the inner validation fail,
        // `intersectValidationData(1, 1)` packs explicit no-expiry time
        // bounds around the failure flag, so only the low 160-bit
        // aggregator field (1 = sig failure) is asserted and emitted. The
        // byte-match target emitted for the Dart side is the main account's
        // stub blob (identical shape).
        sender = address(factory.deployECDSA(SIGNER, _noPackages(), 203));
        enableStubBlob = _enableModeSignature(0, _enablePackages(), STUB_SIGNATURE, STUB_SIGNATURE);
        (enableStubVD,) = _validateEnableOp(sender, 0x08, enableStubBlob);
        enableStubVD = uint160(enableStubVD);
        require(enableStubVD == 1, "enable stub signature must fail cleanly, not revert");
    }

    function _enableUserOpEmit() internal {
        buf = string.concat(buf, ',\n  "enableUserOp": {');
        buf = string.concat(buf, '"sender": "', vm.toString(enableSender), '"');
        buf = string.concat(buf, ', "rootSigner": "', vm.toString(SIGNER), '"');
        buf = string.concat(buf, ', "validator": "', vm.toString(enableValidator), '"');
        buf = string.concat(buf, ', "moduleOwner": "', vm.toString(OTHER_SIGNER), '"');
        buf = string.concat(buf, ', "installNonce": "0"');
        _emitPackages(_enablePackages());
        buf = string.concat(buf, ', "chainSpecificInstallDigest": "', vm.toString(enableChainDigest), '"');
        buf = string.concat(buf, ', "sansChainIdInstallDigest": "', vm.toString(enableSansDigest), '"');
        buf = string.concat(buf, ', "enableSignature": "', vm.toString(enableRootSig), '"');
        _emitEnableOpFields(0x08, enableOpHash);
        buf = string.concat(buf, ', "innerSignature": "', vm.toString(enableInnerSig), '"');
        buf = string.concat(buf, ', "signature": "', vm.toString(enableBlob), '"');
        buf = string.concat(buf, ', "stubSignature": "', vm.toString(enableStubBlob), '"');
        buf = string.concat(buf, ', "validationData": ', vm.toString(enableValidationData));
        buf = string.concat(buf, ', "wrongEnableSignerValidationData": ', vm.toString(enableWrongSignerVD));
        buf = string.concat(buf, ', "wrongDomainValidationData": ', vm.toString(enableWrongDomainVD));
        buf = string.concat(buf, ', "stubSignatureValidationData": ', vm.toString(enableStubVD));
        buf = string.concat(buf, "}");
    }

    /// Emits the shared op-shape fields of an enable case: the packed nonce,
    /// callData, gas fields, and userOpHash.
    function _emitEnableOpFields(uint8 vMode, bytes32 opHash) internal {
        uint256 nonce = uint256(_packNonceKey(vMode, 0x01, bytes20(enableValidator), 0)) << 64;
        buf = string.concat(buf, ', "nonce": "', vm.toString(nonce), '"');
        buf = string.concat(
            buf, ', "callData": "', vm.toString(_executeSetXCallData(Target(enableTarget))), '"'
        );
        _emitGasFields();
        buf = string.concat(buf, ', "userOpHash": "', vm.toString(opHash), '"');
    }

    function _emitPackages(Install[] memory packages) internal {
        buf = string.concat(buf, ', "packages": [');
        for (uint256 i = 0; i < packages.length; i++) {
            if (i > 0) buf = string.concat(buf, ", ");
            buf = string.concat(buf, '{"moduleType": ', vm.toString(packages[i].moduleType));
            buf = string.concat(buf, ', "module": "', vm.toString(packages[i].module), '"');
            buf = string.concat(buf, ', "moduleData": "', vm.toString(packages[i].moduleData), '"');
            buf = string.concat(buf, ', "internalData": "', vm.toString(packages[i].internalData), '"}');
        }
        buf = string.concat(buf, "]");
    }

    /// The replayable-enable case (nonce mode `0x0C` = enable `0x08` +
    /// enable-replayable `0x04`): the root signs the *sans-chainId*
    /// InstallPackages digest, so the same install authorization is portable
    /// across chains. The userOp hash itself stays chain-bound (bit `0x40`
    /// is a separate axis).
    function _enableReplayableUserOpCase() internal {
        enableReplaySender = address(factory.deployECDSA(SIGNER, _noPackages(), 204));

        Install[] memory pkgs = _enablePackages();
        enableReplayChainDigest = _installDigest(enableReplaySender, 0, pkgs, false);
        enableReplaySansDigest = _installDigest(enableReplaySender, 0, pkgs, true);
        enableReplayRootSig = _sign(SIGNER_KEY, enableReplaySansDigest);

        _enableReplayableValidate();
        _enableReplayableEmit();
    }

    function _enableReplayableValidate() internal {
        uint256 nonce = uint256(_packNonceKey(0x0C, 0x01, bytes20(enableValidator), 0)) << 64;
        PackedUserOperation memory op =
            _defaultOp(enableReplaySender, nonce, _executeSetXCallData(Target(enableTarget)));
        enableReplayOpHash = _userOpHash(op);
        enableReplayInnerSig = _sign(WRONG_KEY, enableReplayOpHash);
        enableReplayBlob = _enableModeSignature(0, _enablePackages(), enableReplayRootSig, enableReplayInnerSig);

        op.signature = enableReplayBlob;
        vm.prank(ENTRY_POINT);
        enableReplayValidationData = Kernel(payable(enableReplaySender)).validateUserOp(op, enableReplayOpHash, 0);
        require(enableReplayValidationData == 0, "replayable enable signature was not accepted");

        // The chain-bound digest must NOT pass once the 0x04 bit is set.
        address sender = address(factory.deployECDSA(SIGNER, _noPackages(), 205));
        bytes memory enableSig = _sign(SIGNER_KEY, _installDigest(sender, 0, _enablePackages(), false));
        (enableReplayWrongDomainVD,) = _validateEnableOp(sender, 0x0C, _enableBlobFor(sender, 0x0C, enableSig));
        require(
            enableReplayWrongDomainVD == 1, "chain-specific enable digest unexpectedly accepted in mode 0x0C"
        );
    }

    function _enableReplayableEmit() internal {
        buf = string.concat(buf, ',\n  "enableReplayableUserOp": {');
        buf = string.concat(buf, '"sender": "', vm.toString(enableReplaySender), '"');
        buf = string.concat(buf, ', "rootSigner": "', vm.toString(SIGNER), '"');
        buf = string.concat(buf, ', "validator": "', vm.toString(enableValidator), '"');
        buf = string.concat(buf, ', "moduleOwner": "', vm.toString(OTHER_SIGNER), '"');
        buf = string.concat(buf, ', "installNonce": "0"');
        _emitPackages(_enablePackages());
        buf = string.concat(buf, ', "chainSpecificInstallDigest": "', vm.toString(enableReplayChainDigest), '"');
        buf = string.concat(buf, ', "sansChainIdInstallDigest": "', vm.toString(enableReplaySansDigest), '"');
        buf = string.concat(buf, ', "enableSignature": "', vm.toString(enableReplayRootSig), '"');
        _emitEnableOpFields(0x0C, enableReplayOpHash);
        buf = string.concat(buf, ', "innerSignature": "', vm.toString(enableReplayInnerSig), '"');
        buf = string.concat(buf, ', "signature": "', vm.toString(enableReplayBlob), '"');
        buf = string.concat(buf, ', "validationData": ', vm.toString(enableReplayValidationData));
        buf = string.concat(
            buf, ', "chainSpecificDigestValidationData": ', vm.toString(enableReplayWrongDomainVD)
        );
        buf = string.concat(buf, "}");
    }

    /// The UUPS variant: the account's root is a *validator module* (not the
    /// immutable fallback), so the enable digest routes through the root
    /// validator's `isValidSignatureWithSender`. Proves the same Dart-side
    /// bytes work for both factory-deployed variants. Single-key on purpose
    /// (the root owner also owns the enabled module) — the common SDK flow;
    /// the ImmutableECDSA case above proves the two-key routing.
    function _uupsEnableUserOpCase() internal {
        RootEcdsaValidator rootValidator = new RootEcdsaValidator();
        uupsEnableRootValidator = address(rootValidator);
        Install[] memory rootPkgs = new Install[](1);
        rootPkgs[0] = Install({
            moduleType: 1,
            module: uupsEnableRootValidator,
            moduleData: abi.encodePacked(SIGNER),
            internalData: hex""
        });
        uupsEnableSender = address(factory.deploy(rootPkgs, 206));

        uupsEnableDigest = _installDigest(uupsEnableSender, 0, _enablePackagesFor(SIGNER), false);
        _uupsEnableValidate();
        _uupsEnableEmit();
    }

    function _uupsEnableValidate() internal {
        uupsEnableRootSig = _sign(SIGNER_KEY, uupsEnableDigest);
        uint256 nonce = uint256(_packNonceKey(0x08, 0x01, bytes20(enableValidator), 0)) << 64;
        PackedUserOperation memory op =
            _defaultOp(uupsEnableSender, nonce, _executeSetXCallData(Target(enableTarget)));
        uupsEnableOpHash = _userOpHash(op);
        uupsEnableInnerSig = _sign(SIGNER_KEY, uupsEnableOpHash);
        uupsEnableBlob = _enableModeSignature(0, _enablePackagesFor(SIGNER), uupsEnableRootSig, uupsEnableInnerSig);

        op.signature = uupsEnableBlob;
        vm.prank(ENTRY_POINT);
        uupsEnableValidationData = Kernel(payable(uupsEnableSender)).validateUserOp(op, uupsEnableOpHash, 0);
        require(uupsEnableValidationData == 0, "UUPS enable-mode signature was not accepted");
    }

    function _uupsEnableEmit() internal {
        buf = string.concat(buf, ',\n  "uupsEnableUserOp": {');
        buf = string.concat(buf, '"sender": "', vm.toString(uupsEnableSender), '"');
        buf = string.concat(buf, ', "rootValidator": "', vm.toString(uupsEnableRootValidator), '"');
        buf = string.concat(buf, ', "rootSigner": "', vm.toString(SIGNER), '"');
        buf = string.concat(buf, ', "validator": "', vm.toString(enableValidator), '"');
        buf = string.concat(buf, ', "moduleOwner": "', vm.toString(SIGNER), '"');
        buf = string.concat(buf, ', "installNonce": "0"');
        _emitPackages(_enablePackagesFor(SIGNER));
        buf = string.concat(buf, ', "chainSpecificInstallDigest": "', vm.toString(uupsEnableDigest), '"');
        buf = string.concat(buf, ', "enableSignature": "', vm.toString(uupsEnableRootSig), '"');
        _emitEnableOpFields(0x08, uupsEnableOpHash);
        buf = string.concat(buf, ', "innerSignature": "', vm.toString(uupsEnableInnerSig), '"');
        buf = string.concat(buf, ', "signature": "', vm.toString(uupsEnableBlob), '"');
        buf = string.concat(buf, ', "validationData": ', vm.toString(uupsEnableValidationData));
        buf = string.concat(buf, "}");
    }

    // ------------------------------------------------------------------
    // JSON plumbing
    // ------------------------------------------------------------------

    function _kv(string memory key, string memory value) internal {
        buf = string.concat(buf, '  "', key, '": "', value, '"');
    }
}

struct Execution {
    address target;
    uint256 value;
    bytes callData;
}
