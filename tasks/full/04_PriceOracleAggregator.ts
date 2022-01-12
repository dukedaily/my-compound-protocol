import { task} from 'hardhat/config'
import { deployPriceOracleAggregator, deployTestPriceOracle } from '../../helpers/contracts-deployments'
task("full:deploy-oracle", "Deploy Oracle Chainlink")
    .addFlag('verify', 'Verify contracts at Etherscan')
    .setAction(async ({ verify }, localDRE) => {
        localDRE.run('set-DRE')
        let oracleIns = await deployPriceOracleAggregator(verify)

        let f = await oracleIns.isPriceOracle()
        console.log('isOracle:', f);
        console.log('部署oracle:', oracleIns.address);

        if (localDRE.network.name == 'hardhat') {
            console.log('为hardhat网络部署模拟oracle提供合约!');
            let testPriceOracle = await deployTestPriceOracle()
            console.log('testPriceOracle:', testPriceOracle.address);
        }
    })