import { task } from 'hardhat/config'
import BigNumber from 'bignumber.js';
import {oneEther, createBigNumber18,createBigNumber8 } from '../../helpers/constants'
import {getPriceOracleAggregator,
    getPErc20Delegator,
    getComptroller,
    getUnitroller, getFirstSigner, getStandardToken, 
    getTestPriceOracle, getAllAccounts, 
    getPubMiningRateModelImpl,
} from '../../helpers/contracts-getters'

import { PublicConfig } from '../../config';
import { deployMarginSwapPool, deployController, deployMockAggregator, 
    deployCapital,deployLiquidation, deployPub
} from '../../helpers/contracts-deployments'

/**
 * 
 */

task("full:PubMspInitialize", "initialize ")
    .addFlag('verify', 'Verify contracts at Etherscan')
    .setAction(async ({ verify }, localDRE) => {
        localDRE.run('set-DRE')
        let currNetwork = localDRE.network.name
        console.log("network: ", currNetwork, "verify: ", verify)

        //所有支持的币种市场
        const reserves = Object.entries(PublicConfig.ReservesConfig)

        console.log("*** 1. 创建MockAggregator *** ".yellow);
        let mockAggregator = await deployMockAggregator()
        console.log(`MockAggregator: ${mockAggregator.address}`.green);

        console.log("*** 2. 创建杠杆交易的控制器: MSPController! *** ".yellow);
        let mspController = await deployController()
        console.log(`mspController: ${mspController.address}`.green);

        let oracleIns = await getPriceOracleAggregator()
        console.log("oracleIns1.address:".green, oracleIns.address);

        console.log("--- 3.a Controller设置mockAggregator ---".yellow);
        await mspController.setTxAggregator(mockAggregator.address)
        console.log("MSPController设置mockAggregator:", (await mspController.getTxAggregator()));

        await mockAggregator._setPriceOracle(oracleIns.address);
        console.log(`mockAggregator设置oracle: ${await mockAggregator.oracle()}`.green);
        
        console.log("--- 3.b MSPController设置oracle ---".yellow);
        console.log("oracleIns1.address:".green, oracleIns.address);
        await mspController._setPriceOracle(oracleIns.address)

        console.log("--- 3.c Controller设置bailTypeMax(设置保证金种类上限) ---".yellow);
        await mspController.setBailTypeMax(3)

        // let oracle1 = await mspController.getOracle()
        // let p = await getPriceOracleAggregator(oracle1)
        let deployer = await getFirstSigner()

        for (let [symbol, currReserveConfig] of reserves) {
            // const underlying = PublicConfig.ReserveAssets[localDRE.network.name][symbol]
            console.log(`********* 初始化: ${symbol} ************`.red.bold);

            //1. 获取pToken地址
            let pToken = await getPErc20Delegator(symbol)
            let token = await getStandardToken(symbol)
            console.log("underlying:", token.address);
            console.log("pToken :", pToken.address);

            //4. 查询价格
            let price = await oracleIns.getUnderlyingPrice(pToken.address)
            console.log(`${symbol}的价格为:`, price.toString());
            console.log("deployer(acc0)持有数量:", (await token.balanceOf(deployer.address)).toString());

            //5. 初始化MSP工作
            if (symbol == "USDT" || symbol == "WBTC") {
                await token.transfer(mockAggregator.address, createBigNumber8(10000000))
                console.log(`acc0预先向mock dex ${symbol}:${createBigNumber8(10000000)} 1000w`.red,  );
            } else {
                await token.transfer(mockAggregator.address, createBigNumber18(10000000))
                console.log(`acc0预先向mock dex ${symbol}:${createBigNumber18(10000000)} 1000w`.red,  );
            }

            //保证金白名单
            await mspController.setBailTokenWhiteList(token.address, true)
            //保证金token->pToken
            await mspController.setAssetToPTokenList(token.address, pToken.address);
            //swapToken白名单
            await mspController.setSwapTokenWhiteList(token.address, true);

            console.log("MSPController设置清算系数");
            //杠杆交易中资产抵押系数
            await mspController._setCollateralFactor(pToken.address,createBigNumber18(0.8))

            //杠杆交易中清算触发系数
            await mspController._setCloseFactor(createBigNumber18(1))

            //杠杆交易中清算奖励
            await mspController._setLiquidationIncentive(createBigNumber18(1.08))

            let flag = true
            console.log("是否允许直接清算（开关）:", flag);
            await mspController.setDirectlyLiquidationState(flag)

            let mspName = "MSP" + symbol
            let capital = await deployCapital(symbol, mspName, pToken.address, mspController.address)
            console.log(`部署capital ${symbol}:`, capital.address);

            console.log(`*** 创建MSP${symbol}*** `.red.bold);
            let msp = await deployMarginSwapPool(symbol, capital.address)
            console.log(`MSP-${symbol}部署成功:${msp.address}`.green);

            console.log("部署Liquidation!");
            let liquidation = await deployLiquidation(symbol, msp.address)
            console.log(`MSP-Liquidation-${symbol}部署成功:${liquidation.address}`.green);

            /*
            console.log("检查Controller:", await msp.controller());
            console.log("更新Controller!")
            await capital.setController(mspController1.address)
            console.log("检查Controller:", await msp.controller());

            await msp.setUnderlyPTokenAddress(pToken.address) 
            */

            await mspController._supportMspMarket(msp.address, liquidation.address, true)

            console.log(`设置杠杆倍数`.yellow);
            await mspController.setLeverage(msp.address, 10, 30);
            
            console.log("capital 设置白名单!".yellow.bold);
            await capital.setSuperList(msp.address, true)
            await capital.setSuperList(liquidation.address, true)
            //信用贷
            await pToken.setWhiteList(capital.address, true)
            console.log('pToken:', pToken.address, 'capital:',capital.address);
        }

        console.log("********* 初始化结束 *********");
        console.log("杠杆交易=> 所有supportMspMarktes:", await mspController.getAllMspMarkets())
    })