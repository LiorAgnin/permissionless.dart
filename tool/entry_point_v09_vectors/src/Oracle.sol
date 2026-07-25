// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@aa/interfaces/PackedUserOperation.sol";
import "@aa/core/UserOperationLib.sol";

/// @notice Thin external wrapper over the pinned EntryPoint v0.9 hashing
/// internals, so off-chain test vectors are generated from contract truth
/// rather than from a reimplementation.
///
/// Everything here delegates to `UserOperationLib` in the `account-abstraction`
/// checkout. The only logic that is restated is the EIP-712 domain separator
/// and the `\x19\x01` wrap, which `EntryPoint` inherits from OpenZeppelin's
/// `EIP712` (pulled in here would drag the whole EntryPoint dependency tree).
contract Oracle {
    using UserOperationLib for PackedUserOperation;

    /// Mirrors `EntryPoint.DOMAIN_NAME`.
    string internal constant DOMAIN_NAME = "ERC4337";

    /// Mirrors `EntryPoint.DOMAIN_VERSION`.
    string internal constant DOMAIN_VERSION = "1";

    bytes32 internal constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function domainSeparator(uint256 chainId, address entryPoint) public pure returns (bytes32) {
        return keccak256(
            abi.encode(TYPE_HASH, keccak256(bytes(DOMAIN_NAME)), keccak256(bytes(DOMAIN_VERSION)), chainId, entryPoint)
        );
    }

    /// EIP-712 struct hash of a PackedUserOperation under EntryPoint v0.9
    /// rules, including the paymasterSignature suffix strip.
    function structHash(PackedUserOperation calldata userOp, bytes32 overrideInitCodeHash)
        public
        pure
        returns (bytes32)
    {
        return userOp.hash(overrideInitCodeHash);
    }

    /// Equivalent to `EntryPoint.getUserOpHash`, with the EIP-7702 initCode
    /// hash override supplied explicitly instead of read from `sender.code`.
    function userOpHash(
        PackedUserOperation calldata userOp,
        bytes32 overrideInitCodeHash,
        uint256 chainId,
        address entryPoint
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(hex"1901", domainSeparator(chainId, entryPoint), userOp.hash(overrideInitCodeHash))
        );
    }

    function paymasterSignatureLength(bytes calldata paymasterAndData) public pure returns (uint256) {
        return UserOperationLib.getPaymasterSignatureLength(paymasterAndData);
    }

    function signedPaymasterData(bytes calldata paymasterAndData) public pure returns (bytes memory) {
        return UserOperationLib.getSignedPaymasterData(paymasterAndData);
    }

    function paymasterSignature(bytes calldata paymasterAndData) public pure returns (bytes memory) {
        return UserOperationLib.getPaymasterSignature(paymasterAndData);
    }

    function encodePaymasterSignature(bytes calldata sig) public pure returns (bytes memory) {
        return UserOperationLib.encodePaymasterSignature(sig);
    }
}
