// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import './IPool.sol';
import './IAaveIncentivesController.sol';

/**
 * @title IInitializableEToken
 * @notice Interface for the initialize function on EToken
 * @author Evolving
 **/
interface IInitializableEToken {
  /**
   * @dev Emitted when an eToken is initialized
   * @param underlyingAsset The address of the underlying asset
   * @param pool The address of the associated lending pool
   * @param treasury The address of the treasury
   * @param incentivesController The address of the incentives controller for this eToken
   * @param eTokenDecimals the decimals of the underlying
   * @param eTokenName the name of the eToken
   * @param eTokenSymbol the symbol of the eToken
   * @param params A set of encoded parameters for additional initialization
   **/
  event Initialized(
    address indexed underlyingAsset,
    address indexed pool,
    address treasury,
    address incentivesController,
    uint8 eTokenDecimals,
    string eTokenName,
    string eTokenSymbol,
    bytes params
  );

  /**
   * @dev Initializes the eToken
   * @param pool The address of the lending pool where this eToken will be used
   * @param treasury The address of the Aave treasury, receiving the fees on this eToken
   * @param underlyingAsset The address of the underlying asset of this eToken (E.g. WETH for aWETH)
   * @param incentivesController The smart contract managing potential incentives distribution
   * @param eTokenDecimals The decimals of the eToken, same as the underlying asset's
   * @param eTokenName The name of the eToken
   * @param eTokenSymbol The symbol of the eToken
   */
  function initialize(
    IPool pool,
    address treasury,
    address underlyingAsset,
    IAaveIncentivesController incentivesController,
    uint8 eTokenDecimals,
    string calldata eTokenName,
    string calldata eTokenSymbol,
    bytes calldata params
  ) external;
}
