// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IWETH} from "../src/interfaces/IWETH.sol";
import {IWormhole} from "../src/interfaces/IWormhole.sol";
import {ITokenBridge} from "../src/interfaces/ITokenBridge.sol";
import {ITokenBridgeRelayer} from "../src/interfaces/ITokenBridgeRelayer.sol";

import {ForgeHelpers} from "wormhole-solidity/ForgeHelpers.sol";
import {Helpers} from "./Helpers.sol";

import {TokenBridgeRelayerSetup} from "../src/token-bridge-relayer/TokenBridgeRelayerSetup.sol";
import {TokenBridgeRelayerProxy} from "../src/token-bridge-relayer/TokenBridgeRelayerProxy.sol";
import {TokenBridgeRelayerImplementation} from "../src/token-bridge-relayer/TokenBridgeRelayerImplementation.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/libraries/BytesLib.sol";

/**
 * @title A Test Suite for the EVM Token Bridge avaxRelayer Messages module
 */
contract TestTokenBridgeRelayerGovernance is Helpers, ForgeHelpers, Test {
    using BytesLib for bytes;

    // contract instances
    IWormhole wormhole;
    ITokenBridgeRelayer avaxRelayer;

    // random wallet for pranks
    address wallet = vm.envAddress("TESTING_AVAX_RELAYER");

    // tokens
    address wavax = vm.envAddress("TESTING_WRAPPED_AVAX_ADDRESS");
    address ethUsdc = vm.envAddress("TESTING_ETH_USDC_ADDRESS");

    function setupTokenBridgeRelayer() internal {
        // deploy Setup
        TokenBridgeRelayerSetup setup = new TokenBridgeRelayerSetup();

        // deploy Implementation
        TokenBridgeRelayerImplementation implementation =
            new TokenBridgeRelayerImplementation();

        // cache avax chain ID
        uint16 avaxChainId = 6;

        // wormhole address
        address wormholeAddress = vm.envAddress("TESTING_AVAX_WORMHOLE_ADDRESS");

        // deploy Proxy
        TokenBridgeRelayerProxy proxy = new TokenBridgeRelayerProxy(
            address(setup),
            abi.encodeWithSelector(
                bytes4(
                    keccak256("setup(address,uint16,address,address,uint256)")
                ),
                address(implementation),
                avaxChainId,
                wormholeAddress,
                vm.envAddress("TESTING_AVAX_BRIDGE_ADDRESS"),
                1e8 // initial swap rate precision
            )
        );
        avaxRelayer = ITokenBridgeRelayer(address(proxy));

        // verify initial state
        assertEq(avaxRelayer.isInitialized(address(implementation)), true);
        assertEq(avaxRelayer.chainId(), avaxChainId);
        assertEq(address(avaxRelayer.wormhole()), wormholeAddress);
        assertEq(
            address(avaxRelayer.tokenBridge()),
            vm.envAddress("TESTING_AVAX_BRIDGE_ADDRESS")
        );
        assertEq(avaxRelayer.nativeSwapRatePrecision(), 1e8);
    }

    /**
     * @notice sets up the Token Bridge avaxRelayer contract before each test
     */
    function setUp() public {
        setupTokenBridgeRelayer();
    }

    /**
     * @notice This test confirms that the owner can correctly upgrade the
     * contract implementation.
     */
    function testUpgrade() public {
        // hashed slot of implementation
        bytes32 implementationSlot =
            0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

        // grap current implementation
        bytes32 implementationBefore = vm.load(
            address(avaxRelayer),
            implementationSlot
        );

         // deploy implementation and upgrade the contract
        TokenBridgeRelayerImplementation implementation =
            new TokenBridgeRelayerImplementation();

        // upgrade the contract and fetch the new implementation slot
        avaxRelayer.upgrade(avaxRelayer.chainId(), address(implementation));
        bytes32 implementationAfter = vm.load(
            address(avaxRelayer),
            implementationSlot
        );

        // confrim state changes
        assertEq(implementationAfter != implementationBefore, true);
        assertEq(
            implementationAfter == addressToBytes32(address(implementation)),
            true
        );

        // confirm the new implementation is initialized
        assertEq(avaxRelayer.isInitialized(address(implementation)), true);
    }

    /**
     * @notice This test confirms that the owner cannot upgrade the
     * contract implementation to the wrong chain.
     */
    function testUpgradeWrongChain() public {
        uint16 wrongChainId_ = 69;

        // deploy implementation and upgrade the contract
        TokenBridgeRelayerImplementation implementation =
            new TokenBridgeRelayerImplementation();

        // expect the upgrade call to fail
        vm.expectRevert("wrong chain");
        avaxRelayer.upgrade(wrongChainId_, address(implementation));
    }

    /**
     * @notice This test confirms that ONLY the owner can upgrade the contract.
     */
    function testUpgradeOnlyOwner() public {
        // deploy implementation and upgrade the contract
        TokenBridgeRelayerImplementation implementation =
            new TokenBridgeRelayerImplementation();

        // prank the caller address to something different than the owner's
        vm.startPrank(wallet);

        // expect the upgrade call to fail
        bytes memory encodedSignature = abi.encodeWithSignature(
            "upgrade(uint16,address)",
            avaxRelayer.chainId(),
            address(implementation)
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "caller not the owner"
        );

        vm.stopPrank();
    }

    /**
     * @notice This test confirms that the owner cannot update the
     * implementation to the zero address.
     */
    function testUpgradeOnlyInvalidImplementation() public {
        // deploy implementation and upgrade the contract
        address implementation = address(0);

        // expect the upgrade call to fail
        bytes memory encodedSignature = abi.encodeWithSignature(
            "upgrade(uint16,address)",
            avaxRelayer.chainId(),
            implementation
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "invalid implementation"
        );
    }

    /**
     * @notice This test confirms that the owner can submit a request to
     * transfer ownership of the contract.
     */
    function testSubmitOwnershipTransferRequest(address newOwner) public {
        vm.assume(newOwner != address(0));

        // call submitOwnershipTransferRequest
        avaxRelayer.submitOwnershipTransferRequest(
            avaxRelayer.chainId(),
            newOwner
        );

        // confirm state changes
        assertEq(avaxRelayer.pendingOwner(), newOwner);
    }

    /**
     * @notice This test confirms that the owner cannot submit a request to
     * transfer ownership of the contract on the wrong chain.
     */
    function testSubmitOwnershipTransferRequestWrongChain(uint16 chainId_) public {
        vm.assume(chainId_ != avaxRelayer.chainId());

        // expect the submitOwnershipTransferRequest call to revert
        vm.expectRevert("wrong chain");
        avaxRelayer.submitOwnershipTransferRequest(chainId_, address(this));
    }

    /**
     * @notice This test confirms that the owner cannot submit a request to
     * transfer ownership of the contract to address(0).
     */
    function testSubmitOwnershipTransferRequestZeroAddress() public {
        address zeroAddress = address(0);

        // expect the submitOwnershipTransferRequest call to revert
        bytes memory encodedSignature = abi.encodeWithSignature(
            "submitOwnershipTransferRequest(uint16,address)",
            avaxRelayer.chainId(),
            zeroAddress
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "newOwner cannot equal address(0)"
        );
    }

    /**
     * @notice This test confirms that ONLY the owner can submit a request
     * to transfer ownership of the contract.
     */
    function testSubmitOwnershipTransferRequestOwnerOnly() public {
        address newOwner = address(this);

        // prank the caller address to something different than the owner's
        vm.startPrank(wallet);

        // expect the submitOwnershipTransferRequest call to revert
        bytes memory encodedSignature = abi.encodeWithSignature(
            "submitOwnershipTransferRequest(uint16,address)",
            avaxRelayer.chainId(),
            newOwner
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "caller not the owner"
        );

        vm.stopPrank();
    }

    /**
     * This test confirms that the pending owner can confirm an ownership
     * transfer request from their wallet.
     */
    function testConfirmOwnershipTransferRequest(address newOwner) public {
        vm.assume(newOwner != address(0));

        // verify pendingOwner and owner state variables
        assertEq(avaxRelayer.pendingOwner(), address(0));
        assertEq(avaxRelayer.owner(), address(this));

        // submit ownership transfer request
        avaxRelayer.submitOwnershipTransferRequest(
            avaxRelayer.chainId(),
            newOwner
        );

        // verify the pendingOwner state variable
        assertEq(avaxRelayer.pendingOwner(), newOwner);

        // Invoke the confirmOwnershipTransferRequest method from the
        // new owner's wallet.
        vm.prank(newOwner);
        avaxRelayer.confirmOwnershipTransferRequest();

        // Verify the ownership change, and that the pendingOwner
        // state variable has been set to address(0).
        assertEq(avaxRelayer.owner(), newOwner);
        assertEq(avaxRelayer.pendingOwner(), address(0));
    }

    /**
     * @notice This test confirms that only the pending owner can confirm an
     * ownership transfer request.
     */

     function testConfirmOwnershipTransferRequestNotPendingOwner(
        address pendingOwner
    ) public {
        vm.assume(
            pendingOwner != address(0) &&
            pendingOwner != address(this)
        );

        // set the pending owner and confirm the pending owner state variable
        avaxRelayer.submitOwnershipTransferRequest(
            avaxRelayer.chainId(),
            pendingOwner
        );
        assertEq(avaxRelayer.pendingOwner(), pendingOwner);

        // Attempt to confirm the ownership transfer request from a wallet that is
        // not the pending owner's.
        vm.startPrank(address(this));
        vm.expectRevert("caller must be pendingOwner");
        avaxRelayer.confirmOwnershipTransferRequest();

        vm.stopPrank();
    }

    /**
     * @notice This test confirms that the owner can correctly register a foreign
     * TokenBridgeRelayer contract.
     */
    function testRegisterContract(
        uint16 chainId_,
        bytes32 tokenBridgeRelayerContract
    ) public {
        vm.assume(tokenBridgeRelayerContract != bytes32(0));
        vm.assume(chainId_ != 0 && chainId_ != avaxRelayer.chainId());

        // register the contract
        avaxRelayer.registerContract(chainId_, tokenBridgeRelayerContract);

        // verify that the state was updated correctly
        bytes32 registeredContract = avaxRelayer.getRegisteredContract(
            chainId_
        );
        assertEq(registeredContract, tokenBridgeRelayerContract);
    }

    /// @notice This test confirms that the owner cannot register address(0).
    function testRegisterContractZeroAddress() public {
        uint16 chainId_ = 42;
        bytes32 zeroAddress = addressToBytes32(address(0));

        // expect the registerContract call to revert
        vm.expectRevert("contractAddress cannot equal bytes32(0)");
        avaxRelayer.registerContract(chainId_, zeroAddress);
    }

    /**
     * @notice This test confirms that the owner cannot register a foreign
     * TokenBridgeRelayer contract with the same chainId.
     */
    function testRegisterContractThisChainId() public {
        bytes32 tokenBridgeRelayerContract = addressToBytes32(address(this));

        // expect the registerContract call to fail
        bytes memory encodedSignature = abi.encodeWithSignature(
            "registerContract(uint16,bytes32)",
            avaxRelayer.chainId(),
            tokenBridgeRelayerContract
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "chainId_ cannot equal 0 or this chainId"
        );
    }

    /**
     * @notice This test confirms that the owner cannot register a foreign
     * TokenBridgeRelayer contract with a chainId of zero.
     */
    function testRegisterContractChainIdZero() public {
        uint16 chainId_ = 0;
        bytes32 tokenBridgeRelayerContract = addressToBytes32(address(this));

        // expect the registerContract call to revert
        vm.expectRevert("chainId_ cannot equal 0 or this chainId");
        avaxRelayer.registerContract(chainId_, tokenBridgeRelayerContract);
    }

    /**
     * @notice This test confirms that ONLY the owner can register a foreign
     * TokenBridgeRelayer contract.
     */
    function testRegisterContractOwnerOnly() public {
        uint16 chainId_ = 42;
        bytes32 tokenBridgeRelayerContract = addressToBytes32(address(this));

        // prank the caller address to something different than the owner's
        vm.startPrank(wallet);

        // expect the registerContract call to revert
        vm.expectRevert("caller not the owner");
        avaxRelayer.registerContract(chainId_, tokenBridgeRelayerContract);

        vm.stopPrank();
    }

    /**
     * @notice This test confirms that the owner can correctly register a token.
     */
    function testRegisterToken() public {
        // test variables
        address token = wavax;

        assertEq(avaxRelayer.isAcceptedToken(token), false);

        // register the contract
        avaxRelayer.registerToken(avaxRelayer.chainId(), token);

        // verify that the state was updated correctly
        assertEq(avaxRelayer.isAcceptedToken(token), true);
    }

    /// @notice This test confirms that the contract cannot register address(0).
    function testRegisterTokenZeroAddress() public {
        // test variables
        address token = address(0);

        // expect the registerToken call to fail
        bytes memory encodedSignature = abi.encodeWithSignature(
            "registerToken(uint16,address)",
            avaxRelayer.chainId(),
            token
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "invalid token"
        );
    }

    /**
     * @notice This test confirms that the owner cannot register a token
     * with the same chainId.
     */
    function testRegisterContractWrongChainId(uint16 chainId_) public {
        vm.assume(chainId_ != avaxRelayer.chainId());

        // test variables
        address token = address(0);

        // expect the registerToken call to fail
        bytes memory encodedSignature = abi.encodeWithSignature(
            "registerToken(uint16,address)",
            chainId_,
            token
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "wrong chain"
        );
    }

    /**
     * @notice This test confirms that the owner cannot register the same
     * token twice.
     */
    function testRegisterTokenAlreadyRegistered() public {
        // test variables
        address token = wavax;

        assertEq(avaxRelayer.isAcceptedToken(token), false);

        // register the contract
        avaxRelayer.registerToken(avaxRelayer.chainId(), token);

        // verify that the state was updated correctly
        assertEq(avaxRelayer.isAcceptedToken(token), true);

        // expect the registerToken call to fail
        bytes memory encodedSignature = abi.encodeWithSignature(
            "registerToken(uint16,address)",
            avaxRelayer.chainId(),
            token
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "token already registered"
        );
    }

    ///@notice This test confirms that ONLY the owner can register a token.
    function testRegisterTokenOwnerOnly() public {
        // test variables
        address token = wavax;

        // prank the caller address to something different than the owner's
        vm.startPrank(wallet);

        // expect the registerToken call to fail
        bytes memory encodedSignature = abi.encodeWithSignature(
            "registerToken(uint16,address)",
            avaxRelayer.chainId(),
            token
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "caller not the owner"
        );

        vm.stopPrank();
    }

    /**
     * @notice This test confirms that the owner can update the relayer fee
     * for any registered relayer contract.
     */
    function testUpdateRelayerFee(uint16 chainId_, uint256 relayerFee) public {
        address token = address(avaxRelayer.WETH());

        // make some assumptions about the fuzz test values
        vm.assume(chainId_ != 0 && chainId_ != avaxRelayer.chainId());
        vm.assume(
            relayerFee == 0 ||
            normalizeAmount(relayerFee, getDecimals(token)) > 0
        );

        // register random target contract
        avaxRelayer.registerContract(chainId_, addressToBytes32(address(this)));

        // register the token
        avaxRelayer.registerToken(avaxRelayer.chainId(), token);

        // update the relayer fee
        avaxRelayer.updateRelayerFee(
            chainId_,
            token,
            relayerFee
        );

        // confirm state changes
        assertEq(avaxRelayer.relayerFee(chainId_, token), relayerFee);
    }

    /**
     * @notice This test confirms that the relayer contract reverts when the
     * owner attemps to update the relayer fee to a normalized value of zero.
     */
    function testUpdateRelayerFeeZeroNormalizedFee(
        uint16 chainId_,
        uint256 relayerFee
    ) public {
        address token = address(avaxRelayer.WETH());

        // make some assumptions about the fuzz test values
        vm.assume(chainId_ != 0 && chainId_ != avaxRelayer.chainId());
        vm.assume(
            relayerFee > 0 &&
            normalizeAmount(relayerFee, getDecimals(token)) == 0
        );

        // register random target contract
        avaxRelayer.registerContract(chainId_, addressToBytes32(address(this)));

        // register the token
        avaxRelayer.registerToken(avaxRelayer.chainId(), token);

        // expect the updateRelayerFee call to revert
        bytes memory encodedSignature = abi.encodeWithSignature(
            "updateRelayerFee(uint16,address,uint256)",
            chainId_,
            token,
            relayerFee
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "invalid relayer fee"
        );
    }

    /**
     * @notice This test confirms that the owner can only update the relayerFee
     * for a registered relayer contract or for its own chainId.
     * @dev Explicitly don't register a target contract.
     */
    function testUpdateRelayerFeeContractNotRegistered(uint16 chainId_) public {
        vm.assume(chainId_ != avaxRelayer.chainId());

        // expect the updateRelayerFee method call to fail
        bytes memory encodedSignature = abi.encodeWithSignature(
            "updateRelayerFee(uint16,address,uint256)",
            chainId_,
            address(avaxRelayer.WETH()),
            1e18
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "contract doesn't exist"
        );
    }

    /**
     * @notice This test confirms that the owner cannot update the relayer
     * fee for an unregistered token.
     */
    function testUpdateRelayerFeeInvalidToken() public {
        address unregisteredToken = address(avaxRelayer.WETH());
        uint256 relayerFee = 1e8;

        // expect the updateRelayerFee method call to fail
        bytes memory encodedSignature = abi.encodeWithSignature(
            "updateRelayerFee(uint16,address,uint256)",
            avaxRelayer.chainId(),
            unregisteredToken,
            relayerFee
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "token not accepted"
        );
    }

    /**
     * @notice This test confirms that ONLY the owner can update the relayer
     * fee for registered relayer contracts.
     */
    function testUpdateRelayerFeeOwnerOnly() public {
        address token = address(avaxRelayer.WETH());
        uint16 chainId_ = 42069;
        uint256 relayerFee = 1e8;

        // register random target contract
        avaxRelayer.registerContract(chainId_, addressToBytes32(address(this)));

        // prank the caller address to something different than the owner's
        vm.startPrank(wallet);

        // expect the updateRelayerFee call to revert
        vm.expectRevert("caller not the owner");
        avaxRelayer.updateRelayerFee(
            chainId_,
            token,
            relayerFee
        );

        vm.stopPrank();
    }

    /**
     * @notice This test confirms that the owner can update the native swap
     * rate for accepted tokens.
     */
    function testUpdateNativeSwapRate(uint256 swapRate) public {
        vm.assume(swapRate > 0);

        // cache token address
        address token = address(avaxRelayer.WETH());

        // register the token
        avaxRelayer.registerToken(avaxRelayer.chainId(), token);

        // update the native to WETH swap rate
        avaxRelayer.updateNativeSwapRate(
            avaxRelayer.chainId(),
            token,
            swapRate
        );

        // confirm state changes
        assertEq(avaxRelayer.nativeSwapRate(token), swapRate);
    }

    /**
     * @notice This test confirms that the owner cannot update the native
     * swap rate to zero.
     */
    function testUpdateNativeSwapRateZeroRate() public {
        // cache token address
        address token = address(avaxRelayer.WETH());
        uint256 swapRate = 0;

        // register the token
        avaxRelayer.registerToken(avaxRelayer.chainId(), token);

        // expect the updateNativeSwapRate call to revert
        bytes memory encodedSignature = abi.encodeWithSignature(
            "updateNativeSwapRate(uint16,address,uint256)",
            avaxRelayer.chainId(),
            token,
            swapRate
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "swap rate must be nonzero"
        );
    }

    /**
     * @notice This test confirms that the owner cannot update the native
     * swap rate for an unregistered token.
     */
    function testUpdateNativeSwapRateInvalidToken() public {
        // cache token address
        address token = address(avaxRelayer.WETH());
        uint256 swapRate = 1e10;

        // expect the updateNativeSwapRate call to revert
        bytes memory encodedSignature = abi.encodeWithSignature(
            "updateNativeSwapRate(uint16,address,uint256)",
            avaxRelayer.chainId(),
            token,
            swapRate
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "token not accepted"
        );
    }

    /**
     * @notice This test confirms that ONLY the owner can update the native
     * swap rate.
     */
    function testUpdateNativeSwapRateOwnerOnly() public {
        address token = address(avaxRelayer.WETH());
        uint256 swapRate = 1e10;

        // prank the caller address to something different than the owner's
        vm.startPrank(wallet);

        // expect the updateNativeSwapRate call to revert
        bytes memory encodedSignature = abi.encodeWithSignature(
            "updateNativeSwapRate(uint16,address,uint256)",
            avaxRelayer.chainId(),
            token,
            swapRate
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "caller not the owner"
        );

        vm.stopPrank();
    }

    /**
     * @notice This test confirms that the owner cannot update the native
     * swap rate for the wrong chain.
     */
    function testUpdateNativeSwapRateWrongChain(uint16 chainId_) public {
        vm.assume(chainId_ != avaxRelayer.chainId());

        address token = address(avaxRelayer.WETH());
        uint256 swapRate = 1e10;

        // expect the updateNativeSwapRate call to revert
        vm.expectRevert("wrong chain");
        avaxRelayer.updateNativeSwapRate(
            chainId_,
            token,
            swapRate
        );
    }

    /**
     * @notice This test confirms that the owner can update the native swap
     * rate precision.
     */
    function testUpdateNativeSwapRatePrecision(
        uint256 nativeSwapRatePrecision_
    ) public {
        vm.assume(nativeSwapRatePrecision_ > 0);

        // update the native swap rate precision
        avaxRelayer.updateNativeSwapRatePrecision(
            avaxRelayer.chainId(),
            nativeSwapRatePrecision_
        );

        // confirm state changes
        assertEq(
            avaxRelayer.nativeSwapRatePrecision(),
            nativeSwapRatePrecision_
        );
    }

    /**
     * @notice This test confirms that the owner cannot update the native swap
     * rate precision to zero.
     */
    function testUpdateNativeSwapRatePrecisionZeroAmount() public {
        uint256 nativeSwapRatePrecision_ = 0;

        // expect the updateNativeSwapRatePrecision to revert
        bytes memory encodedSignature = abi.encodeWithSignature(
            "updateNativeSwapRatePrecision(uint16,uint256)",
            avaxRelayer.chainId(),
            nativeSwapRatePrecision_
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "precision must be > 0"
        );
    }

    /**
     * @notice This test confirms that ONLY the owner can update the native
     * swap rate precision.
     */
    function testUpdateNativeSwapRatePrecisionOwnerOnly() public {
        uint256 nativeSwapRatePrecision_ = 1e10;

        // prank the caller address to something different than the owner's
        vm.startPrank(wallet);

        // expect the updateNativeSwapRatePrecision call to revert
        bytes memory encodedSignature = abi.encodeWithSignature(
            "updateNativeSwapRatePrecision(uint16,uint256)",
            avaxRelayer.chainId(),
            nativeSwapRatePrecision_
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "caller not the owner"
        );

        vm.stopPrank();
    }

    /**
     * @notice This test confirms that owner cannot update the native
     * swap rate precision for the wrong chain.
     */
    function testUpdateNativeSwapRatePrecisionWrongChain(uint16 chainId_) public {
        vm.assume(chainId_ != avaxRelayer.chainId());

        uint256 nativeSwapRatePrecision_ = 1e10;

        // expect the updateNativeSwapRate call to revert
        vm.expectRevert("wrong chain");
        avaxRelayer.updateNativeSwapRatePrecision(
            chainId_,
            nativeSwapRatePrecision_
        );
    }

    /**
     * @notice This test confirms that the owner can update the max native
     * swap amount.
     */
    function testUpdateMaxNativeSwapAmount(uint256 maxAmount) public {
        // cache token address
        address token = address(avaxRelayer.WETH());

        // register the token
        avaxRelayer.registerToken(avaxRelayer.chainId(), token);

        // update the native to WETH swap rate
        avaxRelayer.updateMaxNativeSwapAmount(
            avaxRelayer.chainId(),
            token,
            maxAmount
        );

        // confirm state changes
        assertEq(avaxRelayer.maxNativeSwapAmount(token), maxAmount);
    }

    /**
     * @notice This test confirms that the owner can not update the max
     * native swap amount for unregistered tokens.
     */
    function testUpdateMaxNativeSwapAmountInvalidToken() public {
        // cache token address
        address token = address(avaxRelayer.WETH());
        uint256 maxAmount = 1e10;

        // expect the updateMaxNativeSwapAmount call to revert
        bytes memory encodedSignature = abi.encodeWithSignature(
            "updateMaxNativeSwapAmount(uint16,address,uint256)",
            avaxRelayer.chainId(),
            token,
            maxAmount
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "token not accepted"
        );
    }

    /**
     * @notice This test confirms that ONLY the owner can update the native
     * max swap amount.
     */
    function testUpdateMaxNativeSwapAmountOwnerOnly() public {
        address token = address(avaxRelayer.WETH());
        uint256 maxAmount = 1e10;

        // register the token
        avaxRelayer.registerToken(avaxRelayer.chainId(), token);

        // prank the caller address to something different than the owner's
        vm.startPrank(wallet);

        // expect the updateNativeMaxSwapAmount call to revert
        bytes memory encodedSignature = abi.encodeWithSignature(
            "updateMaxNativeSwapAmount(uint16,address,uint256)",
            avaxRelayer.chainId(),
            token,
            maxAmount
        );
        expectRevert(
            address(avaxRelayer),
            encodedSignature,
            "caller not the owner"
        );

        vm.stopPrank();
    }

    /**
     * @notice This test confirms that the owner cannot update the max swap
     * amount for the wrong chain.
     */
    function testUpdateMaxNativeSwapAmountWrongChain(uint16 chainId_) public {
        vm.assume(chainId_ != avaxRelayer.chainId());

        address token = address(avaxRelayer.WETH());
        uint256 maxAmount = 1e10;

        // expect the updateNativeSwapRate call to revert
        vm.expectRevert("wrong chain");
        avaxRelayer.updateMaxNativeSwapAmount(
            chainId_,
            token,
            maxAmount
        );
    }
}
