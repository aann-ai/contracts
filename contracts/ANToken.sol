// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";

import "./interfaces/IWormholeRelayer.sol";
import "./interfaces/IWormholeReceiver.sol";

contract ANToken is IERC20Metadata, IWormholeReceiver, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    using PRBMathUD60x18 for uint256;

    uint256 public constant MAXIMUM_SUPPLY = 100_000_000_000 ether;
    uint256 public constant MAXIMUM_GAS_LIMIT = 300_000;
    uint256 public constant MINIMUM_GAS_LIMIT = 100_000;
    uint256 public constant BASE_PERCENTAGE = 10_000;
    uint256 public constant MAXIMUM_BURN_PERCENTAGE = 400;
    uint256 public constant PURCHASE_PROTECTION_PERIOD = 3 minutes;
    uint256 public constant SALE_PROTECTION_PERIOD = 60 minutes;
    uint256 public constant LIMIT_DURING_PURCHASE_PROTECTION_PERIOD = 500_000 ether;
    bytes32 public constant LIQUIDITY_PROVIDER_ROLE = keccak256("LIQUIDITY_PROVIDER_ROLE");

    IWormholeRelayer public immutable wormholeRelayer;

    uint256 public gasLimit = 150_000;
    uint256 public cumulativeAdjustmentFactor = PRBMathUD60x18.fromUint(1);
    uint256 public tradingEnableTimestamp;
    uint256 public lastBurnTimestamp;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    bool public isTradingEnabled;
    bool public isMinted;

    EnumerableSet.AddressSet private _liquidityPools;
    EnumerableSet.AddressSet private _burnProtectedAccounts;

    mapping(address => bool) public isPurchaseMadeDuringProtectionPeriodByAccount;
    mapping(address => uint256) public availableAmountToPurchaseDuringProtectionPeriodByAccount;
    mapping(bytes32 => bool) public notUniqueHash;
    mapping(uint16 => address) public sourceAddresses;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    error EmptySetOfLiquidityPools();
    error TradingAlreadyEnabled();
    error ForbiddenToEnableTrading();
    error ZeroAddressEntry();
    error ForbiddenToMintTokens();
    error ForbiddenToBurnTokens();
    error MaximumBurnPercentageExceeded();
    error AlreadyInLiquidityPoolsSet(address account);
    error NotFoundInLiquidityPoolsSet(address account);
    error InvalidArrayLengths();
    error InvalidGasLimit();
    error InvalidTargetAddress();
    error InvalidCallee();
    error NotUniqueHash();
    error InvalidSourceAddress();
    error AlreadyInBurnProtectedAccountsSet();
    error NotFoundInBurnProtectedAccountsSet();
    error ForbiddenToTransferTokens(address from, address to, uint256 amount);
    error ForbiddenToSaleTokens();

    event TradingEnabled(uint256 indexed tradingEnableTimestamp);
    event LiquidityPoolsAdded(address[] indexed liquidityPools);
    event LiquidityPoolsRemoved(address[] indexed liquidityPools);
    event SourceAddressesUpdated(uint16[] chainIds, address[] sourceAddresses);
    event GasLimitUpdated(uint256 indexed newGasLimit);
    event BurnProtectedAccountAdded(address indexed account);
    event BurnProtectedAccountRemoved(address indexed account);
    event MultichainTransferCompleted(address indexed from, address indexed to, uint256 indexed amount, uint16 sourceChain);

    constructor(IWormholeRelayer wormholeRelayer_, address liquidityProvider_) {
        wormholeRelayer = wormholeRelayer_;
        _name = "AN on BSC";
        _symbol = "AN";
        _burnProtectedAccounts.add(address(this));
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(LIQUIDITY_PROVIDER_ROLE, liquidityProvider_);
    }

    function enableTrading() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_liquidityPools.length() == 0) {
            revert EmptySetOfLiquidityPools();
        }
        if (isTradingEnabled) {
            revert TradingAlreadyEnabled();
        }
        if (!isMinted) {
            revert ForbiddenToEnableTrading();
        }
        isTradingEnabled = true;
        tradingEnableTimestamp = block.timestamp;
        lastBurnTimestamp = block.timestamp;
        emit TradingEnabled(block.timestamp);
    }

    function mint(address account_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account_ == address(0)) {
            revert ZeroAddressEntry();
        }
        if (isMinted) {
            revert ForbiddenToMintTokens();
        }
        unchecked {
            _totalSupply += MAXIMUM_SUPPLY;
            _balances[account_] += MAXIMUM_SUPPLY;
        }
        isMinted = true;
        emit Transfer(address(0), account_, MAXIMUM_SUPPLY);
    }

    function burn(uint256 percentage_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!isTradingEnabled || block.timestamp < lastBurnTimestamp + 30 days) {
            revert ForbiddenToBurnTokens();
        }
        if (percentage_ > MAXIMUM_BURN_PERCENTAGE) {
            revert MaximumBurnPercentageExceeded();
        }
        uint256 currentTotalSupply = _totalSupply;
        uint256 nonBurnableSupply = totalSupplyOfBurnProtectedAccounts();
        uint256 burnableSupply = currentTotalSupply - nonBurnableSupply;
        uint256 burnAmount = burnableSupply * percentage_ / BASE_PERCENTAGE;
        uint256 adjustmentFactor = burnableSupply.div(burnableSupply - burnAmount);
        cumulativeAdjustmentFactor = cumulativeAdjustmentFactor.mul(adjustmentFactor);
        _totalSupply = nonBurnableSupply + burnableSupply.div(adjustmentFactor);
        lastBurnTimestamp = block.timestamp;
        emit Transfer(address(this), address(0), currentTotalSupply - _totalSupply);
    }

    function addLiquidityPools(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; ) {
            if (!_liquidityPools.add(accounts_[i])) {
                revert AlreadyInLiquidityPoolsSet(accounts_[i]);
            }
            unchecked {
                ++i;
            }
        }
        emit LiquidityPoolsAdded(accounts_);
    }

    function removeLiquidityPools(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; ) {
            if (!_liquidityPools.remove(accounts_[i])) {
                revert NotFoundInLiquidityPoolsSet(accounts_[i]);
            }
            unchecked {
                ++i;
            }
        }
        emit LiquidityPoolsRemoved(accounts_);
    }

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

    function updateGasLimit(uint256 gasLimit_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (gasLimit < MINIMUM_GAS_LIMIT || gasLimit > MAXIMUM_GAS_LIMIT) {
            revert InvalidGasLimit();
        }
        gasLimit = gasLimit_;
        emit GasLimitUpdated(gasLimit_);
    }

    function approve(address spender_, uint256 amount_) external returns (bool) {
        if (msg.sender == address(0) || spender_ == address(0)) {
            revert ZeroAddressEntry();
        }
        _allowances[msg.sender][spender_] = amount_;
        emit Approval(msg.sender, spender_, amount_);
        return true;
    }

    function transfer(address to_, uint256 amount_) external returns (bool) {
        _transfer(msg.sender, to_, amount_);
        return true;
    }

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
            revert InvalidMsgValue(msg.value, cost);
        }
        if (msg.sender == address(0) || to_ == address(0)) {
            revert ZeroAddressEntry();
        }
        address target = sourceAddresses[targetChain_];
        if (target == address(0) || target != targetAddress_) {
            revert InvalidTargetAddress();
        }
        if (!isTradingEnabled && _hasLimits(msg.sender, to_)) {
            revert ForbiddenToTransferTokens(msg.sender, to_, amount_);
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
    
    function transferFrom(address from_, address to_, uint256 amount_) external returns (bool) {
        _allowances[from_][msg.sender] -= amount_;
        _transfer(from_, to_, amount_);
        return true;
    }

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
            revert InvalidMsgValue(msg.value, cost);
        }
        if (from_ == address(0) || to_ == address(0)) {
            revert ZeroAddressEntry();
        }
        address target = sourceAddresses[targetChain_];
        if (target == address(0) || target != targetAddress_) {
            revert InvalidTargetAddress();
        }
        if (!isTradingEnabled && _hasLimits(msg.sender, to_)) {
            revert ForbiddenToTransferTokens(msg.sender, to_, amount_);
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
        emit MultichainTransferCompleted(from, to, amount, sourceChain_);
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function allowance(address owner_, address spender_) external view returns (uint256) {
        return _allowances[owner_][spender_];
    }

    function name() external view returns (string memory) {
        return _name;
    }
    
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function isLiquidityPool(address account_) external view returns (bool) {
        return _liquidityPools.contains(account_);
    }

    function isBurnProtectedAccount(address account_) external view returns (bool) {
        return _burnProtectedAccounts.contains(account_);
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function addBurnProtectedAccount(address account_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_burnProtectedAccounts.add(account_)) {
            revert AlreadyInBurnProtectedAccountsSet();
        }
        _balances[account_] = _balances[account_].div(cumulativeAdjustmentFactor);
        emit BurnProtectedAccountAdded(account_);
    }

    function removeBurnProtectedAccount(address account_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_burnProtectedAccounts.remove(account_)) {
            revert NotFoundInBurnProtectedAccountsSet();
        }
        _balances[account_] = _balances[account_].mul(cumulativeAdjustmentFactor);
        emit BurnProtectedAccountRemoved(account_);
    }

    function balanceOf(address account_) public view returns (uint256) {
        if (_burnProtectedAccounts.contains(account_)) {
            return _balances[account_];
        } else {
            return _balances[account_].div(cumulativeAdjustmentFactor);
        }
    }

    function quoteEVMDeliveryPrice(uint16 targetChain_) public view returns (uint256 cost_) {
        (cost_, ) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain_, 0, gasLimit);
    }
    
    function totalSupplyOfBurnProtectedAccounts() public view returns (uint256 supply_) {
        uint256 length = _burnProtectedAccounts.length();
        for (uint256 i = 0; i < length; ) {
            unchecked {
                supply_ += _balances[_burnProtectedAccounts.at(i)];
                ++i;
            }
        }
    }

    function _transfer(address from_, address to_, uint256 amount_) private {
        if (from_ == address(0) || to_ == address(0)) {
            revert ZeroAddressEntry();
        }
        if (!isTradingEnabled) {
            if (_hasLimits(from_, to_)) {
                revert ForbiddenToTransferTokens(from_, to_, amount_);
            }
        } else {
            uint256 timeElapsed = block.timestamp - tradingEnableTimestamp;
            if (timeElapsed < PURCHASE_PROTECTION_PERIOD && _liquidityPools.contains(from_)) {
                if (!isPurchaseMadeDuringProtectionPeriodByAccount[tx.origin]) {
                    availableAmountToPurchaseDuringProtectionPeriodByAccount[tx.origin] 
                        = LIMIT_DURING_PURCHASE_PROTECTION_PERIOD - amount_;
                    isPurchaseMadeDuringProtectionPeriodByAccount[tx.origin] = true;
                } else {
                    availableAmountToPurchaseDuringProtectionPeriodByAccount[tx.origin] -= amount_;
                }
            }
            if (timeElapsed < SALE_PROTECTION_PERIOD && _liquidityPools.contains(to_)) {
                revert ForbiddenToSaleTokens();
            }
        }
        if (!_burnProtectedAccounts.contains(from_) && _burnProtectedAccounts.contains(to_)) {
            uint256 adjustedAmount = amount_.mul(cumulativeAdjustmentFactor);
            _balances[from_] -= adjustedAmount;
            _balances[to_] += amount_;
        } else if (_burnProtectedAccounts.contains(from_) && !_burnProtectedAccounts.contains(to_)) {
            uint256 adjustedAmount = amount_.mul(cumulativeAdjustmentFactor);
            _balances[from_] -= amount_;
            _balances[to_] += adjustedAmount;
        } else if (!_burnProtectedAccounts.contains(from_) && !_burnProtectedAccounts.contains(to_)) {
            uint256 adjustedAmount = amount_.mul(cumulativeAdjustmentFactor);
            _balances[from_] -= adjustedAmount;
            _balances[to_] += adjustedAmount;
        } else {
            _balances[from_] -= amount_;
            _balances[to_] += amount_;
        }
        emit Transfer(from_, to_, amount_);
    }

    function _mint(address account_, uint256 amount_) private {
        _totalSupply += amount_;
        if (_burnProtectedAccounts.contains(account_)) {
            _balances[account_] += amount_;
        } else {
            uint256 adjustedAmount = amount_.mul(cumulativeAdjustmentFactor);
            _balances[account_] += adjustedAmount;
        }
        emit Transfer(address(0), account_, amount_);
    }
    
    function _burn(address account_, uint256 amount_) private {
        _totalSupply -= amount_;
        if (_burnProtectedAccounts.contains(account_)) {
            _balances[account_] -= amount_;
        } else {
            uint256 adjustedAmount = amount_.mul(cumulativeAdjustmentFactor);
            _balances[account_] -= adjustedAmount;
        }
        emit Transfer(account_, address(0), amount_);
    }

    function _hasLimits(address from_, address to_) private view returns (bool) {
        return !hasRole(LIQUIDITY_PROVIDER_ROLE, from_) && !hasRole(LIQUIDITY_PROVIDER_ROLE, to_);
    }
}