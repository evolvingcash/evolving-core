// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

import './interfaces/IBank.sol';
import './interfaces/IEToken.sol';
import './interfaces/IVariableDebtToken.sol';
import './interfaces/IBankKeeper.sol';
import './interfaces/IBankHelper.sol';

import './libraries/configuration/ReserveConfiguration.sol';

/**
 * @title BankHelper contract
 * @dev helper create bank list asset and upgrade bank/etoken/dtoken/etc
 * @author Evolving
 **/
contract BankHelper is IBankHelper {
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  /**
   * @dev Initializes reserves in batch
   **/
  function batchInitReserve(IBankKeeper pool, InitReserveInput[] calldata input) external { // onlyPoolAdmin {
    for (uint256 i = 0; i < input.length; i++) {
      _initReserve(pool, input[i]);
    }
  }

  function _initReserve(IBankKeeper pool, InitReserveInput calldata input) internal {
    address eTokenProxyAddress =
      _initTokenWithProxy(
        input.eTokenImpl,
        abi.encodeWithSelector(
          IInitializableEToken.initialize.selector,
          pool,
          input.treasury,
          input.underlyingAsset,
          IAaveIncentivesController(input.incentivesController),
          input.underlyingAssetDecimals,
          input.eTokenName,
          input.eTokenSymbol,
          input.params
        )
      );

    address variableDebtTokenProxyAddress =
      _initTokenWithProxy(
        input.variableDebtTokenImpl,
        abi.encodeWithSelector(
          IInitializableDebtToken.initialize.selector,
          pool,
          input.underlyingAsset,
          IAaveIncentivesController(input.incentivesController),
          input.underlyingAssetDecimals,
          input.variableDebtTokenName,
          input.variableDebtTokenSymbol,
          input.params
        )
      );

    pool.initReserve(
      input.underlyingAsset,
      eTokenProxyAddress,
      variableDebtTokenProxyAddress,
      input.interestRateStrategyAddress
    );

    DataTypes.ReserveConfigurationMap memory currentConfig =
      pool.getConfiguration(input.underlyingAsset);

    currentConfig.setDecimals(input.underlyingAssetDecimals);

    currentConfig.setActive(true);
    currentConfig.setFrozen(false);

    pool.setConfiguration(input.underlyingAsset, currentConfig.data);

    emit ReserveInitialized(
      input.underlyingAsset,
      eTokenProxyAddress,
      variableDebtTokenProxyAddress,
      input.interestRateStrategyAddress
    );
  }

  /**
   * @dev Updates the eToken implementation for the reserve
   **/
  function updateEToken(IBankKeeper pool, UpdateETokenInput calldata input) external { // onlyPoolAdmin {
    DataTypes.ReserveData memory reserveData = pool.getReserveData(input.asset);

    (, , , uint256 decimals, ) = pool.getConfiguration().getParamsMemory();

    bytes memory encodedCall = abi.encodeWithSelector(
        IInitializableEToken.initialize.selector,
        address(this),
        input.treasury,
        input.asset,
        input.incentivesController,
        decimals,
        input.name,
        input.symbol,
        input.params
      );

    _upgradeTokenImplementation(
      reserveData.eTokenAddress,
      input.implementation,
      encodedCall
    );

    emit ETokenUpgraded(input.asset, reserveData.eTokenAddress, input.implementation);
  }

  function _initTokenWithProxy(address implementation, bytes memory initParams)
    internal
    returns (address)
  {
    TransparentUpgradeableProxy proxy =
      new TransparentUpgradeableProxy(implementation, address(this), initParams);

    return address(proxy);
  }

  function _upgradeTokenImplementation(
    address proxyAddress,
    address implementation,
    bytes memory initParams
  ) internal {
    TransparentUpgradeableProxy proxy =
      TransparentUpgradeableProxy(payable(proxyAddress));

    proxy.upgradeToAndCall(implementation, initParams);
  }
}