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
import '../../interfaces/IPool.sol';
import '../../interfaces/IPriceOracleGetter.sol';
import '../../interfaces/IEToken.sol';
import '../../interfaces/IVariableDebtToken.sol';

/**
 * @title Liquidation logic library
 * @author Evolving
 * @title Implements protocol-level borrow logic
 */
library LiquidationLogic {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using ReserveLogic for DataTypes.ReserveData;
  using UserConfiguration for DataTypes.UserConfigurationMap;
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  struct LiquidationCallLocalVars {
    uint256 userCollateralBalance;
    uint256 userVariableDebt;
    uint256 maxLiquidatableDebt;
    uint256 actualDebtToLiquidate;
    uint256 liquidationRatio;
    uint256 maxAmountCollateralToLiquidate;
    uint256 maxCollateralToLiquidate;
    uint256 debtAmountNeeded;
    uint256 healthFactor;
    uint256 liquidatorPreviousETokenBalance;
    IEToken collateralEtoken;
    bool isCollateralEnabled;
    uint256 errorCode;
    string errorMsg;
  }

  event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);
  event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);
  event LiquidationCall(
    address indexed collateralAsset,
    address indexed debtAsset,
    address indexed user,
    uint256 debtToCover,
    uint256 liquidatedCollateralAmount,
    address liquidator,
    bool receiveEToken
  );

  uint256 internal constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000;

  /**
   * @dev Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
   * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
   *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
   * @param reserves pool _reserves
   * @param reservesList pool _reservesList
   * @param userConfig user config
   * @param liquidatorConfig liquidator config
   * @param param LiquidationCallParams param
   **/
  function liquidationCall(
    mapping(address => DataTypes.ReserveData) storage reserves,
    mapping(uint256 => address) storage reservesList,
    DataTypes.UserConfigurationMap storage userConfig,
    DataTypes.UserConfigurationMap storage liquidatorConfig,
    DataTypes.LiquidationCallParams memory param
  ) external {
    DataTypes.ReserveData storage collateralReserve = reserves[param.collateralAsset];
    DataTypes.ReserveData storage debtReserve = reserves[param.debtAsset];
    // DataTypes.UserConfigurationMap storage userConfig = _usersConfig[user];

    LiquidationCallLocalVars memory vars;

    (, , , , vars.healthFactor) = GenericLogic.calculateUserAccountData(
      param.user,
      reserves,
      userConfig,
      reservesList,
      param.reservesCount,
      param.priceOracle
    );

    // (vars.userStableDebt, vars.userVariableDebt) = Helpers.getUserCurrentDebt(user, debtReserve);
    vars.userVariableDebt = IERC20(debtReserve.variableDebtTokenAddress).balanceOf(param.user);
    ValidationLogic.validateLiquidationCall(
      collateralReserve,
      debtReserve,
      userConfig,
      vars.healthFactor,
    //   vars.userStableDebt,
      vars.userVariableDebt
    );

    // if (Errors.CollateralManagerErrors(vars.errorCode) != Errors.CollateralManagerErrors.NO_ERROR) {
    //   return (vars.errorCode, vars.errorMsg);
    // }

    vars.collateralEtoken = IEToken(collateralReserve.eTokenAddress);

    vars.userCollateralBalance = vars.collateralEtoken.balanceOf(param.user);

    vars.maxLiquidatableDebt = vars.userVariableDebt.percentMul(
      LIQUIDATION_CLOSE_FACTOR_PERCENT
    );

    vars.actualDebtToLiquidate = param.debtToCover > vars.maxLiquidatableDebt
      ? vars.maxLiquidatableDebt
      : param.debtToCover;

    (
      vars.maxCollateralToLiquidate,
      vars.debtAmountNeeded
    ) = _calculateAvailableCollateralToLiquidate(
      collateralReserve,
      debtReserve,
      param.collateralAsset,
      param.debtAsset,
      vars.actualDebtToLiquidate,
      vars.userCollateralBalance,
      IPriceOracleGetter(param.priceOracle)
    );

    // If debtAmountNeeded < actualDebtToLiquidate, there isn't enough
    // collateral to cover the actual amount that is being liquidated, hence we liquidate
    // a smaller amount

    if (vars.debtAmountNeeded < vars.actualDebtToLiquidate) {
      vars.actualDebtToLiquidate = vars.debtAmountNeeded;
    }

    // If the liquidator reclaims the underlying asset, we make sure there is enough available liquidity in the
    // collateral reserve
    if (!param.receiveEToken) {
      uint256 currentAvailableCollateral =
        IERC20(param.collateralAsset).balanceOf(address(vars.collateralEtoken));
      require(currentAvailableCollateral >= vars.maxCollateralToLiquidate,
          Errors.LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE);
      // if (currentAvailableCollateral < vars.maxCollateralToLiquidate) {
      //   return (
      //     uint256(Errors.CollateralManagerErrors.NOT_ENOUGH_LIQUIDITY),
      //     Errors.LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE
      //   );
      // }
    }

    debtReserve.updateState();

    if (vars.userVariableDebt >= vars.actualDebtToLiquidate) {
      IVariableDebtToken(debtReserve.variableDebtTokenAddress).burn(
        param.user,
        vars.actualDebtToLiquidate,
        debtReserve.variableBorrowIndex
      );
    } else {
      // If the user doesn't have variable debt, no need to try to burn variable debt tokens
      if (vars.userVariableDebt > 0) {
        IVariableDebtToken(debtReserve.variableDebtTokenAddress).burn(
          param.user,
          vars.userVariableDebt,
          debtReserve.variableBorrowIndex
        );
      }
    //   IStableDebtToken(debtReserve.stableDebtTokenAddress).burn(
    //     user,
    //     vars.actualDebtToLiquidate.sub(vars.userVariableDebt)
    //   );
    }

    debtReserve.updateInterestRates(
      param.debtAsset,
      debtReserve.eTokenAddress,
      vars.actualDebtToLiquidate,
      0
    );

    if (param.receiveEToken) {
      vars.liquidatorPreviousETokenBalance = IERC20(vars.collateralEtoken).balanceOf(msg.sender);
      vars.collateralEtoken.transferOnLiquidation(param.user, msg.sender, vars.maxCollateralToLiquidate);

      if (vars.liquidatorPreviousETokenBalance == 0) {
        // DataTypes.UserConfigurationMap storage liquidatorConfig = usersConfig[msg.sender];
        liquidatorConfig.setUsingAsCollateral(collateralReserve.id, true);
        emit ReserveUsedAsCollateralEnabled(param.collateralAsset, msg.sender);
      }
    } else {
      collateralReserve.updateState();
      collateralReserve.updateInterestRates(
        param.collateralAsset,
        address(vars.collateralEtoken),
        0,
        vars.maxCollateralToLiquidate
      );

      // Burn the equivalent amount of eToken, sending the underlying to the liquidator
      vars.collateralEtoken.burn(
        param.user,
        msg.sender,
        vars.maxCollateralToLiquidate,
        collateralReserve.liquidityIndex
      );
    }

    // If the collateral being liquidated is equal to the user balance,
    // we set the currency as not being used as collateral anymore
    if (vars.maxCollateralToLiquidate == vars.userCollateralBalance) {
      userConfig.setUsingAsCollateral(collateralReserve.id, false);
      emit ReserveUsedAsCollateralDisabled(param.collateralAsset, param.user);
    }

    // Transfers the debt asset being repaid to the eToken, where the liquidity is kept
    IERC20(param.debtAsset).safeTransferFrom(
      msg.sender,
      debtReserve.eTokenAddress,
      vars.actualDebtToLiquidate
    );

    emit LiquidationCall(
      param.collateralAsset,
      param.debtAsset,
      param.user,
      vars.actualDebtToLiquidate,
      vars.maxCollateralToLiquidate,
      msg.sender,
      param.receiveEToken
    );

    // return (uint256(Errors.CollateralManagerErrors.NO_ERROR), Errors.LPCM_NO_ERRORS);
  }

  struct AvailableCollateralToLiquidateLocalVars {
    uint256 userCompoundedBorrowBalance;
    uint256 liquidationBonus;
    uint256 collateralPrice;
    uint256 debtAssetPrice;
    uint256 maxAmountCollateralToLiquidate;
    uint256 debtAssetDecimals;
    uint256 collateralDecimals;
    uint256 collateralAssetUnit;
    uint256 debtAssetUnit;
  }

  /**
   * @dev Calculates how much of a specific collateral can be liquidated, given
   * a certain amount of debt asset.
   * - This function needs to be called after all the checks to validate the liquidation have been performed,
   *   otherwise it might fail.
   * @param collateralReserve The data of the collateral reserve
   * @param debtReserve The data of the debt reserve
   * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
   * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
   * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
   * @param userCollateralBalance The collateral balance for the specific `collateralAsset` of the user being liquidated
   * @return collateralAmount: The maximum amount that is possible to liquidate given all the liquidation constraints
   *                           (user balance, close factor)
   *         debtAmountNeeded: The amount to repay with the liquidation
   **/
  function _calculateAvailableCollateralToLiquidate(
    DataTypes.ReserveData storage collateralReserve,
    DataTypes.ReserveData storage debtReserve,
    address collateralAsset,
    address debtAsset,
    uint256 debtToCover,
    uint256 userCollateralBalance,
    IPriceOracleGetter oracle
  ) internal view returns (uint256, uint256) {
    uint256 collateralAmount = 0;
    uint256 debtAmountNeeded = 0;
    // IPriceOracleGetter oracle = IPriceOracleGetter(_addressesProvider.getPriceOracle());

    AvailableCollateralToLiquidateLocalVars memory vars;

    vars.collateralPrice = oracle.getAssetPrice(collateralAsset);
    vars.debtAssetPrice = oracle.getAssetPrice(debtAsset);

    (, , vars.liquidationBonus, vars.collateralDecimals, ) = collateralReserve
      .configuration
      .getParams();
    vars.debtAssetDecimals = debtReserve.configuration.getDecimals();

    unchecked {
      vars.collateralAssetUnit = 10**vars.collateralDecimals;
      vars.debtAssetUnit = 10**vars.debtAssetDecimals;
    }

    // This is the maximum possible amount of the selected collateral that can be liquidated, given the
    // max amount of liquidatable debt
    vars.maxAmountCollateralToLiquidate = vars
      .debtAssetPrice
      .mul(debtToCover)
      .mul(vars.collateralAssetUnit)
      .percentMul(vars.liquidationBonus)
      .div(vars.collateralPrice.mul(vars.debtAssetUnit));
      // .div(vars.collateralPrice.mul(10**vars.debtAssetDecimals));

    if (vars.maxAmountCollateralToLiquidate > userCollateralBalance) {
      collateralAmount = userCollateralBalance;
      debtAmountNeeded = vars
        .collateralPrice
        .mul(collateralAmount)
        .mul(10**vars.debtAssetDecimals)
        .div(vars.debtAssetPrice.mul(vars.collateralAssetUnit))
        .percentDiv(vars.liquidationBonus);
    } else {
      collateralAmount = vars.maxAmountCollateralToLiquidate;
      debtAmountNeeded = debtToCover;
    }
    return (collateralAmount, debtAmountNeeded);
  }
}
