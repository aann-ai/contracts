// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";

import "./interfaces/IANTokenMultichain.sol";
import "./interfaces/IWormholeRelayer.sol";
import "./interfaces/IWormholeReceiver.sol";

contract ANTokenMultichain is IANTokenMultichain, IWormholeReceiver, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    using PRBMathUD60x18 for uint256;

    uint256 public constant MAXIMUM_GAS_LIMIT = 300_000;
    uint256 public constant MINIMUM_GAS_LIMIT = 100_000;
    uint256 public constant BASE_PERCENTAGE = 10_000;
    uint256 public constant MAXIMUM_BURN_PERCENTAGE = 400;
    uint256 public constant MAXIMUM_PERCENTAGE_OF_SALES_COMMISSION = 400;

    IWormholeRelayer public immutable wormholeRelayer;
    address public commissionRecipient;
    uint256 public gasLimit = 150_000;
    uint256 public percentageOfSalesCommission = 150;
    uint256 public cumulativeAdjustmentFactor = PRBMathUD60x18.fromUint(1);
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    EnumerableSet.AddressSet private _liquidityPools;
    EnumerableSet.AddressSet private _commissionExemptAccounts;
    EnumerableSet.AddressSet private _burnProtectedAccounts;

    mapping(bytes32 => bool) public notUniqueHash;
    mapping(uint16 => address) public sourceAddresses;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @param wormholeRelayer_ Wormhole relayer contract address.
    /// @param commissionRecipient_ Commission recipient address.
    constructor(IWormholeRelayer wormholeRelayer_, address commissionRecipient_) {
        wormholeRelayer = wormholeRelayer_;
        commissionRecipient = commissionRecipient_;
        _name = "AN on ETH";
        _symbol = "AN";
        _commissionExemptAccounts.add(commissionRecipient_);
        _burnProtectedAccounts.add(commissionRecipient_);
        _burnProtectedAccounts.add(address(this));
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @inheritdoc IANTokenMultichain
    function withdrawAccumulatedCommission() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 commissionAmount = _balances[address(this)];
        if (commissionAmount > 0) {
            _transfer(address(this), commissionRecipient, commissionAmount);
            emit AccumulatedCommissionWithdrawn(commissionAmount);
        }
    }

    /// @inheritdoc IANTokenMultichain
    function burn(uint256 percentage_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (percentage_ > MAXIMUM_BURN_PERCENTAGE) {
            revert MaximumBurnPercentageExceeded();
        }
        uint256 currentTotalSupply = _totalSupply;
        uint256 nonBurnableSupply = _totalSupplyOfBurnProtectedAccounts();
        uint256 burnableSupply = currentTotalSupply - nonBurnableSupply;
        uint256 burnAmount = currentTotalSupply * percentage_ / BASE_PERCENTAGE;
        uint256 adjustmentFactor = burnableSupply.div(burnableSupply - burnAmount);
        cumulativeAdjustmentFactor = cumulativeAdjustmentFactor.mul(adjustmentFactor);
        _totalSupply = nonBurnableSupply + burnableSupply.div(adjustmentFactor);
        emit Transfer(address(this), address(0), currentTotalSupply - _totalSupply);
    }

    /// @inheritdoc IANTokenMultichain
    function addLiquidityPools(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; ) {
            if (!_liquidityPools.add(accounts_[i])) {
                revert AlreadyInLiquidityPoolsSet({account: accounts_[i]});
            }
            unchecked {
                ++i;
            }
        }
        emit LiquidityPoolsAdded(accounts_);
    }

    /// @inheritdoc IANTokenMultichain
    function removeLiquidityPools(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; ) {
            if (!_liquidityPools.remove(accounts_[i])) {
                revert NotFoundInLiquidityPoolsSet({account: accounts_[i]});
            }
            unchecked {
                ++i;
            }
        }
        emit LiquidityPoolsRemoved(accounts_);
    }

    /// @inheritdoc IANTokenMultichain
    function addCommissionExemptAccounts(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; ) {
            if (!_commissionExemptAccounts.add(accounts_[i])) {
                revert AlreadyInCommissionExemptAccountsSet({account: accounts_[i]});
            }
            unchecked {
                ++i;
            }
        }
        emit CommissionExemptAccountsAdded(accounts_);
    }

    /// @inheritdoc IANTokenMultichain
    function removeCommissionExemptAccounts(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; ) {
            if (!_commissionExemptAccounts.remove(accounts_[i])) {
                revert NotFoundInCommissionExemptAccountsSet({account: accounts_[i]});
            }
            unchecked {
                ++i;
            }
        }
        emit CommissionExemptAccountsRemoved(accounts_);
    }

    /// @inheritdoc IANTokenMultichain
    function updateSourceAddresses(
        uint16[] calldata chainIds_, 
        address[] calldata sourceAddresses_
    ) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        if (chainIds_.length != sourceAddresses_.length) {
            revert InvalidArrayLengths();
        }
        for (uint256 i = 0; i < sourceAddresses_.length; ) {
            sourceAddresses[chainIds_[i]] = sourceAddresses_[i];
            unchecked {
                ++i;
            }
        }
        emit SourceAddressesUpdated(chainIds_, sourceAddresses_);
    }

    /// @inheritdoc IANTokenMultichain
    function updateGasLimit(uint256 gasLimit_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (gasLimit < MINIMUM_GAS_LIMIT && gasLimit > MAXIMUM_GAS_LIMIT) {
            revert InvalidGasLimit();
        }
        gasLimit = gasLimit_;
        emit GasLimitUpdated(gasLimit_);
    }

    /// @inheritdoc IANTokenMultichain
    function updateCommissionRecipient(address commissionRecipient_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address currentCommissionRecipient = commissionRecipient;
        if (currentCommissionRecipient == commissionRecipient_ || commissionRecipient_ == address(0)) {
            revert InvalidCommissionRecipient();
        }
        removeBurnProtectedAccount(currentCommissionRecipient);
        commissionRecipient = commissionRecipient_;
        addBurnProtectedAccount(commissionRecipient_);
        emit CommissionRecipientUpdated(commissionRecipient_);
    }

    /// @inheritdoc IANTokenMultichain
    function updatePercentageOfSalesCommission(
        uint256 percentageOfSalesCommission_
    )   
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        if (percentageOfSalesCommission_ > MAXIMUM_PERCENTAGE_OF_SALES_COMMISSION) {
            revert MaximumPercentageOfSalesCommissionExceeded();
        }
        percentageOfSalesCommission = percentageOfSalesCommission_;
        emit PercentageOfSalesCommissionUpdated(percentageOfSalesCommission_);
    }

    /// @inheritdoc IERC20
    function approve(address spender_, uint256 amount_) external returns (bool) {
        if (msg.sender == address(0) || spender_ == address(0)) {
            revert ZeroAddressEntry();
        }
        _allowances[msg.sender][spender_] = amount_;
        emit Approval(msg.sender, spender_, amount_);
        return true;
    }

    /// @inheritdoc IERC20
    function transfer(address to_, uint256 amount_) external returns (bool) {
        _transfer(msg.sender, to_, amount_);
        return true;
    }

    /// @inheritdoc IANTokenMultichain
    function transferMultichain(
        uint16 targetChain_, 
        address targetAddress_, 
        address to_, 
        uint256 amount_
    ) 
        external 
        payable
        returns (bool) 
    {
        uint256 cost = quoteEVMDeliveryPrice(targetChain_);
        if (msg.value != cost) {
            revert InvalidMsgValue();
        }
        if (msg.sender == address(0) || to_ == address(0)) {
            revert ZeroAddressEntry();
        }
        address target = sourceAddresses[targetChain_];
        if (target == address(0) || target != targetAddress_) {
            revert InvalidTargetAddress();
        }
        _burn(msg.sender, amount_);
        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain_,
            targetAddress_,
            abi.encode(msg.sender, to_, amount_),
            0,
            gasLimit
        );
        return true;
    }
    
    /// @inheritdoc IERC20
    function transferFrom(address from_, address to_, uint256 amount_) external returns (bool) {
        _allowances[from_][msg.sender] -= amount_;
        _transfer(from_, to_, amount_);
        return true;
    }

    /// @inheritdoc IANTokenMultichain
    function transferFromMultichain(
        uint16 targetChain_, 
        address targetAddress_, 
        address from_,
        address to_, 
        uint256 amount_
    ) 
        external 
        payable
        returns (bool) 
    {
        uint256 cost = quoteEVMDeliveryPrice(targetChain_);
        if (msg.value != cost) {
            revert InvalidMsgValue();
        }
        if (from_ == address(0) || to_ == address(0)) {
            revert ZeroAddressEntry();
        }
        address target = sourceAddresses[targetChain_];
        if (target == address(0) || target != targetAddress_) {
            revert InvalidTargetAddress();
        }
        _allowances[from_][msg.sender] -= amount_;
        _burn(from_, amount_);
        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain_,
            targetAddress_,
            abi.encode(from_, to_, amount_),
            0,
            gasLimit
        );
        return true;
    }

    /// @inheritdoc IWormholeReceiver
    function receiveWormholeMessages(
        bytes memory payload_,
        bytes[] memory,
        bytes32 sourceAddress_,
        uint16 sourceChain_,
        bytes32 deliveryHash_
    )
        external
        payable
    {
        if (msg.sender != address(wormholeRelayer)) {
            revert InvalidCallee();
        }
        if (notUniqueHash[deliveryHash_]) {
            revert NotUniqueHash();
        }
        if (sourceAddresses[sourceChain_] != address(uint160(uint256(sourceAddress_)))) {
            revert InvalidSourceAddress();
        }
        (address from, address to, uint256 amount) = abi.decode(payload_, (address, address, uint256));
        notUniqueHash[deliveryHash_] = true;
        _mint(to, amount);
        emit TokensReceived(from, to, amount, sourceChain_);
    }

    /// @inheritdoc IERC20
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @inheritdoc IERC20
    function allowance(address owner_, address spender_) external view returns (uint256) {
        return _allowances[owner_][spender_];
    }

    /// @inheritdoc IERC20Metadata
    function name() external view returns (string memory) {
        return _name;
    }
    
    /// @inheritdoc IERC20Metadata
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /// @inheritdoc IANTokenMultichain
    function isLiquidityPool(address account_) external view returns (bool) {
        return _liquidityPools.contains(account_);
    }

    /// @inheritdoc IANTokenMultichain
    function isCommissionExemptAccount(address account_) external view returns (bool) {
        return _commissionExemptAccounts.contains(account_);
    }

    /// @inheritdoc IANTokenMultichain
    function isBurnProtectedAccount(address account_) external view returns (bool) {
        return _burnProtectedAccounts.contains(account_);
    }

    /// @inheritdoc IERC20Metadata
    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// @inheritdoc IANTokenMultichain
    function addBurnProtectedAccount(address account_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_burnProtectedAccounts.add(account_)) {
            revert AlreadyInBurnProtectedAccountsSet();
        }
        _balances[account_] = _balances[account_].div(cumulativeAdjustmentFactor);
        emit BurnProtectedAccountAdded(account_);
    }

    /// @inheritdoc IANTokenMultichain
    function removeBurnProtectedAccount(address account_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_burnProtectedAccounts.remove(account_)) {
            revert NotFoundInBurnProtectedAccountsSet();
        }
        _balances[account_] = _balances[account_].mul(cumulativeAdjustmentFactor);
        emit BurnProtectedAccountRemoved(account_);
    }

    /// @inheritdoc IERC20
    function balanceOf(address account_) public view returns (uint256) {
        if (_burnProtectedAccounts.contains(account_)) {
            return _balances[account_];
        } else {
            return _balances[account_].div(cumulativeAdjustmentFactor);
        }
    }

    /// @inheritdoc IANTokenMultichain
    function quoteEVMDeliveryPrice(uint16 targetChain_) public view returns (uint256 cost_) {
        (cost_, ) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain_, 0, gasLimit);
    }

    /// @notice Moves `amount_` of tokens from `from_` to `to_`. 
    /// @param from_ Token sender.
    /// @param to_ Token receiver.
    /// @param amount_ Amount of tokens to transfer.
    function _transfer(address from_, address to_, uint256 amount_) private {
        if (from_ == address(0) || to_ == address(0)) {
            revert ZeroAddressEntry();
        }
        bool shouldTakeSalesCommission;
        if (!_commissionExemptAccounts.contains(from_) && _liquidityPools.contains(to_)) {
            shouldTakeSalesCommission = true;
        }
        uint256 adjustmentFactor = cumulativeAdjustmentFactor;
        uint256 adjustedAmount = amount_.mul(adjustmentFactor);
        uint256 amountToReceive = shouldTakeSalesCommission ? _takeSalesCommission(from_, amount_) : amount_;
        uint256 adjustedAmountToReceive = amountToReceive.mul(adjustmentFactor);
        if (!_burnProtectedAccounts.contains(from_) && _burnProtectedAccounts.contains(to_)) {
            _balances[from_] -= adjustedAmount;
            _balances[to_] += amountToReceive;
        } else if (_burnProtectedAccounts.contains(from_) && !_burnProtectedAccounts.contains(to_)) {
            _balances[from_] -= amount_;
            _balances[to_] += adjustedAmountToReceive;
        } else if (!_burnProtectedAccounts.contains(from_) && !_burnProtectedAccounts.contains(to_)) {
            _balances[from_] -= adjustedAmount;
            _balances[to_] += adjustedAmountToReceive;
        } else {
            _balances[from_] -= amount_;
            _balances[to_] += amountToReceive;
        }
        emit Transfer(from_, to_, amountToReceive);
    }

    /// @notice Creates the `amount_` tokens and assigns them to an `account_`, increasing the total supply.
    /// @param account_ Account address.
    /// @param amount_ Amount of tokens to mint.
    function _mint(address account_, uint256 amount_) private {
        _totalSupply += amount_;
        uint256 adjustedAmount = amount_.mul(cumulativeAdjustmentFactor);
        if (_burnProtectedAccounts.contains(account_)) {
            _balances[account_] += amount_;
        } else {
            _balances[account_] += adjustedAmount;
        }
        emit Transfer(address(0), account_, amount_);
    }
    
    /// @notice Burns the `amount_` tokens from an `account_`, reducing the total supply.
    /// @param account_ Account address.
    /// @param amount_ Amount of tokens to burn.
    function _burn(address account_, uint256 amount_) private {
        _totalSupply -= amount_;
        uint256 adjustedAmount = amount_.mul(cumulativeAdjustmentFactor);
        if (_burnProtectedAccounts.contains(account_)) {
            _balances[account_] -= amount_;
        } else {
            _balances[account_] -= adjustedAmount;
        }
        emit Transfer(account_, address(0), amount_);
    }

    /// @notice Takes the sales commission and transfers it to the balance of the contract.
    /// @param from_ Token sender.
    /// @param amount_ Amount of tokens to transfer.
    /// @return Amount of tokens to transfer including the sales commission.
    function _takeSalesCommission(address from_, uint256 amount_) private returns (uint256) {
        uint256 commissionAmount = amount_ * percentageOfSalesCommission / BASE_PERCENTAGE;
        if (commissionAmount > 0) {
            unchecked {
                _balances[address(this)] += commissionAmount;
            }
            emit Transfer(from_, address(this), commissionAmount);
        }
        return amount_ - commissionAmount;
    }

    /// @notice Retrieves the total supply of burn-protected accounts.
    /// @return supply_ Total supply of burn-protected accounts.
    function _totalSupplyOfBurnProtectedAccounts() private view returns (uint256 supply_) {
        uint256 length = _burnProtectedAccounts.length();
        for (uint256 i = 0; i < length; ) {
            unchecked {
                supply_ += _balances[_burnProtectedAccounts.at(i)];
                ++i;
            }
        }
    }
}