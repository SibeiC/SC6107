// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArbitrageExecutor } from "./ArbitrageExecutor.sol";
import { IRouter, Route } from "../interfaces/IRouter.sol";

/// @title CommitRevealExecutor
/// @notice MEV-resistant wrapper around {ArbitrageExecutor}: a caller
///         first publishes a `keccak256` hash of their intended trade,
///         waits at least `minRevealDelay` blocks, then `reveal`s the
///         preimage to actually execute it. A reveal is single-use and
///         binds the committer's address into the hash so an observer
///         that learns the preimage cannot replay it.
/// @dev    Why this works on Sepolia: Flashbots' private mempool isn't
///         available there, but the task brief explicitly accepts
///         commit-reveal as a substitute. `minRevealDelay` and
///         `maxRevealWindow` are constructor arguments (no built-in
///         contract default; the deploy script picks 1 / 256). With
///         `minRevealDelay = 1` the contract is equivalent to a
///         1-block timelock — the simplest fallback path. Owner can
///         tighten or loosen the window later via {setRevealParams}.
contract CommitRevealExecutor is ArbitrageExecutor {
    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    /// @notice `commits[hash]` is the block in which a commit was published.
    ///         A zero value means "no live commit".
    mapping(bytes32 commitHash => uint256 committedAt) public commits;

    /// @notice Minimum number of blocks between commit and reveal. Always >= 1.
    uint64 public minRevealDelay;

    /// @notice Window after which a commit goes stale and cannot be revealed.
    ///         Packs onto the same slot as {minRevealDelay}.
    uint64 public maxRevealWindow;

    // ---------------------------------------------------------------------
    // Events / errors
    // ---------------------------------------------------------------------

    event Committed(address indexed committer, bytes32 indexed commitHash, uint256 blockNumber);
    event Revealed(address indexed committer, bytes32 indexed commitHash);
    event Cancelled(address indexed committer, bytes32 indexed commitHash);
    event Cleaned(address indexed cleaner, bytes32 indexed commitHash);
    event RevealParamsUpdated(uint64 minDelay, uint64 maxWindow);

    error CommitAlreadyExists();
    error NoSuchCommit();
    error RevealTooEarly(uint256 current, uint256 earliest);
    error RevealExpired();
    error CommitStillLive(uint256 current, uint256 earliestCleanup);
    error InvalidRevealParams();

    // ---------------------------------------------------------------------
    // Init
    // ---------------------------------------------------------------------

    constructor(address initialOwner, IRouter router_, uint64 minRevealDelay_, uint64 maxRevealWindow_)
        ArbitrageExecutor(initialOwner, router_)
    {
        if (minRevealDelay_ == 0 || maxRevealWindow_ < minRevealDelay_) revert InvalidRevealParams();
        minRevealDelay = minRevealDelay_;
        maxRevealWindow = maxRevealWindow_;
        emit RevealParamsUpdated(minRevealDelay_, maxRevealWindow_);
    }

    // ---------------------------------------------------------------------
    // Commit / Reveal / Cancel
    // ---------------------------------------------------------------------

    /// @notice Publish the hash of an intended trade. Anyone may commit any
    ///         hash; the only effect is to start the reveal window for the
    ///         caller whose address matches the preimage's `beneficiary`.
    function commit(bytes32 commitHash) external {
        if (commits[commitHash] != 0) revert CommitAlreadyExists();
        commits[commitHash] = block.number;
        emit Committed(msg.sender, commitHash, block.number);
    }

    /// @notice Reveal a previously committed trade and execute it. The
    ///         beneficiary is bound to `msg.sender`, so anyone else
    ///         learning the preimage cannot reveal it on the committer's
    ///         behalf — their address would change the hash.
    function reveal(
        address provider,
        address asset,
        uint256 amount,
        Route calldata route,
        uint256 minProfit,
        bytes32 salt
    ) external {
        bytes32 h = computeCommitHash(provider, asset, amount, route, minProfit, salt, msg.sender);
        uint256 ca = commits[h];
        if (ca == 0) revert NoSuchCommit();

        uint256 earliest;
        unchecked {
            earliest = ca + uint256(minRevealDelay);
        }
        if (block.number < earliest) revert RevealTooEarly(block.number, earliest);
        if (block.number > ca + uint256(maxRevealWindow)) revert RevealExpired();

        // Clear the commit before running the arb so a successful reveal is
        // single-use. NOTE: this delete is in the SAME transaction as
        // _doArb. If _doArb reverts (e.g. NotProfitable) the whole tx —
        // including this delete — is rolled back and the commit slot
        // survives. The committer must then either cancel() it or wait
        // for maxRevealWindow to expire before cleanup() can prune it.
        // See test_reveal_unprofitable_revertsAndCommitSurvives.
        delete commits[h];
        emit Revealed(msg.sender, h);

        _doArb(msg.sender, provider, asset, amount, route, minProfit);
    }

    /// @notice Withdraw a commit you placed. Useful when a price moves
    ///         and your committed trade is no longer worth revealing.
    /// @dev    Authorisation: the commit hash binds the beneficiary
    ///         (msg.sender of `reveal`) into its preimage. cancel()
    ///         recomputes the hash with msg.sender as the beneficiary,
    ///         so only the address that would be entitled to reveal
    ///         can cancel. A third party that knows the preimage but
    ///         is not the bound beneficiary cannot cancel — their
    ///         msg.sender would produce a different hash. This is
    ///         deliberate: a permissive cancel would let anyone grief a
    ///         committer by deleting their slot.
    function cancel(
        address provider,
        address asset,
        uint256 amount,
        Route calldata route,
        uint256 minProfit,
        bytes32 salt
    ) external {
        bytes32 h = computeCommitHash(provider, asset, amount, route, minProfit, salt, msg.sender);
        if (commits[h] == 0) revert NoSuchCommit();
        delete commits[h];
        emit Cancelled(msg.sender, h);
    }

    /// @notice Prune an expired commit slot. Anyone may call this once
    ///         `maxRevealWindow` blocks have passed since the commit —
    ///         the slot is dead at that point (it can no longer be
    ///         revealed) so clearing it costs no security and bounds
    ///         long-term state growth.
    /// @dev    Mitigates the spam vector where a griefer publishes
    ///         random hashes whose preimages they alone know (or know
    ///         nothing about). Such commits can never be cancelled by
    ///         a third party (cancel binds beneficiary = msg.sender)
    ///         nor revealed, so without cleanup() they would persist
    ///         indefinitely. Note this does NOT prevent state growth
    ///         during the window itself — a determined spammer can
    ///         still pay for `maxRevealWindow` blocks' worth of
    ///         storage. We treat that as a bounded cost rather than
    ///         introduce a stake / commit fee that would also tax
    ///         legitimate users.
    function cleanup(bytes32 commitHash) external {
        uint256 ca = commits[commitHash];
        if (ca == 0) revert NoSuchCommit();
        uint256 earliestCleanup;
        unchecked {
            earliestCleanup = ca + uint256(maxRevealWindow) + 1;
        }
        if (block.number < earliestCleanup) revert CommitStillLive(block.number, earliestCleanup);
        delete commits[commitHash];
        emit Cleaned(msg.sender, commitHash);
    }

    // ---------------------------------------------------------------------
    // Helper used by both on-chain reveal and off-chain bots
    // ---------------------------------------------------------------------

    function computeCommitHash(
        address provider,
        address asset,
        uint256 amount,
        Route calldata route,
        uint256 minProfit,
        bytes32 salt,
        address beneficiary
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(provider, asset, amount, route, minProfit, salt, beneficiary));
    }

    // ---------------------------------------------------------------------
    // Owner controls
    // ---------------------------------------------------------------------

    function setRevealParams(uint64 minDelay, uint64 maxWindow) external onlyOwner {
        if (minDelay == 0 || maxWindow < minDelay) revert InvalidRevealParams();
        minRevealDelay = minDelay;
        maxRevealWindow = maxWindow;
        emit RevealParamsUpdated(minDelay, maxWindow);
    }
}
