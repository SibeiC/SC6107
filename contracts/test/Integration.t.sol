// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { ArbitrageExecutor } from "../src/executor/ArbitrageExecutor.sol";
import { IRouter, Route, Hop } from "../src/interfaces/IRouter.sol";

import { AaveV3FlashAdapter } from "../src/adapters/AaveV3FlashAdapter.sol";
import { BalancerV2FlashAdapter } from "../src/adapters/BalancerV2FlashAdapter.sol";
import { MockAaveV3Pool } from "../src/mocks/MockAaveV3Pool.sol";
import { MockBalancerVault } from "../src/mocks/MockBalancerVault.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockRouter } from "./helpers/MockRouter.sol";

/// @notice End-to-end integration suite: {Aave, Balancer} × {profit,
///         break-even, loss}. Exercises the full stack — adapter,
///         executor, mock router — without re-mocking anything Person A
///         already covers in their adapter tests.
contract IntegrationTest is Test {
    ArbitrageExecutor internal executor;
    MockRouter internal router;
    AaveV3FlashAdapter internal aaveAdapter;
    BalancerV2FlashAdapter internal balAdapter;
    MockAaveV3Pool internal pool;
    MockBalancerVault internal vault;
    MockERC20 internal usdc;

    address internal owner = address(0xA11CE);
    address internal user = address(0xB0B);
    uint128 internal constant AAVE_BPS = 5;
    uint256 internal constant LOAN = 200_000e6;

    function setUp() public {
        pool = new MockAaveV3Pool(AAVE_BPS);
        vault = new MockBalancerVault(0);
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        usdc.mint(address(pool), 50_000_000e6);
        usdc.mint(address(vault), 50_000_000e6);

        aaveAdapter = new AaveV3FlashAdapter(address(pool));
        balAdapter = new BalancerV2FlashAdapter(address(vault));

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

    function _route() internal view returns (Route memory r) {
        r.amountIn = LOAN;
        r.minAmountOut = 0;
        r.hops = new Hop[](1);
        r.hops[0] = Hop({ adapter: address(0), tokenIn: address(usdc), tokenOut: address(usdc) });
    }

    function _aaveFee() internal pure returns (uint256) {
        return (LOAN * uint256(AAVE_BPS) + 1e4 - 1) / 1e4;
    }

    function _balFee() internal pure returns (uint256) {
        return 0;
    }

    function _runAndExpectProfit(address provider, uint256 expectedProfit) internal {
        uint256 before = executor.profitWithdrawable(user, address(usdc));
        vm.prank(user);
        executor.requestArb(provider, address(usdc), LOAN, _route(), 0);
        uint256 credited = executor.profitWithdrawable(user, address(usdc)) - before;
        assertEq(credited, expectedProfit, "credited profit mismatch");
    }

    function _runAndExpectRevert(address provider, uint256 got, uint256 floor) internal {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ArbitrageExecutor.NotProfitable.selector, got, floor)
        );
        executor.requestArb(provider, address(usdc), LOAN, _route(), 0);
    }

    // -----------------------------------------------------------------
    // {Aave, Balancer} × {profit, break-even with minProfit=1, loss}
    // -----------------------------------------------------------------

    function test_integration_aave_profit() public {
        uint256 fee = _aaveFee();
        router.setReturn(LOAN + fee + 100e6);
        _runAndExpectProfit(address(aaveAdapter), 100e6);
    }

    function test_integration_aave_breakEven_revertsWithMinProfit() public {
        uint256 fee = _aaveFee();
        router.setReturn(LOAN + fee);
        // minProfit=0 would pass; we explicitly require 1 so break-even
        // becomes a revert — exactly what production would do.
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ArbitrageExecutor.NotProfitable.selector, LOAN + fee, LOAN + fee + 1)
        );
        executor.requestArb(address(aaveAdapter), address(usdc), LOAN, _route(), 1);
    }

    function test_integration_aave_loss() public {
        uint256 fee = _aaveFee();
        router.setReturn(LOAN + fee - 1);
        _runAndExpectRevert(address(aaveAdapter), LOAN + fee - 1, LOAN + fee);
    }

    function test_integration_balancer_profit() public {
        router.setReturn(LOAN + 50e6); // 0 fee
        _runAndExpectProfit(address(balAdapter), 50e6);
    }

    function test_integration_balancer_breakEven_revertsWithMinProfit() public {
        uint256 fee = _balFee();
        router.setReturn(LOAN + fee);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ArbitrageExecutor.NotProfitable.selector, LOAN + fee, LOAN + fee + 1)
        );
        executor.requestArb(address(balAdapter), address(usdc), LOAN, _route(), 1);
    }

    function test_integration_balancer_loss() public {
        uint256 fee = _balFee();
        router.setReturn(LOAN - 1);
        _runAndExpectRevert(address(balAdapter), LOAN - 1, LOAN + fee);
    }

    // -----------------------------------------------------------------
    // Round-trip: profit accrues, then withdraw nets it out
    // -----------------------------------------------------------------

    function test_integration_profit_then_withdraw() public {
        uint256 fee = _aaveFee();
        router.setReturn(LOAN + fee + 250e6);

        vm.prank(user);
        executor.requestArb(address(aaveAdapter), address(usdc), LOAN, _route(), 0);
        assertEq(executor.profitWithdrawable(user, address(usdc)), 250e6);

        vm.prank(user);
        executor.withdraw(address(usdc), user, 250e6);
        assertEq(usdc.balanceOf(user), 250e6);
        assertEq(executor.profitWithdrawable(user, address(usdc)), 0);
    }
}
