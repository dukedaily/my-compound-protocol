import { task } from 'hardhat/config'
import { deployStandardToken } from '../../helpers/contracts-deployments'
import { PublicConfig } from '../../config';
import { SupportTokens } from '../../helpers/types'

task("full:deploy-new-assets", "Deploy unitroller")
    .addFlag('verify', 'Verify contracts at Etherscan')
    .setAction(async ({ verify }, localDRE) => {
        localDRE.run('set-DRE')
        console.log("verify:", verify)

        // const reserves = Object.entries(PublicConfig.ReservesConfig)
        const reserves = Object.entries(PublicConfig.ReservesConfig).filter(
            ([symbol, _]) => symbol !== SupportTokens.ETHER
        )
        // console.log('reserves:', reserves)

        for (let [_, stragety] of reserves) {
            let { initialAmount, tokenName, symbol, decimalUnits } = stragety.underlying
            console.log(initialAmount, tokenName,symbol,decimalUnits)
            let token = await deployStandardToken(initialAmount, tokenName, decimalUnits, symbol, verify)
            console.log(`deploy ${symbol} new address: ${token.address}`);
        }
    })