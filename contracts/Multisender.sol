// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./interfaces/IMultisender.sol";

contract Multisender is IMultisender {
    IERC721Enumerable public immutable collection;

    /// @param collection_ Collection contract address.
    constructor(IERC721Enumerable collection_) {
        collection = collection_;
    }

    /// @inheritdoc IMultisender
    function multisend(address[] calldata accounts_) external {
        if (accounts_.length > 100 || accounts_.length == 0) {
            revert InvalidLength();
        }
        for (uint256 i = 0; i < accounts_.length; ) {
            collection.safeTransferFrom(msg.sender, accounts_[i], collection.tokenOfOwnerByIndex(msg.sender, 0));
            unchecked {
                ++i;
            }
        }
    }
}