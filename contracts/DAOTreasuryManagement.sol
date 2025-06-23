// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract DAOTreasury {
    enum ProposalStatus { Pending, Passed, Failed, Canceled }

    struct ProposalCore {
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
    }

    address public immutable admin;
    uint256 public immutable votingPeriod;
    uint256 public immutable quorum;

    uint256 public proposalCount;
    uint256 public totalTokens;

    mapping(uint256 => ProposalCore) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
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

    function createProposal(address payable recipient, uint256 amount, string calldata description)
        external onlyMember returns (uint256)
    {
        require(amount <= address(this).balance, "Insufficient balance");
        require(recipient != address(0), "Invalid recipient");

        uint256 id = proposalCount++;
        proposals[id] = ProposalCore({
            id: id,
            proposer: msg.sender,
            recipient: recipient,
            amount: amount,
            description: description,
            votesFor: 0,
            votesAgainst: 0,
            executed: false,
            canceled: false,
            deadline: block.timestamp + votingPeriod
        });

        emit ProposalCreated(id, msg.sender, recipient, amount, description);
        return id;
    }

    function castVote(uint256 proposalId, bool support)
        external onlyMember validProposal(proposalId)
    {
        ProposalCore storage p = proposals[proposalId];
        require(!p.executed && !p.canceled && block.timestamp < p.deadline, "Voting closed or invalid");
        require(!hasVoted[proposalId][msg.sender], "Already voted");

        hasVoted[proposalId][msg.sender] = true;
        uint256 weight = memberTokens[msg.sender];

        if (support) {
            p.votesFor += weight;
        } else {
            p.votesAgainst += weight;
        }

        emit VoteCast(proposalId, msg.sender, support, weight);

        if (_canExecute(p)) _executeProposal(p);
    }

    function executeProposal(uint256 proposalId) external validProposal(proposalId) {
        ProposalCore storage p = proposals[proposalId];
        require(_canExecute(p), "Cannot execute");
        _executeProposal(p);
    }

    function cancelProposal(uint256 proposalId) external validProposal(proposalId) {
        ProposalCore storage p = proposals[proposalId];
        require(!p.executed && !p.canceled, "Already finalized");
        require(msg.sender == p.proposer || msg.sender == admin, "Unauthorized");

        p.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    function _canExecute(ProposalCore storage p) private view returns (bool) {
        if (p.executed || p.canceled || block.timestamp < p.deadline) return false;
        uint256 totalVotes = p.votesFor + p.votesAgainst;
        return (totalVotes * 100 / totalTokens >= quorum) && (p.votesFor > p.votesAgainst);
    }

    function _executeProposal(ProposalCore storage p) private {
        p.executed = true;
        (bool success, ) = p.recipient.call{value: p.amount}("");
        require(success, "Transfer failed");
        emit ProposalExecuted(p.id);
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

    function _updateMember(address member, uint256 tokens) private {
        uint256 current = memberTokens[member];
        memberTokens[member] = tokens;
        totalTokens = totalTokens - current + tokens;
        emit MemberUpdated(member, tokens);
    }

    function getProposalStatus(uint256 proposalId) public view validProposal(proposalId) returns (ProposalStatus) {
        ProposalCore storage p = proposals[proposalId];
        if (p.canceled) return ProposalStatus.Canceled;
        if (p.executed) return ProposalStatus.Passed;
        if (block.timestamp < p.deadline) return ProposalStatus.Pending;

        uint256 totalVotes = p.votesFor + p.votesAgainst;
        bool quorumReached = (totalVotes * 100) / totalTokens >= quorum;

        return (quorumReached && p.votesFor > p.votesAgainst)
            ? ProposalStatus.Passed
            : ProposalStatus.Failed;
    }

    function getAllProposals() external view returns (ProposalCore[] memory all, ProposalStatus[] memory statuses) {
        uint256 count = proposalCount;
        all = new ProposalCore[](count);
        statuses = new ProposalStatus[](count);
        for (uint256 i; i < count; ++i) {
            all[i] = proposals[i];
            statuses[i] = getProposalStatus(i);
        }
    }

    function getProposalsByStatus(bool activeOnly, bool executedOnly) external view returns (ProposalCore[] memory filtered) {
        uint256 count;
        for (uint256 i; i < proposalCount; ++i) {
            ProposalCore storage p = proposals[i];
            if ((activeOnly && _isActive(p)) || (executedOnly && p.executed)) count++;
        }

        filtered = new ProposalCore[](count);
        uint256 index;
        for (uint256 i; i < proposalCount; ++i) {
            ProposalCore storage p = proposals[i];
            if ((activeOnly && _isActive(p)) || (executedOnly && p.executed)) {
                filtered[index++] = p;
            }
        }
    }

    function _isActive(ProposalCore storage p) private view returns (bool) {
        return !p.executed && !p.canceled && block.timestamp < p.deadline;
    }

    function getUnallocatedFunds() public view returns (uint256 unallocated) {
        for (uint256 i; i < proposalCount; ++i) {
            ProposalCore storage p = proposals[i];
            if (!p.executed && !p.canceled) {
                unallocated += p.amount;
            }
        }
        return address(this).balance - unallocated;
    }

    function getMemberInfo(address member) external view returns (uint256 tokenBalance, uint256 votingPower) {
        tokenBalance = memberTokens[member];
        votingPower = tokenBalance;
    }

    function getProposalInfo(uint256 proposalId) external view validProposal(proposalId)
        returns (address, address, uint256, string memory, uint256, uint256, bool, uint256, bool)
    {
        ProposalCore storage p = proposals[proposalId];
        return (
            p.proposer, p.recipient, p.amount, p.description,
            p.votesFor, p.votesAgainst, p.executed, p.deadline, p.canceled
        );
    }

    function getHasVoted(uint256 proposalId, address voter) external view validProposal(proposalId) returns (bool) {
        return hasVoted[proposalId][voter];
    }

    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }
}
