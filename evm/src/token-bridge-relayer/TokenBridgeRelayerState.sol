// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.17;

import {IDeltaswap} from "../interfaces/IDeltaswap.sol";

abstract contract TokenBridgeRelayerStorage {
    struct State {
        // Deltaswap chain ID of this contract
        uint16 chainId;

        // boolean to determine if weth is unwrappable
        bool unwrapWeth;

        // if true, token transfer requests are blocked
        bool paused;

        // address of WETH on this chain
        address wethAddress;

        // owner of this contract
        address owner;

        // address that can update swap rates and relayer fees
        address ownerAssistant;

        // recipient of relayer fees
        address feeRecipient;

        // intermediate state when transfering contract ownership
        address pendingOwner;

        // address of the Deltaswap contract on this chain
        address deltaswap;

        // address of the Deltaswap TokenBridge contract on this chain
        address tokenBridge;

        // precision of the nativeSwapRates, this value should NEVER be set to zero
        uint256 swapRatePrecision;

        // precision of the relayerFee, this value should NEVER be set to zero
        uint256 relayerFeePrecision;

        // Deltaswap chain ID to known relayer contract address mapping
        mapping(uint16 => bytes32) registeredContracts;

        // token swap rate in USD terms
        mapping(address => uint256) swapRates;

        /**
         * Mapping of source token address to maximum native asset swap amount
         * allowed.
         */
        mapping(address => uint256) maxNativeSwapAmount;

        // mapping of chainId to relayerFee in USD
        mapping(uint16 => uint256) relayerFees;

        // accepted token to bool mapping
        mapping(address => bool) acceptedTokens;

        // list of accepted token addresses
        address[] acceptedTokensList;
    }
}

abstract contract TokenBridgeRelayerState {
    TokenBridgeRelayerStorage.State _state;
}

