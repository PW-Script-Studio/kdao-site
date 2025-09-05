// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title ElectionManager
 * @dev On-chain election system for KDAO leadership positions
 * @notice Manages nominations, campaigns, voting, and term limits
 * @author KDAO Development Team
 */
contract ElectionManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeMath for uint256;

    // ============ Roles ============
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant ELECTION_ADMIN_ROLE = keccak256("ELECTION_ADMIN_ROLE");
    
    // ============ State Variables ============
    IERC20 public immutable kdaoToken;
    address public stakingContract;
    address public governanceContract;
    
    // Election Parameters
    uint256 public constant NOMINATION_PERIOD = 7 days;
    uint256 public constant CAMPAIGN_PERIOD = 5 days;
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant TERM_LENGTH = 180 days;  // 6 months
    uint256 public constant MIN_NOMINATION_STAKE = 100 * 10**18;  // 100 KDAO
    uint256 public constant QUORUM_PERCENTAGE = 30;  // 30% participation required
    
    // Election tracking
    uint256 public electionCounter;
    uint256 public activeElections;
    
    // ============ Enums ============
    enum ElectionPhase {
        NotStarted,
        Nomination,
        Campaign,
        Voting,
        Ended,
        Cancelled
    }
    
    enum Position {
        ProjectLead,        // Projektleiter / Koordinator
        TechLead,          // Tech Lead
        TreasuryManager,   // Treasury Manager
        CommunityLead,     // Community Lead
        PartnershipManager,// Partnership Manager
        GovernanceLead,    // Governance & Compliance
        MarketingLead,     // Marketing Lead
        BackendDev,        // Backend Developer
        FrontendDev        // Frontend Developer (Peter Wittner)
    }
    
    enum VoteChoice {
        None,
        Candidate1,
        Candidate2,
        Candidate3,
        Candidate4,
        Candidate5,
        Abstain
    }
    
    // ============ Structs ============
    struct Election {
        uint256 electionId;
        Position position;
        string positionTitle;
        string description;
        ElectionPhase phase;
        uint256 nominationStart;
        uint256 nominationEnd;
        uint256 campaignEnd;
        uint256 votingEnd;
        uint256 totalVotes;
        uint256 quorumVotes;
        address winner;
        bool quorumReached;
        Candidate[] candidates;
        mapping(address => bool) hasNominated;
        mapping(address => bool) hasVoted;
        mapping(address => uint256) voterWeight;
    }
    
    struct Candidate {
        address candidateAddress;
        string name;
        string manifesto;
        string experience;
        string discordHandle;
        string githubProfile;
        uint256 nominationStake;
        uint256 votes;
        uint256 supporterCount;
        bool isActive;
        bool isElected;
    }
    
    struct Leadership {
        address holder;
        Position position;
        uint256 termStart;
        uint256 termEnd;
        uint256 performance; // 0-100 score
        bool isActive;
    }
    
    struct VoteReceipt {
        bool hasVoted;
        VoteChoice choice;
        uint256 weight;
        uint256 timestamp;
    }
    
    // ============ Storage ============
    mapping(uint256 => Election) public elections;
    mapping(Position => Leadership) public currentLeadership;
    mapping(address => Position[]) public userPositions;
    mapping(address => mapping(uint256 => VoteReceipt)) public voteReceipts;
    
    // Position requirements
    mapping(Position => string) public positionRequirements;
    mapping(Position => bool) public positionVacant;
    
    // Historical data
    mapping(Position => address[]) public positionHistory;
    mapping(address => uint256) public leadershipScore;
    
    // ============ Events ============
    event ElectionCreated(
        uint256 indexed electionId,
        Position position,
        string title,
        uint256 nominationStart,
        uint256 votingEnd
    );
    
    event CandidateNominated(
        uint256 indexed electionId,
        address indexed candidate,
        string name,
        uint256 stake
    );
    
    event VoteCast(
        uint256 indexed electionId,
        address indexed voter,
        uint256 weight
    );
    
    event ElectionFinalized(
        uint256 indexed electionId,
        address indexed winner,
        uint256 totalVotes,
        bool quorumReached
    );
    
    event LeadershipTermStarted(
        address indexed leader,
        Position position,
        uint256 termEnd
    );
    
    event LeadershipTermEnded(
        address indexed leader,
        Position position,
        uint256 performanceScore
    );
    
    event CandidateWithdrawn(
        uint256 indexed electionId,
        address indexed candidate
    );
    
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
        _grantRole(ELECTION_ADMIN_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, _governanceContract);
        
        // Initialize position requirements
        _initializePositions();
        
        // Mark Peter Wittner as Frontend Dev (already elected)
        currentLeadership[Position.FrontendDev] = Leadership({
            holder: 0x1234567890123456789012345678901234567890, // Peter's address
            position: Position.FrontendDev,
            termStart: block.timestamp,
            termEnd: block.timestamp + TERM_LENGTH,
            performance: 78, // 78% support as shown in UI
            isActive: true
        });
        positionVacant[Position.FrontendDev] = false;
    }
    
    // ============ Core Functions ============
    
    /**
     * @dev Create a new election for a position
     */
    function createElection(
        Position _position,
        string memory _title,
        string memory _description
    ) external onlyRole(ELECTION_ADMIN_ROLE) whenNotPaused returns (uint256) {
        require(positionVacant[_position], "Position not vacant");
        require(activeElections < 3, "Too many active elections");
        
        electionCounter++;
        uint256 electionId = electionCounter;
        
        Election storage newElection = elections[electionId];
        newElection.electionId = electionId;
        newElection.position = _position;
        newElection.positionTitle = _title;
        newElection.description = _description;
        newElection.phase = ElectionPhase.Nomination;
        newElection.nominationStart = block.timestamp;
        newElection.nominationEnd = block.timestamp + NOMINATION_PERIOD;
        newElection.campaignEnd = newElection.nominationEnd + CAMPAIGN_PERIOD;
        newElection.votingEnd = newElection.campaignEnd + VOTING_PERIOD;
        
        activeElections++;
        
        emit ElectionCreated(
            electionId,
            _position,
            _title,
            block.timestamp,
            newElection.votingEnd
        );
        
        return electionId;
    }
    
    /**
     * @dev Nominate yourself as a candidate
     */
    function nominateCandidate(
        uint256 _electionId,
        string memory _name,
        string memory _manifesto,
        string memory _experience,
        string memory _discordHandle,
        string memory _githubProfile
    ) external nonReentrant whenNotPaused {
        Election storage election = elections[_electionId];
        require(election.phase == ElectionPhase.Nomination, "Not in nomination phase");
        require(block.timestamp <= election.nominationEnd, "Nomination period ended");
        require(!election.hasNominated[msg.sender], "Already nominated");
        require(kdaoToken.balanceOf(msg.sender) >= MIN_NOMINATION_STAKE, "Insufficient KDAO");
        
        // Check if candidate already exists in other elections
        require(!_hasActivePosition(msg.sender), "Already holding a position");
        
        // Transfer nomination stake
        require(
            kdaoToken.transferFrom(msg.sender, address(this), MIN_NOMINATION_STAKE),
            "Stake transfer failed"
        );
        
        Candidate memory newCandidate = Candidate({
            candidateAddress: msg.sender,
            name: _name,
            manifesto: _manifesto,
            experience: _experience,
            discordHandle: _discordHandle,
            githubProfile: _githubProfile,
            nominationStake: MIN_NOMINATION_STAKE,
            votes: 0,
            supporterCount: 0,
            isActive: true,
            isElected: false
        });
        
        election.candidates.push(newCandidate);
        election.hasNominated[msg.sender] = true;
        
        emit CandidateNominated(_electionId, msg.sender, _name, MIN_NOMINATION_STAKE);
    }
    
    /**
     * @dev Cast vote for a candidate
     */
    function vote(uint256 _electionId, uint256 _candidateIndex) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        Election storage election = elections[_electionId];
        require(_updateElectionPhase(_electionId), "Election phase update failed");
        require(election.phase == ElectionPhase.Voting, "Not in voting phase");
        require(!election.hasVoted[msg.sender], "Already voted");
        require(_candidateIndex < election.candidates.length, "Invalid candidate");
        
        // Get voting power from staking contract
        uint256 votingPower = _getVotingPower(msg.sender);
        require(votingPower > 0, "No voting power");
        
        election.hasVoted[msg.sender] = true;
        election.voterWeight[msg.sender] = votingPower;
        election.totalVotes = election.totalVotes.add(votingPower);
        
        // Record vote
        Candidate storage candidate = election.candidates[_candidateIndex];
        candidate.votes = candidate.votes.add(votingPower);
        candidate.supporterCount++;
        
        // Store receipt
        voteReceipts[msg.sender][_electionId] = VoteReceipt({
            hasVoted: true,
            choice: VoteChoice(_candidateIndex + 1),
            weight: votingPower,
            timestamp: block.timestamp
        });
        
        emit VoteCast(_electionId, msg.sender, votingPower);
    }
    
    /**
     * @dev Finalize election and determine winner
     */
    function finalizeElection(uint256 _electionId) 
        external 
        onlyRole(ELECTION_ADMIN_ROLE) 
        nonReentrant 
    {
        Election storage election = elections[_electionId];
        require(_updateElectionPhase(_electionId), "Phase update failed");
        require(election.phase == ElectionPhase.Voting, "Not in voting phase");
        require(block.timestamp > election.votingEnd, "Voting not ended");
        
        // Check quorum
        uint256 totalSupply = kdaoToken.totalSupply();
        election.quorumVotes = totalSupply.mul(QUORUM_PERCENTAGE).div(100);
        election.quorumReached = election.totalVotes >= election.quorumVotes;
        
        if (election.quorumReached && election.candidates.length > 0) {
            // Find winner
            uint256 maxVotes = 0;
            uint256 winnerIndex = 0;
            
            for (uint i = 0; i < election.candidates.length; i++) {
                if (election.candidates[i].votes > maxVotes) {
                    maxVotes = election.candidates[i].votes;
                    winnerIndex = i;
                }
            }
            
            Candidate storage winner = election.candidates[winnerIndex];
            winner.isElected = true;
            election.winner = winner.candidateAddress;
            
            // Update leadership
            _updateLeadership(election.position, winner.candidateAddress);
            
            // Return nomination stakes to non-winners
            for (uint i = 0; i < election.candidates.length; i++) {
                if (i != winnerIndex) {
                    kdaoToken.transfer(
                        election.candidates[i].candidateAddress,
                        election.candidates[i].nominationStake
                    );
                }
            }
        } else {
            // Quorum not reached or no candidates - return all stakes
            for (uint i = 0; i < election.candidates.length; i++) {
                kdaoToken.transfer(
                    election.candidates[i].candidateAddress,
                    election.candidates[i].nominationStake
                );
            }
        }
        
        election.phase = ElectionPhase.Ended;
        activeElections--;
        
        emit ElectionFinalized(
            _electionId,
            election.winner,
            election.totalVotes,
            election.quorumReached
        );
    }
    
    /**
     * @dev Withdraw candidacy
     */
    function withdrawCandidacy(uint256 _electionId) external nonReentrant {
        Election storage election = elections[_electionId];
        require(
            election.phase == ElectionPhase.Nomination || 
            election.phase == ElectionPhase.Campaign,
            "Cannot withdraw now"
        );
        
        for (uint i = 0; i < election.candidates.length; i++) {
            if (election.candidates[i].candidateAddress == msg.sender) {
                election.candidates[i].isActive = false;
                
                // Return nomination stake
                kdaoToken.transfer(msg.sender, MIN_NOMINATION_STAKE);
                
                emit CandidateWithdrawn(_electionId, msg.sender);
                break;
            }
        }
    }
    
    /**
     * @dev Step down from position
     */
    function resignPosition() external {
        Position position = _getUserPosition(msg.sender);
        require(position != Position.ProjectLead, "Invalid position");
        
        Leadership storage leadership = currentLeadership[position];
        require(leadership.holder == msg.sender, "Not position holder");
        require(leadership.isActive, "Position not active");
        
        leadership.isActive = false;
        leadership.termEnd = block.timestamp;
        positionVacant[position] = true;
        
        emit LeadershipTermEnded(msg.sender, position, leadership.performance);
    }
    
    // ============ Internal Functions ============
    
    function _initializePositions() internal {
        // Set all positions as vacant except FrontendDev
        positionVacant[Position.ProjectLead] = true;
        positionVacant[Position.TechLead] = true;
        positionVacant[Position.TreasuryManager] = true;
        positionVacant[Position.CommunityLead] = true;
        positionVacant[Position.PartnershipManager] = true;
        positionVacant[Position.GovernanceLead] = true;
        positionVacant[Position.MarketingLead] = true;
        positionVacant[Position.BackendDev] = true;
        positionVacant[Position.FrontendDev] = false; // Peter Wittner
        
        // Set position requirements
        positionRequirements[Position.ProjectLead] = "Leadership experience, strategic vision";
        positionRequirements[Position.TechLead] = "Smart contract expertise, blockchain development";
        positionRequirements[Position.TreasuryManager] = "DeFi experience, financial management";
        positionRequirements[Position.CommunityLead] = "Community building, communication skills";
        positionRequirements[Position.PartnershipManager] = "Business development, networking";
        positionRequirements[Position.GovernanceLead] = "Legal knowledge, compliance expertise";
        positionRequirements[Position.MarketingLead] = "Marketing strategy, content creation";
        positionRequirements[Position.BackendDev] = "Node.js, database, API development";
        positionRequirements[Position.FrontendDev] = "React, Web3, UI/UX design";
    }
    
    function _updateElectionPhase(uint256 _electionId) internal returns (bool) {
        Election storage election = elections[_electionId];
        
        if (election.phase == ElectionPhase.Ended || 
            election.phase == ElectionPhase.Cancelled) {
            return false;
        }
        
        uint256 currentTime = block.timestamp;
        
        if (currentTime > election.votingEnd) {
            election.phase = ElectionPhase.Ended;
        } else if (currentTime > election.campaignEnd) {
            election.phase = ElectionPhase.Voting;
        } else if (currentTime > election.nominationEnd) {
            election.phase = ElectionPhase.Campaign;
        }
        
        return true;
    }
    
    function _updateLeadership(Position _position, address _newLeader) internal {
        // End current term if exists
        Leadership storage current = currentLeadership[_position];
        if (current.isActive) {
            current.isActive = false;
            current.termEnd = block.timestamp;
            positionHistory[_position].push(current.holder);
        }
        
        // Start new term
        currentLeadership[_position] = Leadership({
            holder: _newLeader,
            position: _position,
            termStart: block.timestamp,
            termEnd: block.timestamp + TERM_LENGTH,
            performance: 50, // Start at neutral
            isActive: true
        });
        
        positionVacant[_position] = false;
        userPositions[_newLeader].push(_position);
        
        emit LeadershipTermStarted(_newLeader, _position, block.timestamp + TERM_LENGTH);
    }
    
    function _getVotingPower(address _voter) internal view returns (uint256) {
        // Get voting power from staking contract
        // This would call stakingContract.getVotingPower(_voter)
        // For now, use token balance as fallback
        return kdaoToken.balanceOf(_voter);
    }
    
    function _hasActivePosition(address _user) internal view returns (bool) {
        for (uint i = 0; i <= uint(Position.FrontendDev); i++) {
            if (currentLeadership[Position(i)].holder == _user && 
                currentLeadership[Position(i)].isActive) {
                return true;
            }
        }
        return false;
    }
    
    function _getUserPosition(address _user) internal view returns (Position) {
        for (uint i = 0; i <= uint(Position.FrontendDev); i++) {
            if (currentLeadership[Position(i)].holder == _user && 
                currentLeadership[Position(i)].isActive) {
                return Position(i);
            }
        }
        revert("User has no position");
    }
    
    // ============ View Functions ============
    
    function getElection(uint256 _electionId) 
        external 
        view 
        returns (
            Position position,
            string memory title,
            ElectionPhase phase,
            uint256 totalVotes,
            uint256 candidateCount,
            address winner
        ) 
    {
        Election storage election = elections[_electionId];
        return (
            election.position,
            election.positionTitle,
            election.phase,
            election.totalVotes,
            election.candidates.length,
            election.winner
        );
    }
    
    function getCandidates(uint256 _electionId) 
        external 
        view 
        returns (Candidate[] memory) 
    {
        return elections[_electionId].candidates;
    }
    
    function getCurrentLeadership() 
        external 
        view 
        returns (Leadership[] memory) 
    {
        Leadership[] memory leaders = new Leadership[](9);
        for (uint i = 0; i <= uint(Position.FrontendDev); i++) {
            leaders[i] = currentLeadership[Position(i)];
        }
        return leaders;
    }
    
    function getVacantPositions() 
        external 
        view 
        returns (Position[] memory) 
    {
        uint vacantCount = 0;
        for (uint i = 0; i <= uint(Position.FrontendDev); i++) {
            if (positionVacant[Position(i)]) vacantCount++;
        }
        
        Position[] memory vacant = new Position[](vacantCount);
        uint index = 0;
        for (uint i = 0; i <= uint(Position.FrontendDev); i++) {
            if (positionVacant[Position(i)]) {
                vacant[index] = Position(i);
                index++;
            }
        }
        return vacant;
    }
    
    function getElectionPhase(uint256 _electionId) external view returns (ElectionPhase) {
        return elections[_electionId].phase;
    }
    
    function getUserVoteReceipt(address _user, uint256 _electionId) 
        external 
        view 
        returns (VoteReceipt memory) 
    {
        return voteReceipts[_user][_electionId];
    }
    
    // ============ Admin Functions ============
    
    function cancelElection(uint256 _electionId) 
        external 
        onlyRole(GOVERNANCE_ROLE) 
    {
        Election storage election = elections[_electionId];
        require(election.phase != ElectionPhase.Ended, "Already ended");
        
        election.phase = ElectionPhase.Cancelled;
        activeElections--;
        
        // Return all nomination stakes
        for (uint i = 0; i < election.candidates.length; i++) {
            if (election.candidates[i].isActive) {
                kdaoToken.transfer(
                    election.candidates[i].candidateAddress,
                    election.candidates[i].nominationStake
                );
            }
        }
    }
    
    function updatePerformanceScore(Position _position, uint256 _score) 
        external 
        onlyRole(GOVERNANCE_ROLE) 
    {
        require(_score <= 100, "Invalid score");
        currentLeadership[_position].performance = _score;
    }
    
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}