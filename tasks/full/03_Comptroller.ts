import { task } from 'hardhat/config'
import { deployComptroller } from '../../helpers/contracts-deployments'
import { getUnitroller, getFirstSigner, getComptroller } from '../../helpers/contracts-getters'

task("full:deploy-comptroller", "Deploy Comptroller")
    .addFlag('verify', 'Verify contracts at Etherscan')
    .setAction(async ({ verify }, DRE) => {
        let network = DRE.network
        console.log("verify:", verify);
        console.log("task deploy comptroller called!", 'network:', network.name);

        let overrides = {
            gasLimit: 12450000
        }

        let deployer = await getFirstSigner()
        console.log('deployer:', deployer.address, 'balance:', (await deployer.getBalance()).toString())

        let comptroller = await deployComptroller(overrides, verify)
        console.log("comptroller address: ", comptroller.address);

        console.log("\nset comptroller into unitroller");
        let unitroller = await getUnitroller()
        await unitroller._setPendingImplementation(comptroller.address)
        await comptroller._become(unitroller.address)

        console.log("unitroller.comptroller: ", await unitroller.comptrollerImplementation());

        //comptroller abi
        //unitroller address
        let unitrollerIns = await getComptroller(unitroller.address)
        let compAddr = await unitrollerIns.getPubAddress()

        //0xc00e94Cb662C3520282E6f5717214004A7f26888
        console.log('compAddr called!: ', compAddr);
    })
