// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title DAOTreasury
 * @dev A smart contract for managing DAO treasury with proposal and voting mechanisms
 * @notice Refactored to improve code organization, gas efficiency, and readability
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

    // External Functions

    /**
     * @notice Create a new proposal
     */
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

    /**
     * @notice Cast a vote on a proposal
     */
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

        // Try to execute if conditions are met
        if (canExecute(_proposalId)) {
            executeProposal(_proposalId);
        }
    }

    /**
     * @notice Execute a proposal that has passed
     */
    function executeProposal(uint256 _proposalId) public validProposal(_proposalId) {
        require(canExecute(_proposalId), "Cannot execute");

        Proposal storage proposal = proposals[_proposalId];
        proposal.executed = true;

        (bool success, ) = proposal.recipient.call{value: proposal.amount}("");
        require(success, "Transfer failed");

        emit ProposalExecuted(_proposalId);
    }

    /**
     * @notice Cancel a proposal
     */
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

    /**
     * @notice Update member's token balance
     */
    function updateMember(address _member, uint256 _tokens) external onlyAdmin {
        require(_member != address(0), "Invalid address");
        _updateMember(_member, _tokens);
    }

    /**
     * @notice Admin withdrawal function
     */
    function adminWithdraw(uint256 _amount, address payable _recipient) external onlyAdmin {
        require(_amount <= address(this).balance, "Insufficient balance");
        require(_recipient != address(0), "Invalid recipient");

        (bool success, ) = _recipient.call{value: _amount}("");
        require(success, "Withdrawal failed");
    }

    // Public View Functions

    /**
     * @notice Check if a proposal can be executed
     */
    function canExecute(uint256 _proposalId) public view validProposal(_proposalId) returns (bool) {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.executed || proposal.canceled) return false;
        if (block.timestamp < proposal.deadline) return false;

        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        bool quorumReached = (totalVotes * 100) / totalTokens >= quorum;

        return quorumReached && proposal.votesFor > proposal.votesAgainst;
    }

    /**
     * @notice Get basic proposal information
     */
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

    /**
     * @notice Get proposal status
     */
    function getProposalResult(uint256 _proposalId) public view validProposal(_proposalId) returns (ProposalStatus) {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.canceled) return ProposalStatus.Canceled;
        if (block.timestamp < proposal.deadline) return ProposalStatus.Pending;

        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        bool quorumReached = (totalVotes * 100) / totalTokens >= quorum;

        if (quorumReached && proposal.votesFor > proposal.votesAgainst) {
            return ProposalStatus.Passed;
        }
        return ProposalStatus.Failed;
    }

    /**
     * @notice Check if a member has voted on a proposal
     */
    function getHasVoted(uint256 _proposalId, address _voter) public view validProposal(_proposalId) returns (bool) {
        return proposals[_proposalId].hasVoted[_voter];
    }

    // External View Functions

    /**
     * @notice Get all active proposals
     */
    function getActiveProposals() external view returns (uint256[] memory) {
        return _filterProposals(false, false, true);
    }

    /**
     * @notice Get all proposals created by a member
     */
    function getMemberProposals(address member) external view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](proposalCount);
        uint256 count = 0;

        for (uint256 i = 0; i < proposalCount; i++) {
            if (proposals[i].proposer == member) {
                result[count++] = i;
            }
        }

        return _trimArray(result, count);
    }

    /**
     * @notice Get all proposals a member has voted on
     */
    function getMemberVotingHistory(address member) external view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](proposalCount);
        uint256 count = 0;

        for (uint256 i = 0; i < proposalCount; i++) {
            if (proposals[i].hasVoted[member]) {
                result[count++] = i;
            }
        }

        return _trimArray(result, count);
    }

    /**
     * @notice Get top N most voted proposals
     */
    function getTopVotedProposals(uint256 topN) external view returns (uint256[] memory) {
        require(topN > 0, "topN must be > 0");
        
        uint256[] memory proposalIds = new uint256[](proposalCount);
        uint256[] memory votes = new uint256[](proposalCount);

        // Initialize arrays
        for (uint256 i = 0; i < proposalCount; i++) {
            proposalIds[i] = i;
            votes[i] = proposals[i].votesFor;
        }

        // Sort by votes (descending)
        for (uint256 i = 0; i < proposalCount - 1; i++) {
            for (uint256 j = i + 1; j < proposalCount; j++) {
                if (votes[j] > votes[i]) {
                    (votes[i], votes[j]) = (votes[j], votes[i]);
                    (proposalIds[i], proposalIds[j]) = (proposalIds[j], proposalIds[i]);
                }
            }
        }

        // Return top N results
        uint256 resultSize = topN < proposalCount ? topN : proposalCount;
        uint256[] memory topProposals = new uint256[](resultSize);
        
        for (uint256 k = 0; k < resultSize; k++) {
            topProposals[k] = proposalIds[k];
        }

        return topProposals;
    }

    // Private Functions

    /**
     * @dev Internal function to update member tokens
     */
    function _updateMember(address _member, uint256 _tokens) private {
        uint256 currentTokens = memberTokens[_member];
        memberTokens[_member] = _tokens;
        totalTokens = totalTokens - currentTokens + _tokens;
        emit MemberUpdated(_member, _tokens);
    }

    /**
     * @dev Filter proposals based on parameters
     */
    function _filterProposals(
        bool includeExecuted,
        bool includeCanceled,
        bool includeActive
    ) private view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](proposalCount);
        uint256 count = 0;

        for (uint256 i = 0; i < proposalCount; i++) {
            Proposal storage p = proposals[i];
            
            bool isActive = !p.executed && !p.canceled && block.timestamp < p.deadline;
            bool include = 
                (includeExecuted && p.executed) ||
                (includeCanceled && p.canceled) ||
                (includeActive && isActive);

            if (include) {
                result[count++] = i;
            }
        }

        return _trimArray(result, count);
    }

    /**
     * @dev Trim an array to its actual size
     */
    function _trimArray(uint256[] memory arr, uint256 size) private pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            result[i] = arr[i];
        }
        return result;
    }

    // Fallback function
    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }
}
