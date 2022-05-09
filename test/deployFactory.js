const {expect} = require("chai");
const {ethers} = require("hardhat");
const namehash = require("eth-ens-namehash");

describe("Zecrey-Legend contract", function () {

    let owner, governor, addr1, addr2, addrs;
    let ZNSRegistry, znsRegistry;
    let ZNSController, znsController;
    let PublicResolver, znsResolver;
    let ZecreyLegend, zecreyLegend;
    let Verifier, verifier;
    let Governance, governance;
    let AssetGovernance, assetGovernance;
    let DeployFactory, deployFactory, deployFactoryTx, deployFactoryTxReceipt;
    let UpgradeGatekeeper, upgradeGatekeeper;
    let Proxy, zecreyLegendProxy, znsControllerProxy;
    let Utils, utils;

    // `beforeEach` will run before each test, re-deploying the contract every
    // time. It receives a callback, which can be async.
    beforeEach(async function () {
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
        governor = owner.address;

        // Step 1: deploy zns and register root node
        ZNSRegistry = await ethers.getContractFactory('ZNSRegistry');
        znsRegistry = await ZNSRegistry.deploy();
        await znsRegistry.deployed();

        // Step 2: deploy proxied contract
        // governance
        Governance = await ethers.getContractFactory('Governance');
        governance = await Governance.deploy();
        await governance.deployed();
        // asset governance
        AssetGovernance = await ethers.getContractFactory('AssetGovernance')
        // assetGovernance = await AssetGovernance.deploy()
        // await assetGovernance.deployed()
        // verifier
        Verifier = await ethers.getContractFactory('ZecreyVerifier')
        verifier = await Verifier.deploy()
        await verifier.deployed()
        // zecrey legend with utils
        const Utils = await ethers.getContractFactory("Utils")
        const utils = await Utils.deploy()
        await utils.deployed()
        ZecreyLegend = await ethers.getContractFactory('ZecreyLegend', {
            libraries: {
                Utils: utils.address
            }
        })
        zecreyLegend = await ZecreyLegend.deploy()
        await zecreyLegend.deployed()
        // ZNS controller
        ZNSController = await ethers.getContractFactory('ZNSController');
        znsController = await ZNSController.deploy();
        await znsController.deployed();
        // ZNS resolver
        PublicResolver = await ethers.getContractFactory('PublicResolver');
        znsResolver = await PublicResolver.deploy();
        await znsResolver.deployed()

        // Step 3: initialize deploy factory and finish deployment
        const _genesisAccountRoot = '0x01ef55cdf3b9b0d65e6fb6317f79627534d971fd96c811281af618c0028d5e7a';
        const _listingFee = ethers.utils.parseEther('100');
        const _listingCap = 2 ** 16 - 1;
        const baseNode = namehash.hash('legend');
        DeployFactory = await ethers.getContractFactory("DeployFactory");
        deployFactory = await DeployFactory.connect(owner).deploy(
            governance.address, verifier.address, zecreyLegend.address, znsController.address, znsResolver.address,
            _genesisAccountRoot, verifier.address, governor, governance.address, _listingFee, _listingCap,
            znsRegistry.address, baseNode
        );
        await deployFactory.deployed();
        // Get deployed proxy contracts and the gatekeeper contract,
        // they are used for invoking methods.
        deployFactoryTx = await deployFactory.deployTransaction;
        deployFactoryTxReceipt = await deployFactoryTx.wait();
        const AddressesInterface = new ethers.utils.Interface(["event Addresses(address governance, address assetGovernance, address verifier, address znsController, address znsResolver, address zecreyLegend, address gatekeeper)"]);
        // The event 2 is the required event.
        // console.log(deployFactoryTxReceipt.logs)
        let event = AddressesInterface.decodeEventLog("Addresses", deployFactoryTxReceipt.logs[7].data, deployFactoryTxReceipt.logs[7].topics);
        // Get inner contract proxy address
        // console.log(event)
        assetGovernance = AssetGovernance.attach(event[1])
        znsControllerProxy = ZNSController.attach(event[3])
        zecreyLegendProxy = ZecreyLegend.attach(event[5])

        // Step 4: register zns base node
        const rootNode = namehash.hash('');
        const baseNameHash = getKeccak256('legend');
        const setBaseNodeTx = await znsRegistry.connect(owner).setSubnodeOwner(rootNode, baseNameHash, znsControllerProxy.address, ethers.constants.HashZero);
        await setBaseNodeTx.wait();
        expect(await znsRegistry.owner(baseNode)).to.equal(await znsControllerProxy.address);
    });

    describe('Zecrey Deploy Test', function () {
        it("test ZNS register", async function () {
            // register ZNS
            const sherPubKey = ethers.utils.formatBytes32String('sher.legend')
            const registerZNSTx = await zecreyLegendProxy.registerZNS('sher', await addr1.getAddress(), sherPubKey)
            await registerZNSTx.wait()

            const sherNameHash = namehash.hash('sher.legend');
            expect(await zecreyLegendProxy.connect(owner).getAddressByAccountNameHash(sherNameHash)).to.equal(await addr1.getAddress());
            expect(await znsRegistry.owner(sherNameHash)).to.equal(await addr1.getAddress());
        });

        it("test Deposit BNB", async function () {
            // register ZNS
            const sherPubKey = ethers.utils.formatBytes32String('sher.legend')
            const registerZNSTx = await zecreyLegendProxy.registerZNS('sher', await addr1.getAddress(), sherPubKey)
            await registerZNSTx.wait()

            const sherNameHash = namehash.hash('sher.legend');
            expect(await zecreyLegendProxy.connect(owner).getAddressByAccountNameHash(sherNameHash)).to.equal(await addr1.getAddress());
            expect(await znsRegistry.owner(sherNameHash)).to.equal(await addr1.getAddress());

            const depositBNBTx = await zecreyLegendProxy.connect(addr1).depositBNB(sherNameHash, {
                value: ethers.utils.parseEther('1.0'),
            });
            await depositBNBTx.wait()
        })

        it("test Deposit BEP20", async function () {
            // deploy BEP20 token
            const TokenFactory = await ethers.getContractFactory('ZecreyRelatedERC20')
            const token = await TokenFactory.connect(addr1).deploy(10000, '', '')
            await token.deployed()
            expect(await token.balanceOf(addr1.address)).to.equal(10000)
            // set allowance
            const setAllowanceTx = await token.connect(addr1).approve(zecreyLegendProxy.address, 10000)
            await setAllowanceTx.wait()
            expect(await token.allowance(addr1.address, zecreyLegendProxy.address)).to.equal(10000)

            // add asset
            const addAssetTx = await assetGovernance.connect(owner).addAsset(token.address)
            await addAssetTx.wait()

            // register ZNS
            const sherPubKey = ethers.utils.formatBytes32String('sher.legend')
            const registerZNSTx = await zecreyLegendProxy.registerZNS('sher', await addr1.getAddress(), sherPubKey)
            await registerZNSTx.wait()

            const sherNameHash = namehash.hash('sher.legend');
            expect(await zecreyLegendProxy.connect(owner).getAddressByAccountNameHash(sherNameHash)).to.equal(await addr1.getAddress());
            expect(await znsRegistry.owner(sherNameHash)).to.equal(await addr1.getAddress());

            const depositBEP20Tx = await zecreyLegendProxy.connect(addr1).depositBEP20(token.address, 100, sherNameHash);
            await depositBEP20Tx.wait()
            expect(await token.balanceOf(zecreyLegendProxy.address)).to.equal(100);
        })
    });

    // get the keccak256 hash of a specified string name
    // eg: getKeccak256('zecrey') = '0x621eacce7c1f02dbf62859801a97d1b2903abc1c3e00e28acfb32cdac01ab36d'
    const getKeccak256 = (name) => {
        return ethers.utils.keccak256(ethers.utils.toUtf8Bytes(name))
    }
});