// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { FlashLoanReceiverBase } from "../base/FlashLoanReceiverBase.sol";
import { IRouter, Route } from "../interfaces/IRouter.sol";

/// @title ArbitrageExecutor
/// @notice Atomic flash-loan arbitrage entry point. Borrows `asset` from a
///         trusted flash-loan adapter, routes it through Person B's
///         `Router` over 1-3 hops, and credits the surplus to the caller
///         under a pull-payment ledger. Reverts the entire transaction if
///         the realised round-trip output cannot cover loan + fee +
///         configured minimum profit.
/// @dev    The trust model is inherited from {FlashLoanReceiverBase}: the
///         owner whitelists each adapter via `setAdapter`. The callback
///         re-checks the whitelist, so an unlisted adapter cannot reach
///         `_executeOperation` even if it impersonates a trusted one.
///
///         Beneficiary is held in EIP-1153 transient storage for the
///         lifetime of `requestArb`/`reveal` — never written to permanent
///         storage and never serialised into the flash-loan payload. This
///         removes a tampering surface (the adapter forwards `data`
///         verbatim) and saves ~20k gas vs a storage slot per call.
contract ArbitrageExecutor is FlashLoanReceiverBase {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    /// @notice Person B's routing engine. Owner-swappable so we can deploy
    ///         the executor before the router is final (set to address(0)
    ///         initially, point at the real router once it lands).
    IRouter public router;

    /// @notice Profit ledger: `profitWithdrawable[beneficiary][asset]`.
    /// @dev    Pull-payment pattern — pushing inside the callback would
    ///         re-introduce a reentry vector for contract beneficiaries.
    mapping(address beneficiary => mapping(address asset => uint256 amount)) public profitWithdrawable;

    /// @notice Optional floor expressed in basis points of the borrowed
    ///         amount. Stacked on top of the per-call `minProfit`.
    /// @dev    `uint64` is more than enough headroom (10_000 = 100%) and
    ///         leaves room to pack neighbours on the same slot later.
    uint64 public minProfitBps;

    /// @dev Transient storage slot for the in-flight beneficiary. Computed
    ///      as `keccak256(...)` so it cannot collide with any other
    ///      transient slot a future mixin might choose.
    bytes32 internal constant T_BENEFICIARY = keccak256("ArbitrageExecutor.beneficiary");

    // ---------------------------------------------------------------------
    // Events / errors
    // ---------------------------------------------------------------------

    event ArbExecuted(
        address indexed beneficiary, address indexed asset, uint256 amount, uint256 fee, uint256 profit
    );
    event ProfitWithdrawn(
        address indexed beneficiary, address indexed asset, address indexed to, uint256 amount
    );
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);
    event MinProfitBpsUpdated(uint64 oldBps, uint64 newBps);

    error EmptyRoute();
    error AssetMismatch();
    error NoBeneficiary();
    error NotProfitable(uint256 got, uint256 required);
    error NothingToWithdraw();
    error InsufficientProfit(uint256 available, uint256 requested);
    error ZeroAddress();
    error RouterNotSet();

    // ---------------------------------------------------------------------
    // Init
    // ---------------------------------------------------------------------

    /// @param initialOwner Owner of the executor (adapter whitelist + param tuning).
    /// @param router_      Person B's router, or `address(0)` if not yet deployed
    ///                     (owner must call {setRouter} before the first arb).
    constructor(address initialOwner, IRouter router_) FlashLoanReceiverBase(initialOwner) {
        // Allow zero so we can deploy ahead of Person B; emit anyway so the
        // off-chain index can pick the change up later via {setRouter}.
        router = router_;
        emit RouterUpdated(address(0), address(router_));
    }

    // ---------------------------------------------------------------------
    // Entry points
    // ---------------------------------------------------------------------

    /// @notice Borrow `amount` of `asset` via `provider`, run `route`, and
    ///         credit any profit beyond `loan + fee + minProfit` to
    ///         `msg.sender`.
    /// @dev    Not marked `nonReentrant` — the inherited callback already
    ///         enters the same guard. A second `nonReentrant` on this
    ///         entry would deadlock the legitimate adapter callback.
    function requestArb(
        address provider,
        address asset,
        uint256 amount,
        Route calldata route,
        uint256 minProfit
    ) external {
        _doArb(msg.sender, provider, asset, amount, route, minProfit);
    }

    /// @dev Shared core used by {requestArb} and (in the subclass)
    ///      `CommitRevealExecutor.reveal`. Kept `internal` so subclasses
    ///      do not lose their `msg.sender` to an external hop.
    function _doArb(
        address beneficiary,
        address provider,
        address asset,
        uint256 amount,
        Route calldata route,
        uint256 minProfit
    ) internal {
        if (address(router) == address(0)) revert RouterNotSet();
        if (beneficiary == address(0)) revert ZeroAddress();

        uint256 hopsLen = route.hops.length;
        if (hopsLen == 0) revert EmptyRoute();
        if (route.hops[0].tokenIn != asset) revert AssetMismatch();
        // hopsLen >= 1 here so the unchecked decrement is safe.
        unchecked {
            if (route.hops[hopsLen - 1].tokenOut != asset) revert AssetMismatch();
        }
        if (!trustedAdapter[provider]) revert UntrustedAdapter(provider);

        bytes32 slot = T_BENEFICIARY;
        // Stash the beneficiary in transient storage so `_executeOperation`
        // can read it without relying on the flash-loan payload.
        assembly ("memory-safe") {
            tstore(slot, beneficiary)
        }

        _flashLoan(provider, asset, amount, abi.encode(route, minProfit));

        // Explicit clear (auto-cleared at tx end anyway). Cheap and lets
        // invariant tests assert the slot is empty between top-level calls.
        assembly ("memory-safe") {
            tstore(slot, 0)
        }
    }

    // ---------------------------------------------------------------------
    // Flash-loan callback hook
    // ---------------------------------------------------------------------

    /// @inheritdoc FlashLoanReceiverBase
    function _executeOperation(address asset, uint256 amount, uint256 fee, bytes calldata data)
        internal
        override
    {
        bytes32 slot = T_BENEFICIARY;
        address bene;
        assembly ("memory-safe") {
            bene := tload(slot)
        }
        if (bene == address(0)) revert NoBeneficiary();

        (Route memory route, uint256 minProfit) = abi.decode(data, (Route, uint256));

        IRouter r = router;
        // Approve, execute, immediately revoke. Defence-in-depth at a ~5k
        // gas cost — accepted because a stale allowance to a swappable
        // router is too sharp an edge to leave outstanding.
        IERC20(asset).forceApprove(address(r), amount);
        r.execute(route);
        IERC20(asset).forceApprove(address(r), 0);

        uint256 owed = amount + fee;
        uint256 bpsFloor = (amount * uint256(minProfitBps)) / 10_000;
        uint256 floor;
        unchecked {
            // `owed + minProfit + bpsFloor` cannot realistically overflow
            // for any asset+amount combination Aave/Balancer will lend.
            floor = owed + minProfit + bpsFloor;
        }

        uint256 bal = IERC20(asset).balanceOf(address(this));
        if (bal < floor) revert NotProfitable(bal, floor);

        uint256 profit;
        unchecked {
            profit = bal - owed;
            profitWithdrawable[bene][asset] += profit;
        }
        emit ArbExecuted(bene, asset, amount, fee, profit);
        // Base contract transfers `owed` to the adapter (msg.sender).
    }

    // ---------------------------------------------------------------------
    // Profit ledger
    // ---------------------------------------------------------------------

    /// @notice Pull credited profit. Anyone may withdraw their own balance
    ///         to any non-zero address.
    /// @dev    Pull-payment + CEI. Outer `nonReentrant` blocks the rare
    ///         path where a malicious router re-enters `withdraw` mid-arb.
    function withdraw(address asset, address to, uint256 amount) external nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert NothingToWithdraw();

        uint256 bal = profitWithdrawable[msg.sender][asset];
        if (bal < amount) revert InsufficientProfit(bal, amount);

        unchecked {
            profitWithdrawable[msg.sender][asset] = bal - amount;
        }
        IERC20(asset).safeTransfer(to, amount);
        emit ProfitWithdrawn(msg.sender, asset, to, amount);
    }

    // ---------------------------------------------------------------------
    // Owner controls
    // ---------------------------------------------------------------------

    function setRouter(IRouter newRouter) external onlyOwner {
        if (address(newRouter) == address(0)) revert ZeroAddress();
        address oldRouter = address(router);
        router = newRouter;
        emit RouterUpdated(oldRouter, address(newRouter));
    }

    function setMinProfitBps(uint64 bps) external onlyOwner {
        uint64 old = minProfitBps;
        minProfitBps = bps;
        emit MinProfitBpsUpdated(old, bps);
    }
}
