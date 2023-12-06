import {expect} from "chai";
import {ethers} from "ethers";
import {
  CHAIN_ID_AVAX,
  CHAIN_ID_ETH,
  tryNativeToHexString,
} from "@deltaswapio/deltaswap-sdk";
import {MockPhylaxs} from "@deltaswapio/deltaswap-sdk/lib/cjs/mock";
import {
  FORK_AVAX_CHAIN_ID,
  FORK_ETH_CHAIN_ID,
  GUARDIAN_PRIVATE_KEY,
  AVAX_HOST,
  AVAX_DELTASWAP_ADDRESS,
  AVAX_BRIDGE_ADDRESS,
  AVAX_DELTASWAP_CHAIN_ID,
  AVAX_DELTASWAP_GUARDIAN_SET_INDEX,
  AVAX_DELTASWAP_MESSAGE_FEE,
  ETH_HOST,
  ETH_DELTASWAP_ADDRESS,
  ETH_BRIDGE_ADDRESS,
  ETH_DELTASWAP_CHAIN_ID,
  ETH_DELTASWAP_GUARDIAN_SET_INDEX,
  ETH_DELTASWAP_MESSAGE_FEE,
  WALLET_PRIVATE_KEY,
} from "../helpers/consts";
import {
  formatDeltaswapMessageFromReceipt,
  readWormUSDContractAddress,
} from "../helpers/utils";
import {IDeltaswap__factory, IERC20__factory} from "../src/ethers-contracts";
import {ITokenBridge__factory} from "@deltaswapio/deltaswap-sdk/lib/cjs/ethers-contracts";

