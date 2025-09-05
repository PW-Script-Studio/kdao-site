// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title TreasuryManager
 * @dev Treasury management and project funding for KDAO 2.0
 * @notice Handles milestone-based funding, ROI tracking, and profit distribution
 * @author KDAO Development Team
 */
contract TreasuryManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeMath for uint256;

    // ============ Roles ============
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");
    
    // ============ State Variables ============
    IERC20 public kdaoToken;
    address public stakingContract;
    address public governanceContract;
    
    // Treasury Statistics
    uint256 public totalTreasuryBalance;
    uint256 public totalFundedProjects;
    uint256 public totalReturnedFunds;
    uint256 public totalDistributedRewards;
    
    // Distribution Parameters (in basis points, 10000 = 100%)
    uint256 public constant STAKER_SHARE = 7000;      // 70% to stakers
    uint256 public constant TREASURY_SHARE = 1000;    // 10% to treasury
    uint256 public constant RESTAKING_SHARE = 2000;   // 20% for auto-restaking
    
    // Funding Limits
    uint256 public constant MIN_FUNDING_AMOUNT = 1000 * 10**18;     // 1,000 KDAO minimum
    uint256 public constant MAX_FUNDING_AMOUNT = 500000 * 10**18;   // 500,000 KDAO maximum
    uint256 public constant MAX_ACTIVE_PROJECTS = 20;
    
    // ============ Enums ============
    enum ProjectStatus {
        Proposed,
        Approved,
        Active,
        Completed,
        Failed,
        Cancelled
    }
    
    enum FundingCategory {
        Utility,      // Bridges, Wallets, DEXs, Explorers
        Token,        // KRC20 Tokens, DeFi Tokens
        Education,    // Workshops, Tutorials, Documentation
        Marketing,    // Campaigns, Events, Partnerships
        Infrastructure // Nodes, Tools, Security
    }
    
    // ============ Structs ============
    struct Project {
        uint256 projectId;
        string name;
        string description;
        address payable recipient;
        FundingCategory category;
        uint256 requestedAmount;
        uint256 fundedAmount;
        uint256 returnedAmount;
        uint256 expectedROI;
        uint256 actualROI;
        ProjectStatus status;
        uint256 startTime;
        uint256 completionTime;
        uint256 repaymentDeadline;
        Milestone[] milestones;
        mapping(address => uint256) supporters;
        uint256 totalSupporters;
    }
    
    struct Milestone {
        uint256 milestoneId;
        string description;
        uint256 amount;
        uint256 deadline;
        bool completed;
        bool fundsReleased;
        uint256 completedTime;
    }
    
    struct FundingAllocation {
        uint256 utility;
        uint256 token;
        uint256 education;
        uint256 marketing;
        uint256 infrastructure;
        uint256 quarter;
        uint256 year;
    }
    
    // ============ Storage ============
    uint256 public projectCounter;
    mapping(uint256 => Project) public projects;
    mapping(address => uint256[]) public recipientProjects;
    mapping(FundingCategory => uint256) public categoryAllocations;
    
    // Active projects tracking
    uint256[] public activeProjectIds;
    mapping(uint256 => bool) public isProjectActive;
    
    // Quarterly allocations
    mapping(uint256 => mapping(uint256 => FundingAllocation)) public quarterlyAllocations;
    
    // Reward tracking
    mapping(address => uint256) public pendingRewards;
    mapping(address => uint256) public claimedRewards;
    
    // Insurance pool for failed projects
    uint256 public insurancePool;
    uint256 public constant INSURANCE_RATE = 300; // 3% of funding
    
    // ============ Events ============
    event ProjectProposed(
        uint256 indexed projectId,
        string name,
        address indexed recipient,
        uint256 requestedAmount,
        FundingCategory category
    );
    
    event ProjectApproved(uint256 indexed projectId);
    event ProjectFunded(uint256 indexed projectId, uint256 amount);
    event MilestoneCompleted(uint256 indexed projectId, uint256 milestoneId);
    event FundsReleased(uint256 indexed projectId, uint256 milestoneId, uint256 amount);
    event FundsReturned(uint256 indexed projectId, uint256 amount, uint256 roi);
    event RewardsDistributed(uint256 amount, uint256 toStakers, uint256 toTreasury, uint256 toRestaking);
    event InsurancePoolFunded(uint256 amount);
    event InsuranceClaimPaid(uint256 indexed projectId, uint256 amount);
    event QuarterlyAllocationSet(uint256 year, uint256 quarter, uint256 totalAmount);
    
    // ============ Constructor ============
    constructor(
        address _kdaoToken,
        address _stakingContract,
        address _governanceContract
    ) {
        kdaoToken = IERC20(_kdaoToken);
        stakingContract = _stakingContract;
        governanceContract = _governanceContract;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, _governanceContract);
        _grantRole(TREASURER_ROLE, msg.sender);
    }
    
    // ============ Modifiers ============
    modifier onlyGovernance() {
        require(
            hasRole(GOVERNANCE_ROLE, msg.sender) || msg.sender == governanceContract,
            "Only governance can call"
        );
        _;
    }
    
    modifier projectExists(uint256 _projectId) {
        require(projects[_projectId].projectId > 0, "Project does not exist");
        _;
    }
    
    // ============ Core Functions ============
    
    /**
     * @dev Propose a new project for funding
     */
    function proposeProject(
        string memory _name,
        string memory _description,
        address payable _recipient,
        FundingCategory _category,
        uint256 _requestedAmount,
        uint256 _expectedROI,
        uint256 _repaymentDeadline
    ) external whenNotPaused returns (uint256) {
        require(_requestedAmount >= MIN_FUNDING_AMOUNT, "Below minimum funding");
        require(_requestedAmount <= MAX_FUNDING_AMOUNT, "Above maximum funding");
        require(_recipient != address(0), "Invalid recipient");
        require(activeProjectIds.length < MAX_ACTIVE_PROJECTS, "Too many active projects");
        
        projectCounter++;
        uint256 projectId = projectCounter;
        
        Project storage newProject = projects[projectId];
        newProject.projectId = projectId;
        newProject.name = _name;
        newProject.description = _description;
        newProject.recipient = _recipient;
        newProject.category = _category;
        newProject.requestedAmount = _requestedAmount;
        newProject.expectedROI = _expectedROI;
        newProject.status = ProjectStatus.Proposed;
        newProject.repaymentDeadline = _repaymentDeadline;
        
        recipientProjects[_recipient].push(projectId);
        
        emit ProjectProposed(projectId, _name, _recipient, _requestedAmount, _category);
        
        return projectId;
    }
    
    /**
     * @dev Approve a project (called by governance after vote)
     */
    function approveProject(uint256 _projectId) 
        external 
        onlyGovernance 
        projectExists(_projectId) 
    {
        Project storage project = projects[_projectId];
        require(project.status == ProjectStatus.Proposed, "Invalid project status");
        
        project.status = ProjectStatus.Approved;
        project.startTime = block.timestamp;
        
        emit ProjectApproved(_projectId);
    }
    
    /**
     * @dev Add milestones to an approved project
     */
    function addMilestone(
        uint256 _projectId,
        string memory _description,
        uint256 _amount,
        uint256 _deadline
    ) external onlyRole(TREASURER_ROLE) projectExists(_projectId) {
        Project storage project = projects[_projectId];
        require(project.status == ProjectStatus.Approved, "Project not approved");
        
        uint256 totalMilestoneAmount = _amount;
        for (uint i = 0; i < project.milestones.length; i++) {
            totalMilestoneAmount = totalMilestoneAmount.add(project.milestones[i].amount);
        }
        require(totalMilestoneAmount <= project.requestedAmount, "Exceeds requested amount");
        
        Milestone memory newMilestone = Milestone({
            milestoneId: project.milestones.length,
            description: _description,
            amount: _amount,
            deadline: _deadline,
            completed: false,
            fundsReleased: false,
            completedTime: 0
        });
        
        project.milestones.push(newMilestone);
    }
    
    /**
     * @dev Fund a project and activate it
     */
    function fundProject(uint256 _projectId) 
        external 
        onlyRole(TREASURER_ROLE) 
        projectExists(_projectId) 
        nonReentrant 
    {
        Project storage project = projects[_projectId];
        require(project.status == ProjectStatus.Approved, "Project not approved");
        require(project.milestones.length > 0, "No milestones defined");
        require(totalTreasuryBalance >= project.requestedAmount, "Insufficient treasury funds");
        
        // Calculate insurance contribution
        uint256 insuranceContribution = project.requestedAmount.mul(INSURANCE_RATE).div(10000);
        insurancePool = insurancePool.add(insuranceContribution);
        
        project.status = ProjectStatus.Active;
        project.fundedAmount = project.requestedAmount;
        totalFundedProjects++;
        
        // Track as active project
        activeProjectIds.push(_projectId);
        isProjectActive[_projectId] = true;
        
        // Update category allocation
        categoryAllocations[project.category] = categoryAllocations[project.category].add(
            project.requestedAmount
        );
        
        emit ProjectFunded(_projectId, project.requestedAmount);
        emit InsurancePoolFunded(insuranceContribution);
    }
    
    /**
     * @dev Complete a milestone and request fund release
     */
    function completeMilestone(uint256 _projectId, uint256 _milestoneId) 
        external 
        projectExists(_projectId) 
    {
        Project storage project = projects[_projectId];
        require(msg.sender == project.recipient, "Only recipient can complete");
        require(project.status == ProjectStatus.Active, "Project not active");
        require(_milestoneId < project.milestones.length, "Invalid milestone");
        
        Milestone storage milestone = project.milestones[_milestoneId];
        require(!milestone.completed, "Already completed");
        require(block.timestamp <= milestone.deadline, "Milestone expired");
        
        milestone.completed = true;
        milestone.completedTime = block.timestamp;
        
        emit MilestoneCompleted(_projectId, _milestoneId);
    }
    
    /**
     * @dev Release funds for completed milestone (after verification)
     */
    function releaseMilestoneFunds(uint256 _projectId, uint256 _milestoneId) 
        external 
        onlyRole(AUDITOR_ROLE) 
        projectExists(_projectId) 
        nonReentrant 
    {
        Project storage project = projects[_projectId];
        require(project.status == ProjectStatus.Active, "Project not active");
        
        Milestone storage milestone = project.milestones[_milestoneId];
        require(milestone.completed, "Milestone not completed");
        require(!milestone.fundsReleased, "Funds already released");
        require(totalTreasuryBalance >= milestone.amount, "Insufficient treasury");
        
        milestone.fundsReleased = true;
        totalTreasuryBalance = totalTreasuryBalance.sub(milestone.amount);
        
        // Transfer funds to project recipient
        require(kdaoToken.transfer(project.recipient, milestone.amount), "Transfer failed");
        
        emit FundsReleased(_projectId, _milestoneId, milestone.amount);
    }
    
    /**
     * @dev Return funds with ROI after project completion
     */
    function returnFunds(uint256 _projectId, uint256 _amount) 
        external 
        projectExists(_projectId) 
        nonReentrant 
    {
        Project storage project = projects[_projectId];
        require(msg.sender == project.recipient, "Only recipient can return");
        require(project.status == ProjectStatus.Active, "Project not active");
        require(_amount > 0, "Amount must be positive");
        
        // Transfer returned funds from recipient
        require(kdaoToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        
        project.returnedAmount = project.returnedAmount.add(_amount);
        totalReturnedFunds = totalReturnedFunds.add(_amount);
        
        // Calculate actual ROI
        if (project.returnedAmount >= project.fundedAmount) {
            uint256 profit = project.returnedAmount.sub(project.fundedAmount);
            project.actualROI = profit.mul(10000).div(project.fundedAmount);
            
            // Mark project as completed
            project.status = ProjectStatus.Completed;
            project.completionTime = block.timestamp;
            _removeActiveProject(_projectId);
            
            // Distribute profits
            if (profit > 0) {
                _distributeReturns(profit);
            }
        }
        
        emit FundsReturned(_projectId, _amount, project.actualROI);
    }
    
    /**
     * @dev Distribute returns according to the 70/10/20 split
     */
    function _distributeReturns(uint256 _profit) internal {
        uint256 toStakers = _profit.mul(STAKER_SHARE).div(10000);
        uint256 toTreasury = _profit.mul(TREASURY_SHARE).div(10000);
        uint256 toRestaking = _profit.mul(RESTAKING_SHARE).div(10000);
        
        // Send to staking contract for distribution
        if (toStakers > 0 && stakingContract != address(0)) {
            require(kdaoToken.transfer(stakingContract, toStakers), "Staker transfer failed");
        }
        
        // Add to treasury
        totalTreasuryBalance = totalTreasuryBalance.add(toTreasury);
        
        // Handle restaking (could be sent to a restaking pool or back to staking)
        if (toRestaking > 0 && stakingContract != address(0)) {
            require(kdaoToken.transfer(stakingContract, toRestaking), "Restaking transfer failed");
        }
        
        totalDistributedRewards = totalDistributedRewards.add(_profit);
        
        emit RewardsDistributed(_profit, toStakers, toTreasury, toRestaking);
    }
    
    /**
     * @dev Mark project as failed and potentially use insurance
     */
    function markProjectFailed(uint256 _projectId) 
        external 
        onlyRole(GOVERNANCE_ROLE) 
        projectExists(_projectId) 
    {
        Project storage project = projects[_projectId];
        require(project.status == ProjectStatus.Active, "Project not active");
        require(
            block.timestamp > project.repaymentDeadline || 
            project.returnedAmount < project.fundedAmount.div(2),
            "Cannot mark as failed yet"
        );
        
        project.status = ProjectStatus.Failed;
        _removeActiveProject(_projectId);
        
        // Use insurance pool to cover partial losses if available
        uint256 insurancePayout = 0;
        if (insurancePool > 0) {
            uint256 loss = project.fundedAmount.sub(project.returnedAmount);
            insurancePayout = loss > insurancePool ? insurancePool : loss;
            insurancePool = insurancePool.sub(insurancePayout);
            totalTreasuryBalance = totalTreasuryBalance.add(insurancePayout);
            
            emit InsuranceClaimPaid(_projectId, insurancePayout);
        }
    }
    
    /**
     * @dev Set quarterly funding allocation
     */
    function setQuarterlyAllocation(
        uint256 _year,
        uint256 _quarter,
        uint256 _utility,
        uint256 _token,
        uint256 _education,
        uint256 _marketing,
        uint256 _infrastructure
    ) external onlyGovernance {
        require(_quarter >= 1 && _quarter <= 4, "Invalid quarter");
        
        FundingAllocation storage allocation = quarterlyAllocations[_year][_quarter];
        allocation.utility = _utility;
        allocation.token = _token;
        allocation.education = _education;
        allocation.marketing = _marketing;
        allocation.infrastructure = _infrastructure;
        allocation.quarter = _quarter;
        allocation.year = _year;
        
        uint256 total = _utility.add(_token).add(_education).add(_marketing).add(_infrastructure);
        
        emit QuarterlyAllocationSet(_year, _quarter, total);
    }
    
    // ============ View Functions ============
    
    function getProject(uint256 _projectId) 
        external 
        view 
        returns (
            string memory name,
            address recipient,
            uint256 requestedAmount,
            uint256 fundedAmount,
            uint256 returnedAmount,
            ProjectStatus status,
            uint256 actualROI
        ) 
    {
        Project storage project = projects[_projectId];
        return (
            project.name,
            project.recipient,
            project.requestedAmount,
            project.fundedAmount,
            project.returnedAmount,
            project.status,
            project.actualROI
        );
    }
    
    function getProjectMilestones(uint256 _projectId) 
        external 
        view 
        returns (Milestone[] memory) 
    {
        return projects[_projectId].milestones;
    }
    
    function getActiveProjects() external view returns (uint256[] memory) {
        return activeProjectIds;
    }
    
    function getCategoryAllocation(FundingCategory _category) 
        external 
        view 
        returns (uint256) 
    {
        return categoryAllocations[_category];
    }
    
    function getTreasuryStats() 
        external 
        view 
        returns (
            uint256 balance,
            uint256 funded,
            uint256 returned,
            uint256 distributed,
            uint256 insurance
        ) 
    {
        return (
            totalTreasuryBalance,
            totalFundedProjects,
            totalReturnedFunds,
            totalDistributedRewards,
            insurancePool
        );
    }
    
    // ============ Internal Functions ============
    
    function _removeActiveProject(uint256 _projectId) internal {
        isProjectActive[_projectId] = false;
        
        // Remove from active projects array
        for (uint i = 0; i < activeProjectIds.length; i++) {
            if (activeProjectIds[i] == _projectId) {
                activeProjectIds[i] = activeProjectIds[activeProjectIds.length - 1];
                activeProjectIds.pop();
                break;
            }
        }
    }
    
    // ============ Admin Functions ============
    
    function updateContracts(address _staking, address _governance) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        stakingContract = _staking;
        governanceContract = _governance;
    }
    
    function depositToTreasury(uint256 _amount) external {
        require(kdaoToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        totalTreasuryBalance = totalTreasuryBalance.add(_amount);
    }
    
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
    
    // ============ Receive Function ============
    receive() external payable {
        // Accept ETH/KAS deposits
    }
}