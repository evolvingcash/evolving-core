// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;


import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
// Prettier ignore to prevent buidler flatter bug
// prettier-ignore
// import '../libraries/aave-upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol';

import './interfaces/IMarket.sol';

/**
 * @title Market contract
 * @dev Main registry of addresses part of or connected to the protocol, including permissioned roles
 * - Acting also as factory of proxies and admin of those, so with right to change its implementations
 * - Owned by the Aave Governance
 * @author Aave
 **/
contract Market is Ownable, IMarket {
  mapping(bytes32 => address) private _addresses;

  bytes32 private constant LENDING_POOL = 'LENDING_POOL';
  bytes32 private constant LENDING_POOL_CONFIGURATOR = 'LENDING_POOL_CONFIGURATOR';
  bytes32 private constant POOL_ADMIN = 'POOL_ADMIN';
  bytes32 private constant EMERGENCY_ADMIN = 'EMERGENCY_ADMIN';
  bytes32 private constant LENDING_POOL_COLLATERAL_MANAGER = 'COLLATERAL_MANAGER';
  bytes32 private constant PRICE_ORACLE = 'PRICE_ORACLE';
  bytes32 private constant LENDING_RATE_ORACLE = 'LENDING_RATE_ORACLE';

  constructor() public {
  }

  /**
   * @dev General function to update the implementation of a proxy registered with
   * certain `id`. If there is no proxy registered, it will instantiate one and
   * set as implementation the `implementationAddress`
   * IMPORTANT Use this function carefully, only for ids that don't have an explicit
   * setter function, in order to avoid unexpected consequences
   * @param id The id
   * @param implementationAddress The address of the new implementation
   */
  function setAddressAsProxy(bytes32 id, address implementationAddress)
    external
    override
    onlyOwner
  {
    _updateImpl(id, implementationAddress);
    emit AddressSet(id, implementationAddress, true);
  }

  /**
   * @dev Sets an address for an id replacing the address saved in the addresses map
   * IMPORTANT Use this function carefully, as it will do a hard replacement
   * @param id The id
   * @param newAddress The address to set
   */
  function setAddress(bytes32 id, address newAddress) external override onlyOwner {
    _addresses[id] = newAddress;
    emit AddressSet(id, newAddress, false);
  }

  /**
   * @dev Returns an address by id
   * @return The address
   */
  function getAddress(bytes32 id) public view override returns (address) {
    return _addresses[id];
  }

  /**
   * @dev Returns the address of the Pool proxy
   * @return The Pool proxy address
   **/
  function getPool() external view override returns (address) {
    return getAddress(LENDING_POOL);
  }

  /**
   * @dev Updates the implementation of the Pool, or creates the proxy
   * setting the new `pool` implementation on the first time calling it
   * @param pool The new Pool implementation
   **/
  function setPoolImpl(address pool) external override onlyOwner {
    _updateImpl(LENDING_POOL, pool);
    emit PoolUpdated(pool);
  }

  /**
   * @dev Returns the address of the PoolConfigurator proxy
   * @return The PoolConfigurator proxy address
   **/
  function getPoolConfigurator() external view override returns (address) {
    return getAddress(LENDING_POOL_CONFIGURATOR);
  }

  /**
   * @dev Updates the implementation of the PoolConfigurator, or creates the proxy
   * setting the new `configurator` implementation on the first time calling it
   * @param configurator The new PoolConfigurator implementation
   **/
  function setPoolConfiguratorImpl(address configurator) external override onlyOwner {
    _updateImpl(LENDING_POOL_CONFIGURATOR, configurator);
    emit PoolConfiguratorUpdated(configurator);
  }

  /**
   * @dev Returns the address of the PoolCollateralManager. Since the manager is used
   * through delegateCall within the Pool contract, the proxy contract pattern does not work properly hence
   * the addresses are changed directly
   * @return The address of the PoolCollateralManager
   **/

  function getPoolCollateralManager() external view override returns (address) {
    return getAddress(LENDING_POOL_COLLATERAL_MANAGER);
  }

  /**
   * @dev Updates the address of the PoolCollateralManager
   * @param manager The new PoolCollateralManager address
   **/
  function setPoolCollateralManager(address manager) external override onlyOwner {
    _addresses[LENDING_POOL_COLLATERAL_MANAGER] = manager;
    emit PoolCollateralManagerUpdated(manager);
  }

  /**
   * @dev The functions below are getters/setters of addresses that are outside the context
   * of the protocol hence the upgradable proxy pattern is not used
   **/

  function getPoolAdmin() external view override returns (address) {
    return getAddress(POOL_ADMIN);
  }

  function setPoolAdmin(address admin) external override onlyOwner {
    _addresses[POOL_ADMIN] = admin;
    emit ConfigurationAdminUpdated(admin);
  }

  function getEmergencyAdmin() external view override returns (address) {
    return getAddress(EMERGENCY_ADMIN);
  }

  function setEmergencyAdmin(address emergencyAdmin) external override onlyOwner {
    _addresses[EMERGENCY_ADMIN] = emergencyAdmin;
    emit EmergencyAdminUpdated(emergencyAdmin);
  }

  function getPriceOracle() external view override returns (address) {
    return getAddress(PRICE_ORACLE);
  }

  function setPriceOracle(address priceOracle) external override onlyOwner {
    _addresses[PRICE_ORACLE] = priceOracle;
    emit PriceOracleUpdated(priceOracle);
  }

  function getLendingRateOracle() external view override returns (address) {
    return getAddress(LENDING_RATE_ORACLE);
  }

  function setLendingRateOracle(address lendingRateOracle) external override onlyOwner {
    _addresses[LENDING_RATE_ORACLE] = lendingRateOracle;
    emit LendingRateOracleUpdated(lendingRateOracle);
  }

  /**
   * @dev Internal function to update the implementation of a specific proxied component of the protocol
   * - If there is no proxy registered in the given `id`, it creates the proxy setting `newAdress`
   *   as implementation and calls the initialize() function on the proxy
   * - If there is already a proxy registered, it just updates the implementation to `newAddress` and
   *   calls the initialize() function via upgradeToAndCall() in the proxy
   * @param id The id of the proxy to be updated
   * @param newAddress The address of the new implementation
   **/
  function _updateImpl(bytes32 id, address newAddress) internal {
    address payable proxyAddress = payable(_addresses[id]);

    TransparentUpgradeableProxy proxy =
      TransparentUpgradeableProxy(proxyAddress);
    bytes memory params = abi.encodeWithSignature('initialize(address)', address(this));

    if (proxyAddress == address(0)) {
      proxy = new TransparentUpgradeableProxy(newAddress, address(this), params); //new bytes(0));
      // proxy.initialize(newAddress, params);
      _addresses[id] = address(proxy);
      emit ProxyCreated(id, address(proxy));
    } else {
      proxy.upgradeToAndCall(newAddress, params);
    }
  }
}
