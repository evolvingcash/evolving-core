// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '../libraries/types/DataTypes.sol';
import './IBank.sol';
import './IBankKeeper.sol';

interface IBankHelper {
  struct InitReserveInput {
    address eTokenImpl;
    address variableDebtTokenImpl;
    uint8 underlyingAssetDecimals;
    address interestRateStrategyAddress;
    address underlyingAsset;
    address treasury;
    address incentivesController;
    string underlyingAssetName;
    string eTokenName;
    string eTokenSymbol;
    string variableDebtTokenName;
    string variableDebtTokenSymbol;
    bytes params;
  }

  struct UpdateETokenInput {
    address asset;
    address treasury;
    address incentivesController;
    string name;
    string symbol;
    address implementation;
    bytes params;
  }

  struct UpdateDebtTokenInput {
    address asset;
    address incentivesController;
    string name;
    string symbol;
    address implementation;
    bytes params;
  }

  /**
   * @dev Emitted when an eToken implementation is upgraded
   * @param asset The address of the underlying asset of the reserve
   * @param proxy The eToken proxy address
   * @param implementation The new eToken implementation
   **/
  event ETokenUpgraded(
    address indexed asset,
    address indexed proxy,
    address indexed implementation
  );

  /**
   * @dev Emitted when the implementation of a variable debt token is upgraded
   * @param asset The address of the underlying asset of the reserve
   * @param proxy The variable debt token proxy address
   * @param implementation The new eToken implementation
   **/
  event VariableDebtTokenUpgraded(
    address indexed asset,
    address indexed proxy,
    address indexed implementation
  );

  /**
   * @dev Emitted when a reserve is initialized.
   * @param asset The address of the underlying asset of the reserve
   * @param eToken The address of the associated eToken contract
   * @param variableDebtToken The address of the associated variable rate debt token
   * @param interestRateStrategyAddress The address of the interest rate strategy for the reserve
   **/
  event ReserveInitialized(
    address indexed asset,
    address indexed eToken,
    address variableDebtToken,
    address interestRateStrategyAddress
  );

  function batchInitReserve(IBankKeeper pool, InitReserveInput[] calldata input) external;
  function updateEToken(IBank pool, UpdateETokenInput calldata input) external;
  function updateVariableDebtToken(IBank pool, UpdateDebtTokenInput calldata input) external;
}
