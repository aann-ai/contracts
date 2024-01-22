// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface IMultisender {
    error InvalidLength();

    /// @notice Multisends NFTs to the specified accounts.
    /// @param accounts_ Account addresses.
    function multisend(address[] calldata accounts_) external;
}