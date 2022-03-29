// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/utils/math/SafeCast.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import './ValidationLogic.sol';
import '../types/DataTypes.sol';
import '../configuration/ReserveConfiguration.sol';
import '../../interfaces/IPriceOracleGetter.sol';
import '../../interfaces/IEToken.sol';
import '../../interfaces/IBank.sol';
import '../../interfaces/IVariableDebtToken.sol';

/**
 * @title BorrowLogic library
 * @author Evolving
 * @title Implements protocol-level borrow logic
 */
library BorrowLogic {
  using SafeCast for uint256;
  using SafeMath for uint256;
  using ReserveLogic for DataTypes.ReserveData;
  using UserConfiguration for DataTypes.UserConfigurationMap;
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  event Borrow(
    address indexed reserve,
    address user,
    address indexed onBehalfOf,
    uint256 amount,
    // uint256 borrowRateMode,
    uint256 borrowRate,
    uint16 indexed referral
  );

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
      reserve,
      vars.onBehalfOf,
      vars.amount,
      amountInETH,
      // vars.interestRateMode,
      // vars.maxStableRateBorrowSizePercent,
      _reserves,
      userConfig,
      _reservesList,
      vars.reservesCount,
      oracle
    );

    reserve.updateState();

    // uint256 currentStableRate = 0;

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
      reserve.eTokenAddress,
      0,
      vars.releaseUnderlying ? vars.amount : 0
    );

    if (vars.releaseUnderlying) {
      IEToken(reserve.eTokenAddress).transferUnderlyingTo(vars.user, vars.amount);
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