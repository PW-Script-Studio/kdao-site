// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title KDAOGovernance
 * @dev Main governance contract for KDAO 2.0 - Decentralized funding engine for Kaspa ecosystem
 * @author KDAO Development Team
 */
contract KDAOGovernance is AccessControl, ReentrancyGuard, Pausable {
    using SafeMath for uint256;

    // ============ Roles ============
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    
    // ============ State Variables ============
    IERC20 public kdaoToken;
    uint256 public proposalCount;
    uint256 public constant MIN_PROPOSAL_THRESHOLD = 100 * 10**18; // 100 KDAO
    uint256 public constant QUORUM_PERCENTAGE = 30; // 30% quorum required
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant EXECUTION_DELAY = 2 days;
    
    // ============ Enums ============
    enum ProposalState {
        Pending,
        Active,
        Defeated,
        Succeeded,
        Queued,
        Executed,
        Cancelled
    }
    
    enum ProposalType {
        Funding,      // Projektfinanzierung
        Treasury,     // Treasury Allocation
        Governance,   // Governance Changes
        Election      // Leadership Election
    }
    
    enum VoteType {
        Against,
        For,
        Abstain
    }
    
    // ============ Structs ============
    struct Proposal {
        uint256 id;
        address proposer;
        ProposalType proposalType;
        string title;
        string description;
        address target;
        uint256 value;
        bytes callData;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 executionTime;
        ProposalState state;
        mapping(address => Receipt) receipts;
    }
    
    struct Receipt {
        bool hasVoted;
        VoteType vote;
        uint256 votes;
    }
    
    // ============ Storage ============
    mapping(uint256 => Proposal) public proposals;
    mapping(address => uint256) public votingPower;
    mapping(address => address) public voteDelegation;
    mapping(address => uint256) public stakedBalance;
    
    // Treasury Management
    uint256 public treasuryBalance;
    mapping(address => uint256) public projectFunding;
    
    // ============ Events ============
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        ProposalType proposalType,
        string title,
        uint256 startBlock,
        uint256 endBlock
    );
    
    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        VoteType vote,
        uint256 votes
    );
    
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);
    event VotesDelegated(address indexed delegator, address indexed delegatee);
    event TokensStaked(address indexed staker, uint256 amount);
    event TokensUnstaked(address indexed staker, uint256 amount);
    event FundingAllocated(address indexed project, uint256 amount);
    
    // ============ Constructor ============
    constructor(address _kdaoToken) {
        kdaoToken = IERC20(_kdaoToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);
        _grantRole(GUARDIAN_ROLE, msg.sender);
    }
    
    // ============ Modifiers ============
    modifier onlyProposer() {
        require(
            votingPower[msg.sender] >= MIN_PROPOSAL_THRESHOLD,
            "Insufficient KDAO to propose"
        );
        _;
    }
    
    // ============ Core Functions ============
    
    /**
     * @dev Create a new proposal
     */
    function createProposal(
        ProposalType _type,
        string memory _title,
        string memory _description,
        address _target,
        uint256 _value,
        bytes memory _callData
    ) external onlyProposer whenNotPaused returns (uint256) {
        proposalCount++;
        uint256 proposalId = proposalCount;
        
        Proposal storage newProposal = proposals[proposalId];
        newProposal.id = proposalId;
        newProposal.proposer = msg.sender;
        newProposal.proposalType = _type;
        newProposal.title = _title;
        newProposal.description = _description;
        newProposal.target = _target;
        newProposal.value = _value;
        newProposal.callData = _callData;
        newProposal.startBlock = block.number + 1;
        newProposal.endBlock = block.number + (VOTING_PERIOD / 12); // ~12 sec blocks
        newProposal.state = ProposalState.Active;
        
        emit ProposalCreated(
            proposalId,
            msg.sender,
            _type,
            _title,
            newProposal.startBlock,
            newProposal.endBlock
        );
        
        return proposalId;
    }
    
    /**
     * @dev Cast vote on a proposal
     */
    function castVote(uint256 _proposalId, VoteType _vote) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        require(state(_proposalId) == ProposalState.Active, "Voting not active");
        
        Proposal storage proposal = proposals[_proposalId];
        Receipt storage receipt = proposal.receipts[msg.sender];
        
        require(!receipt.hasVoted, "Already voted");
        
        uint256 votes = getVotingPower(msg.sender);
        require(votes > 0, "No voting power");
        
        receipt.hasVoted = true;
        receipt.vote = _vote;
        receipt.votes = votes;
        
        if (_vote == VoteType.For) {
            proposal.forVotes = proposal.forVotes.add(votes);
        } else if (_vote == VoteType.Against) {
            proposal.againstVotes = proposal.againstVotes.add(votes);
        } else {
            proposal.abstainVotes = proposal.abstainVotes.add(votes);
        }
        
        emit VoteCast(msg.sender, _proposalId, _vote, votes);
    }
    
    /**
     * @dev Execute a successful proposal
     */
    function executeProposal(uint256 _proposalId) 
        external 
        payable 
        whenNotPaused 
        nonReentrant 
    {
        require(state(_proposalId) == ProposalState.Succeeded, "Proposal not successful");
        
        Proposal storage proposal = proposals[_proposalId];
        proposal.state = ProposalState.Executed;
        proposal.executionTime = block.timestamp;
        
        // Execute based on proposal type
        if (proposal.proposalType == ProposalType.Funding) {
            _allocateFunding(proposal.target, proposal.value);
        } else if (proposal.target != address(0)) {
            (bool success, ) = proposal.target.call{value: proposal.value}(
                proposal.callData
            );
            require(success, "Execution failed");
        }
        
        emit ProposalExecuted(_proposalId);
    }
    
    /**
     * @dev Stake KDAO tokens for voting power
     */
    function stakeTokens(uint256 _amount) external whenNotPaused nonReentrant {
        require(_amount > 0, "Amount must be greater than 0");
        require(kdaoToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        
        stakedBalance[msg.sender] = stakedBalance[msg.sender].add(_amount);
        votingPower[msg.sender] = votingPower[msg.sender].add(_amount);
        
        emit TokensStaked(msg.sender, _amount);
    }
    
    /**
     * @dev Unstake KDAO tokens
     */
    function unstakeTokens(uint256 _amount) external whenNotPaused nonReentrant {
        require(_amount > 0, "Amount must be greater than 0");
        require(stakedBalance[msg.sender] >= _amount, "Insufficient staked balance");
        
        stakedBalance[msg.sender] = stakedBalance[msg.sender].sub(_amount);
        votingPower[msg.sender] = votingPower[msg.sender].sub(_amount);
        
        require(kdaoToken.transfer(msg.sender, _amount), "Transfer failed");
        
        emit TokensUnstaked(msg.sender, _amount);
    }
    
    /**
     * @dev Delegate voting power
     */
    function delegateVotes(address _delegatee) external {
        require(_delegatee != address(0), "Invalid delegatee");
        require(_delegatee != msg.sender, "Cannot delegate to self");
        
        address oldDelegatee = voteDelegation[msg.sender];
        uint256 delegatorVotes = stakedBalance[msg.sender];
        
        if (oldDelegatee != address(0)) {
            votingPower[oldDelegatee] = votingPower[oldDelegatee].sub(delegatorVotes);
        }
        
        voteDelegation[msg.sender] = _delegatee;
        votingPower[_delegatee] = votingPower[_delegatee].add(delegatorVotes);
        
        emit VotesDelegated(msg.sender, _delegatee);
    }
    
    // ============ Internal Functions ============
    
    function _allocateFunding(address _project, uint256 _amount) internal {
        require(treasuryBalance >= _amount, "Insufficient treasury funds");
        treasuryBalance = treasuryBalance.sub(_amount);
        projectFunding[_project] = projectFunding[_project].add(_amount);
        
        // Transfer funds to project
        payable(_project).transfer(_amount);
        
        emit FundingAllocated(_project, _amount);
    }
    
    // ============ View Functions ============
    
    function state(uint256 _proposalId) public view returns (ProposalState) {
        Proposal storage proposal = proposals[_proposalId];
        
        if (proposal.state == ProposalState.Cancelled || 
            proposal.state == ProposalState.Executed) {
            return proposal.state;
        }
        
        if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        }
        
        if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        }
        
        // Check if proposal succeeded
        uint256 totalVotes = proposal.forVotes.add(proposal.againstVotes);
        uint256 quorumVotes = kdaoToken.totalSupply().mul(QUORUM_PERCENTAGE).div(100);
        
        if (totalVotes < quorumVotes) {
            return ProposalState.Defeated; // Quorum not reached
        }
        
        if (proposal.forVotes > proposal.againstVotes) {
            return ProposalState.Succeeded;
        }
        
        return ProposalState.Defeated;
    }
    
    function getVotingPower(address _account) public view returns (uint256) {
        return votingPower[_account];
    }
    
    function getProposal(uint256 _proposalId) 
        external 
        view 
        returns (
            uint256 id,
            address proposer,
            ProposalType proposalType,
            string memory title,
            string memory description,
            ProposalState proposalState
        ) 
    {
        Proposal storage proposal = proposals[_proposalId];
        return (
            proposal.id,
            proposal.proposer,
            proposal.proposalType,
            proposal.title,
            proposal.description,
            state(_proposalId)
        );
    }
    
    // ============ Admin Functions ============
    
    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(GUARDIAN_ROLE) {
        _unpause();
    }
    
    function cancelProposal(uint256 _proposalId) external onlyRole(GUARDIAN_ROLE) {
        proposals[_proposalId].state = ProposalState.Cancelled;
        emit ProposalCancelled(_proposalId);
    }
    
    // ============ Receive Function ============
    receive() external payable {
        treasuryBalance = treasuryBalance.add(msg.value);
    }
}