// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

interface ICpChainBase {
    event MinDepositUpdated(uint256 previousValue, uint256 newValue);

    event MaxDepositUpdated(uint256 previousValue, uint256 newValue);

    function deposit(
        uint256 amount,
        address staker
    ) external payable returns (uint256);

    function withdraw(address recipient, uint256 amountShares) external;

    function sharesToUnderlying(
        uint256 amountShares
    ) external returns (uint256);

    function underlyingToShares(
        uint256 amountUnderlying
    ) external returns (uint256);

    function userUnderlying(address user) external returns (uint256);

    function shares(address user) external view returns (uint256);

    function sharesToUnderlyingView(
        uint256 amountShares
    ) external view returns (uint256);

    function underlyingToSharesView(
        uint256 amountUnderlying
    ) external view returns (uint256);

    function userUnderlyingView(address user) external view returns (uint256);

    function totalShares() external view returns (uint256);

    function explanation() external view returns (string memory);

    function setDepositLimits(
        uint256 newMaxPerDeposit,
        uint256 newMaxTotalDeposits
    ) external;

    function getDepositLimits() external view returns (uint256, uint256);

    function deleteStaker(address staker) external;

    function stakerListLength() external view returns (uint256);

    function stakerListFind(uint256 index) external view returns (address);
}
