// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IFlashLoanProvider } from "../interfaces/IFlashLoanProvider.sol";
import { IFlashLoanCallback } from "../interfaces/IFlashLoanCallback.sol";
import { IAaveV3Pool, IAaveV3FlashReceiver } from "../interfaces/IAaveV3Pool.sol";

/// @title AaveV3FlashAdapter
/// @notice Wraps Aave V3's `flashLoanSimple` behind {IFlashLoanProvider} so
///         downstream callers stay protocol-agnostic.
/// @dev    Flow:
///         1. Borrower calls {flashLoan}.
///         2. Adapter calls `pool.flashLoanSimple(this, asset, amount, params, 0)`
///            with `params = abi.encode(borrower, data)`. No adapter state is
///            written between the two calls — everything rides in `params`.
///         3. Aave transfers `amount` to this adapter and calls
///            {executeOperation}, which forwards to `borrower.onFlashLoan`.
///         4. The borrower returns `amount + premium` to the adapter
///            (per the {FlashLoanReceiverBase} convention).
///         5. Adapter approves `amount + premium` to the pool and returns
///            true; Aave then pulls via `transferFrom`.
contract AaveV3FlashAdapter is IFlashLoanProvider, IAaveV3FlashReceiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Aave V3 Pool address this adapter is bound to.
    IAaveV3Pool public immutable POOL;

    /// @dev Magic return value the borrower must produce in onFlashLoan.
    bytes32 private constant CALLBACK_OK = keccak256("IFlashLoanCallback.onFlashLoan");

    event FlashLoanExecuted(address indexed borrower, address indexed asset, uint256 amount, uint256 premium);

    error NotPool(address caller);
    error WrongInitiator(address initiator);
    error BadCallbackReturn(bytes32 ret);

    constructor(address pool) {
        require(pool != address(0), "AaveV3FlashAdapter: pool=0");
        POOL = IAaveV3Pool(pool);
    }

    /// @notice Quote the current Aave V3 premium for an `amount` borrowed.
    /// @dev    Aave stores the premium in basis points (1e4 denominator).
    function quotePremium(uint256 amount) public view returns (uint256) {
        uint256 bps = uint256(POOL.FLASHLOAN_PREMIUM_TOTAL());
        // Match Aave's _calculateFlashLoanFee: `(amount * bps + 1e4 - 1) / 1e4`
        return (amount * bps + 1e4 - 1) / 1e4;
    }

    /// @inheritdoc IFlashLoanProvider
    function flashLoan(address asset, uint256 amount, bytes calldata data) external override nonReentrant {
        // Tunnel the original caller through Aave's `params` field so we keep
        // the adapter stateless between the outbound call and the callback.
        bytes memory params = abi.encode(msg.sender, data);
        POOL.flashLoanSimple(address(this), asset, amount, params, 0);
    }

    /// @inheritdoc IAaveV3FlashReceiver
    /// @dev Called by the Aave Pool after it has sent `amount` of `asset` here.
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        if (msg.sender != address(POOL)) revert NotPool(msg.sender);
        // initiator (from Aave's view) is this adapter, because we called the pool.
        if (initiator != address(this)) revert WrongInitiator(initiator);

        (address borrower, bytes memory data) = abi.decode(params, (address, bytes));

        // Hand the borrowed funds to the borrower.
        IERC20(asset).safeTransfer(borrower, amount);

        // Run the borrower's business logic. The borrower must transfer
        // `amount + premium` of `asset` back to us before returning.
        bytes32 ret = IFlashLoanCallback(borrower).onFlashLoan(asset, amount, premium, borrower, data);
        if (ret != CALLBACK_OK) revert BadCallbackReturn(ret);

        // Authorise the pool to pull the principal + premium from us.
        IERC20(asset).forceApprove(address(POOL), amount + premium);

        emit FlashLoanExecuted(borrower, asset, amount, premium);
        return true;
    }
}
