// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import './libraries/configuration/UserConfiguration.sol';
import './libraries/configuration/ReserveConfiguration.sol';
import './libraries/logic/ReserveLogic.sol';
import './interfaces/IMarket.sol';
import './libraries/types/DataTypes.sol';

/**
 * @title BankKeeperStorage
 * @author Evolving
 * @notice Contract used as storage of the BankKeeper contract.
 * @dev It defines the storage layout of the BankKeeper contract.
 */
contract BankKeeperStorage {
  // bank admin address
  address internal bankAdmin;
  // emergency admin address
  address internal emergencyAdmin;
  // price oracle address
  address internal _priceOracle;
  // lending rate oracle address
  address internal lendingRateOracle;
}

/**
 * @title BankStorage
 * @author Evolving
 * @notice Contract used as storage of the Bank contract.
 * @dev It defines the storage layout of the Bank contract.
 */
contract BankStorage is BankKeeperStorage {
  using ReserveLogic for DataTypes.ReserveData;
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
  using UserConfiguration for DataTypes.UserConfigurationMap;

  // IMarket internal _market;
  // address internal _priceOracle;

  mapping(address => DataTypes.ReserveData) internal _reserves;
  mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;

  // the list of the available reserves, structured as a mapping for gas savings reasons
  mapping(uint256 => address) internal _reservesList;

  uint256 internal _reservesCount;

  bool internal _paused;

  uint256 internal _flashLoanPremiumTotal;

  uint256 internal _maxNumberOfReserves;
}
