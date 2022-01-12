import { task } from 'hardhat/config'
import { deployPubMiningRateModelImpl } from '../../helpers/contracts-deployments'
import { getUnitroller, getFirstSigner, getComptroller } from '../../helpers/contracts-getters'
import {kink_, supplyBaseSpeed_,supplyG0_, supplyG1_, supplyG2_, borrowBaseSpeed_, borrowG0_, borrowG1_, borrowG2_} from '../../helpers/constants'

task("full:deploy-pubMiningRateModel", "Deploy Comptroller")
    .addFlag('verify', 'Verify contracts at Etherscan')
    .setAction(async ({ verify }, localDRE) => {
        console.log("verify:", verify);
        localDRE.run('set-DRE')
        let network = localDRE.network.name
        console.log("task deploy pubMiningRateModel called!", 'network:', network);

        let deployer = await getFirstSigner()
        console.log('deployer:', deployer.address, ', balance:', (await deployer.getBalance()).toString())

        console.log( kink_, supplyBaseSpeed_,supplyG0_, supplyG1_, supplyG2_, borrowBaseSpeed_, borrowG0_, borrowG1_, borrowG2_);

        let pubMiningRateModel = await deployPubMiningRateModelImpl(
            kink_, supplyBaseSpeed_,supplyG0_, supplyG1_, supplyG2_, borrowBaseSpeed_, borrowG0_, borrowG1_, borrowG2_, deployer.address, verify)
        console.log("pubMiningRateModel address: ", pubMiningRateModel.address);
    })