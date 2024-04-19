// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract DataKeeper is Ownable {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    EnumerableSet.Bytes32Set private _merkleRoots;

    event MerkleRootAdded(bytes32 indexed merkleRoot);

    function addMerkleRoot(bytes32 merkleRoot_) external onlyOwner {
        _merkleRoots.add(merkleRoot_);
        emit MerkleRootAdded(merkleRoot_);
    }

    function numberOfRoots() external view returns (uint256) {
        return _merkleRoots.length();
    }

    function getMerkleRootAt(uint256 index_) external view returns (bytes32) {
        return _merkleRoots.at(index_);
    }

    function isMerkleRootInArray(bytes32 merkleRoot_) external view returns (bool) {
        return _merkleRoots.contains(merkleRoot_);
    }

    function verify(bytes32 merkleRoot_, bytes32 leaf_, bytes32[] calldata merkleProof_) external pure returns (bool isValid_) {
        assembly {
            let ptr := merkleProof_.offset
            for { let end := add(ptr, mul(0x20, merkleProof_.length)) } lt(ptr, end) { ptr := add(ptr, 0x20) } {
                let node := calldataload(ptr)
                switch lt(leaf_, node)
                case 1 {
                    mstore(0x00, leaf_)
                    mstore(0x20, node)
                }
                default {
                    mstore(0x00, node)
                    mstore(0x20, leaf_)
                }
                leaf_ := keccak256(0x00, 0x40)
            }
            isValid_ := eq(merkleRoot_, leaf_)
        }
    }
}