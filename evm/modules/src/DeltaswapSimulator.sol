// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.17;

import {IDeltaswap} from "../../src/interfaces/IDeltaswap.sol";
import "../../src/libraries/BytesLib.sol";

import "forge-std/Vm.sol";
import "forge-std/console.sol";

/**
 * @title A Deltaswap Phylax Simulator
 * @notice This contract simulates signing Deltaswap messages emitted in a forge test.
 * It overrides the Deltaswap phylax set to allow for signing messages with a single
 * private key on any EVM where Deltaswap core contracts are deployed.
 * @dev This contract is meant to be used when testing against a mainnet fork.
 */
contract DeltaswapSimulator {
    using BytesLib for bytes;

    // Taken from forge-std/Script.sol
    address private constant VM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));
    Vm public constant vm = Vm(VM_ADDRESS);

    // Allow access to Deltaswap
    IDeltaswap public deltaswap;

    // Save the phylax PK to sign messages with
    uint256 private devnetPhylaxPK;

    /**
     * @param deltaswap_ address of the Deltaswap core contract for the mainnet chain being forked
     * @param devnetPhylax private key of the devnet Phylax
     */
    constructor(address deltaswap_, uint256 devnetPhylax) {
        deltaswap = IDeltaswap(deltaswap_);
        devnetPhylaxPK = devnetPhylax;
        overrideToDevnetPhylax(vm.addr(devnetPhylax));
    }

    function overrideToDevnetPhylax(address devnetPhylax) internal {
        {
            bytes32 data = vm.load(address(this), bytes32(uint256(2)));
            require(data == bytes32(0), "incorrect slot");

            // Get slot for Phylax Set at the current index
            uint32 phylaxSetIndex = deltaswap.getCurrentPhylaxSetIndex();
            bytes32 phylaxSetSlot = keccak256(abi.encode(phylaxSetIndex, 2));

            // Overwrite all but first phylax set to zero address. This isn't
            // necessary, but just in case we inadvertently access these slots
            // for any reason.
            uint256 numPhylaxs = uint256(vm.load(address(deltaswap), phylaxSetSlot));
            for (uint256 i = 1; i < numPhylaxs;) {
                vm.store(
                    address(deltaswap), bytes32(uint256(keccak256(abi.encodePacked(phylaxSetSlot))) + i), bytes32(0)
                );
                unchecked {
                    i += 1;
                }
            }

            // Now overwrite the first phylax key with the devnet key specified
            // in the function argument.
            vm.store(
                address(deltaswap),
                bytes32(uint256(keccak256(abi.encodePacked(phylaxSetSlot))) + 0), // just explicit w/ index 0
                bytes32(uint256(uint160(devnetPhylax)))
            );

            // Change the length to 1 phylax
            vm.store(
                address(deltaswap),
                phylaxSetSlot,
                bytes32(uint256(1)) // length == 1
            );

            // Confirm phylax set override
            address[] memory phylaxs = deltaswap.getPhylaxSet(phylaxSetIndex).keys;
            require(phylaxs.length == 1, "phylaxs.length != 1");
            require(phylaxs[0] == devnetPhylax, "incorrect phylax set override");
        }
    }

    function doubleKeccak256(bytes memory body) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(keccak256(body)));
    }

    function parseVMFromLogs(Vm.Log memory log) internal pure returns (IDeltaswap.VM memory vm_) {
        uint256 index = 0;

        // emitterAddress
        vm_.emitterAddress = bytes32(log.topics[1]);

        // sequence
        vm_.sequence = log.data.toUint64(index + 32 - 8);
        index += 32;

        // nonce
        vm_.nonce = log.data.toUint32(index + 32 - 4);
        index += 32;

        // skip random bytes
        index += 32;

        // consistency level
        vm_.consistencyLevel = log.data.toUint8(index + 32 - 1);
        index += 32;

        // length of payload
        uint256 payloadLen = log.data.toUint256(index);
        index += 32;

        vm_.payload = log.data.slice(index, payloadLen);
        index += payloadLen;

        // trailing bytes (due to 32 byte slot overlap)
        index += log.data.length - index;

        require(index == log.data.length, "failed to parse deltaswap message");
    }

    /**
     * @notice Finds published Deltaswap events in forge logs
     * @param logs The forge Vm.log captured when recording events during test execution
     * @param numMessages The expected number of Deltaswap events in the forge logs
     */
    function fetchDeltaswapMessageFromLog(
        Vm.Log[] memory logs,
        uint8 numMessages
    ) public pure returns (Vm.Log[] memory) {
        // create log array to save published messages
        Vm.Log[] memory published = new Vm.Log[](numMessages);

        uint8 publishedIndex = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] == keccak256(
                    "LogMessagePublished(address,uint64,uint32,bytes,uint8)"
                )
            ) {
                published[publishedIndex] = logs[i];
                publishedIndex += 1;
            }
        }

        return published;
    }

    /**
     * @notice Encodes Deltaswap message body into bytes
     * @param vm_ Deltaswap VM struct
     * @return encodedObservation Deltaswap message body encoded into bytes
     */
    function encodeObservation(IDeltaswap.VM memory vm_) public pure returns (bytes memory encodedObservation) {
        encodedObservation = abi.encodePacked(
            vm_.timestamp,
            vm_.nonce,
            vm_.emitterChainId,
            vm_.emitterAddress,
            vm_.sequence,
            vm_.consistencyLevel,
            vm_.payload
        );
    }

    /**
     * @notice Formats and signs a simulated Deltaswap message using the emitted log from calling `publishMessage`
     * @param log The forge Vm.log captured when recording events during test execution
     * @return signedMessage Formatted and signed Deltaswap message
     */
    function fetchSignedMessageFromLogs(
        Vm.Log memory log,
        uint16 emitterChainId,
        address emitterAddress
    ) public view returns (bytes memory signedMessage) {
        // Create message instance
        IDeltaswap.VM memory vm_;

        // Parse deltaswap message from ethereum logs
        vm_ = parseVMFromLogs(log);

        // Set empty body values before computing the hash
        vm_.version = uint8(1);
        vm_.timestamp = uint32(block.timestamp);
        vm_.emitterChainId = emitterChainId;
        vm_.emitterAddress = bytes32(uint256(uint160(emitterAddress)));

        return encodeAndSignMessage(vm_);
    }

    /**
     * @notice Signs and preformatted simulated Deltaswap message
     * @param vm_ The preformatted Deltaswap message
     * @return signedMessage Formatted and signed Deltaswap message
     */
    function encodeAndSignMessage(
        IDeltaswap.VM memory vm_
    ) public view returns (bytes memory signedMessage) {
        // Compute the hash of the body
        bytes memory body = encodeObservation(vm_);
        vm_.hash = doubleKeccak256(body);

        // Sign the hash with the devnet phylax private key
        IDeltaswap.Signature[] memory sigs = new IDeltaswap.Signature[](1);
        (sigs[0].v, sigs[0].r, sigs[0].s) = vm.sign(devnetPhylaxPK, vm_.hash);
        sigs[0].phylaxIndex = 0;

        signedMessage = abi.encodePacked(
            vm_.version,
            deltaswap.getCurrentPhylaxSetIndex(),
            uint8(sigs.length),
            sigs[0].phylaxIndex,
            sigs[0].r,
            sigs[0].s,
            sigs[0].v - 27,
            body
        );
    }
}
