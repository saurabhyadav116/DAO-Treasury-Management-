// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract DAOTreasury {
    enum ProposalStatus { Pending, Passed, Failed, Canceled }

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

    address public immutable admin;
    uint256 public immutable votingPeriod;
    uint256 public immutable quorum;

    uint256 public proposalCount;
    uint256 public totalTokens;

    mapping(uint256 => Proposal) public proposals;
    mapping(address => uint256) public memberTokens;

    event ProposalCreated(uint256 indexed id, address indexed proposer, address indexed recipient, uint256 amount, string description);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);
    event MemberUpdated(address indexed member, uint256 tokens);
    event FundsDeposited(address indexed from, uint256 amount);

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
        require(_quorum <= 100, "Quorum must be <= 100%");
        admin = msg.sender;
        quorum = _quorum;
        votingPeriod = _votingPeriod;

        _updateMember(admin, 1);
    }

    function createProposal(
        address payable _recipient,
        uint256 _amount,
        string memory _description
    ) external onlyMember returns (uint256) {
        require(_amount <= address(this).balance, "Insufficient balance");
        require(_recipient != address(0), "Invalid recipient");

        uint256 id = proposalCount++;
        Proposal storage p = proposals[id];

        p.id = id;
        p.proposer = msg.sender;
        p.recipient = _recipient;
        p.amount = _amount;
        p.description = _description;
        p.deadline = block.timestamp + votingPeriod;

        emit ProposalCreated(id, msg.sender, _recipient, _amount, _description);
        return id;
    }

    function castVote(uint256 proposalId, bool support)
        external
        onlyMember
        validProposal(proposalId)
    {
        Proposal storage p = proposals[proposalId];

        require(!p.executed, "Already executed");
        require(!p.canceled, "Proposal canceled");
        require(block.timestamp < p.deadline, "Voting closed");
        require(!p.hasVoted[msg.sender], "Already voted");

        p.hasVoted[msg.sender] = true;
        uint256 weight = memberTokens[msg.sender];

        if (support) {
            p.votesFor += weight;
        } else {
            p.votesAgainst += weight;
        }

        emit VoteCast(proposalId, msg.sender, support, weight);

        if (_canExecute(p)) {
            _executeProposal(p);
        }
    }

    function executeProposal(uint256 proposalId) external validProposal(proposalId) {
        Proposal storage p = proposals[proposalId];
        require(_canExecute(p), "Cannot execute");
        _executeProposal(p);
    }

    function cancelProposal(uint256 proposalId) external validProposal(proposalId) {
        Proposal storage p = proposals[proposalId];

        require(!p.executed, "Already executed");
        require(!p.canceled, "Already canceled");
        require(msg.sender == p.proposer || msg.sender == admin, "Unauthorized");

        p.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    function updateMember(address member, uint256 tokens) external onlyAdmin {
        require(member != address(0), "Invalid address");
        _updateMember(member, tokens);
    }

    function withdrawUnallocatedFunds(address payable to, uint256 amount) external onlyAdmin {
        require(to != address(0), "Invalid address");
        require(amount <= getUnallocatedFunds(), "Insufficient unallocated funds");

        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");
    }

    function getProposalInfo(uint256 proposalId)
        external
        view
        validProposal(proposalId)
        returns (
            address proposer,
            address recipient,
            uint256 amount,
            string memory description,
            uint256 votesFor,
            uint256 votesAgainst,
            bool executed,
            uint256 deadline,
            bool canceled
        )
    {
        Proposal storage p = proposals[proposalId];
        return (
            p.proposer,
            p.recipient,
            p.amount,
            p.description,
            p.votesFor,
            p.votesAgainst,
            p.executed,
            p.deadline,
            p.canceled
        );
    }

    function getHasVoted(uint256 proposalId, address voter)
        external
        view
        validProposal(proposalId)
        returns (bool)
    {
        return proposals[proposalId].hasVoted[voter];
    }

    function getProposalStatus(uint256 proposalId)
        public
        view
        validProposal(proposalId)
        returns (ProposalStatus)
    {
        Proposal storage p = proposals[proposalId];
        if (p.canceled) return ProposalStatus.Canceled;
        if (p.executed) return ProposalStatus.Passed;
        if (block.timestamp < p.deadline) return ProposalStatus.Pending;

        uint256 totalVotes = p.votesFor + p.votesAgainst;
        bool quorumReached = (totalVotes * 100) / totalTokens >= quorum;

        if (quorumReached && p.votesFor > p.votesAgainst) {
            return ProposalStatus.Passed;
        }

        return ProposalStatus.Failed;
    }

    function canExecute(uint256 proposalId)
        external
        view
        validProposal(proposalId)
        returns (bool)
    {
        return _canExecute(proposals[proposalId]);
    }

    function getAllProposals()
        external
        view
        returns (
            uint256[] memory ids,
            address[] memory proposers,
            address[] memory recipients,
            uint256[] memory amounts,
            ProposalStatus[] memory statuses,
            uint256[] memory deadlines
        )
    {
        uint256 count = proposalCount;

        ids = new uint256[](count);
        proposers = new address[](count);
        recipients = new address[](count);
        amounts = new uint256[](count);
        statuses = new ProposalStatus[](count);
        deadlines = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            Proposal storage p = proposals[i];
            ids[i] = p.id;
            proposers[i] = p.proposer;
            recipients[i] = p.recipient;
            amounts[i] = p.amount;
            statuses[i] = getProposalStatus(i);
            deadlines[i] = p.deadline;
        }
    }

    /// ✅ New Function: Get all active proposals
    function getActiveProposals()
        external
        view
        returns (
            uint256[] memory ids,
            address[] memory proposers,
            address[] memory recipients,
            uint256[] memory amounts,
            string[] memory descriptions,
            uint256[] memory deadlines
        )
    {
        uint256 activeCount;

        // Count active proposals
        for (uint256 i = 0; i < proposalCount; i++) {
            Proposal storage p = proposals[i];
            if (!p.executed && !p.canceled && block.timestamp < p.deadline) {
                activeCount++;
            }
        }

        ids = new uint256[](activeCount);
        proposers = new address[](activeCount);
        recipients = new address[](activeCount);
        amounts = new uint256[](activeCount);
        descriptions = new string[](activeCount);
        deadlines = new uint256[](activeCount);

        uint256 index = 0;
        for (uint256 i = 0; i < proposalCount; i++) {
            Proposal storage p = proposals[i];
            if (!p.executed && !p.canceled && block.timestamp < p.deadline) {
                ids[index] = p.id;
                proposers[index] = p.proposer;
                recipients[index] = p.recipient;
                amounts[index] = p.amount;
                descriptions[index] = p.description;
                deadlines[index] = p.deadline;
                index++;
            }
        }
    }

    /// ✅ New Function: Get all executed proposals
    function getExecutedProposals()
        external
        view
        returns (
            uint256[] memory ids,
            address[] memory proposers,
            address[] memory recipients,
            uint256[] memory amounts,
            string[] memory descriptions,
            uint256[] memory timestamps
        )
    {
        uint256 executedCount;

        for (uint256 i = 0; i < proposalCount; i++) {
            if (proposals[i].executed) {
                executedCount++;
            }
        }

        ids = new uint256[](executedCount);
        proposers = new address[](executedCount);
        recipients = new address[](executedCount);
        amounts = new uint256[](executedCount);
        descriptions = new string[](executedCount);
        timestamps = new uint256[](executedCount);

        uint256 index = 0;
        for (uint256 i = 0; i < proposalCount; i++) {
            Proposal storage p = proposals[i];
            if (p.executed) {
                ids[index] = p.id;
                proposers[index] = p.proposer;
                recipients[index] = p.recipient;
                amounts[index] = p.amount;
                descriptions[index] = p.description;
                timestamps[index] = p.deadline;
                index++;
            }
        }
    }

    function getUnallocatedFunds() public view returns (uint256) {
        uint256 committed;

        for (uint256 i = 0; i < proposalCount; i++) {
            Proposal storage p = proposals[i];
            if (!p.executed && !p.canceled) {
                committed += p.amount;
            }
        }

        return address(this).balance - committed;
    }

    function _updateMember(address member, uint256 tokens) internal {
        uint256 current = memberTokens[member];
        memberTokens[member] = tokens;
        totalTokens = totalTokens - current + tokens;

        emit MemberUpdated(member, tokens);
    }

    function _canExecute(Proposal storage p) internal view returns (bool) {
        if (p.executed || p.canceled || block.timestamp < p.deadline) return false;

        uint256 totalVotes = p.votesFor + p.votesAgainst;
        bool quorumReached = (totalVotes * 100) / totalTokens >= quorum;

        return quorumReached && p.votesFor > p.votesAgainst;
    }

    function _executeProposal(Proposal storage p) internal {
        p.executed = true;

        (bool success, ) = p.recipient.call{value: p.amount}("");
        require(success, "Transfer failed");

        emit ProposalExecuted(p.id);
    }

    /// @notice Returns a member's token balance and voting power
    function getMemberInfo(address member)
        external
        view
        returns (uint256 tokenBalance, uint256 votingPower)
    {
        tokenBalance = memberTokens[member];
        votingPower = tokenBalance;
    }

    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }
}
