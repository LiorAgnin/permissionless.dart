// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Kernel} from "@kernel/Kernel.sol";
import {KernelUUPS} from "@kernel/KernelUUPS.sol";
import {KernelImmutableECDSA} from "@kernel/KernelImmutableECDSA.sol";
import {KernelFactory} from "@kernel/KernelFactory.sol";
import {Install} from "@kernel/types/Structs.sol";
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

    KernelFactory internal factory;
    HashOracle internal hashOracle;
    address internal localUups;
    address internal localImmutableEcdsa;
    string internal buf;

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
        buf = string.concat(buf, "\n  ]");

        _rootUserOpCase();
        _executeCases();

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
        pkgs = new Install[](1);
        pkgs[0] = Install({
            moduleType: 1,
            module: ECDSA_VALIDATOR,
            moduleData: abi.encodePacked(SIGNER),
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
        buf = string.concat(buf, "}");
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
