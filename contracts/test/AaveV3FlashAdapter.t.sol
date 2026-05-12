// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { AaveV3FlashAdapter } from "../src/adapters/AaveV3FlashAdapter.sol";
import { MockAaveV3Pool } from "../src/mocks/MockAaveV3Pool.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { TestReceiver } from "./helpers/TestReceiver.sol";
import { BaseReceiver } from "./helpers/BaseReceiver.sol";
import { FlashLoanReceiverBase } from "../src/base/FlashLoanReceiverBase.sol";

contract AaveV3FlashAdapterTest is Test {
    AaveV3FlashAdapter internal adapter;
    MockAaveV3Pool internal pool;
    MockERC20 internal token;

    address internal owner = address(0xA11CE);
    uint128 internal constant POOL_PREMIUM_BPS = 5; // 0.05%, mirrors Aave V3 mainnet default

    function setUp() public {
        pool = new MockAaveV3Pool(POOL_PREMIUM_BPS);
        token = new MockERC20("Mock USDC", "mUSDC", 6);
        // Fund the pool so it has liquidity for the loan.
        token.mint(address(pool), 1_000_000e6);
        adapter = new AaveV3FlashAdapter(address(pool));
    }

    // -----------------------------------------------------------------
    // Construction
    // -----------------------------------------------------------------

    function test_constructor_setsPool() public view {
        assertEq(address(adapter.POOL()), address(pool));
    }

    function test_constructor_rejectsZero() public {
        vm.expectRevert(bytes("AaveV3FlashAdapter: pool=0"));
        new AaveV3FlashAdapter(address(0));
    }

    function test_quotePremium_matchesPoolFormula() public view {
        // (1e9 * 5 + 9999) / 1e4 = 500_001
        assertEq(adapter.quotePremium(1e9), (1e9 * POOL_PREMIUM_BPS + 9999) / 1e4);
    }

    function test_quotePremium_zeroAmount() public view {
        assertEq(adapter.quotePremium(0), 0);
    }

    function test_quotePremium_smallAmount_roundsUp() public view {
        // (1 * 5 + 9999) / 1e4 = 1 (ceiling)
        assertEq(adapter.quotePremium(1), 1);
    }

    // -----------------------------------------------------------------
    // Happy path via TestReceiver (covers the adapter end-to-end)
    // -----------------------------------------------------------------

    function _deployReceiver() internal returns (TestReceiver r) {
        vm.prank(owner);
        r = new TestReceiver(owner);
        vm.prank(owner);
        r.setAdapter(address(adapter), true);
    }

    function test_flashLoan_happyPath_emitsEvent() public {
        TestReceiver r = _deployReceiver();
        uint256 amount = 100_000e6;
        uint256 premium = adapter.quotePremium(amount);
        // Fund the receiver with the premium up front so it can repay.
        token.mint(address(r), premium);

        vm.expectEmit(true, true, false, true, address(adapter));
        emit AaveV3FlashAdapter.FlashLoanExecuted(address(r), address(token), amount, premium);

        r.startLoan(address(adapter), address(token), amount, hex"deadbeef");

        // Receiver lost exactly the premium; adapter holds nothing.
        assertEq(token.balanceOf(address(r)), 0);
        assertEq(token.balanceOf(address(adapter)), 0);
    }

    function test_flashLoan_zeroAmount_succeeds() public {
        TestReceiver r = _deployReceiver();
        // 0 amount → 0 premium → no funding needed.
        r.startLoan(address(adapter), address(token), 0, "");
    }

    function test_flashLoan_largeAmount() public {
        TestReceiver r = _deployReceiver();
        uint256 amount = 500_000e6;
        uint256 premium = adapter.quotePremium(amount);
        token.mint(address(r), premium);
        r.startLoan(address(adapter), address(token), amount, "");
        assertEq(token.balanceOf(address(r)), 0);
    }

    // -----------------------------------------------------------------
    // Failure paths
    // -----------------------------------------------------------------

    function test_executeOperation_revertsIfCalledByNonPool() public {
        bytes memory params = abi.encode(address(this), bytes(""));
        vm.expectRevert(abi.encodeWithSelector(AaveV3FlashAdapter.NotPool.selector, address(this)));
        adapter.executeOperation(address(token), 0, 0, address(adapter), params);
    }

    function test_executeOperation_revertsOnWrongInitiator() public {
        bytes memory params = abi.encode(address(this), bytes(""));
        vm.prank(address(pool));
        vm.expectRevert(abi.encodeWithSelector(AaveV3FlashAdapter.WrongInitiator.selector, address(0xBEEF)));
        adapter.executeOperation(address(token), 0, 0, address(0xBEEF), params);
    }

    function test_flashLoan_revertsOnShortfall() public {
        TestReceiver r = _deployReceiver();
        r.setMode(TestReceiver.Mode.Shortfall);
        uint256 amount = 100_000e6;
        uint256 premium = adapter.quotePremium(amount);
        // Even with funding, the receiver only repays `amount`, not `amount+premium`.
        token.mint(address(r), premium);
        vm.expectRevert(); // ERC20InsufficientAllowance bubble-up
        r.startLoan(address(adapter), address(token), amount, "");
    }

    function test_flashLoan_revertsOnBadReturn() public {
        TestReceiver r = _deployReceiver();
        r.setMode(TestReceiver.Mode.BadReturn);
        r.setSpoofedReturn(bytes32(uint256(0xdead)));
        uint256 amount = 1_000e6;
        uint256 premium = adapter.quotePremium(amount);
        token.mint(address(r), premium);

        vm.expectRevert(
            abi.encodeWithSelector(AaveV3FlashAdapter.BadCallbackReturn.selector, bytes32(uint256(0xdead)))
        );
        r.startLoan(address(adapter), address(token), amount, "");
    }

    function test_flashLoan_nonReentrant_blocksNestedCall() public {
        TestReceiver r = _deployReceiver();
        r.setMode(TestReceiver.Mode.Reenter);
        r.setReentry(address(adapter), address(token), 100e6);
        token.mint(address(r), adapter.quotePremium(100e6) + adapter.quotePremium(100e6));
        // The inner call should hit ReentrancyGuard; the whole tx reverts.
        vm.expectRevert();
        r.startLoan(address(adapter), address(token), 100e6, "");
    }

    // -----------------------------------------------------------------
    // FlashLoanReceiverBase path (covers the base contract logic)
    // -----------------------------------------------------------------

    function test_baseReceiver_singleAsset_happy() public {
        vm.prank(owner);
        BaseReceiver br = new BaseReceiver(owner);
        vm.prank(owner);
        br.setAdapter(address(adapter), true);

        uint256 amount = 50_000e6;
        uint256 premium = adapter.quotePremium(amount);
        // Pre-fund the receiver with the fee so it can repay.
        token.mint(address(br), premium);

        br.startLoan(address(adapter), address(token), amount, "");

        assertEq(token.balanceOf(address(br)), 0, "all funds repaid");
    }

    function test_baseReceiver_revertsOnIncompleteRepayment() public {
        vm.prank(owner);
        BaseReceiver br = new BaseReceiver(owner);
        vm.prank(owner);
        br.setAdapter(address(adapter), true);
        br.setMode(BaseReceiver.Mode.Shortfall, address(token), address(0xDEAD));

        uint256 amount = 50_000e6;
        uint256 premium = adapter.quotePremium(amount);
        token.mint(address(br), premium); // give it enough …
        // but mode == Shortfall transfers the fee out before the base checks.
        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoanReceiverBase.IncompleteRepayment.selector, address(token), amount + premium, amount
            )
        );
        br.startLoan(address(adapter), address(token), amount, "");
    }

    function test_baseReceiver_callback_rejectsUntrustedAdapter() public {
        vm.prank(owner);
        BaseReceiver br = new BaseReceiver(owner);
        // not whitelisted
        vm.expectRevert(abi.encodeWithSelector(FlashLoanReceiverBase.UntrustedAdapter.selector, address(this)));
        br.onFlashLoan(address(token), 0, 0, address(br), "");
    }

    function test_baseReceiver_callback_rejectsWrongInitiator() public {
        vm.prank(owner);
        BaseReceiver br = new BaseReceiver(owner);
        vm.prank(owner);
        br.setAdapter(address(this), true);
        vm.expectRevert(abi.encodeWithSelector(FlashLoanReceiverBase.WrongInitiator.selector, address(0xBEEF)));
        br.onFlashLoan(address(token), 0, 0, address(0xBEEF), "");
    }

    function test_baseReceiver_setAdapter_onlyOwner() public {
        vm.prank(owner);
        BaseReceiver br = new BaseReceiver(owner);

        vm.expectRevert(); // OwnableUnauthorizedAccount
        br.setAdapter(address(adapter), true);

        vm.prank(owner);
        br.setAdapter(address(adapter), true);
        assertTrue(br.trustedAdapter(address(adapter)));
    }

    // -----------------------------------------------------------------
    // Fuzz
    // -----------------------------------------------------------------

    function testFuzz_quotePremium_isCeiling(uint256 amount, uint128 bps) public {
        amount = bound(amount, 0, 1e30);
        bps = uint128(bound(uint256(bps), 0, 1e4));
        pool.setPremium(bps);
        uint256 expected = (amount * uint256(bps) + 9999) / 1e4;
        assertEq(adapter.quotePremium(amount), expected);
    }

    function testFuzz_flashLoan_anyAmount(uint256 amount) public {
        amount = bound(amount, 0, 1_000_000e6);
        TestReceiver r = _deployReceiver();
        uint256 premium = adapter.quotePremium(amount);
        if (premium > 0) token.mint(address(r), premium);
        r.startLoan(address(adapter), address(token), amount, "");
        assertEq(token.balanceOf(address(r)), 0);
    }
}
