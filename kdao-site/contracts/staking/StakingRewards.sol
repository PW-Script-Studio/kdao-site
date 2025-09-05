// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title StakingRewards
 * @dev Staking contract for KDAO with dynamic APY and liquidity mining support
 * @notice Supports single staking, LP staking, and auto-compounding
 * @author KDAO Development Team
 */
contract StakingRewards is AccessControl, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // ============ Roles ============
    bytes32 public constant REWARDS_MANAGER_ROLE = keccak256("REWARDS_MANAGER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    
    // ============ State Variables ============
    IERC20 public immutable kdaoToken;
    IERC20 public immutable lpToken;  // KDAO/USDT LP Token
    
    // Reward rates (in basis points, 10000 = 100%)
    uint256 public baseAPY = 1500;           // 15% base APY
    uint256 public lpBonusAPY = 2500;        // 25% for LP stakers
    uint256 public longTermBonus = 500;      // 5% bonus for 6+ months
    uint256 public compoundBonus = 200;      // 2% bonus for auto-compound
    
    // Staking periods
    uint256 public constant MIN_STAKE_DURATION = 1 days;
    uint256 public constant UNLOCK_PERIOD = 7 days;
    uint256 public constant LONG_TERM_THRESHOLD = 180 days;
    
    // Pool limits
    uint256 public totalStakedKDAO;
    uint256 public totalStakedLP;
    uint256 public maxPoolSize = 100_000_000 * 10**18;  // 100M KDAO max
    uint256 public minStakeAmount = 100 * 10**18;       // 100 KDAO minimum
    
    // Reward distribution
    uint256 public rewardPool;
    uint256 public totalDistributed;
    uint256 public lastRewardUpdate;
    uint256 public rewardRate;  // Rewards per second
    
    // ============ Enums ============
    enum StakeType {
        KDAO,           // Single KDAO staking
        LP,             // KDAO/USDT LP staking
        COMPOUND        // Auto-compounding stake
    }
    
    enum LockStatus {
        Unlocked,
        Locked,
        Unlocking
    }
    
    // ============ Structs ============
    struct StakeInfo {
        uint256 amount;
        uint256 lpAmount;
        uint256 startTime;
        uint256 lastClaimTime;
        uint256 accumulatedRewards;
        uint256 claimedRewards;
        StakeType stakeType;
        LockStatus lockStatus;
        uint256 unlockTime;
        bool autoCompound;
        uint256 compoundedAmount;
        uint256 votingPower;
    }
    
    struct PoolInfo {
        uint256 totalStaked;
        uint256 rewardPerTokenStored;
        uint256 lastUpdateTime;
        uint256 periodFinish;
    }
    
    struct UserStats {
        uint256 totalStaked;
        uint256 totalEarned;
        uint256 stakingDuration;
        uint256 currentAPY;
        uint256 tier;  // 0: Bronze, 1: Silver, 2: Gold, 3: Diamond
    }
    
    // ============ Storage ============
    mapping(address => StakeInfo) public stakes;
    mapping(address => UserStats) public userStats;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    
    // Tier requirements (in KDAO)
    uint256[] public tierThresholds = [
        1000 * 10**18,      // Bronze: 1,000 KDAO
        10000 * 10**18,     // Silver: 10,000 KDAO
        50000 * 10**18,     // Gold: 50,000 KDAO
        100000 * 10**18     // Diamond: 100,000 KDAO
    ];
    
    // Tier bonuses (in basis points)
    uint256[] public tierBonuses = [0, 100, 300, 500];  // 0%, 1%, 3%, 5%
    
    PoolInfo public poolInfo;
    
    // Emergency withdrawal fee (anti-whale protection)
    uint256 public emergencyWithdrawFee = 1000;  // 10%
    
    // ============ Events ============
    event Staked(address indexed user, uint256 amount, StakeType stakeType);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 reward);
    event RewardsCompounded(address indexed user, uint256 amount);
    event UnlockRequested(address indexed user, uint256 unlockTime);
    event EmergencyWithdraw(address indexed user, uint256 amount, uint256 fee);
    event RewardPoolReplenished(uint256 amount);
    event APYUpdated(uint256 newBaseAPY, uint256 newLPBonus);
    event TierUpgraded(address indexed user, uint256 newTier);
    
    // ============ Constructor ============
    constructor(
        address _kdaoToken,
        address _lpToken
    ) {
        kdaoToken = IERC20(_kdaoToken);
        lpToken = IERC20(_lpToken);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REWARDS_MANAGER_ROLE, msg.sender);
        
        lastRewardUpdate = block.timestamp;
        poolInfo.lastUpdateTime = block.timestamp;
    }
    
    // ============ Modifiers ============
    modifier updateReward(address _account) {
        poolInfo.rewardPerTokenStored = rewardPerToken();
        poolInfo.lastUpdateTime = block.timestamp;
        
        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = poolInfo.rewardPerTokenStored;
        }
        _;
    }
    
    // ============ Core Staking Functions ============
    
    /**
     * @dev Stake KDAO tokens
     */
    function stakeKDAO(uint256 _amount, bool _autoCompound) 
        external 
        nonReentrant 
        whenNotPaused 
        updateReward(msg.sender) 
    {
        require(_amount >= minStakeAmount, "Below minimum stake");
        require(totalStakedKDAO.add(_amount) <= maxPoolSize, "Pool limit reached");
        
        kdaoToken.safeTransferFrom(msg.sender, address(this), _amount);
        
        StakeInfo storage stake = stakes[msg.sender];
        
        if (stake.amount == 0) {
            // New stake
            stake.startTime = block.timestamp;
            stake.stakeType = _autoCompound ? StakeType.COMPOUND : StakeType.KDAO;
            stake.autoCompound = _autoCompound;
        }
        
        stake.amount = stake.amount.add(_amount);
        stake.lastClaimTime = block.timestamp;
        stake.lockStatus = LockStatus.Locked;
        stake.votingPower = stake.amount;  // 1:1 voting power
        
        totalStakedKDAO = totalStakedKDAO.add(_amount);
        
        // Update user stats
        _updateUserStats(msg.sender, _amount, true);
        
        emit Staked(msg.sender, _amount, stake.stakeType);
    }
    
    /**
     * @dev Stake LP tokens (KDAO/USDT)
     */
    function stakeLP(uint256 _amount) 
        external 
        nonReentrant 
        whenNotPaused 
        updateReward(msg.sender) 
    {
        require(_amount > 0, "Cannot stake 0");
        
        lpToken.safeTransferFrom(msg.sender, address(this), _amount);
        
        StakeInfo storage stake = stakes[msg.sender];
        
        if (stake.lpAmount == 0) {
            stake.startTime = block.timestamp;
            stake.stakeType = StakeType.LP;
        }
        
        stake.lpAmount = stake.lpAmount.add(_amount);
        stake.lastClaimTime = block.timestamp;
        stake.lockStatus = LockStatus.Locked;
        stake.votingPower = stake.votingPower.add(_amount.mul(2)); // 2x voting power for LP
        
        totalStakedLP = totalStakedLP.add(_amount);
        
        _updateUserStats(msg.sender, _amount, true);
        
        emit Staked(msg.sender, _amount, StakeType.LP);
    }
    
    /**
     * @dev Request unlock (starts 7-day timer)
     */
    function requestUnlock() external updateReward(msg.sender) {
        StakeInfo storage stake = stakes[msg.sender];
        require(stake.amount > 0 || stake.lpAmount > 0, "No active stake");
        require(stake.lockStatus == LockStatus.Locked, "Already unlocking");
        require(
            block.timestamp >= stake.startTime.add(MIN_STAKE_DURATION),
            "Minimum stake period not met"
        );
        
        stake.lockStatus = LockStatus.Unlocking;
        stake.unlockTime = block.timestamp.add(UNLOCK_PERIOD);
        
        emit UnlockRequested(msg.sender, stake.unlockTime);
    }
    
    /**
     * @dev Unstake tokens after unlock period
     */
    function unstake(uint256 _amount) 
        external 
        nonReentrant 
        updateReward(msg.sender) 
    {
        StakeInfo storage stake = stakes[msg.sender];
        require(stake.lockStatus == LockStatus.Unlocking, "Not unlocked");
        require(block.timestamp >= stake.unlockTime, "Still in unlock period");
        
        if (stake.stakeType == StakeType.LP) {
            require(_amount <= stake.lpAmount, "Insufficient LP balance");
            stake.lpAmount = stake.lpAmount.sub(_amount);
            totalStakedLP = totalStakedLP.sub(_amount);
            lpToken.safeTransfer(msg.sender, _amount);
        } else {
            require(_amount <= stake.amount, "Insufficient balance");
            stake.amount = stake.amount.sub(_amount);
            totalStakedKDAO = totalStakedKDAO.sub(_amount);
            kdaoToken.safeTransfer(msg.sender, _amount);
        }
        
        // Reset lock if fully unstaked
        if (stake.amount == 0 && stake.lpAmount == 0) {
            stake.lockStatus = LockStatus.Unlocked;
            stake.votingPower = 0;
        } else {
            stake.lockStatus = LockStatus.Locked;  // Re-lock remaining
        }
        
        _updateUserStats(msg.sender, _amount, false);
        
        emit Unstaked(msg.sender, _amount);
    }
    
    /**
     * @dev Emergency withdraw with penalty
     */
    function emergencyWithdraw() 
        external 
        nonReentrant 
        updateReward(msg.sender) 
    {
        StakeInfo storage stake = stakes[msg.sender];
        require(stake.amount > 0 || stake.lpAmount > 0, "No active stake");
        
        uint256 kdaoAmount = stake.amount;
        uint256 lpAmount = stake.lpAmount;
        uint256 fee = 0;
        
        // Apply emergency fee
        if (kdaoAmount > 0) {
            fee = kdaoAmount.mul(emergencyWithdrawFee).div(10000);
            kdaoAmount = kdaoAmount.sub(fee);
            kdaoToken.safeTransfer(msg.sender, kdaoAmount);
            if (fee > 0) {
                rewardPool = rewardPool.add(fee);  // Fee goes to reward pool
            }
        }
        
        if (lpAmount > 0) {
            uint256 lpFee = lpAmount.mul(emergencyWithdrawFee).div(10000);
            lpAmount = lpAmount.sub(lpFee);
            lpToken.safeTransfer(msg.sender, lpAmount);
        }
        
        // Reset stake
        totalStakedKDAO = totalStakedKDAO.sub(stake.amount);
        totalStakedLP = totalStakedLP.sub(stake.lpAmount);
        delete stakes[msg.sender];
        delete userStats[msg.sender];
        rewards[msg.sender] = 0;
        
        emit EmergencyWithdraw(msg.sender, kdaoAmount.add(lpAmount), fee);
    }
    
    /**
     * @dev Claim accumulated rewards
     */
    function claimRewards() 
        external 
        nonReentrant 
        updateReward(msg.sender) 
    {
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No rewards to claim");
        
        rewards[msg.sender] = 0;
        stakes[msg.sender].claimedRewards = stakes[msg.sender].claimedRewards.add(reward);
        userStats[msg.sender].totalEarned = userStats[msg.sender].totalEarned.add(reward);
        totalDistributed = totalDistributed.add(reward);
        
        kdaoToken.safeTransfer(msg.sender, reward);
        
        emit RewardsClaimed(msg.sender, reward);
    }
    
    /**
     * @dev Auto-compound rewards (for compound stakers)
     */
    function compound() 
        external 
        nonReentrant 
        updateReward(msg.sender) 
    {
        StakeInfo storage stake = stakes[msg.sender];
        require(stake.autoCompound, "Auto-compound not enabled");
        
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No rewards to compound");
        
        rewards[msg.sender] = 0;
        stake.amount = stake.amount.add(reward);
        stake.compoundedAmount = stake.compoundedAmount.add(reward);
        stake.votingPower = stake.amount;
        totalStakedKDAO = totalStakedKDAO.add(reward);
        
        emit RewardsCompounded(msg.sender, reward);
    }
    
    // ============ Reward Calculation Functions ============
    
    /**
     * @dev Calculate current APY for user
     */
    function calculateAPY(address _user) public view returns (uint256) {
        StakeInfo memory stake = stakes[_user];
        uint256 apy = baseAPY;
        
        // Add LP bonus
        if (stake.stakeType == StakeType.LP) {
            apy = apy.add(lpBonusAPY);
        }
        
        // Add long-term bonus
        if (block.timestamp >= stake.startTime.add(LONG_TERM_THRESHOLD)) {
            apy = apy.add(longTermBonus);
        }
        
        // Add compound bonus
        if (stake.autoCompound) {
            apy = apy.add(compoundBonus);
        }
        
        // Add tier bonus
        uint256 tier = getUserTier(_user);
        apy = apy.add(tierBonuses[tier]);
        
        return apy;
    }
    
    /**
     * @dev Calculate reward per token
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalStakedKDAO == 0) {
            return poolInfo.rewardPerTokenStored;
        }
        
        uint256 timeDelta = block.timestamp.sub(poolInfo.lastUpdateTime);
        uint256 rewardAdded = timeDelta.mul(rewardRate);
        
        return poolInfo.rewardPerTokenStored.add(
            rewardAdded.mul(1e18).div(totalStakedKDAO)
        );
    }
    
    /**
     * @dev Calculate earned rewards
     */
    function earned(address _account) public view returns (uint256) {
        StakeInfo memory stake = stakes[_account];
        uint256 effectiveBalance = stake.amount;
        
        // LP stakers earn 2x
        if (stake.stakeType == StakeType.LP && stake.lpAmount > 0) {
            // Convert LP value to KDAO equivalent (assuming 1 LP = 2 KDAO value)
            effectiveBalance = effectiveBalance.add(stake.lpAmount.mul(2));
        }
        
        uint256 baseReward = effectiveBalance
            .mul(rewardPerToken().sub(userRewardPerTokenPaid[_account]))
            .div(1e18)
            .add(rewards[_account]);
        
        // Apply APY multiplier
        uint256 apy = calculateAPY(_account);
        uint256 timeStaked = block.timestamp.sub(stake.lastClaimTime);
        uint256 apyReward = effectiveBalance.mul(apy).mul(timeStaked).div(365 days).div(10000);
        
        return baseReward.add(apyReward);
    }
    
    /**
     * @dev Get user tier based on stake amount
     */
    function getUserTier(address _user) public view returns (uint256) {
        uint256 totalStake = stakes[_user].amount.add(stakes[_user].lpAmount.mul(2));
        
        for (uint256 i = tierThresholds.length; i > 0; i--) {
            if (totalStake >= tierThresholds[i - 1]) {
                return i - 1;
            }
        }
        return 0;
    }
    
    // ============ Internal Functions ============
    
    function _updateUserStats(address _user, uint256 _amount, bool _isStaking) internal {
        UserStats storage stats = userStats[_user];
        
        if (_isStaking) {
            stats.totalStaked = stats.totalStaked.add(_amount);
            
            // Check for tier upgrade
            uint256 oldTier = getUserTier(_user);
            uint256 newTier = getUserTier(_user);
            if (newTier > oldTier) {
                stats.tier = newTier;
                emit TierUpgraded(_user, newTier);
            }
        } else {
            stats.totalStaked = stats.totalStaked > _amount ? 
                stats.totalStaked.sub(_amount) : 0;
        }
        
        stats.currentAPY = calculateAPY(_user);
        stats.stakingDuration = block.timestamp.sub(stakes[_user].startTime);
    }
    
    // ============ Admin Functions ============
    
    /**
     * @dev Add rewards to the pool
     */
    function addRewards(uint256 _amount) 
        external 
        onlyRole(REWARDS_MANAGER_ROLE) 
    {
        require(_amount > 0, "Cannot add 0 rewards");
        kdaoToken.safeTransferFrom(msg.sender, address(this), _amount);
        
        rewardPool = rewardPool.add(_amount);
        
        // Update reward rate (distribute over 30 days)
        rewardRate = rewardPool.div(30 days);
        poolInfo.periodFinish = block.timestamp.add(30 days);
        
        emit RewardPoolReplenished(_amount);
    }
    
    /**
     * @dev Update APY rates
     */
    function updateAPY(
        uint256 _baseAPY,
        uint256 _lpBonus,
        uint256 _longTermBonus,
        uint256 _compoundBonus
    ) external onlyRole(REWARDS_MANAGER_ROLE) {
        require(_baseAPY <= 10000, "APY too high");  // Max 100%
        require(_lpBonus <= 10000, "LP bonus too high");
        
        baseAPY = _baseAPY;
        lpBonusAPY = _lpBonus;
        longTermBonus = _longTermBonus;
        compoundBonus = _compoundBonus;
        
        emit APYUpdated(_baseAPY, _lpBonus);
    }
    
    /**
     * @dev Update tier thresholds
     */
    function updateTierThresholds(uint256[] memory _thresholds) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_thresholds.length == 4, "Must have 4 tiers");
        tierThresholds = _thresholds;
    }
    
    /**
     * @dev Update pool limits
     */
    function updatePoolLimits(uint256 _maxPool, uint256 _minStake) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        maxPoolSize = _maxPool;
        minStakeAmount = _minStake;
    }
    
    /**
     * @dev Emergency pause
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
    
    // ============ View Functions ============
    
    function getUserInfo(address _user) 
        external 
        view 
        returns (
            uint256 stakedKDAO,
            uint256 stakedLP,
            uint256 pendingRewards,
            uint256 currentAPY,
            uint256 tier,
            uint256 votingPower,
            bool isAutoCompound
        ) 
    {
        StakeInfo memory stake = stakes[_user];
        return (
            stake.amount,
            stake.lpAmount,
            earned(_user),
            calculateAPY(_user),
            getUserTier(_user),
            stake.votingPower,
            stake.autoCompound
        );
    }
    
    function getPoolStats() 
        external 
        view 
        returns (
            uint256 totalKDAO,
            uint256 totalLP,
            uint256 rewardsAvailable,
            uint256 distributed,
            uint256 currentRewardRate
        ) 
    {
        return (
            totalStakedKDAO,
            totalStakedLP,
            rewardPool,
            totalDistributed,
            rewardRate
        );
    }
    
    function getAPYRates() 
        external 
        view 
        returns (
            uint256 base,
            uint256 lpBonus,
            uint256 longTerm,
            uint256 compound
        ) 
    {
        return (baseAPY, lpBonusAPY, longTermBonus, compoundBonus);
    }
}