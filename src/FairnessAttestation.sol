// SPDX-License-Identifier: MIT
// *****************************************************************************
// BAISHOU — FairnessAttestation.sol — participant-verified fairness registry.
//
// WHAT THIS IS: an immutable, no-admin, no-funds registry where ONLY wallets
// that actually claimed BAISHOU's free allocation can record, once, an
// on-chain attestation that they received identical terms: same price, same
// cap, same rules. The act of attesting is the statement; there is no
// message field and nothing to endorse, rate or review. This turns the
// project's fairness claim into evidence recorded by its own participants,
// each entry tied to an Agent ID whose free claim is readable in AgentMint.
//
// ELIGIBILITY (both checks, in order):
//   1. msg.sender holds a Binance Agent ID, resolved exactly the way
//      AgentMint._agent() and AgentVote resolve it:
//        id = uint256(keccak256(bytes(handleOf(user)))); ok = ownerOf(id) == user
//   2. That Agent ID has claimed the free allocation:
//      AgentMint.claimedFree(id) == true.
//
// WHAT THIS IS NOT: it holds no funds, moves no tokens, has no owner, no
// admin functions and no upgrade path. One attestation per Agent ID, ever;
// attestations cannot be edited or withdrawn. The only external
// dependencies are the Agent ID registry and the AgentMint contract, both
// read-only.
// *****************************************************************************
pragma solidity ^0.8.24;

interface IAgentHandles {
    function ownerOf(uint256 tokenId) external view returns (address);
    function handleOf(address owner) external view returns (string memory);
}

interface IAgentMintClaims {
    function claimedFree(uint256 agentTokenId) external view returns (bool);
}

contract FairnessAttestation {
    /// @notice The Binance Agent ID registry (SPACE ID Agent ID, ERC-721).
    IAgentHandles public immutable registrar;

    /// @notice The BAISHOU AgentMint contract (free-claim registry).
    IAgentMintClaims public immutable agentMint;

    /// @notice Number of Agent IDs that have attested.
    uint256 public attestationCount;

    // agentTokenId => attestation timestamp (0 = no attestation yet)
    mapping(uint256 => uint256) private _attestedAt;

    event Attested(uint256 indexed agentTokenId, address indexed wallet, uint256 timestamp);

    error NotAgentIdHolder();
    error NotFreeClaimer();
    error AlreadyAttested();

    constructor(address registrar_, address agentMint_) {
        registrar = IAgentHandles(registrar_);
        agentMint = IAgentMintClaims(agentMint_);
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

    /// @notice Record your attestation that you received identical terms.
    ///         Caller must hold an Agent ID that claimed the free
    ///         allocation. One attestation per Agent ID, ever.
    function attest() external {
        (uint256 id, bool ok) = agentIdOf(msg.sender);
        if (!ok) revert NotAgentIdHolder();
        if (!agentMint.claimedFree(id)) revert NotFreeClaimer();
        if (_attestedAt[id] != 0) revert AlreadyAttested();

        _attestedAt[id] = block.timestamp;
        attestationCount += 1;

        emit Attested(id, msg.sender, block.timestamp);
    }

    /// @notice Whether an Agent ID has attested.
    function hasAttested(uint256 agentTokenId) external view returns (bool) {
        return _attestedAt[agentTokenId] != 0;
    }

    /// @notice When an Agent ID attested (0 if it has not).
    function attestedAt(uint256 agentTokenId) external view returns (uint256) {
        return _attestedAt[agentTokenId];
    }
}
