// SPDX-License-Identifier: MIT
// *****************************************************************************
// BAISHOU — AgentVote.sol — Agent governance vote for the v4 relaunch.
//
// WHAT THIS IS: an immutable, no-admin, no-funds voting contract. Holders of a
// Binance Agent ID (name.ai, non-transferable) decide the BAISHOU v4 relaunch
// parameters by on-chain vote. One Agent ID = one vote per question; because
// Agent IDs cannot be transferred or bought, the vote is sybil-resistant by
// design. Votes can be changed until the deadline; results stay readable
// forever after it.
//
// WHAT THIS IS NOT: it holds no funds, moves no tokens, has no owner, no
// admin functions and no upgrade path. The only external dependency is the
// Agent ID registry, read the exact same way AgentMint reads it:
//   id = uint256(keccak256(bytes(handleOf(user)))); ok = ownerOf(id) == user
//
// QUESTIONS (fixed at deploy, multiple choice):
//   Q0 pool-open threshold, paid shares:      168000 / 84000 / 42000 / 16800
//   Q1 base price per share, wei:             0.00168 / 0.00084 / 0.00336 BNB
//   Q2 free allocation per Agent ID, tokens:  168000000 / 84000000 / 336000000
//   Q3 sale window, days:                     14 / 21 / 30
//
// Voting closes 2026-12-09 08:00 UTC (the hackathon submission deadline).
// *****************************************************************************
pragma solidity ^0.8.24;

interface IAgentHandles {
    function ownerOf(uint256 tokenId) external view returns (address);
    function handleOf(address owner) external view returns (string memory);
}

contract AgentVote {
    /// @notice The Binance Agent ID registry (SPACE ID Agent ID, ERC-721).
    IAgentHandles public immutable registrar;

    /// @notice Voting deadline: 2026-12-09 08:00:00 UTC. Votes revert at
    ///         and after this timestamp; results remain readable forever.
    uint256 public constant DEADLINE = 1_796_803_200;

    /// @notice Number of fixed questions.
    uint256 public constant QUESTIONS = 4;

    /// @notice Unique Agent IDs that have voted on at least one question.
    uint256 public voterCount;

    // tokenId => question => chosen option + 1 (0 = no vote cast yet)
    mapping(uint256 => uint256[QUESTIONS]) private _choice;
    // question => option => vote count
    mapping(uint256 => uint256[4]) private _tally;
    // tokenId => has ever voted (for voterCount)
    mapping(uint256 => bool) private _seen;

    event Voted(uint256 indexed agentTokenId, uint256 question, uint256 option);

    error NotAgentIdHolder();
    error VotingClosed();
    error BadQuestion();
    error BadOption();

    constructor(address registrar_) {
        registrar = IAgentHandles(registrar_);
    }

    /// @notice Resolve an address to its Agent ID tokenId, mirroring
    ///         AgentMint._agent() exactly.
    /// @return id The Agent ID tokenId (keccak256 of the handle).
    /// @return ok True only if the address holds that Agent ID.
    function agentIdOf(address who) public view returns (uint256 id, bool ok) {
        try registrar.handleOf(who) returns (string memory handle) {
            if (bytes(handle).length == 0) return (0, false);
            id = uint256(keccak256(bytes(handle)));
            try registrar.ownerOf(id) returns (address owner) {
                ok = owner == who;
            } catch {
                ok = false;
            }
        } catch {
            ok = false;
        }
    }

    /// @notice Number of options for a question (4 for Q0, 3 for Q1..Q3).
    function optionCount(uint256 question) public pure returns (uint256) {
        if (question >= QUESTIONS) revert BadQuestion();
        return question == 0 ? 4 : 3;
    }

    /// @notice The fixed value an option stands for (see header for units).
    function optionValue(uint256 question, uint256 option) public pure returns (uint256) {
        if (question >= QUESTIONS) revert BadQuestion();
        if (option >= (question == 0 ? 4 : 3)) revert BadOption();
        if (question == 0) {
            // Pool-open threshold, paid shares.
            if (option == 0) return 168_000;
            if (option == 1) return 84_000;
            if (option == 2) return 42_000;
            return 16_800;
        }
        if (question == 1) {
            // Base price per share, wei.
            if (option == 0) return 0.00168 ether;
            if (option == 1) return 0.00084 ether;
            return 0.00336 ether;
        }
        if (question == 2) {
            // Free allocation per Agent ID, tokens.
            if (option == 0) return 168_000_000;
            if (option == 1) return 84_000_000;
            return 336_000_000;
        }
        // Sale window, days.
        if (option == 0) return 14;
        if (option == 1) return 21;
        return 30;
    }

    /// @notice Cast or change your vote on a question. One vote per Agent ID
    ///         per question; changing a vote moves the tally. Reverts after
    ///         the deadline.
    function vote(uint256 question, uint256 option) external {
        if (block.timestamp >= DEADLINE) revert VotingClosed();
        if (question >= QUESTIONS) revert BadQuestion();
        if (option >= (question == 0 ? 4 : 3)) revert BadOption();

        (uint256 id, bool ok) = agentIdOf(msg.sender);
        if (!ok) revert NotAgentIdHolder();

        uint256 prev = _choice[id][question];
        if (prev != 0 && prev - 1 != option) {
            _tally[question][prev - 1] -= 1;
            _tally[question][option] += 1;
        } else if (prev == 0) {
            _tally[question][option] += 1;
        }
        _choice[id][question] = option + 1;

        if (!_seen[id]) {
            _seen[id] = true;
            voterCount += 1;
        }

        emit Voted(id, question, option);
    }

    /// @notice Vote counts per option for a question (length-4 array; the
    ///         4th slot is always 0 for the 3-option questions).
    function getResults(uint256 question) external view returns (uint256[4] memory) {
        if (question >= QUESTIONS) revert BadQuestion();
        return _tally[question];
    }

    /// @notice Whether an Agent ID has voted on a question.
    function hasVoted(uint256 agentTokenId, uint256 question) external view returns (bool) {
        if (question >= QUESTIONS) revert BadQuestion();
        return _choice[agentTokenId][question] != 0;
    }

    /// @notice The option an Agent ID currently backs on a question.
    /// @return voted True if a vote exists.
    /// @return option The chosen option index (meaningful only if voted).
    function myVote(uint256 agentTokenId, uint256 question)
        external
        view
        returns (bool voted, uint256 option)
    {
        if (question >= QUESTIONS) revert BadQuestion();
        uint256 c = _choice[agentTokenId][question];
        return (c != 0, c == 0 ? 0 : c - 1);
    }
}
