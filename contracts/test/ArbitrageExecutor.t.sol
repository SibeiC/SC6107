// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { ArbitrageExecutor } from "../src/executor/ArbitrageExecutor.sol";
import { FlashLoanReceiverBase } from "../src/base/FlashLoanReceiverBase.sol";
import { IRouter, Route, Hop } from "../src/interfaces/IRouter.sol";

import { AaveV3FlashAdapter } from "../src/adapters/AaveV3FlashAdapter.sol";
import { BalancerV2FlashAdapter } from "../src/adapters/BalancerV2FlashAdapter.sol";
import { MockAaveV3Pool } from "../src/mocks/MockAaveV3Pool.sol";
import { MockBalancerVault } from "../src/mocks/MockBalancerVault.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";

import { MockRouter } from "./helpers/MockRouter.sol";

contract ArbitrageExecutorTest is Test {
    ArbitrageExecutor internal executor;
    MockRouter internal router;

    AaveV3FlashAdapter internal aaveAdapter;
    BalancerV2FlashAdapter internal balAdapter;
    MockAaveV3Pool internal pool;
    MockBalancerVault internal vault;
    MockERC20 internal usdc;

    address internal owner = address(0xA11CE);
    address internal user = address(0xB0B);
    uint128 internal constant AAVE_BPS = 5;          // 0.05% premium
    uint256 internal constant LOAN = 100_000e6;       // 100k mUSDC

    function setUp() public {
        // --- protocol mocks
        pool = new MockAaveV3Pool(AAVE_BPS);
        vault = new MockBalancerVault(0); // Balancer Sepolia is 0-fee
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        usdc.mint(address(pool), 10_000_000e6);
        usdc.mint(address(vault), 10_000_000e6);

        // --- adapters
        aaveAdapter = new AaveV3FlashAdapter(address(pool));
        balAdapter = new BalancerV2FlashAdapter(address(vault));

        // --- executor + router
        router = new MockRouter();
        vm.prank(owner);
        executor = new ArbitrageExecutor(owner, router);

        vm.startPrank(owner);
        executor.setAdapter(address(aaveAdapter), true);
        executor.setAdapter(address(balAdapter), true);
        vm.stopPrank();
    }

    // -----------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------

    function _singleHopRoute(uint256 amountIn) internal view returns (Route memory r) {
        r.amountIn = amountIn;
        r.minAmountOut = 0;
        r.hops = new Hop[](1);
        r.hops[0] = Hop({ adapter: address(0), tokenIn: address(usdc), tokenOut: address(usdc) });
    }

    function _twoHopRoute(uint256 amountIn) internal view returns (Route memory r) {
        r.amountIn = amountIn;
        r.minAmountOut = 0;
        r.hops = new Hop[](2);
        r.hops[0] = Hop({ adapter: address(0), tokenIn: address(usdc), tokenOut: address(usdc) });
        r.hops[1] = Hop({ adapter: address(0), tokenIn: address(usdc), tokenOut: address(usdc) });
    }

    // -----------------------------------------------------------------
    // Construction / owner controls
    // -----------------------------------------------------------------

    function test_constructor_setsRouterAndOwner() public view {
        assertEq(address(executor.router()), address(router));
        assertEq(executor.owner(), owner);
    }

    function test_setRouter_onlyOwner() public {
        MockRouter newRouter = new MockRouter();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        vm.prank(user);
        executor.setRouter(newRouter);

        vm.expectEmit(true, true, false, false, address(executor));
        emit ArbitrageExecutor.RouterUpdated(address(router), address(newRouter));
        vm.prank(owner);
        executor.setRouter(newRouter);
        assertEq(address(executor.router()), address(newRouter));
    }

    function test_setRouter_zeroReverts() public {
        vm.expectRevert(ArbitrageExecutor.ZeroAddress.selector);
        vm.prank(owner);
        executor.setRouter(IRouter(address(0)));
    }

    function test_setMinProfitBps_onlyOwner_emits() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        vm.prank(user);
        executor.setMinProfitBps(50);

        vm.expectEmit(false, false, false, true, address(executor));
        emit ArbitrageExecutor.MinProfitBpsUpdated(0, 50);
        vm.prank(owner);
        executor.setMinProfitBps(50);
        assertEq(executor.minProfitBps(), 50);
    }

    // -----------------------------------------------------------------
    // Pre-flight validation
    // -----------------------------------------------------------------

    function test_requestArb_revertsOnEmptyRoute() public {
        Route memory r;
        vm.expectRevert(ArbitrageExecutor.EmptyRoute.selector);
        executor.requestArb(address(aaveAdapter), address(usdc), LOAN, r, 0);
    }

    function test_requestArb_revertsOnAssetMismatch_firstHop() public {
        MockERC20 other = new MockERC20("Other", "OTH", 18);
        Route memory r = _singleHopRoute(LOAN);
        r.hops[0].tokenIn = address(other);
        vm.expectRevert(ArbitrageExecutor.AssetMismatch.selector);
        executor.requestArb(address(aaveAdapter), address(usdc), LOAN, r, 0);
    }

    function test_requestArb_revertsOnAssetMismatch_lastHop() public {
        MockERC20 other = new MockERC20("Other", "OTH", 18);
        Route memory r = _singleHopRoute(LOAN);
        r.hops[0].tokenOut = address(other);
        vm.expectRevert(ArbitrageExecutor.AssetMismatch.selector);
        executor.requestArb(address(aaveAdapter), address(usdc), LOAN, r, 0);
    }

    function test_requestArb_revertsOnUntrustedProvider() public {
        address fake = address(0xDEAD);
        Route memory r = _singleHopRoute(LOAN);
        vm.expectRevert(abi.encodeWithSelector(FlashLoanReceiverBase.UntrustedAdapter.selector, fake));
        executor.requestArb(fake, address(usdc), LOAN, r, 0);
    }

    function test_requestArb_revertsIfRouterNotSet() public {
        // Deploy a second executor with no router set.
        vm.prank(owner);
        ArbitrageExecutor naked = new ArbitrageExecutor(owner, IRouter(address(0)));
        vm.prank(owner);
        naked.setAdapter(address(aaveAdapter), true);

        Route memory r = _singleHopRoute(LOAN);
        vm.expectRevert(ArbitrageExecutor.RouterNotSet.selector);
        naked.requestArb(address(aaveAdapter), address(usdc), LOAN, r, 0);
    }

    // -----------------------------------------------------------------
    // Aave end-to-end — profit, break-even, loss
    // -----------------------------------------------------------------

    function _expectedAaveFee(uint256 amount) internal pure returns (uint256) {
        return (amount * uint256(AAVE_BPS) + 1e4 - 1) / 1e4;
    }

    function test_requestArb_aave_profitable_creditsBeneficiary() public {
        uint256 fee = _expectedAaveFee(LOAN);
        uint256 profit = 10e6;
        router.setReturn(LOAN + fee + profit);

        vm.prank(user);
        executor.requestArb(address(aaveAdapter), address(usdc), LOAN, _singleHopRoute(LOAN), 0);

        assertEq(executor.profitWithdrawable(user, address(usdc)), profit);
        // Executor holds the unwithdrawn profit; adapter and router hold nothing.
        assertEq(usdc.balanceOf(address(executor)), profit);
        assertEq(usdc.balanceOf(address(aaveAdapter)), 0);
        assertEq(usdc.balanceOf(address(router)), LOAN); // router pulled amountIn
    }

    function test_requestArb_aave_breakEven_revertsIfMinProfitPositive() public {
        uint256 fee = _expectedAaveFee(LOAN);
        router.setReturn(LOAN + fee); // exact break-even, no surplus.

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ArbitrageExecutor.NotProfitable.selector, LOAN + fee, LOAN + fee + 1)
        );
        executor.requestArb(address(aaveAdapter), address(usdc), LOAN, _singleHopRoute(LOAN), 1);
    }

    function test_requestArb_aave_loss_reverts() public {
        uint256 fee = _expectedAaveFee(LOAN);
        router.setReturn(LOAN + fee - 1); // 1 wei short.

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ArbitrageExecutor.NotProfitable.selector, LOAN + fee - 1, LOAN + fee)
        );
        executor.requestArb(address(aaveAdapter), address(usdc), LOAN, _singleHopRoute(LOAN), 0);
    }

    function test_requestArb_aave_minProfitBps_appliesOnTop() public {
        // 100 bps of LOAN = 1% = 1_000e6.
        vm.prank(owner);
        executor.setMinProfitBps(100);

        uint256 fee = _expectedAaveFee(LOAN);
        uint256 floor = LOAN + fee + (LOAN / 100); // bps floor only, minProfit=0
        router.setReturn(floor - 1);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ArbitrageExecutor.NotProfitable.selector, floor - 1, floor)
        );
        executor.requestArb(address(aaveAdapter), address(usdc), LOAN, _singleHopRoute(LOAN), 0);
    }

    // -----------------------------------------------------------------
    // Balancer end-to-end (zero-fee)
    // -----------------------------------------------------------------

    function test_requestArb_balancer_profitable() public {
        uint256 profit = 7e6;
        router.setReturn(LOAN + profit); // 0 fee.

        vm.prank(user);
        executor.requestArb(address(balAdapter), address(usdc), LOAN, _singleHopRoute(LOAN), 0);

        assertEq(executor.profitWithdrawable(user, address(usdc)), profit);
    }

    // -----------------------------------------------------------------
    // Multi-hop route shapes
    // -----------------------------------------------------------------

    function test_requestArb_twoHopRoute_profitable() public {
        uint256 fee = _expectedAaveFee(LOAN);
        uint256 profit = 5e6;
        router.setReturn(LOAN + fee + profit);

        vm.prank(user);
        executor.requestArb(address(aaveAdapter), address(usdc), LOAN, _twoHopRoute(LOAN), 0);

        assertEq(executor.profitWithdrawable(user, address(usdc)), profit);
    }

    // -----------------------------------------------------------------
    // Callback safety
    // -----------------------------------------------------------------

    function test_callback_revertsIfTransientBeneficiaryUnset() public {
        // Direct call from the adapter (whitelisted) with `initiator =
        // executor`, simulating a confused adapter trying to invoke the
        // callback outside a real `requestArb`. The transient slot is
        // empty, so we must hit {NoBeneficiary}.
        bytes memory data = abi.encode(_singleHopRoute(LOAN), uint256(0));
        vm.prank(address(aaveAdapter));
        vm.expectRevert(ArbitrageExecutor.NoBeneficiary.selector);
        executor.onFlashLoan(address(usdc), LOAN, 0, address(executor), data);
    }

    function test_callback_revertsOnUntrustedAdapter() public {
        bytes memory data = abi.encode(_singleHopRoute(LOAN), uint256(0));
        vm.prank(address(0xCAFE));
        vm.expectRevert(
            abi.encodeWithSelector(FlashLoanReceiverBase.UntrustedAdapter.selector, address(0xCAFE))
        );
        executor.onFlashLoan(address(usdc), LOAN, 0, address(executor), data);
    }

    // -----------------------------------------------------------------
    // Reentry: router that re-enters the executor must be blocked.
    // -----------------------------------------------------------------

    function test_reentry_routerCallsRequestArb_reverts() public {
        router.setMode(MockRouter.Mode.ReenterRequestArb);
        router.setReentry(address(aaveAdapter), address(usdc), LOAN, _singleHopRoute(LOAN));
        router.setReturn(LOAN + _expectedAaveFee(LOAN) + 1);

        vm.prank(user);
        // The inner flash loan triggers a second `onFlashLoan` on the
        // executor while the outer guard is held → OZ guard reverts.
        vm.expectRevert();
        executor.requestArb(address(aaveAdapter), address(usdc), LOAN, _singleHopRoute(LOAN), 0);
    }

    function test_reentry_routerCallsWithdraw_reverts() public {
        // Pre-credit the user so withdraw has a balance to chase.
        router.setMode(MockRouter.Mode.Normal);
        router.setReturn(LOAN + _expectedAaveFee(LOAN) + 100);
        vm.prank(user);
        executor.requestArb(address(aaveAdapter), address(usdc), LOAN, _singleHopRoute(LOAN), 0);

        // Now flip the router into reenter-withdraw and run again.
        router.setMode(MockRouter.Mode.ReenterWithdraw);
        router.setReentry(address(usdc), address(usdc), 0, _singleHopRoute(LOAN));

        vm.prank(user);
        vm.expectRevert();
        executor.requestArb(address(aaveAdapter), address(usdc), LOAN, _singleHopRoute(LOAN), 0);
    }

    // -----------------------------------------------------------------
    // Pull-payment withdraw
    // -----------------------------------------------------------------

    function _profitableSetup(uint256 profit) internal {
        router.setReturn(LOAN + _expectedAaveFee(LOAN) + profit);
        vm.prank(user);
        executor.requestArb(address(aaveAdapter), address(usdc), LOAN, _singleHopRoute(LOAN), 0);
    }

    function test_withdraw_happyPath() public {
        _profitableSetup(50e6);

        vm.expectEmit(true, true, true, true, address(executor));
        emit ArbitrageExecutor.ProfitWithdrawn(user, address(usdc), user, 30e6);
        vm.prank(user);
        executor.withdraw(address(usdc), user, 30e6);

        assertEq(usdc.balanceOf(user), 30e6);
        assertEq(executor.profitWithdrawable(user, address(usdc)), 20e6);
    }

    function test_withdraw_revertsOnZeroAddress() public {
        _profitableSetup(10e6);
        vm.prank(user);
        vm.expectRevert(ArbitrageExecutor.ZeroAddress.selector);
        executor.withdraw(address(usdc), address(0), 1);
    }

    function test_withdraw_revertsOnZeroAmount() public {
        _profitableSetup(10e6);
        vm.prank(user);
        vm.expectRevert(ArbitrageExecutor.NothingToWithdraw.selector);
        executor.withdraw(address(usdc), user, 0);
    }

    function test_withdraw_revertsOnInsufficient() public {
        _profitableSetup(5e6);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ArbitrageExecutor.InsufficientProfit.selector, 5e6, 6e6)
        );
        executor.withdraw(address(usdc), user, 6e6);
    }

    // -----------------------------------------------------------------
    // Fuzz: profitable ↔ revert is monotone in router's return amount
    // -----------------------------------------------------------------

    function testFuzz_profitable_iff_returnCoversFee(uint64 spreadSeed) public {
        uint256 fee = _expectedAaveFee(LOAN);
        // Map seed to a return between [LOAN, LOAN + fee + 1e9].
        uint256 ret = LOAN + uint256(spreadSeed) % (fee + 1e9 + 1);
        router.setReturn(ret);

        vm.prank(user);
        if (ret >= LOAN + fee) {
            executor.requestArb(address(aaveAdapter), address(usdc), LOAN, _singleHopRoute(LOAN), 0);
            assertEq(executor.profitWithdrawable(user, address(usdc)), ret - LOAN - fee);
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(ArbitrageExecutor.NotProfitable.selector, ret, LOAN + fee)
            );
            executor.requestArb(address(aaveAdapter), address(usdc), LOAN, _singleHopRoute(LOAN), 0);
        }
    }
}
