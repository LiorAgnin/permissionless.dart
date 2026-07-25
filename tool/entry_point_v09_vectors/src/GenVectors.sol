// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@aa/interfaces/PackedUserOperation.sol";
import "./Oracle.sol";

/// Minimal subset of the Foundry cheatcode interface, declared inline so this
/// generator needs no `forge install` step.
interface Vm {
    function toString(bytes32 value) external pure returns (string memory);
    function toString(bytes memory value) external pure returns (string memory);
    function toString(uint256 value) external pure returns (string memory);
    function toString(address value) external pure returns (string memory);
    function writeFile(string calldata path, string calldata data) external;
}

/// @notice Generates the committed EntryPoint v0.9 hashing fixture consumed by
/// `test/utils/user_operation_hash_test.dart`.
///
/// Run with `forge script src/GenVectors.sol:GenVectors` from this directory.
/// See README.md.
contract GenVectors {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant OUT_PATH = "../../packages/permissionless/test/fixtures/entry_point_v09_vectors.json";

    uint256 internal constant CHAIN_ID = 1;
    address internal constant ENTRY_POINT = 0x433709009B8330FDa32311DF1C2AFA402eD8D009;
    address internal constant SENDER = 0x1234567890123456789012345678901234567890;
    address internal constant PAYMASTER = 0x00000000000000000000000000000000000000AA;
    address internal constant FACTORY = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
    address internal constant DELEGATE = 0xe6Cae83BdE06E4c305530e199D7217f42808555B;
    address internal constant EIP7702_MARKER = 0x7702000000000000000000000000000000000000;

    /// The 65-byte ECDSA-shaped paymaster signature used by the primary case.
    bytes internal constant PM_SIG_65 =
        hex"111111111111111111111111111111111111111111111111111111111111111122222222222222222222222222222222222222222222222222222222222222221b";

    /// A deliberately odd-length paymaster signature. Its userOpHash must equal
    /// the 65-byte case: the hash covers neither the signature nor its length.
    bytes internal constant PM_SIG_3 = hex"aabbcc";

    Oracle internal oracle;
    string internal buf;

    struct Case {
        string name;
        address factory;
        bytes factoryData;
        address delegate;
        address paymaster;
        bytes paymasterData;
        bytes paymasterSignature;
    }

    function run() external {
        oracle = new Oracle();

        buf = "{\n";
        _kv("_generator", "tool/entry_point_v09_vectors -- regenerate, do not hand-edit");
        _kv("entryPoint", vm.toString(ENTRY_POINT));
        _kvRaw("chainId", vm.toString(CHAIN_ID));
        _kv("domainSeparator", vm.toString(oracle.domainSeparator(CHAIN_ID, ENTRY_POINT)));
        _kv("paymasterSignatureMagic", "0x22e325a297439656");
        _kv("emptyPaymasterSignatureSuffix", vm.toString(oracle.encodePaymasterSignature(hex"")));

        buf = string.concat(buf, '  "cases": [\n');
        _case(Case("base", address(0), hex"", address(0), address(0), hex"", hex""), true);
        _case(Case("factory", FACTORY, hex"c0ffee", address(0), address(0), hex"", hex""), false);
        _case(Case("eip7702", EIP7702_MARKER, hex"beef", DELEGATE, address(0), hex"", hex""), false);
        _case(Case("eip7702NoPayload", EIP7702_MARKER, hex"", DELEGATE, address(0), hex"", hex""), false);
        _case(Case("paymaster", address(0), hex"", address(0), PAYMASTER, hex"d00d", hex""), false);
        _case(Case("paymasterEmptyData", address(0), hex"", address(0), PAYMASTER, hex"", hex""), false);
        _case(Case("paymasterSig65", address(0), hex"", address(0), PAYMASTER, hex"d00d", PM_SIG_65), false);
        _case(Case("paymasterSig3", address(0), hex"", address(0), PAYMASTER, hex"d00d", PM_SIG_3), false);
        _case(Case("paymasterSigNoData", address(0), hex"", address(0), PAYMASTER, hex"", PM_SIG_65), false);
        _case(Case("factoryAndPaymasterSig", FACTORY, hex"c0ffee", address(0), PAYMASTER, hex"d00d", PM_SIG_65), false);
        buf = string.concat(buf, "\n  ],\n");

        // paymasterData values that look like they carry a signature suffix,
        // pinning the detection boundaries in getPaymasterSignatureLength. None
        // of these is a real suffix, so all are expressible as plain
        // paymasterData with no paymasterSignature.
        buf = string.concat(buf, '  "suffixLookalikes": [\n');
        // 60 bytes total: ends with the magic but is below the 62-byte floor,
        // so the magic is data.
        _lookalike("magicBelowMinimumLength", 1, 2, hex"22e325a297439656", true);
        // Well-formed-looking suffix declaring a zero-length signature: the
        // contract reports length 0 and hashes the blob verbatim.
        _lookalike("magicWithZeroDeclaredLength", 60000, 70000, hex"d00d000022e325a297439656", false);
        // Exactly at the floor: 52 static bytes + 10 trailing bytes.
        _lookalike("magicAtMinimumLength", 60000, 70000, hex"000022e325a297439656", false);
        // Trailing 8 bytes that are not the magic.
        _lookalike("noMagic", 60000, 70000, hex"d00d0002deadbeefdeadbeef", false);
        buf = string.concat(buf, "\n  ]\n}\n");

        vm.writeFile(OUT_PATH, buf);
    }

    // ---------------------------------------------------------------- helpers

    function _kv(string memory k, string memory v) internal {
        buf = string.concat(buf, '  "', k, '": "', v, '",\n');
    }

    function _kvRaw(string memory k, string memory v) internal {
        buf = string.concat(buf, '  "', k, '": ', v, ",\n");
    }

    function _case(Case memory c, bool first) internal {
        bytes memory initCode = c.factory == address(0) ? bytes("") : abi.encodePacked(c.factory, c.factoryData);

        bytes32 overrideInitCodeHash = 0;
        if (c.delegate != address(0)) {
            overrideInitCodeHash = keccak256(abi.encodePacked(c.delegate, c.factoryData));
        }

        bytes memory paymasterAndData = c.paymaster == address(0)
            ? bytes("")
            : abi.encodePacked(
                c.paymaster,
                bytes16(uint128(60000)),
                bytes16(uint128(70000)),
                c.paymasterData,
                oracle.encodePaymasterSignature(c.paymasterSignature)
            );

        PackedUserOperation memory op = PackedUserOperation({
            sender: SENDER,
            nonce: 1,
            initCode: initCode,
            callData: hex"abcdef",
            accountGasLimits: bytes32(abi.encodePacked(bytes16(uint128(200000)), bytes16(uint128(100000)))),
            preVerificationGas: 50000,
            gasFees: bytes32(abi.encodePacked(bytes16(uint128(100000000)), bytes16(uint128(1000000000)))),
            paymasterAndData: paymasterAndData,
            signature: hex""
        });

        buf = string.concat(buf, first ? "    {" : ",\n    {");
        buf = string.concat(buf, '"name": "', c.name, '"');
        buf = string.concat(buf, ', "sender": "', vm.toString(SENDER), '"');
        buf = string.concat(buf, ', "nonce": 1');
        buf = string.concat(
            buf, ', "factory": ', c.factory == address(0) ? "null" : string.concat('"', vm.toString(c.factory), '"')
        );
        buf = string.concat(
            buf,
            ', "factoryData": ',
            c.factory == address(0) ? "null" : string.concat('"', vm.toString(c.factoryData), '"')
        );
        buf = string.concat(
            buf, ', "delegate": ', c.delegate == address(0) ? "null" : string.concat('"', vm.toString(c.delegate), '"')
        );
        buf = string.concat(buf, ', "callData": "0xabcdef"');
        buf = string.concat(buf, ', "callGasLimit": 100000, "verificationGasLimit": 200000');
        buf = string.concat(buf, ', "preVerificationGas": 50000');
        buf = string.concat(buf, ', "maxFeePerGas": 1000000000, "maxPriorityFeePerGas": 100000000');
        buf = string.concat(
            buf, ', "paymaster": ', c.paymaster == address(0) ? "null" : string.concat('"', vm.toString(c.paymaster), '"')
        );
        if (c.paymaster == address(0)) {
            buf = string.concat(buf, ', "paymasterVerificationGasLimit": null, "paymasterPostOpGasLimit": null');
            buf = string.concat(buf, ', "paymasterData": null');
        } else {
            buf = string.concat(buf, ', "paymasterVerificationGasLimit": 60000, "paymasterPostOpGasLimit": 70000');
            buf = string.concat(buf, ', "paymasterData": "', vm.toString(c.paymasterData), '"');
        }
        buf = string.concat(
            buf,
            ', "paymasterSignature": ',
            c.paymasterSignature.length == 0 ? "null" : string.concat('"', vm.toString(c.paymasterSignature), '"')
        );
        // The bytes actually hashed differ from the wire initCode for EIP-7702:
        // the EntryPoint substitutes the on-chain delegate for the 0x7702 marker.
        bytes memory hashedInitCode =
            c.delegate == address(0) ? initCode : abi.encodePacked(c.delegate, c.factoryData);

        buf = string.concat(buf, ', "expectedInitCode": "', vm.toString(initCode), '"');
        buf = string.concat(buf, ', "expectedHashedInitCode": "', vm.toString(hashedInitCode), '"');
        buf = string.concat(buf, ', "expectedPaymasterAndData": "', vm.toString(paymasterAndData), '"');
        buf = string.concat(
            buf, ', "expectedStructHash": "', vm.toString(oracle.structHash(op, overrideInitCodeHash)), '"'
        );
        buf = string.concat(
            buf,
            ', "expectedUserOpHash": "',
            vm.toString(oracle.userOpHash(op, overrideInitCodeHash, CHAIN_ID, ENTRY_POINT)),
            '"'
        );
        buf = string.concat(buf, "}");
    }

    function _lookalike(
        string memory name,
        uint128 verificationGasLimit,
        uint128 postOpGasLimit,
        bytes memory paymasterData,
        bool first
    ) internal {
        bytes memory paymasterAndData = abi.encodePacked(
            PAYMASTER, bytes16(verificationGasLimit), bytes16(postOpGasLimit), paymasterData
        );

        PackedUserOperation memory op = PackedUserOperation({
            sender: SENDER,
            nonce: 1,
            initCode: hex"",
            callData: hex"abcdef",
            accountGasLimits: bytes32(abi.encodePacked(bytes16(uint128(200000)), bytes16(uint128(100000)))),
            preVerificationGas: 50000,
            gasFees: bytes32(abi.encodePacked(bytes16(uint128(100000000)), bytes16(uint128(1000000000)))),
            paymasterAndData: paymasterAndData,
            signature: hex""
        });

        buf = string.concat(buf, first ? "    {" : ",\n    {");
        buf = string.concat(buf, '"name": "', name, '"');
        buf = string.concat(buf, ', "paymaster": "', vm.toString(PAYMASTER), '"');
        buf = string.concat(
            buf, ', "paymasterVerificationGasLimit": ', vm.toString(uint256(verificationGasLimit))
        );
        buf = string.concat(buf, ', "paymasterPostOpGasLimit": ', vm.toString(uint256(postOpGasLimit)));
        buf = string.concat(buf, ', "paymasterData": "', vm.toString(paymasterData), '"');
        buf = string.concat(buf, ', "paymasterAndData": "', vm.toString(paymasterAndData), '"');
        buf = string.concat(
            buf, ', "paymasterSignatureLength": ', vm.toString(oracle.paymasterSignatureLength(paymasterAndData))
        );
        buf = string.concat(
            buf, ', "paymasterSignature": "', vm.toString(oracle.paymasterSignature(paymasterAndData)), '"'
        );
        buf = string.concat(
            buf, ', "signedPaymasterData": "', vm.toString(oracle.signedPaymasterData(paymasterAndData)), '"'
        );
        buf = string.concat(
            buf, ', "expectedUserOpHash": "', vm.toString(oracle.userOpHash(op, 0, CHAIN_ID, ENTRY_POINT)), '"'
        );
        buf = string.concat(buf, "}");
    }
}
