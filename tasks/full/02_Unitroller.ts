import { task } from 'hardhat/config'
import { deployUnitroller } from '../../helpers/contracts-deployments'

task("full:deploy-unitroller", "Deploy unitroller")
    .addFlag('verify', 'Verify contracts at Etherscan')
    .setAction(async ({ verify }, localDRE) => {
        console.log("verify:", verify);
        localDRE.run('set-DRE')
        let unitroller = await deployUnitroller(verify)
        console.log("unitroller address:", unitroller.address);
    })