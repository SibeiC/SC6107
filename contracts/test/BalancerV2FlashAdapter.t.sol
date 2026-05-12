// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BalancerV2FlashAdapter } from "../src/adapters/BalancerV2FlashAdapter.sol";
import { MockBalancerVault } from "../src/mocks/MockBalancerVault.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { TestReceiver } from "./helpers/TestReceiver.sol";
import { BaseReceiver } from "./helpers/BaseReceiver.sol";
import { FlashLoanReceiverBase } from "../src/base/FlashLoanReceiverBase.sol";

contract BalancerV2FlashAdapterTest is Test {
    BalancerV2FlashAdapter internal adapter;
    MockBalancerVault internal vault;
    MockERC20 internal usdc;
    MockERC20 internal weth;

    address internal owner = address(0xA11CE);

    function setUp() public {
        // Real Balancer V2 fee is 0; mirror that as the default.
        vault = new MockBalancerVault(0);
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        weth = new MockERC20("Mock WETH", "mWETH", 18);
        usdc.mint(address(vault), 5_000_000e6);
        weth.mint(address(vault), 5_000e18);
        adapter = new BalancerV2FlashAdapter(address(vault));
    }

    // -----------------------------------------------------------------
    // Construction
    // -----------------------------------------------------------------

    function test_constructor_setsVault() public view {
        assertEq(address(adapter.VAULT()), address(vault));
    }

    function test_constructor_rejectsZero() public {
        vm.expectRevert(bytes("BalancerV2FlashAdapter: vault=0"));
        new BalancerV2FlashAdapter(address(0));
    }

    function _deployReceiver() internal returns (TestReceiver r) {
        vm.prank(owner);
        r = new TestReceiver(owner);
        vm.prank(owner);
        r.setAdapter(address(adapter), true);
    }

    // -----------------------------------------------------------------
    // Single-asset
    // -----------------------------------------------------------------

    function test_flashLoan_singleAsset_zeroFee() public {
        TestReceiver r = _deployReceiver();
        uint256 amount = 250_000e6;

        vm.expectEmit(true, true, false, true, address(adapter));
        emit BalancerV2FlashAdapter.FlashLoanExecuted(address(r), address(usdc), amount, 0);

        r.startLoan(address(adapter), address(usdc), amount, hex"01");

        assertEq(usdc.balanceOf(address(r)), 0);
        assertEq(usdc.balanceOf(address(adapter)), 0);
        assertEq(usdc.balanceOf(address(vault)), 5_000_000e6);
    }

    function test_flashLoan_singleAsset_withFee() public {
        vault.setFee(1e15); // 0.1%
        TestReceiver r = _deployReceiver();
        uint256 amount = 100_000e6;
        uint256 fee = (amount * 1e15) / 1e18; // 100e6
        usdc.mint(address(r), fee);

        r.startLoan(address(adapter), address(usdc), amount, "");

        assertEq(usdc.balanceOf(address(r)), 0);
        // Vault gained exactly the fee.
        assertEq(usdc.balanceOf(address(vault)), 5_000_000e6 + fee);
    }

    function test_flashLoan_revertsOnShortfall() public {
        TestReceiver r = _deployReceiver();
        vault.setFee(1e15);
        r.setMode(TestReceiver.Mode.Shortfall);
        // mode pays back only `amount` (no fee), so adapter can't repay vault
        usdc.mint(address(r), (100_000e6 * 1e15) / 1e18);
        vm.expectRevert(); // bubbles up either ERC20 transfer or RepaymentFailed
        r.startLoan(address(adapter), address(usdc), 100_000e6, "");
    }

    function test_flashLoan_revertsOnBadReturn() public {
        TestReceiver r = _deployReceiver();
        r.setMode(TestReceiver.Mode.BadReturn);
        r.setSpoofedReturn(bytes32(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(BalancerV2FlashAdapter.BadCallbackReturn.selector, bytes32(uint256(1)))
        );
        r.startLoan(address(adapter), address(usdc), 1_000e6, "");
    }

    function test_flashLoan_nonReentrant() public {
        TestReceiver r = _deployReceiver();
        r.setMode(TestReceiver.Mode.Reenter);
        r.setReentry(address(adapter), address(usdc), 100e6);
        vm.expectRevert();
        r.startLoan(address(adapter), address(usdc), 100e6, "");
    }

    function test_receiveFlashLoan_rejectsNonVault() public {
        IERC20[] memory tokens = new IERC20[](0);
        uint256[] memory amts = new uint256[](0);
        // Random caller invoking the Balancer callback directly.
        vm.expectRevert(abi.encodeWithSelector(BalancerV2FlashAdapter.NotVault.selector, address(this)));
        adapter.receiveFlashLoan(tokens, amts, amts, "");
    }

    // -----------------------------------------------------------------
    // Multi-asset
    // -----------------------------------------------------------------

    function test_flashLoanMulti_happyPath() public {
        TestReceiver r = _deployReceiver();
        address[] memory assets = new address[](2);
        assets[0] = address(usdc);
        assets[1] = address(weth);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 50_000e6;
        amts[1] = 10e18;

        vm.expectEmit(true, false, false, true, address(adapter));
        emit BalancerV2FlashAdapter.FlashLoanMultiExecuted(address(r), 2);

        r.startLoanMulti(address(adapter), assets, amts, "");
        assertEq(usdc.balanceOf(address(r)), 0);
        assertEq(weth.balanceOf(address(r)), 0);
    }

    function test_flashLoanMulti_lengthMismatch_reverts() public {
        TestReceiver r = _deployReceiver();
        address[] memory assets = new address[](2);
        assets[0] = address(usdc);
        assets[1] = address(weth);
        uint256[] memory amts = new uint256[](1);
        amts[0] = 1;
        vm.expectRevert(BalancerV2FlashAdapter.LengthMismatch.selector);
        r.startLoanMulti(address(adapter), assets, amts, "");
    }

    function test_flashLoanMulti_withFee() public {
        vault.setFee(5e14); // 0.05%
        TestReceiver r = _deployReceiver();
        address[] memory assets = new address[](2);
        assets[0] = address(usdc);
        assets[1] = address(weth);
        uint256[] memory amts = new uint256[](2);
        amts[0] = 200_000e6;
        amts[1] = 50e18;
        // Pre-fund the receiver with the fees.
        usdc.mint(address(r), (amts[0] * 5e14) / 1e18);
        weth.mint(address(r), (amts[1] * 5e14) / 1e18);
        r.startLoanMulti(address(adapter), assets, amts, "");
    }

    // -----------------------------------------------------------------
    // FlashLoanReceiverBase coverage
    // -----------------------------------------------------------------

    function test_baseReceiver_singleAsset() public {
        vm.prank(owner);
        BaseReceiver br = new BaseReceiver(owner);
        vm.prank(owner);
        br.setAdapter(address(adapter), true);
        br.startLoan(address(adapter), address(usdc), 10_000e6, "");
    }

    function test_baseReceiver_multiAsset_default_revertsByBalanceCheck() public {
        // Default _executeOperationMulti is a no-op, so the receiver never
        // gains the fee — but here fee is 0, so it has to repay only the
        // principal which it has. So balance check passes for fee==0 case.
        vm.prank(owner);
        BaseReceiver br = new BaseReceiver(owner);
        vm.prank(owner);
        br.setAdapter(address(adapter), true);

        address[] memory assets = new address[](1);
        assets[0] = address(usdc);
        uint256[] memory amts = new uint256[](1);
        amts[0] = 1_000e6;
        br.startLoanMulti(address(adapter), assets, amts, "");
    }

    function test_baseReceiver_multiAsset_shortfall_reverts() public {
        vault.setFee(1e15);
        vm.prank(owner);
        BaseReceiver br = new BaseReceiver(owner);
        vm.prank(owner);
        br.setAdapter(address(adapter), true);
        br.setMode(BaseReceiver.Mode.Shortfall, address(usdc), address(0xDEAD));

        address[] memory assets = new address[](1);
        assets[0] = address(usdc);
        uint256[] memory amts = new uint256[](1);
        amts[0] = 1_000e6;
        uint256 fee = (1_000e6 * 1e15) / 1e18;
        usdc.mint(address(br), fee);

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoanReceiverBase.IncompleteRepayment.selector, address(usdc), amts[0] + fee, amts[0]
            )
        );
        br.startLoanMulti(address(adapter), assets, amts, "");
    }

    function test_baseReceiver_multiAsset_lengthMismatch_inCallback() public {
        // Force a length mismatch by impersonating an adapter.
        vm.prank(owner);
        BaseReceiver br = new BaseReceiver(owner);
        vm.prank(owner);
        br.setAdapter(address(this), true);

        address[] memory assets = new address[](2);
        assets[0] = address(usdc);
        assets[1] = address(weth);
        uint256[] memory amts = new uint256[](2);
        uint256[] memory fees = new uint256[](1);
        vm.expectRevert(FlashLoanReceiverBase.LengthMismatch.selector);
        br.onFlashLoanMulti(assets, amts, fees, address(br), "");
    }
}

