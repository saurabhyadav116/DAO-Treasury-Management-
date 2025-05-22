// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title DAOTreasury
 * @dev A smart contract for managing DAO treasury with proposal and voting mechanisms
 */
contract DAOTreasury {
    // Structure for funding proposals
    struct Proposal {
        uint256 id;
        address proposer;
        address payable recipient;
        uint256 amount;
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        bool executed;
        uint256 deadline;
        mapping(address => bool) hasVoted;
    }

    // Contract state variables
    address public admin;
    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;
    mapping(address => uint256) public memberTokens;
    uint256 public totalTokens;
    uint256 public quorum; // Percentage of tokens needed to pass a proposal (0-100)
    uint256 public votingPeriod; // Time in seconds for voting on a proposal

    // Events
    event ProposalCreated(uint256 proposalId, address proposer, address recipient, uint256 amount, string description);
    event VoteCast(uint256 proposalId, address voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 proposalId);
    event MemberAdded(address member, uint256 tokens);
    event FundsDeposited(address from, uint256 amount);

    // Modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    modifier onlyMember() {
        require(memberTokens[msg.sender] > 0, "Only members can perform this action");
        _;
    }

    // Constructor
    constructor(uint256 _quorum, uint256 _votingPeriod) {
        require(_quorum <= 100, "Quorum must be <= 100%");
        admin = msg.sender;
        quorum = _quorum;
        votingPeriod = _votingPeriod;

        // Add admin as first member
        memberTokens[admin] = 1;
        totalTokens = 1;
    }

    /**
     * @dev Allow members to create a funding proposal
     */
    function createProposal(
        address payable _recipient,
        uint256 _amount,
        string memory _description
    ) external onlyMember returns (uint256) {
        require(_amount <= address(this).balance, "Requested amount exceeds treasury balance");

        uint256 proposalId = proposalCount++;

        Proposal storage newProposal = proposals[proposalId];
        newProposal.id = proposalId;
        newProposal.proposer = msg.sender;
        newProposal.recipient = _recipient;
        newProposal.amount = _amount;
        newProposal.description = _description;
        newProposal.deadline = block.timestamp + votingPeriod;
        newProposal.executed = false;

        emit ProposalCreated(proposalId, msg.sender, _recipient, _amount, _description);

        return proposalId;
    }

    /**
     * @dev Allow members to vote on proposals
     */
    function castVote(uint256 _proposalId, bool _support) external onlyMember {
        Proposal storage proposal = proposals[_proposalId];

        require(block.timestamp < proposal.deadline, "Voting period has ended");
        require(!proposal.executed, "Proposal has already been executed");
        require(!proposal.hasVoted[msg.sender], "Member has already voted");

        proposal.hasVoted[msg.sender] = true;

        uint256 voteWeight = memberTokens[msg.sender];

        if (_support) {
            proposal.votesFor += voteWeight;
        } else {
            proposal.votesAgainst += voteWeight;
        }

        emit VoteCast(_proposalId, msg.sender, _support, voteWeight);

        if (canExecute(_proposalId)) {
            executeProposal(_proposalId);
        }
    }

    /**
     * @dev Execute a proposal if it has passed
     */
    function executeProposal(uint256 _proposalId) public {
        require(canExecute(_proposalId), "Proposal cannot be executed");

        Proposal storage proposal = proposals[_proposalId];
        proposal.executed = true;

        (bool success, ) = proposal.recipient.call{value: proposal.amount}("");
        require(success, "Transfer failed");

        emit ProposalExecuted(_proposalId);
    }

    /**
     * @dev Check if a proposal can be executed
     */
    function canExecute(uint256 _proposalId) public view returns (bool) {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.executed) {
            return false;
        }

        bool hasEnded = block.timestamp >= proposal.deadline;
        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        bool quorumReached = (totalVotes * 100) / totalTokens >= quorum;

        return hasEnded && quorumReached && proposal.votesFor > proposal.votesAgainst;
    }

    /**
     * @dev Allow admin to add new members or update existing ones
     */
    function updateMember(address _member, uint256 _tokens) external onlyAdmin {
        uint256 currentTokens = memberTokens[_member];
        memberTokens[_member] = _tokens;

        totalTokens = totalTokens - currentTokens + _tokens;

        emit MemberAdded(_member, _tokens);
    }

    /**
     * @dev Allow anyone to deposit funds into the treasury
     */
    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }

    /**
     * @dev Get basic information about a proposal
     */
    function getProposalInfo(uint256 _proposalId) external view returns (
        address proposer,
        address recipient,
        uint256 amount,
        string memory description,
        uint256 votesFor,
        uint256 votesAgainst,
        bool executed,
        uint256 deadline
    ) {
        Proposal storage proposal = proposals[_proposalId];
        return (
            proposal.proposer,
            proposal.recipient,
            proposal.amount,
            proposal.description,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.executed,
            proposal.deadline
        );
    }

    /**
     * @dev Allow admin to withdraw funds from the treasury
     * @param _amount Amount to withdraw
     * @param _recipient Address to receive the withdrawn funds
     */
    function adminWithdraw(uint256 _amount, address payable _recipient) external onlyAdmin {
        require(_amount <= address(this).balance, "Insufficient treasury balance");
        require(_recipient != address(0), "Invalid recipient address");

        (bool success, ) = _recipient.call{value: _amount}("");
        require(success, "Admin withdrawal failed");
    }

    /**
     * @dev Check if a member has voted on a proposal
     */
    function getHasVoted(uint256 _proposalId, address _voter) external view returns (bool) {
        return proposals[_proposalId].hasVoted[_voter];
    }

    /**
     * @dev Returns a list of active proposal IDs
     */
    function getActiveProposals() external view returns (uint256[] memory) {
        uint256[] memory temp = new uint256[](proposalCount);
        uint256 activeCount = 0;

        for (uint256 i = 0; i < proposalCount; i++) {
            Proposal storage proposal = proposals[i];
            if (!proposal.executed && block.timestamp < proposal.deadline) {
                temp[activeCount] = i;
                activeCount++;
            }
        }

        // Create a trimmed array of active proposal IDs
        uint256[] memory activeProposals = new uint256[](activeCount);
        for (uint256 j = 0; j < activeCount; j++) {
            activeProposals[j] = temp[j];
        }

        return activeProposals;
    }
}
