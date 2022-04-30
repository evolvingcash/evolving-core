// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';

import './interfaces/IBank.sol';
import './interfaces/IBankKeeper.sol';
import './BankStorage.sol';
/**
 * @title BankKeeper contract
 * @dev Main point of configuration with an Evolving protocol's market
 * @author Evolving
 **/
contract BankKeeper is IBankKeeper, OwnableUpgradeable, BankStorage {
  using PercentageMath for uint256;
  using ReserveLogic for DataTypes.ReserveData;
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  modifier onlyPoolAdmin {
    require(bankAdmin == msg.sender, Errors.CALLER_NOT_POOL_ADMIN);
    _;
  }

  modifier onlyEmergencyAdmin {
    require(
      emergencyAdmin == msg.sender,
      Errors.LPC_CALLER_NOT_EMERGENCY_ADMIN
    );
    _;
  }

  /**
   * @dev Initializes a reserve, activating it, assigning an eToken and debt tokens and an
   * interest rate strategy
   * - Only callable by the LendingPoolConfigurator contract
   * @param asset The address of the underlying asset of the reserve
   * @param eTokenAddress The address of the eToken that will be assigned to the reserve
   * @param eTokenAddress The address of the VariableDebtToken that will be assigned to the reserve
   * @param interestRateStrategyAddress The address of the interest rate strategy contract
   **/
  function initReserve(
    address asset,
    address eTokenAddress,
    address variableDebtAddress,
    address interestRateStrategyAddress
  ) external override onlyOwner {
    require(Address.isContract(asset), Errors.LP_NOT_CONTRACT);
    _reserves[asset].init(
      eTokenAddress,
      variableDebtAddress,
      interestRateStrategyAddress
    );
    _addReserveToList(asset);
  }

  /**
   * @dev Updates the address of the interest rate strategy contract
   * - Only callable by the LendingPoolConfigurator contract
   * @param asset The address of the underlying asset of the reserve
   * @param rateStrategyAddress The address of the interest rate strategy contract
   **/
  function setReserveInterestRateStrategyAddress(address asset, address rateStrategyAddress)
    external
    override
    onlyOwner
  {
    _reserves[asset].interestRateStrategyAddress = rateStrategyAddress;
  }

  /**
   * @dev Returns the configuration of the reserve
   * @param asset The address of the underlying asset of the reserve
   * @return The configuration of the reserve
   **/
  function getConfiguration(address asset)
    public
    view
    override
    returns (DataTypes.ReserveConfigurationMap memory)
  {
    return _reserves[asset].configuration;
  }

  /**
   * @dev Sets the configuration bitmap of the reserve as a whole
   * - Only callable by the LendingPoolConfigurator contract
   * @param asset The address of the underlying asset of the reserve
   * @param configuration The new configuration bitmap
   **/
  function setConfiguration(address asset, uint256 configuration)
    public
    override
    onlyOwner
  {
    _reserves[asset].configuration.data = configuration;
  }

  /**
   * @dev Returns if the Bank is paused
   */
  function paused() external view override returns (bool) {
      return _paused;
  }

  /**
   * @dev Set the _pause state of a reserve
   * - Only callable by the admin
   * @param val `true` to pause the reserve, `false` to un-pause it
   */
  function setPause(bool val) external override onlyOwner {
    _paused = val;
    if (_paused) {
      emit Paused();
    } else {
      emit Unpaused();
    }
  }

  function _addReserveToList(address asset) internal {
    uint256 reservesCount = _reservesCount;

    require(reservesCount < _maxNumberOfReserves, Errors.LP_NO_MORE_RESERVES_ALLOWED);

    bool reserveAlreadyAdded = _reserves[asset].id != 0 || _reservesList[0] == asset;

    if (!reserveAlreadyAdded) {
      _reserves[asset].id = uint8(reservesCount);
      _reservesList[reservesCount] = asset;

      _reservesCount = reservesCount + 1;
    }
  }

  /**
   * @dev Initializes reserves in batch
   **/
  function batchInitReserve(InitReserveInput[] calldata input) external onlyPoolAdmin {
    for (uint256 i = 0; i < input.length; i++) {
      _initReserve(input[i]);
    }
  }

  function _initReserve(InitReserveInput calldata input) internal {
    IBankKeeper pool = IBankKeeper(address(this));

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
  function updateEToken(UpdateETokenInput calldata input) external onlyPoolAdmin {
    DataTypes.ReserveData memory reserveData = _reserves[input.asset];

    (, , , uint256 decimals, ) = _reserves[input.asset].configuration.getParamsMemory();

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

  /**
   * @dev Enables borrowing on a reserve
   * @param asset The address of the underlying asset of the reserve
   **/
  function enableBorrowingOnReserve(address asset)
    external
    onlyPoolAdmin
  {
    DataTypes.ReserveConfigurationMap memory currentConfig = getConfiguration(asset);

    currentConfig.setBorrowingEnabled(true);

    setConfiguration(asset, currentConfig.data);

    emit BorrowingEnabledOnReserve(asset);
  }

  /**
   * @dev Disables borrowing on a reserve
   * @param asset The address of the underlying asset of the reserve
   **/
  function disableBorrowingOnReserve(address asset) external onlyPoolAdmin {
    DataTypes.ReserveConfigurationMap memory currentConfig = getConfiguration(asset);

    currentConfig.setBorrowingEnabled(false);

    setConfiguration(asset, currentConfig.data);
    emit BorrowingDisabledOnReserve(asset);
  }

  /**
   * @dev Configures the reserve collateralization parameters
   * all the values are expressed in percentages with two decimals of precision. A valid value is 10000, which means 100.00%
   * @param asset The address of the underlying asset of the reserve
   * @param ltv The loan to value of the asset when used as collateral
   * @param liquidationThreshold The threshold at which loans using this asset as collateral will be considered undercollateralized
   * @param liquidationBonus The bonus liquidators receive to liquidate this asset. The values is always above 100%. A value of 105%
   * means the liquidator will receive a 5% bonus
   **/
  function configureReserveAsCollateral(
    address asset,
    uint256 ltv,
    uint256 liquidationThreshold,
    uint256 liquidationBonus
  ) external onlyPoolAdmin {
    DataTypes.ReserveConfigurationMap memory currentConfig = getConfiguration(asset);

    //validation of the parameters: the LTV can
    //only be lower or equal than the liquidation threshold
    //(otherwise a loan against the asset would cause instantaneous liquidation)
    require(ltv <= liquidationThreshold, Errors.LPC_INVALID_CONFIGURATION);

    if (liquidationThreshold != 0) {
      //liquidation bonus must be bigger than 100.00%, otherwise the liquidator would receive less
      //collateral than needed to cover the debt
      require(
        liquidationBonus > PercentageMath.PERCENTAGE_FACTOR,
        Errors.LPC_INVALID_CONFIGURATION
      );

      //if threshold * bonus is less than PERCENTAGE_FACTOR, it's guaranteed that at the moment
      //a loan is taken there is enough collateral available to cover the liquidation bonus
      require(
        liquidationThreshold.percentMul(liquidationBonus) <= PercentageMath.PERCENTAGE_FACTOR,
        Errors.LPC_INVALID_CONFIGURATION
      );
    } else {
      require(liquidationBonus == 0, Errors.LPC_INVALID_CONFIGURATION);
      //if the liquidation threshold is being set to 0,
      // the reserve is being disabled as collateral. To do so,
      //we need to ensure no liquidity is deposited
      _checkNoLiquidity(asset);
    }

    currentConfig.setLtv(ltv);
    currentConfig.setLiquidationThreshold(liquidationThreshold);
    currentConfig.setLiquidationBonus(liquidationBonus);

    setConfiguration(asset, currentConfig.data);

    emit CollateralConfigurationChanged(asset, ltv, liquidationThreshold, liquidationBonus);
  }

  /**
   * @dev Activates a reserve
   * @param asset The address of the underlying asset of the reserve
   **/
  function activateReserve(address asset) external onlyPoolAdmin {
    DataTypes.ReserveConfigurationMap memory currentConfig = getConfiguration(asset);

    currentConfig.setActive(true);

    setConfiguration(asset, currentConfig.data);

    emit ReserveActivated(asset);
  }

  /**
   * @dev Deactivates a reserve
   * @param asset The address of the underlying asset of the reserve
   **/
  function deactivateReserve(address asset) external onlyPoolAdmin {
    _checkNoLiquidity(asset);

    DataTypes.ReserveConfigurationMap memory currentConfig = getConfiguration(asset);

    currentConfig.setActive(false);

    setConfiguration(asset, currentConfig.data);

    emit ReserveDeactivated(asset);
  }

  /**
   * @dev Freezes a reserve. A frozen reserve doesn't allow any new deposit, borrow or rate swap
   *  but allows repayments, liquidations, rate rebalances and withdrawals
   * @param asset The address of the underlying asset of the reserve
   **/
  function freezeReserve(address asset) external onlyPoolAdmin {
    DataTypes.ReserveConfigurationMap memory currentConfig = getConfiguration(asset);

    currentConfig.setFrozen(true);

    setConfiguration(asset, currentConfig.data);

    emit ReserveFrozen(asset);
  }

  /**
   * @dev Unfreezes a reserve
   * @param asset The address of the underlying asset of the reserve
   **/
  function unfreezeReserve(address asset) external onlyPoolAdmin {
    DataTypes.ReserveConfigurationMap memory currentConfig = getConfiguration(asset);

    currentConfig.setFrozen(false);

    setConfiguration(asset, currentConfig.data);

    emit ReserveUnfrozen(asset);
  }

  /**
   * @dev Updates the reserve factor of a reserve
   * @param asset The address of the underlying asset of the reserve
   * @param reserveFactor The new reserve factor of the reserve
   **/
  function setReserveFactor(address asset, uint256 reserveFactor) external onlyPoolAdmin {
    DataTypes.ReserveConfigurationMap memory currentConfig = getConfiguration(asset);

    currentConfig.setReserveFactor(reserveFactor);

    setConfiguration(asset, currentConfig.data);

    emit ReserveFactorChanged(asset, reserveFactor);
  }

  function _checkNoLiquidity(address asset) internal view {
    DataTypes.ReserveData memory reserveData = _reserves[asset];

    uint256 availableLiquidity = IERC20(asset).balanceOf(reserveData.eTokenAddress);

    require(
      availableLiquidity == 0 && reserveData.currentLiquidityRate == 0,
      Errors.LPC_RESERVE_LIQUIDITY_NOT_0
    );
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
