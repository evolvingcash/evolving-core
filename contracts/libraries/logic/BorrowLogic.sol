// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import './ValidationLogic.sol';
import '../types/DataTypes.sol';
import '../../interfaces/IPriceOracleGetter.sol';
import '../../interfaces/IEToken.sol';
import '../../interfaces/IPool.sol';
import '../../interfaces/IVariableDebtToken.sol';

/**
 * @title BorrwoLogic library
 * @author Evolving
 * @title Implements protocol-level borrow logic
 */
library BorrwoLogic {
  /**
   * @dev excute borrow
   */
  function executeBorrow(
      mapping(address => DataTypes.ReserveData) storage _reserves,
      mapping(uint256 => address) storage _reservesList,
      DataTypes.UserConfigurationMap storage userConfig,
      DataTypes.ExecuteBorrowParams memory vars
    ) internal {
    DataTypes.ReserveData storage reserve = _reserves[vars.asset];

    address oracle = vars.oracle;

    uint256 amountInETH =
      IPriceOracleGetter(oracle).getAssetPrice(vars.asset).mul(vars.amount).div(
        10**reserve.configuration.getDecimals()
      );

    ValidationLogic.validateBorrow(
      vars.asset,
      reserve,
      vars.onBehalfOf,
      vars.amount,
      amountInETH,
      // vars.interestRateMode,
      vars.maxStableRateBorrowSizePercent,
      _reserves,
      userConfig,
      _reservesList,
      vars.reservesCount,
      oracle
    );

    reserve.updateState();

    uint256 currentStableRate = 0;

    bool isFirstBorrowing = false;
    // if (DataTypes.InterestRateMode(vars.interestRateMode) == DataTypes.InterestRateMode.STABLE) {
    //   currentStableRate = reserve.currentStableBorrowRate;

    //   isFirstBorrowing = IStableDebtToken(reserve.stableDebtTokenAddress).mint(
    //     vars.user,
    //     vars.onBehalfOf,
    //     vars.amount,
    //     currentStableRate
    //   );
    // } else {
      isFirstBorrowing = IVariableDebtToken(reserve.variableDebtTokenAddress).mint(
        vars.user,
        vars.onBehalfOf,
        vars.amount,
        reserve.variableBorrowIndex
      );
    // }

    if (isFirstBorrowing) {
      userConfig.setBorrowing(reserve.id, true);
    }

    reserve.updateInterestRates(
      vars.asset,
      vars.eTokenAddress,
      0,
      vars.releaseUnderlying ? vars.amount : 0
    );

    if (vars.releaseUnderlying) {
      IEToken(vars.eTokenAddress).transferUnderlyingTo(vars.user, vars.amount);
    }

    emit Borrow(
      vars.asset,
      vars.user,
      vars.onBehalfOf,
      vars.amount,
      // vars.interestRateMode,
      reserve.currentVariableBorrowRate,
      vars.referralCode
    );
  }

}