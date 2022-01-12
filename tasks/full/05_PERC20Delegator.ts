import { task } from 'hardhat/config'
// import { ethers } from 'hardhat'
import {
    deployJumpRateModelV2,
    deployPErc20Delegate,
    deployPErc20Delegator,
} from '../../helpers/contracts-deployments'

import { SupportTokens } from '../../helpers/types'
import { PublicConfig } from '../../config';
import {
    getFirstSigner,
    getComptroller,
    getPubMiningRateModelImpl,
    getUnitroller
} from '../../helpers/contracts-getters'
import Colors = require('colors.ts');
Colors.enable();

task("full:deploy-PERC20Delegator", "Deploy unitroller")
    .addFlag('verify', 'Verify contracts at Etherscan')
    .setAction(async ({ verify }, localDRE) => {
        localDRE.run('set-DRE')

        let owner = await getFirstSigner()
        const { ReservesConfig } = PublicConfig

        const reserves = Object.entries(ReservesConfig).filter(
            ([symbol, _]) => symbol !== SupportTokens.ETHER
        )

        let balance = await localDRE.ethers.provider.getBalance(owner.address)
        console.log("balance: ".yellow, balance.toString());

        for (let [symbol, currReserveConfig] of reserves) {
            console.log(`\t*** 开始部署: p${symbol} ***`.yellow)
            let { baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink } = currReserveConfig.rateModel

            console.log("利率参数:", baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink);
            console.log("\t1. 部署jumpRateModelV2".yellow)
            const rateIns = await deployJumpRateModelV2(symbol, baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink, owner.address, verify)
            console.log(`\tjumpRateModelV2 addr: ${rateIns.address}\n`)
            console.log("\t2. 部署PErc20Delegate".yellow)

            let overrides = {
                gasLimit: 12450000
            }

            balance = await localDRE.ethers.provider.getBalance(owner.address)
            console.log("owner balance: ".yellow, balance.toString());
            
            const delegateIns = await deployPErc20Delegate(symbol, overrides, verify)
            console.log(`\tPErc20Delegate addr: ${delegateIns.address}\n`)

            console.log("\t3. 准备部署PErc20Delegateor".yellow)
            const underlying = PublicConfig.ReserveAssets[localDRE.network.name][symbol]

            //使用unitroller的地址， Comptroller的abi
            // const comptrollerIns = await getComptroller()
            // let unitroller = await getUnitroller()
            let unitrollerIns = await getComptroller((await getUnitroller()).address)

            const { initialExchangeRateMantissa, cTokenName, decimals, becomeImplementationData } = currReserveConfig
            let pubMiningRateModelIns = await getPubMiningRateModelImpl()
            let assetDecimal = currReserveConfig.underlying.decimalUnits

            console.log(`\t-------------------- p${symbol} 基本信息如下: --------------------`.yellow);
            console.log(`\tunderlying: ${underlying}`);
            console.log(`\tassetDecimal: ${assetDecimal}`);
            console.log(`\tunitroller addr: ${unitrollerIns.address}`);
            console.log(`\tjumpRateModel addr: ${rateIns.address}`);
            console.log(`\tPubMiningRateModelImp addr: ${pubMiningRateModelIns.address}`);
            console.log(`\tinitialExchangeRateMantissa: ${initialExchangeRateMantissa}`);
            console.log(`\tcTokenName: ${cTokenName}`);
            console.log(`\tsymbol: p${symbol}`);
            console.log(`\tdecimals: ${decimals}`);
            console.log(`\tadmin: ${owner.address}`);
            console.log(`\tdelegate addr: ${delegateIns.address}`);
            console.log(`\tbecomeImplementationData: ${becomeImplementationData}\n`);

            console.log("assetDecimal.toString():",  assetDecimal.toString())
            const delegatorIns = await deployPErc20Delegator(
                symbol, 
                underlying,
                assetDecimal.toString(),
                unitrollerIns.address, 
                rateIns.address, 
                pubMiningRateModelIns.address, 
                initialExchangeRateMantissa,
                cTokenName, 
                symbol, 
                decimals, 
                owner.address, 
                delegateIns.address, 
                becomeImplementationData, 
                verify)
            console.log(`部署PErc20Delegator(c${symbol})成功: ${delegatorIns.address}\n`.green)
        }
    })