// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { ArbitrageExecutor } from "../src/executor/ArbitrageExecutor.sol";
import { CommitRevealExecutor } from "../src/executor/CommitRevealExecutor.sol";
import { IRouter, Route, Hop } from "../src/interfaces/IRouter.sol";

import { AaveV3FlashAdapter } from "../src/adapters/AaveV3FlashAdapter.sol";
import { MockAaveV3Pool } from "../src/mocks/MockAaveV3Pool.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";

import { MockRouter } from "./helpers/MockRouter.sol";

contract CommitRevealExecutorTest is Test {
    CommitRevealExecutor internal executor;
    MockRouter internal router;
    AaveV3FlashAdapter internal aaveAdapter;
    MockAaveV3Pool internal pool;
    MockERC20 internal usdc;

    address internal owner = address(0xA11CE);
    address internal alice = address(0xB0B);
    address internal bob = address(0xB1B);

    uint128 internal constant AAVE_BPS = 5;
    uint256 internal constant LOAN = 50_000e6;
    uint64 internal constant MIN_DELAY = 2;
    uint64 internal constant MAX_WINDOW = 100;

    function setUp() public {
        pool = new MockAaveV3Pool(AAVE_BPS);
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        usdc.mint(address(pool), 5_000_000e6);

        aaveAdapter = new AaveV3FlashAdapter(address(pool));
        router = new MockRouter();

        vm.prank(owner);
        executor = new CommitRevealExecutor(owner, router, MIN_DELAY, MAX_WINDOW);
        vm.prank(owner);
        executor.setAdapter(address(aaveAdapter), true);
    }

    // -----------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------

    function _route(uint256 amountIn) internal view returns (Route memory r) {
        r.amountIn = amountIn;
        r.minAmountOut = 0;
        r.hops = new Hop[](1);
        r.hops[0] = Hop({ adapter: address(0), tokenIn: address(usdc), tokenOut: address(usdc) });
    }

    function _fee(uint256 amount) internal pure returns (uint256) {
        return (amount * uint256(AAVE_BPS) + 1e4 - 1) / 1e4;
    }

    function _commitFor(address committer, bytes32 salt, uint256 minProfit) internal returns (bytes32 h) {
        Route memory r = _route(LOAN);
        h = executor.computeCommitHash(
            address(aaveAdapter), address(usdc), LOAN, r, minProfit, salt, committer
        );
        vm.prank(committer);
        executor.commit(h);
    }

    // -----------------------------------------------------------------
    // Constructor & params
    // -----------------------------------------------------------------

    function test_constructor_setsRevealParams() public view {
        assertEq(executor.minRevealDelay(), MIN_DELAY);
        assertEq(executor.maxRevealWindow(), MAX_WINDOW);
    }

    function test_constructor_rejectsZeroDelay() public {
        vm.expectRevert(CommitRevealExecutor.InvalidRevealParams.selector);
        new CommitRevealExecutor(owner, router, 0, MAX_WINDOW);
    }

    function test_constructor_rejectsWindowBelowDelay() public {
        vm.expectRevert(CommitRevealExecutor.InvalidRevealParams.selector);
        new CommitRevealExecutor(owner, router, 10, 5);
    }

    function test_setRevealParams_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        executor.setRevealParams(3, 50);

        vm.prank(owner);
        executor.setRevealParams(3, 50);
        assertEq(executor.minRevealDelay(), 3);
        assertEq(executor.maxRevealWindow(), 50);
    }

    function test_setRevealParams_rejectsInvalid() public {
        vm.prank(owner);
        vm.expectRevert(CommitRevealExecutor.InvalidRevealParams.selector);
        executor.setRevealParams(0, 50);

        vm.prank(owner);
        vm.expectRevert(CommitRevealExecutor.InvalidRevealParams.selector);
        executor.setRevealParams(10, 5);
    }

    // -----------------------------------------------------------------
    // Commit
    // -----------------------------------------------------------------

    function test_commit_storesBlockNumber() public {
        vm.roll(123);
        bytes32 h = _commitFor(alice, bytes32(uint256(1)), 0);
        assertEq(executor.commits(h), 123);
    }

    function test_commit_duplicateReverts() public {
        bytes32 h = _commitFor(alice, bytes32(uint256(1)), 0);
        vm.prank(alice);
        vm.expectRevert(CommitRevealExecutor.CommitAlreadyExists.selector);
        executor.commit(h);
    }

    // -----------------------------------------------------------------
    // Reveal happy path
    // -----------------------------------------------------------------

    function test_reveal_happyPath_clearsCommitAndCreditsProfit() public {
        vm.roll(100);
        bytes32 salt = bytes32(uint256(0xCAFE));
        bytes32 h = _commitFor(alice, salt, 0);

        // Advance past minRevealDelay.
        vm.roll(100 + uint256(MIN_DELAY));

        // Configure profitable router.
        uint256 fee = _fee(LOAN);
        uint256 profit = 12e6;
        router.setReturn(LOAN + fee + profit);

        vm.expectEmit(true, true, false, false, address(executor));
        emit CommitRevealExecutor.Revealed(alice, h);
        vm.prank(alice);
        executor.reveal(address(aaveAdapter), address(usdc), LOAN, _route(LOAN), 0, salt);

        assertEq(executor.commits(h), 0, "commit slot must be cleared");
        assertEq(executor.profitWithdrawable(alice, address(usdc)), profit);
    }

    // -----------------------------------------------------------------
    // Reveal failure modes
    // -----------------------------------------------------------------

    function test_reveal_tooEarly_reverts() public {
        vm.roll(100);
        bytes32 salt = bytes32(uint256(1));
        _commitFor(alice, salt, 0);

        // Reveal in the same block — too early.
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(CommitRevealExecutor.RevealTooEarly.selector, 100, 100 + MIN_DELAY)
        );
        executor.reveal(address(aaveAdapter), address(usdc), LOAN, _route(LOAN), 0, salt);
    }

    function test_reveal_expired_reverts() public {
        vm.roll(100);
        bytes32 salt = bytes32(uint256(2));
        _commitFor(alice, salt, 0);

        // Jump past the window.
        vm.roll(100 + MAX_WINDOW + 1);
        vm.prank(alice);
        vm.expectRevert(CommitRevealExecutor.RevealExpired.selector);
        executor.reveal(address(aaveAdapter), address(usdc), LOAN, _route(LOAN), 0, salt);
    }

    function test_reveal_wrongSalt_revertsNoSuchCommit() public {
        vm.roll(100);
        _commitFor(alice, bytes32(uint256(3)), 0);
        vm.roll(102);

        bytes32 wrongSalt = bytes32(uint256(999));
        vm.prank(alice);
        vm.expectRevert(CommitRevealExecutor.NoSuchCommit.selector);
        executor.reveal(address(aaveAdapter), address(usdc), LOAN, _route(LOAN), 0, wrongSalt);
    }

    function test_reveal_wrongBeneficiary_revertsNoSuchCommit() public {
        // Alice commits; Bob tries to reveal.
        vm.roll(100);
        bytes32 salt = bytes32(uint256(4));
        _commitFor(alice, salt, 0);
        vm.roll(102);

        vm.prank(bob);
        vm.expectRevert(CommitRevealExecutor.NoSuchCommit.selector);
        executor.reveal(address(aaveAdapter), address(usdc), LOAN, _route(LOAN), 0, salt);
    }

    function test_reveal_unprofitable_revertsAndCommitSurvives() public {
        vm.roll(100);
        bytes32 salt = bytes32(uint256(5));
        bytes32 h = _commitFor(alice, salt, 0);
        vm.roll(102);

        // Configure loss.
        uint256 fee = _fee(LOAN);
        router.setReturn(LOAN + fee - 1);

        vm.prank(alice);
        vm.expectRevert();
        executor.reveal(address(aaveAdapter), address(usdc), LOAN, _route(LOAN), 0, salt);

        // The whole tx reverted, so the deleted-commit effect was rolled
        // back: the slot is still there, the bot must explicitly cancel
        // it or wait for it to expire.
        assertEq(executor.commits(h), 100);
    }

    // -----------------------------------------------------------------
    // Cancel
    // -----------------------------------------------------------------

    function test_cancel_clearsCommit() public {
        vm.roll(100);
        bytes32 salt = bytes32(uint256(6));
        bytes32 h = _commitFor(alice, salt, 0);

        vm.expectEmit(true, true, false, false, address(executor));
        emit CommitRevealExecutor.Cancelled(alice, h);
        vm.prank(alice);
        executor.cancel(address(aaveAdapter), address(usdc), LOAN, _route(LOAN), 0, salt);

        assertEq(executor.commits(h), 0);
    }

    function test_cancel_unknownReverts() public {
        bytes32 salt = bytes32(uint256(7));
        vm.prank(alice);
        vm.expectRevert(CommitRevealExecutor.NoSuchCommit.selector);
        executor.cancel(address(aaveAdapter), address(usdc), LOAN, _route(LOAN), 0, salt);
    }

    // -----------------------------------------------------------------
    // Inherited ArbitrageExecutor surface still works
    // -----------------------------------------------------------------

    function test_inheritedRequestArb_stillFunctions() public {
        uint256 fee = _fee(LOAN);
        uint256 profit = 3e6;
        router.setReturn(LOAN + fee + profit);

        vm.prank(alice);
        executor.requestArb(address(aaveAdapter), address(usdc), LOAN, _route(LOAN), 0);
        assertEq(executor.profitWithdrawable(alice, address(usdc)), profit);
    }
}
