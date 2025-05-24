// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title DAOTreasury
 * @dev A smart contract for managing DAO treasury with proposal and voting mechanisms
 */
contract DAOTreasury {
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

    address public admin;
    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;
    mapping(address => uint256) public memberTokens;
    uint256 public totalTokens;
    uint256 public quorum;
    uint256 public votingPeriod;

    event ProposalCreated(uint256 proposalId, address proposer, address recipient, uint256 amount, string description);
    event VoteCast(uint256 proposalId, address voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 proposalId);
    event ProposalCanceled(uint256 proposalId);
    event MemberAdded(address member, uint256 tokens);
    event FundsDeposited(address from, uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    modifier onlyMember() {
        require(memberTokens[msg.sender] > 0, "Only members can perform this action");
        _;
    }

    constructor(uint256 _quorum, uint256 _votingPeriod) {
        require(_quorum <= 100, "Quorum must be <= 100%");
        admin = msg.sender;
        quorum = _quorum;
        votingPeriod = _votingPeriod;
        memberTokens[admin] = 1;
        totalTokens = 1;
    }

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
        newProposal.canceled = false;

        emit ProposalCreated(proposalId, msg.sender, _recipient, _amount, _description);

        return proposalId;
    }

    function castVote(uint256 _proposalId, bool _support) external onlyMember {
        Proposal storage proposal = proposals[_proposalId];

        require(!proposal.canceled, "Proposal has been canceled");
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

    function executeProposal(uint256 _proposalId) public {
        require(canExecute(_proposalId), "Proposal cannot be executed");

        Proposal storage proposal = proposals[_proposalId];
        proposal.executed = true;

        (bool success, ) = proposal.recipient.call{value: proposal.amount}("");
        require(success, "Transfer failed");

        emit ProposalExecuted(_proposalId);
    }

    function canExecute(uint256 _proposalId) public view returns (bool) {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.executed || proposal.canceled) {
            return false;
        }

        bool hasEnded = block.timestamp >= proposal.deadline;
        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        bool quorumReached = (totalVotes * 100) / totalTokens >= quorum;

        return hasEnded && quorumReached && proposal.votesFor > proposal.votesAgainst;
    }

    function updateMember(address _member, uint256 _tokens) external onlyAdmin {
        uint256 currentTokens = memberTokens[_member];
        memberTokens[_member] = _tokens;

        totalTokens = totalTokens - currentTokens + _tokens;

        emit MemberAdded(_member, _tokens);
    }

    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }

    function getProposalInfo(uint256 _proposalId) external view returns (
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

    function adminWithdraw(uint256 _amount, address payable _recipient) external onlyAdmin {
        require(_amount <= address(this).balance, "Insufficient treasury balance");
        require(_recipient != address(0), "Invalid recipient address");

        (bool success, ) = _recipient.call{value: _amount}("");
        require(success, "Admin withdrawal failed");
    }

    function getHasVoted(uint256 _proposalId, address _voter) external view returns (bool) {
        return proposals[_proposalId].hasVoted[_voter];
    }

    function getActiveProposals() external view returns (uint256[] memory) {
        uint256[] memory temp = new uint256[](proposalCount);
        uint256 activeCount = 0;

        for (uint256 i = 0; i < proposalCount; i++) {
            Proposal storage proposal = proposals[i];
            if (!proposal.executed && !proposal.canceled && block.timestamp < proposal.deadline) {
                temp[activeCount] = i;
                activeCount++;
            }
        }

        uint256[] memory activeProposals = new uint256[](activeCount);
        for (uint256 j = 0; j < activeCount; j++) {
            activeProposals[j] = temp[j];
        }

        return activeProposals;
    }

    /**
     * @dev Returns the current result status of a proposal
     * @return result 0 = Pending, 1 = Passed, 2 = Failed, 3 = Canceled
     */
    function getProposalResult(uint256 _proposalId) external view returns (uint8 result) {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.canceled) {
            return 3; // Canceled
        }

        if (block.timestamp < proposal.deadline) {
            return 0; // Pending
        }

        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        bool quorumReached = (totalVotes * 100) / totalTokens >= quorum;

        if (quorumReached && proposal.votesFor > proposal.votesAgainst) {
            return 1; // Passed
        } else {
            return 2; // Failed
        }
    }

    /**
     * @dev Allows the proposer or admin to cancel a proposal before execution
     */
    function cancelProposal(uint256 _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        require(!proposal.executed, "Cannot cancel an already executed proposal");
        require(!proposal.canceled, "Proposal already canceled");
        require(msg.sender == proposal.proposer || msg.sender == admin, "Only proposer or admin can cancel");

        proposal.canceled = true;

        emit ProposalCanceled(_proposalId);
    }
}
