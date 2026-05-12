// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAaveV3Pool
/// @notice Minimal subset of the Aave V3 Pool interface we depend on.
interface IAaveV3Pool {
    /// @notice Single-asset flash loan (cheaper than the multi-asset variant).
    /// @dev    Aave will call back `executeOperation` on `receiverAddress`.
    /// @param  receiverAddress Contract implementing the Aave callback (our adapter).
    /// @param  asset           Token to borrow.
    /// @param  amount          Amount to borrow.
    /// @param  params          Arbitrary payload forwarded to the callback.
    /// @param  referralCode    Aave referral code (0 if none).
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;

    /// @notice Premium charged on flashLoanSimple in basis points (e.g. 5 = 0.05%).
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);
}

/// @title IAaveV3FlashReceiver
/// @notice Callback the Aave V3 Pool invokes on the borrower of a single-asset flash loan.
interface IAaveV3FlashReceiver {
    /// @return success Aave expects `true` on success; the pool then pulls
    ///         `amount + premium` via `transferFrom` from the receiver.
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool success);
}
