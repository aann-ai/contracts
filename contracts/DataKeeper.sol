// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

contract DataKeeper is Ownable {
    bytes32 public merkleRoot;

    event MerkleRootUpdated(bytes32 indexed oldMerkleRoot, bytes32 indexed newMerkleRoot);

    function setMerkleRoot(bytes32 merkleRoot_) external onlyOwner {
        emit MerkleRootUpdated(merkleRoot, merkleRoot_);
        merkleRoot = merkleRoot_;
    }

    function verify(bytes32[] calldata merkleProof_, bytes32 merkleRoot_, bytes32 leaf_) external pure returns (bool isValid_) {
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