describe("Environment Test", () => {
  // avax wallet
  const avaxProvider = new ethers.providers.StaticJsonRpcProvider(AVAX_HOST);
  const avaxWallet = new ethers.Wallet(WALLET_PRIVATE_KEY, avaxProvider);

  // eth wallet
  const ethProvider = new ethers.providers.StaticJsonRpcProvider(ETH_HOST);
  const ethWallet = new ethers.Wallet(WALLET_PRIVATE_KEY, ethProvider);

  // deltaswap contract
  const avaxDeltaswap = IDeltaswap__factory.connect(
    AVAX_DELTASWAP_ADDRESS,
    avaxWallet
  );
  const ethDeltaswap = IDeltaswap__factory.connect(
    ETH_DELTASWAP_ADDRESS,
    ethWallet
  );

  // token bridge contract
  const avaxBridge = ITokenBridge__factory.connect(
    AVAX_BRIDGE_ADDRESS,
    avaxWallet
  );
  const ethBridge = ITokenBridge__factory.connect(
    ETH_BRIDGE_ADDRESS,
    ethWallet
  );

  // wormUSD ERC20 contract
  const avaxWormUsd = IERC20__factory.connect(
    readWormUSDContractAddress(FORK_AVAX_CHAIN_ID),
    avaxWallet
  );
  const ethWormUsd = IERC20__factory.connect(
    readWormUSDContractAddress(FORK_ETH_CHAIN_ID),
    ethWallet
  );

  describe("Verify Mainnet Forks", () => {
    it("AVAX Chain ID", async () => {
      const network = await avaxProvider.getNetwork();
      expect(network.chainId).to.equal(FORK_AVAX_CHAIN_ID);
    });

    it("ETH Chain ID", async () => {
      const network = await ethProvider.getNetwork();
      expect(network.chainId).to.equal(FORK_ETH_CHAIN_ID);
    });
  });

  describe("Verify AVAX Deltaswap Contract", () => {
    it("Chain ID", async () => {
      const chainId = await avaxDeltaswap.chainId();
      expect(chainId).to.equal(AVAX_DELTASWAP_CHAIN_ID);
    });

    it("Message Fee", async () => {
      const messageFee: ethers.BigNumber = await avaxDeltaswap.messageFee();
      expect(messageFee.eq(AVAX_DELTASWAP_MESSAGE_FEE)).to.be.true;
    });

    it("Phylax Set", async () => {
      // check phylax set index
      const phylaxSetIndex = await avaxDeltaswap.getCurrentPhylaxSetIndex();
      expect(phylaxSetIndex).to.equal(AVAX_DELTASWAP_GUARDIAN_SET_INDEX);

      // override phylax set
      const abiCoder = ethers.utils.defaultAbiCoder;

      // get slot for Phylax Set at the current index
      const phylaxSetSlot = ethers.utils.keccak256(
        abiCoder.encode(["uint32", "uint256"], [phylaxSetIndex, 2])
      );

      // Overwrite all but first phylax set to zero address. This isn't
      // necessary, but just in case we inadvertently access these slots
      // for any reason.
      const numPhylaxs = await avaxProvider
        .getStorageAt(AVAX_DELTASWAP_ADDRESS, phylaxSetSlot)
        .then((value) => ethers.BigNumber.from(value).toBigInt());
      for (let i = 1; i < numPhylaxs; ++i) {
        await avaxProvider.send("anvil_setStorageAt", [
          AVAX_DELTASWAP_ADDRESS,
          abiCoder.encode(
            ["uint256"],
            [
              ethers.BigNumber.from(
                ethers.utils.keccak256(phylaxSetSlot)
              ).add(i),
            ]
          ),
          ethers.utils.hexZeroPad("0x0", 32),
        ]);
      }

      // Now overwrite the first phylax key with the devnet key specified
      // in the function argument.
      const devnetPhylax = new ethers.Wallet(GUARDIAN_PRIVATE_KEY).address;
      await avaxProvider.send("anvil_setStorageAt", [
        AVAX_DELTASWAP_ADDRESS,
        abiCoder.encode(
          ["uint256"],
          [
            ethers.BigNumber.from(ethers.utils.keccak256(phylaxSetSlot)).add(
              0 // just explicit w/ index 0
            ),
          ]
        ),
        ethers.utils.hexZeroPad(devnetPhylax, 32),
      ]);

      // change the length to 1 phylax
      await avaxProvider.send("anvil_setStorageAt", [
        AVAX_DELTASWAP_ADDRESS,
        phylaxSetSlot,
        ethers.utils.hexZeroPad("0x1", 32),
      ]);

      // confirm phylax set override
      const phylaxs = await avaxDeltaswap
        .getPhylaxSet(phylaxSetIndex)
        .then(
          (phylaxSet: any) => phylaxSet[0] // first element is array of keys
        );
      expect(phylaxs.length).to.equal(1);
      expect(phylaxs[0]).to.equal(devnetPhylax);
    });
  });

  describe("Verify ETH Deltaswap Contract", () => {
    it("Chain ID", async () => {
      const chainId = await ethDeltaswap.chainId();
      expect(chainId).to.equal(ETH_DELTASWAP_CHAIN_ID);
    });

    it("Message Fee", async () => {
      const messageFee: ethers.BigNumber = await ethDeltaswap.messageFee();
      expect(messageFee.eq(ETH_DELTASWAP_MESSAGE_FEE)).to.be.true;
    });

    it("Phylax Set", async () => {
      // check phylax set index
      const phylaxSetIndex = await ethDeltaswap.getCurrentPhylaxSetIndex();
      expect(phylaxSetIndex).to.equal(ETH_DELTASWAP_GUARDIAN_SET_INDEX);

      // override phylax set
      const abiCoder = ethers.utils.defaultAbiCoder;

      // get slot for Phylax Set at the current index
      const phylaxSetSlot = ethers.utils.keccak256(
        abiCoder.encode(["uint32", "uint256"], [phylaxSetIndex, 2])
      );

      // Overwrite all but first phylax set to zero address. This isn't
      // necessary, but just in case we inadvertently access these slots
      // for any reason.
      const numPhylaxs = await ethProvider
        .getStorageAt(ETH_DELTASWAP_ADDRESS, phylaxSetSlot)
        .then((value) => ethers.BigNumber.from(value).toBigInt());
      for (let i = 1; i < numPhylaxs; ++i) {
        await ethProvider.send("anvil_setStorageAt", [
          ETH_DELTASWAP_ADDRESS,
          abiCoder.encode(
            ["uint256"],
            [
              ethers.BigNumber.from(
                ethers.utils.keccak256(phylaxSetSlot)
              ).add(i),
            ]
          ),
          ethers.utils.hexZeroPad("0x0", 32),
        ]);
      }

      // Now overwrite the first phylax key with the devnet key specified
      // in the function argument.
      const devnetPhylax = new ethers.Wallet(GUARDIAN_PRIVATE_KEY).address;
      await ethProvider.send("anvil_setStorageAt", [
        ETH_DELTASWAP_ADDRESS,
        abiCoder.encode(
          ["uint256"],
          [
            ethers.BigNumber.from(ethers.utils.keccak256(phylaxSetSlot)).add(
              0 // just explicit w/ index 0
            ),
          ]
        ),
        ethers.utils.hexZeroPad(devnetPhylax, 32),
      ]);

      // change the length to 1 phylax
      await ethProvider.send("anvil_setStorageAt", [
        ETH_DELTASWAP_ADDRESS,
        phylaxSetSlot,
        ethers.utils.hexZeroPad("0x1", 32),
      ]);

      // confirm phylax set override
      const phylaxs = await ethDeltaswap.getPhylaxSet(phylaxSetIndex).then(
        (phylaxSet: any) => phylaxSet[0] // first element is array of keys
      );
      expect(phylaxs.length).to.equal(1);
      expect(phylaxs[0]).to.equal(devnetPhylax);
    });
  });

  describe("Verify AVAX Bridge Contract", () => {
    it("Chain ID", async () => {
      const chainId = await avaxBridge.chainId();
      expect(chainId).to.equal(AVAX_DELTASWAP_CHAIN_ID);
    });
    it("Deltaswap", async () => {
      const deltaswap = await avaxBridge.deltaswap();
      expect(deltaswap).to.equal(AVAX_DELTASWAP_ADDRESS);
    });
  });

  describe("Verify ETH Bridge Contract", () => {
    it("Chain ID", async () => {
      const chainId = await ethBridge.chainId();
      expect(chainId).to.equal(ETH_DELTASWAP_CHAIN_ID);
    });
    it("Deltaswap", async () => {
      const deltaswap = await ethBridge.deltaswap();
      expect(deltaswap).to.equal(ETH_DELTASWAP_ADDRESS);
    });
  });

  describe("Check deltaswap-sdk", () => {
    it("tryNativeToHexString", async () => {
      const accounts = await avaxProvider.listAccounts();
      expect(tryNativeToHexString(accounts[0], "ethereum")).to.equal(
        "00000000000000000000000090f8bf6a479f320ead074411a4b0e7944ea8c9c1"
      );
    });
  });

  describe("Verify AVAX WormUSD", () => {
    const phylaxs = new MockPhylaxs(AVAX_DELTASWAP_GUARDIAN_SET_INDEX, [
      GUARDIAN_PRIVATE_KEY,
    ]);

    let signedTokenAttestation: Buffer;

    it("Tokens Minted to Wallet", async () => {
      // fetch the total supply and confirm it was all minted to the avaxWallet
      const totalSupply = await avaxWormUsd.totalSupply();
      const walletBalance = await avaxWormUsd.balanceOf(avaxWallet.address);
      expect(totalSupply.eq(walletBalance)).is.true;
    });

    it("Attest Tokens on Avax Bridge", async () => {
      const receipt: ethers.ContractReceipt = await avaxBridge
        .attestToken(avaxWormUsd.address, 0) // set nonce to zero
        .then((tx: ethers.ContractTransaction) => tx.wait());

      // simulate signing the VAA with the mock phylax
      const unsignedMessages = await formatDeltaswapMessageFromReceipt(
        receipt,
        CHAIN_ID_AVAX
      );
      expect(unsignedMessages.length).to.equal(1);
      signedTokenAttestation = phylaxs.addSignatures(unsignedMessages[0], [
        0,
      ]);
    });

    it("Create Wrapped Token Contract on ETH", async () => {
      // create wrapped token on eth using signedTokenAttestation message
      const receipt: ethers.ContractReceipt = await ethBridge
        .createWrapped(signedTokenAttestation) // set nonce to zero
        .then((tx: ethers.ContractTransaction) => tx.wait());

      // confirm that the token contract was created
      const wrappedAsset = await ethBridge.wrappedAsset(
        CHAIN_ID_AVAX,
        "0x" + tryNativeToHexString(avaxWormUsd.address, CHAIN_ID_AVAX)
      );
      const isWrapped = await ethBridge.isWrappedAsset(wrappedAsset);
      expect(isWrapped).is.true;
    });
  });

  describe("Verify ETH WormUSD", () => {
    const phylaxs = new MockPhylaxs(ETH_DELTASWAP_GUARDIAN_SET_INDEX, [
      GUARDIAN_PRIVATE_KEY,
    ]);

    let signedTokenAttestation: Buffer;

    it("Tokens Minted to Wallet", async () => {
      // fetch the total supply and confirm it was all minted to the avaxWallet
      const totalSupply = await ethWormUsd.totalSupply();
      const walletBalance = await ethWormUsd.balanceOf(ethWallet.address);
      expect(totalSupply.eq(walletBalance)).is.true;
    });

    it("Attest Tokens on Avax Bridge", async () => {
      const receipt: ethers.ContractReceipt = await ethBridge
        .attestToken(ethWormUsd.address, 0) // set nonce to zero
        .then((tx: ethers.ContractTransaction) => tx.wait());

      // simulate signing the VAA with the mock phylax
      const unsignedMessages = await formatDeltaswapMessageFromReceipt(
        receipt,
        CHAIN_ID_ETH
      );
      expect(unsignedMessages.length).to.equal(1);
      signedTokenAttestation = phylaxs.addSignatures(unsignedMessages[0], [
        0,
      ]);
    });

    it("Create Wrapped Token Contract on AVAX", async () => {
      // create wrapped token on avax using signedTokenAttestation message
      const receipt: ethers.ContractReceipt = await avaxBridge
        .createWrapped(signedTokenAttestation) // set nonce to zero
        .then((tx: ethers.ContractTransaction) => tx.wait());

      // confirm that the token contract was created
      const wrappedAsset = await avaxBridge.wrappedAsset(
        CHAIN_ID_ETH,
        "0x" + tryNativeToHexString(ethWormUsd.address, CHAIN_ID_ETH)
      );
      const isWrapped = await avaxBridge.isWrappedAsset(wrappedAsset);
      expect(isWrapped).is.true;
    });
  });
});
