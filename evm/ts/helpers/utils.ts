import {ethers} from "ethers";
import {ChainId, tryNativeToHexString} from "@deltaswapio/deltaswap-sdk";
import {
  DELTASWAP_MESSAGE_EVENT_ABI,
  DELTASWAP_TOPIC,
  SWAP_TOPIC,
  SWAP_EVENT_ABI,
  TRANSFER_EVENT_ABI,
  TRANSFER_EVENT_TOPIC,
} from "./consts";
import * as fs from "fs";

export function readTokenBridgeRelayerContractAddress(
  chain: number,
  isTest = false
): string {
  let broadcastType;
  if (isTest) {
    broadcastType = "broadcast-test";
  } else {
    broadcastType = "broadcast";
  }
  return JSON.parse(
    fs.readFileSync(
      `${__dirname}/../../${broadcastType}/deploy_contracts.sol/${chain}/run-latest.json`,
      "utf-8"
    )
  ).transactions[0].contractAddress;
}

export function readWormUSDContractAddress(chain: number): string {
  return JSON.parse(
    fs.readFileSync(
      `${__dirname}/../../broadcast-test/deploy_wormUSD.sol/${chain}/run-latest.json`,
      "utf-8"
    )
  ).transactions[0].contractAddress;
}

export async function parseDeltaswapEventsFromReceipt(
  receipt: ethers.ContractReceipt
): Promise<ethers.utils.LogDescription[]> {
  // create the deltaswap message interface
  const deltaswapMessageInterface = new ethers.utils.Interface(
    DELTASWAP_MESSAGE_EVENT_ABI
  );

  // loop through the logs and parse the events that were emitted
  let logDescriptions: ethers.utils.LogDescription[] = [];
  for (const log of receipt.logs) {
    if (log.topics.includes(DELTASWAP_TOPIC)) {
      logDescriptions.push(deltaswapMessageInterface.parseLog(log));
    }
  }
  return logDescriptions;
}

export async function formatDeltaswapMessageFromReceipt(
  receipt: ethers.ContractReceipt,
  emitterChainId: ChainId
): Promise<Buffer[]> {
  // parse the deltaswap message logs
  const messageEvents = await parseDeltaswapEventsFromReceipt(receipt);

  // find VAA events
  if (messageEvents.length == 0) {
    throw new Error("No Deltaswap messages found!");
  }

  let results: Buffer[] = [];

  // loop through each event and format the deltaswap Observation (message body)
  for (const event of messageEvents) {
    // create a timestamp and find the emitter address
    const timestamp = Math.floor(+new Date() / 1000);
    const emitterAddress: ethers.utils.BytesLike = ethers.utils.hexlify(
      "0x" + tryNativeToHexString(event.args.sender, emitterChainId)
    );

    // encode the observation
    const encodedObservation = ethers.utils.solidityPack(
      ["uint32", "uint32", "uint16", "bytes32", "uint64", "uint8", "bytes"],
      [
        timestamp,
        event.args.nonce,
        emitterChainId,
        emitterAddress,
        event.args.sequence,
        event.args.consistencyLevel,
        event.args.payload,
      ]
    );

    // append the observation to the results buffer array
    results.push(Buffer.from(encodedObservation.substring(2), "hex"));
  }

  return results;
}

export function findTransferCompletedEventInLogs(
  logs: ethers.providers.Log[],
  contract: string
): ethers.utils.Result {
  let result: ethers.utils.Result = {} as ethers.utils.Result;
  for (const log of logs) {
    if (
      log.address == ethers.utils.getAddress(contract) &&
      log.topics.includes(TRANSFER_EVENT_TOPIC)
    ) {
      const iface = new ethers.utils.Interface(TRANSFER_EVENT_ABI);

      result = iface.parseLog(log).args;
      break;
    }
  }
  return result;
}

export function findSwapExecutedEventInLogs(
  logs: ethers.providers.Log[],
  contract: string
): ethers.utils.Result {
  let result: ethers.utils.Result = {} as ethers.utils.Result;
  for (const log of logs) {
    if (
      log.address == ethers.utils.getAddress(contract) &&
      log.topics.includes(SWAP_TOPIC)
    ) {
      const iface = new ethers.utils.Interface(SWAP_EVENT_ABI);

      result = iface.parseLog(log).args;
      break;
    }
  }
  return result;
}

export function tokenBridgeNormalizeAmount(
  amount: ethers.BigNumber,
  decimals: number
): ethers.BigNumber {
  if (decimals > 8) {
    amount = amount.div(10 ** (decimals - 8));
  }
  return amount;
}

export function tokenBridgeDenormalizeAmount(
  amount: ethers.BigNumber,
  decimals: number
): ethers.BigNumber {
  if (decimals > 8) {
    amount = amount.mul(10 ** (decimals - 8));
  }
  return amount;
}

export function tokenBridgeTransform(
  amount: ethers.BigNumber,
  decimals: number
): ethers.BigNumber {
  return tokenBridgeDenormalizeAmount(
    tokenBridgeNormalizeAmount(amount, decimals),
    decimals
  );
}
