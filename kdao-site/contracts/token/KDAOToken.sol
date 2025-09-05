// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/**
 * @title KDAOToken
 * @dev KDAO Token - KRC20/ERC20 compatible governance token for Kaspa DAO
 * @notice 150M total supply, no mint function, deflationary through burns
 * @author KDAO Development Team
 */
contract KDAOToken is 
    ERC20, 
    ERC20Burnable, 
    ERC20Snapshot, 
    AccessControl, 
    Pausable, 
    ERC20Permit, 
    ERC20Votes 
{
    // ============ Roles ============
    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    // ============ State Variables ============
    uint256 public constant TOTAL_SUPPLY = 150_000_000 * 10**18; // 150 Million KDAO
    uint256 public constant INITIAL_LIQUIDITY = 30_000_000 * 10**18; // 20% for initial liquidity
    uint256 public constant TREASURY_ALLOCATION = 45_000_000 * 10**18; // 30% for treasury
    uint256 public constant TEAM_ALLOCATION = 15_000_000 * 10**18; // 10% for team (vested)
    uint256 public constant STAKING_REWARDS = 30_000_000 * 10**18; // 20% for staking rewards
    uint256 public constant COMMUNITY_ALLOCATION = 30_000_000 * 10**18; // 20% for community/airdrops
    
    // Token Economics
    uint256 public totalBurned;
    uint256 public maxTransferAmount;
    bool public transferRestrictionEnabled;
    
    // Vesting
    mapping(address => VestingSchedule) public vestingSchedules;
    
    struct VestingSchedule {
        uint256 totalAmount;
        uint256 releasedAmount;
        uint256 startTime;
        uint256 cliffDuration;
        uint256 vestingDuration;
    }
    
    // Anti-whale mechanism
    mapping(address => bool) public isExemptFromLimit;
    uint256 public constant MAX_WALLET_PERCENTAGE = 200; // 2% of total supply
    uint256 public maxWalletAmount;
    
    // Fee structure (for future implementation)
    uint256 public transferFee = 0; // 0% initially, can be activated by governance
    uint256 public constant MAX_TRANSFER_FEE = 300; // Max 3%
    address public feeRecipient;
    
    // ============ Events ============
    event TokensBurned(address indexed burner, uint256 amount);
    event VestingScheduleCreated(address indexed beneficiary, uint256 amount, uint256 vestingDuration);
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event TransferFeeUpdated(uint256 oldFee, uint256 newFee);
    event MaxWalletAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event EmergencyWithdraw(address indexed to, uint256 amount);
    
    // ============ Constructor ============
    constructor(
        string memory _name,
        string memory _symbol,
        address _treasury,
        address _stakingRewards,
        address _team
    ) 
        ERC20(_name, _symbol)
        ERC20Permit(_name)
    {
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SNAPSHOT_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        
        // Mint total supply to contract first
        _mint(address(this), TOTAL_SUPPLY);
        
        // Distribute initial allocations
        _transfer(address(this), _treasury, TREASURY_ALLOCATION);
        _transfer(address(this), _stakingRewards, STAKING_REWARDS);
        _transfer(address(this), msg.sender, INITIAL_LIQUIDITY); // For DEX liquidity
        _transfer(address(this), msg.sender, COMMUNITY_ALLOCATION); // For airdrops/marketing
        
        // Setup team vesting (6 month cliff, 2 year total vesting)
        _createVestingSchedule(_team, TEAM_ALLOCATION, 180 days, 730 days);
        
        // Set initial parameters
        maxWalletAmount = (TOTAL_SUPPLY * MAX_WALLET_PERCENTAGE) / 10000;
        maxTransferAmount = TOTAL_SUPPLY / 100; // 1% max transfer initially
        feeRecipient = _treasury;
        
        // Exempt important addresses from limits
        isExemptFromLimit[address(this)] = true;
        isExemptFromLimit[_treasury] = true;
        isExemptFromLimit[_stakingRewards] = true;
        isExemptFromLimit[_team] = true;
        isExemptFromLimit[msg.sender] = true;
        
        // Delegate votes to self for initial setup
        _delegate(msg.sender, msg.sender);
    }
    
    // ============ Transfer Functions ============
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Snapshot) whenNotPaused {
        // Anti-whale check
        if (!isExemptFromLimit[to] && to != address(0)) {
            require(
                balanceOf(to) + amount <= maxWalletAmount,
                "Exceeds max wallet amount"
            );
        }
        
        // Transfer amount restriction
        if (transferRestrictionEnabled && !isExemptFromLimit[from]) {
            require(amount <= maxTransferAmount, "Exceeds max transfer amount");
        }
        
        super._beforeTokenTransfer(from, to, amount);
    }
    
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
        
        // Apply transfer fee if enabled
        if (transferFee > 0 && !isExemptFromLimit[from] && from != address(0) && to != address(0)) {
            uint256 feeAmount = (amount * transferFee) / 10000;
            if (feeAmount > 0) {
                _transfer(to, feeRecipient, feeAmount);
            }
        }
    }
    
    // ============ Vesting Functions ============
    
    function _createVestingSchedule(
        address _beneficiary,
        uint256 _amount,
        uint256 _cliff,
        uint256 _duration
    ) internal {
        require(_beneficiary != address(0), "Invalid beneficiary");
        require(_amount > 0, "Amount must be > 0");
        require(_duration > _cliff, "Duration must be > cliff");
        
        vestingSchedules[_beneficiary] = VestingSchedule({
            totalAmount: _amount,
            releasedAmount: 0,
            startTime: block.timestamp,
            cliffDuration: _cliff,
            vestingDuration: _duration
        });
        
        emit VestingScheduleCreated(_beneficiary, _amount, _duration);
    }
    
    function releaseVestedTokens() external {
        VestingSchedule storage schedule = vestingSchedules[msg.sender];
        require(schedule.totalAmount > 0, "No vesting schedule");
        
        uint256 vestedAmount = _computeVestedAmount(schedule);
        uint256 releasableAmount = vestedAmount - schedule.releasedAmount;
        
        require(releasableAmount > 0, "No tokens to release");
        
        schedule.releasedAmount += releasableAmount;
        _transfer(address(this), msg.sender, releasableAmount);
        
        emit TokensReleased(msg.sender, releasableAmount);
    }
    
    function _computeVestedAmount(VestingSchedule memory schedule) 
        internal 
        view 
        returns (uint256) 
    {
        if (block.timestamp < schedule.startTime + schedule.cliffDuration) {
            return 0;
        } else if (block.timestamp >= schedule.startTime + schedule.vestingDuration) {
            return schedule.totalAmount;
        } else {
            uint256 timeFromStart = block.timestamp - schedule.startTime;
            return (schedule.totalAmount * timeFromStart) / schedule.vestingDuration;
        }
    }
    
    function getVestedAmount(address _beneficiary) external view returns (uint256) {
        return _computeVestedAmount(vestingSchedules[_beneficiary]);
    }
    
    function getReleasableAmount(address _beneficiary) external view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[_beneficiary];
        return _computeVestedAmount(schedule) - schedule.releasedAmount;
    }
    
    // ============ Burn Functions ============
    
    function burn(uint256 amount) public override {
        super.burn(amount);
        totalBurned += amount;
        emit TokensBurned(msg.sender, amount);
    }
    
    function burnFrom(address account, uint256 amount) public override {
        super.burnFrom(account, amount);
        totalBurned += amount;
        emit TokensBurned(account, amount);
    }
    
    // ============ Admin Functions ============
    
    function snapshot() external onlyRole(SNAPSHOT_ROLE) returns (uint256) {
        return _snapshot();
    }
    
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    function setTransferFee(uint256 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_fee <= MAX_TRANSFER_FEE, "Fee too high");
        uint256 oldFee = transferFee;
        transferFee = _fee;
        emit TransferFeeUpdated(oldFee, _fee);
    }
    
    function setFeeRecipient(address _recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_recipient != address(0), "Invalid recipient");
        feeRecipient = _recipient;
    }
    
    function setMaxWalletAmount(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_amount >= TOTAL_SUPPLY / 1000, "Too restrictive"); // Min 0.1%
        uint256 oldAmount = maxWalletAmount;
        maxWalletAmount = _amount;
        emit MaxWalletAmountUpdated(oldAmount, _amount);
    }
    
    function setMaxTransferAmount(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_amount >= TOTAL_SUPPLY / 10000, "Too restrictive"); // Min 0.01%
        maxTransferAmount = _amount;
    }
    
    function setTransferRestriction(bool _enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        transferRestrictionEnabled = _enabled;
    }
    
    function setExemptFromLimit(address _account, bool _exempt) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        isExemptFromLimit[_account] = _exempt;
    }
    
    function emergencyWithdraw(address _to, uint256 _amount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_to != address(0), "Invalid recipient");
        _transfer(address(this), _to, _amount);
        emit EmergencyWithdraw(_to, _amount);
    }
    
    // ============ View Functions ============
    
    function getCirculatingSupply() external view returns (uint256) {
        return totalSupply() - balanceOf(address(this)) - totalBurned;
    }
    
    function getMaxSupply() external pure returns (uint256) {
        return TOTAL_SUPPLY;
    }
    
    // ============ Overrides ============
    
    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }
    
    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }
}