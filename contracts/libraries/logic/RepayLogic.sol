// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import './ValidationLogic.sol';
import '../types/DataTypes.sol';
import '../math/WadRayMath.sol';
import '../math/PercentageMath.sol';
import '../configuration/ReserveConfiguration.sol';
import '../configuration/UserConfiguration.sol';
import '../../interfaces/IBank.sol';
import '../../interfaces/IPriceOracleGetter.sol';
import '../../interfaces/IEToken.sol';
import '../../interfaces/IVariableDebtToken.sol';

/**
 * @title Repay logic library
 * @author Evolving
 * @title Implements protocol-level repay logic
 */
library RepayLogic {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using ReserveLogic for DataTypes.ReserveData;
  using UserConfiguration for DataTypes.UserConfigurationMap;
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  /**
   * @dev Emitted on repay()
   * @param reserve The address of the underlying asset of the reserve
   * @param user The beneficiary of the repayment, getting his debt reduced
   * @param repayer The address of the user initiating the repay(), providing the funds
   * @param amount The amount repaid
   **/
  event Repay(
    address indexed reserve,
    address indexed user,
    address indexed repayer,
    uint256 amount
  );

  function repay(
    DataTypes.ReserveData storage reserve,
    DataTypes.UserConfigurationMap storage userConfig,
    address asset,
    uint256 amount,
    address onBehalfOf
  ) external returns (uint256) {

    // (uint256 stableDebt, uint256 variableDebt) = Helpers.getUserCurrentDebt(onBehalfOf, reserve);
    uint256 variableDebt = IERC20(reserve.variableDebtTokenAddress).balanceOf(onBehalfOf);
    // DataTypes.InterestRateMode interestRateMode = DataTypes.InterestRateMode(rateMode);

    ValidationLogic.validateRepay(
      reserve,
      amount,
    //   interestRateMode,
      onBehalfOf,
    //   stableDebt,
      variableDebt
    );

    uint256 paybackAmount = variableDebt;

    if (amount < paybackAmount) {
      paybackAmount = amount;
    }

    reserve.updateState();

    // if (interestRateMode == DataTypes.InterestRateMode.STABLE) {
    //   IStableDebtToken(reserve.stableDebtTokenAddress).burn(onBehalfOf, paybackAmount);
    // } else {
    IVariableDebtToken(reserve.variableDebtTokenAddress).burn(
        onBehalfOf,
        paybackAmount,
        reserve.variableBorrowIndex
      );
    // }

    address eToken = reserve.eTokenAddress;
    reserve.updateInterestRates(asset, eToken, paybackAmount, 0);

    if (variableDebt.sub(paybackAmount) == 0) {
      userConfig.setBorrowing(reserve.id, false);
    }

    IERC20(asset).safeTransferFrom(msg.sender, eToken, paybackAmount);

    IEToken(eToken).handleRepayment(msg.sender, paybackAmount);

    emit Repay(asset, onBehalfOf, msg.sender, paybackAmount);

    return paybackAmount;
  }
}
