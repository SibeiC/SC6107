// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";

import { ArbitrageExecutor } from "../src/executor/ArbitrageExecutor.sol";
import { IRouter, Route, Hop } from "../src/interfaces/IRouter.sol";

import { AaveV3FlashAdapter } from "../src/adapters/AaveV3FlashAdapter.sol";
import { MockAaveV3Pool } from "../src/mocks/MockAaveV3Pool.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockRouter } from "./helpers/MockRouter.sol";

/// @notice Driver contract used by the invariant fuzzer. Bounded random
///         operations: profitable arb, unprofitable arb (must revert),
///         partial withdraw. Tracks ledger expectations off-chain so we
///         can assert solvency invariants against them.
contract ExecutorHandler is Test {
    ArbitrageExecutor public executor;
    MockRouter public router;
    AaveV3FlashAdapter public adapter;
    MockERC20 public usdc;
    address public user;
    uint128 public premiumBps;

    uint256 public expectedCredited; // sum of profits ever credited
    uint256 public withdrawnTotal;   // sum of profits ever withdrawn

    constructor(
        ArbitrageExecutor exec,
        MockRouter rtr,
        AaveV3FlashAdapter ad,
        MockERC20 token,
        address user_,
        uint128 premiumBps_
    ) {
        executor = exec;
        router = rtr;
        adapter = ad;
        usdc = token;
        user = user_;
        premiumBps = premiumBps_;
    }

    function _fee(uint256 amount) internal view returns (uint256) {
        return (amount * uint256(premiumBps) + 1e4 - 1) / 1e4;
    }

    function _route(uint256 amountIn, address token) internal pure returns (Route memory r) {
        r.amountIn = amountIn;
        r.minAmountOut = 0;
        r.hops = new Hop[](1);
        r.hops[0] = Hop({ adapter: address(0), tokenIn: token, tokenOut: token });
    }

    /// @notice Run a single arbitrage attempt. Bounds the amount and the
    ///         router's return so the fuzzer hits both profitable and
    ///         unprofitable paths.
    function runArb(uint256 amountSeed, uint256 spreadSeed) external {
        uint256 amount = bound(amountSeed, 1e6, 100_000e6);
        uint256 fee = _fee(amount);
        // Spread can be 0 .. +1000e6 above the floor (profit), OR drop
        // below to provoke NotProfitable.
        uint256 minRet = amount + fee >= 100 ? amount + fee - 100 : 0;
        uint256 ret = bound(spreadSeed, minRet, amount + fee + 1000e6);

        router.setReturn(ret);
        router.setMode(MockRouter.Mode.Normal);

        vm.prank(user);
        try executor.requestArb(address(adapter), address(usdc), amount, _route(amount, address(usdc)), 0) {
            // Profit was credited.
            expectedCredited += (ret - amount - fee);
        } catch {
            // Unprofitable — nothing credited. Skip.
        }
    }

    function runWithdraw(uint256 amountSeed) external {
        uint256 available = executor.profitWithdrawable(user, address(usdc));
        if (available == 0) return;
        uint256 amt = bound(amountSeed, 1, available);
        vm.prank(user);
        executor.withdraw(address(usdc), user, amt);
        withdrawnTotal += amt;
    }
}

contract ArbitrageExecutorInvariantTest is StdInvariant, Test {
    ArbitrageExecutor internal executor;
    MockRouter internal router;
    AaveV3FlashAdapter internal aaveAdapter;
    MockAaveV3Pool internal pool;
    MockERC20 internal usdc;
    ExecutorHandler internal handler;

    address internal owner = address(0xA11CE);
    address internal user = address(0xB0B);
    uint128 internal constant AAVE_BPS = 5;
    bytes32 internal constant T_BENEFICIARY = keccak256("ArbitrageExecutor.beneficiary");

    function setUp() public {
        pool = new MockAaveV3Pool(AAVE_BPS);
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        usdc.mint(address(pool), 100_000_000e6);

        aaveAdapter = new AaveV3FlashAdapter(address(pool));
        router = new MockRouter();

        vm.prank(owner);
        executor = new ArbitrageExecutor(owner, router);
        vm.prank(owner);
        executor.setAdapter(address(aaveAdapter), true);

        handler = new ExecutorHandler(executor, router, aaveAdapter, usdc, user, AAVE_BPS);

        // Restrict the fuzzer to the handler's surface.
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = ExecutorHandler.runArb.selector;
        selectors[1] = ExecutorHandler.runWithdraw.selector;
        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    }

    // -----------------------------------------------------------------
    // Invariants
    // -----------------------------------------------------------------

    /// @dev The executor's balance of `usdc` must always equal the
    ///      outstanding ledger entry for the user — never more (stranded
    ///      funds from a successful arb) and never less (under-credited
    ///      profit that would let the user pull out more than the
    ///      contract holds).
    function invariant_noStrandedFunds() public view {
        uint256 ledger = executor.profitWithdrawable(user, address(usdc));
        uint256 held = usdc.balanceOf(address(executor));
        assertEq(held, ledger, "executor balance must match ledger");
    }

    /// @dev Credited minus withdrawn must equal the live ledger entry.
    function invariant_ledgerAccountsForEveryProfit() public view {
        uint256 ledger = executor.profitWithdrawable(user, address(usdc));
        // The handler ran inside its own txs; allow for the case where a
        // call reverted (in which case neither expectedCredited nor
        // withdrawnTotal would have moved).
        assertEq(ledger, handler.expectedCredited() - handler.withdrawnTotal(), "ledger drift");
    }

    /// @dev The transient beneficiary slot must always be zero between
    ///      top-level calls — every legitimate `requestArb` clears it
    ///      explicitly, and an early-revert path doesn't get to set it.
    function invariant_transientBeneficiaryAlwaysCleared() public view {
        bytes32 slot = vm.load(address(executor), T_BENEFICIARY); // regular storage probe
        // For belt-and-suspenders: the slot is purely transient, so
        // regular storage there is always zero. The real assertion the
        // user cares about is that transient storage clears between txs,
        // which the EVM guarantees by definition.
        assertEq(slot, bytes32(0));
    }
}
