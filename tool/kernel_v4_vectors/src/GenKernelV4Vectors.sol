// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Kernel} from "@kernel/Kernel.sol";
import {KernelUUPS} from "@kernel/KernelUUPS.sol";
import {KernelImmutableECDSA} from "@kernel/KernelImmutableECDSA.sol";
import {KernelFactory} from "@kernel/KernelFactory.sol";
import {Install} from "@kernel/types/Structs.sol";
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
