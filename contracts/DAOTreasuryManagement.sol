// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title DAOTreasury
 * @dev Core DAO treasury management with proposal and voting mechanisms
 */
contract DAOTreasury {
    // Enums
    enum ProposalStatus { Pending, Passed, Failed, Canceled }

    // Structs
    struct Proposal {
        uint256 id;
        address proposer;
        address payable recipient;
        uint256 amount;
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        bool executed;
        bool canceled;
        uint256 deadline;
        mapping(address => bool) hasVoted;
    }

    // State Variables
    address public immutable admin;
    uint256 public immutable votingPeriod;
    uint256 public immutable quorum;
    
    uint256 public proposalCount;
    uint256 public totalTokens;
    mapping(uint256 => Proposal) public proposals;
    mapping(address => uint256) public memberTokens;

    // Events
    event ProposalCreated(uint256 proposalId, address proposer, address recipient, uint256 amount, string description);
    event VoteCast(uint256 proposalId, address voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 proposalId);
    event ProposalCanceled(uint256 proposalId);
    event MemberUpdated(address member, uint256 tokens);
    event FundsDeposited(address from, uint256 amount);

    // Modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyMember() {
        require(memberTokens[msg.sender] > 0, "Only members");
        _;
    }

    modifier validProposal(uint256 proposalId) {
        require(proposalId < proposalCount, "Invalid proposal");
        _;
    }

    constructor(uint256 _quorum, uint256 _votingPeriod) {
        require(_quorum <= 100, "Quorum <= 100%");
        admin = msg.sender;
        quorum = _quorum;
        votingPeriod = _votingPeriod;
        
        // Initialize admin as first member
        _updateMember(admin, 1);
    }

    // Core Functions

    function createProposal(
        address payable _recipient,
        uint256 _amount,
        string memory _description
    ) external onlyMember returns (uint256) {
        require(_amount <= address(this).balance, "Amount exceeds balance");
        require(_recipient != address(0), "Invalid recipient");

        uint256 proposalId = proposalCount++;
        Proposal storage newProposal = proposals[proposalId];

        newProposal.id = proposalId;
        newProposal.proposer = msg.sender;
        newProposal.recipient = _recipient;
        newProposal.amount = _amount;
        newProposal.description = _description;
        newProposal.deadline = block.timestamp + votingPeriod;

        emit ProposalCreated(proposalId, msg.sender, _recipient, _amount, _description);
        return proposalId;
    }

    function castVote(uint256 _proposalId, bool _support) external onlyMember validProposal(_proposalId) {
        Proposal storage proposal = proposals[_proposalId];
        
        require(!proposal.canceled, "Proposal canceled");
        require(block.timestamp < proposal.deadline, "Voting ended");
        require(!proposal.executed, "Proposal executed");
        require(!proposal.hasVoted[msg.sender], "Already voted");

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

    function executeProposal(uint256 _proposalId) public validProposal(_proposalId) {
        require(canExecute(_proposalId), "Cannot execute");

        Proposal storage proposal = proposals[_proposalId];
        proposal.executed = true;

        (bool success, ) = proposal.recipient.call{value: proposal.amount}("");
        require(success, "Transfer failed");

        emit ProposalExecuted(_proposalId);
    }

    function cancelProposal(uint256 _proposalId) external validProposal(_proposalId) {
        Proposal storage proposal = proposals[_proposalId];
        
        require(!proposal.executed, "Already executed");
        require(!proposal.canceled, "Already canceled");
        require(
            msg.sender == proposal.proposer || msg.sender == admin,
            "Only proposer/admin"
        );

        proposal.canceled = true;
        emit ProposalCanceled(_proposalId);
    }

    function updateMember(address _member, uint256 _tokens) external onlyAdmin {
        require(_member != address(0), "Invalid address");
        _updateMember(_member, _tokens);
    }

    // Essential View Functions

    function canExecute(uint256 _proposalId) public view validProposal(_proposalId) returns (bool) {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.executed || proposal.canceled) return false;
        if (block.timestamp < proposal.deadline) return false;

        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        bool quorumReached = (totalVotes * 100) / totalTokens >= quorum;

        return quorumReached && proposal.votesFor > proposal.votesAgainst;
    }

    function getProposalInfo(uint256 _proposalId) public view validProposal(_proposalId) returns (
        address proposer,
        address recipient,
        uint256 amount,
        string memory description,
        uint256 votesFor,
        uint256 votesAgainst,
        bool executed,
        uint256 deadline,
        bool canceled
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
            proposal.deadline,
            proposal.canceled
        );
    }

    function getHasVoted(uint256 _proposalId, address _voter) public view validProposal(_proposalId) returns (bool) {
        return proposals[_proposalId].hasVoted[_voter];
    }

    // Private Functions

    function _updateMember(address _member, uint256 _tokens) private {
        uint256 currentTokens = memberTokens[_member];
        memberTokens[_member] = _tokens;
        totalTokens = totalTokens - currentTokens + _tokens;
        emit MemberUpdated(_member, _tokens);
    }

    // Fallback function
    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }
}
