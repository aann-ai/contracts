// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";

import "./interfaces/IWormholeReceiver.sol";
import "./interfaces/IWormholeRelayer.sol";

contract ANTokenMultichain is IERC20Metadata, IWormholeReceiver, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using PRBMathUD60x18 for uint256;

    uint256 public constant MAXIMUM_GAS_LIMIT = 300_000;
    uint256 public constant MINIMUM_GAS_LIMIT = 100_000;
    uint256 public constant BASE_PERCENTAGE = 10_000;
    uint256 public constant MAXIMUM_BURN_PERCENTAGE = 400;
    IWormholeRelayer public constant RELAYER = IWormholeRelayer(0x27428DD2d3DD32A4D7f7C497eAaa23130d894911);
    
    uint256 public gasLimit = 150_000;
    uint256 public cumulativeAdjustmentFactor = PRBMathUD60x18.fromUint(1);
    uint256 public lastBurnTimestamp;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    EnumerableSet.AddressSet private _burnProtectedAccounts;

    mapping(bytes32 => bool) public notUniqueHash;
    mapping(uint16 => address) public sourceAddresses;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    error ForbiddenToBurnTokens();
    error MaximumBurnPercentageExceeded();
    error ZeroAddressEntry();
    error InvalidArrayLengths();
    error InvalidGasLimit();
    error InvalidTargetAddress();
    error InvalidCallee();
    error NotUniqueHash();
    error InvalidSourceAddress();
    error AlreadyInBurnProtectedAccountsSet();
    error NotFoundInBurnProtectedAccountsSet();

    event SourceAddressesUpdated(uint16[] chainIds, address[] sourceAddresses);
    event GasLimitUpdated(uint256 indexed newGasLimit);
    event MultichainTransferCompleted(address indexed from, address indexed to, uint256 indexed amount, uint16 sourceChain);
    event BurnProtectedAccountAdded(address indexed account);
    event BurnProtectedAccountRemoved(address indexed account);

    constructor() {
        _name = "AN on Ethereum";
        _symbol = "AN";
        _burnProtectedAccounts.add(address(this));
        lastBurnTimestamp = block.timestamp;
    }

    function burn(uint256 percentage_) external onlyOwner {
        if (block.timestamp < lastBurnTimestamp + 30 days) {
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

    function updateSourceAddresses(
        uint16[] calldata chainIds_, 
        address[] calldata sourceAddresses_
    ) 
        external 
        onlyOwner 
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

    function updateGasLimit(uint256 gasLimit_) external onlyOwner {
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
        _burn(msg.sender, amount_);
        RELAYER.sendPayloadToEvm{value: cost}(
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
        _allowances[from_][msg.sender] -= amount_;
        _burn(from_, amount_);
        RELAYER.sendPayloadToEvm{value: cost}(
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
        if (msg.sender != address(RELAYER)) {
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

    function isBurnProtectedAccount(address account_) external view returns (bool) {
        return _burnProtectedAccounts.contains(account_);
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function addBurnProtectedAccount(address account_) public onlyOwner {
        if (!_burnProtectedAccounts.add(account_)) {
            revert AlreadyInBurnProtectedAccountsSet();
        }
        _balances[account_] = _balances[account_].div(cumulativeAdjustmentFactor);
        emit BurnProtectedAccountAdded(account_);
    }

    function removeBurnProtectedAccount(address account_) public onlyOwner {
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
        (cost_, ) = RELAYER.quoteEVMDeliveryPrice(targetChain_, 0, gasLimit);
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
}