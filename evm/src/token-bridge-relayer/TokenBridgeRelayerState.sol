// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import {IWormhole} from "../interfaces/IWormhole.sol";

contract TokenBridgeRelayerStorage {
    struct State {
        // Wormhole chain ID of this contract
        uint16 chainId;

        // address of WETH on this chain
        address wethAddress;

        // owner of this contract
        address owner;

        // intermediate state when transfering contract ownership
        address pendingOwner;

        // address of the Wormhole contract on this chain
        address wormhole;

        // address of the Wormhole TokenBridge contract on this chain
        address tokenBridge;

        // precision of the nativeSwapRates, this value should NEVER be set to zero
        uint256 swapRatePrecision;

        // precision of the relayerFee, this value should NEVER be set to zero
        uint256 relayerFeePrecision;

        // mapping of initialized implementation (logic) contracts
        mapping(address => bool) initializedImplementations;

        // Wormhole chain ID to known relayer contract address mapping
        mapping(uint16 => bytes32) registeredContracts;

        // allowed list of tokens
        mapping(address => bool) acceptedTokens;

        // token swap rate in USD terms
        mapping(address => uint256) swapRates;

        /**
         * Mapping of source token address to maximum native asset swap amount
         * allowed.
         */
        mapping(address => uint256) maxNativeSwapAmount;

        // mapping of chainId to relayerFee in USD
        mapping(uint16 => uint256) relayerFees;

        /// storage gap for additional state variables in future versions
        uint256[50] ______gap;
    }
}

contract TokenBridgeRelayerState {
    TokenBridgeRelayerStorage.State _state;
}

