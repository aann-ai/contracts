// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IANTokenMultichain is IERC20Metadata {
    error ZeroAddressEntry();
    error MaximumBurnPercentageExceeded();
    error AlreadyInLiquidityPoolsSet(address account);
    error NotFoundInLiquidityPoolsSet(address account);
    error AlreadyInCommissionExemptAccountsSet(address account);
    error NotFoundInCommissionExemptAccountsSet(address account);
    error InvalidArrayLengths();
    error InvalidGasLimit();
    error InvalidCommissionRecipient();
    error MaximumPercentageOfSalesCommissionExceeded();
    error InvalidMsgValue();
    error InvalidTargetChain();
    error InvalidCallee();
    error NotUniqueHash();
    error InvalidSourceAddress();
    error AlreadyInBurnProtectedAccountsSet();
    error NotFoundInBurnProtectedAccountsSet();

    event AccumulatedCommissionWithdrawn(uint256 indexed commissionAmount);
    event LiquidityPoolsAdded(address[] indexed liquidityPools);
    event LiquidityPoolsRemoved(address[] indexed liquidityPools);
    event CommissionExemptAccountsAdded(address[] indexed accounts);
    event CommissionExemptAccountsRemoved(address[] indexed accounts);
    event SourceAddressesUpdated(uint16[] chainIds, address[] sourceAddresses);
    event GasLimitUpdated(uint256 indexed newGasLimit);
    event CommissionRecipientUpdated(address indexed newCommissionRecipient);
    event PercentageOfSalesCommissionUpdated(uint256 indexed newPercentageOfSalesCommission);
    event TokensReceived(address indexed from, address indexed to, uint256 indexed amount, uint16 sourceChain);
    event BurnProtectedAccountAdded(address indexed account);
    event BurnProtectedAccountRemoved(address indexed account);

    /// @notice Transfers the accumulated commission on the contract to the commission recipient.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    function withdrawAccumulatedCommission() external;

    /// @notice Transfers tokens via wormhole relayer.
    /// @param targetChain_ Wormhole representation of target chain id.
    /// @param targetAddress_ ANToken contract address on target chain.
    /// @param to_ Token receiver on target chain.
    /// @param amount_ Amount of tokens to transfer.
    function transferMultichain(
        uint16 targetChain_, 
        address targetAddress_, 
        address to_, 
        uint256 amount_
    ) 
        external 
        payable
        returns (bool);

    /// @notice Transfers tokens via wormhole relayer.
    /// @param targetChain_ Wormhole representation of target chain id.
    /// @param targetAddress_ ANToken contract address on target chain.
    /// @param from_ Token sender on source chain.
    /// @param to_ Token receiver on target chain.
    /// @param amount_ Amount of tokens to transfer.
    function transferFromMultichain(
        uint16 targetChain_, 
        address targetAddress_, 
        address from_,
        address to_, 
        uint256 amount_
    ) 
        external 
        payable
        returns (bool);

    /// @notice Destroys `percentage_` of total supply.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param percentage_ Percentage of total supply to destroy.
    function burn(uint256 percentage_) external;

    /// @notice Adds `accounts_` to the liquidity pools set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function addLiquidityPools(address[] calldata accounts_) external;

    /// @notice Removes `accounts_` from the liquidity pools set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function removeLiquidityPools(address[] calldata accounts_) external;

    /// @notice Adds `accounts_` to the commission exempt accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function addCommissionExemptAccounts(address[] calldata accounts_) external;

    /// @notice Removes `accounts_` from the commission exempt accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function removeCommissionExemptAccounts(address[] calldata accounts_) external;

    /// @notice Updates source addresses by chain id.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param chainIds_ Wormhole representation of chain ids.
    /// @param sourceAddresses_ Source chain contract addresses.
    function updateSourceAddresses(uint16[] calldata chainIds_, address[] calldata sourceAddresses_) external;

    /// @notice Updates the gas limit on multichain transfers.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param gasLimit_ New gas limit value.
    function updateGasLimit(uint256 gasLimit_) external;

    /// @notice Updates the commission recipient.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param commissionRecipient_ New commission recipient address.
    function updateCommissionRecipient(address commissionRecipient_) external;

    /// @notice Updates the percentage of sales commission.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param percentageOfSalesCommission_ New percentage of sales commission value.
    function updatePercentageOfSalesCommission(uint256 percentageOfSalesCommission_) external;

    /// @notice Adds `account_` to the burn-protected accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param account_ Account address.
    function addBurnProtectedAccount(address account_) external;

    /// @notice Removes `account_` from the burn-protected accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param account_ Account address.
    function removeBurnProtectedAccount(address account_) external;

    /// @notice Checks if `account_` is in the liquidity pools set.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether the `account_` is in the liquidity pools set.
    function isLiquidityPool(address account_) external view returns (bool);

    /// @notice Checks if `account_` is in the commission exempt accounts set.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether `account_` is in the commission exempt accounts set.
    function isCommissionExemptAccount(address account_) external view returns (bool);

    /// @notice Checks if `account_` is in the burn-protected accounts set.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether `account_` is in the burn-protected accounts set.
    function isBurnProtectedAccount(address account_) external view returns (bool);

    /// @notice Retrieves the price for transaction via wormhole relayer.
    /// @param targetChain_ Wormhole representation of target chain id.
    function quoteEVMDeliveryPrice(uint16 targetChain_) external view returns (uint256 cost_);
}