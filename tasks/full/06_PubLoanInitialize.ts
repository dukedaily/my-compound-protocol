import { task } from 'hardhat/config'
import BigNumber from 'bignumber.js';
import { oneEther, createBigNumber18} from '../../helpers/constants'
import {
    getPriceOracleAggregator,
    getPErc20Delegator,
    getComptroller,
    getUnitroller, getFirstSigner, getStandardToken,
    getTestPriceOracle, getAllAccounts,
} from '../../helpers/contracts-getters'

import { PublicConfig } from '../../config';
import { deployPub } from '../../helpers/contracts-deployments'

/**
 *  借贷基础：存取借还业务初始化，包括：
 *  1. 设置oracle
 *  2. 增加币种市场
 *  3. 设置超额抵押系数、清算比例、清算收益系数
 */

task("full:PubLoanInitialize", "initialize ")
    .addFlag('verify', 'Verify contracts at Etherscan')
    .setAction(async ({ verify }, localDRE) => {
        localDRE.run('set-DRE')
        let currNetwork = localDRE.network.name
        let oracleIns = await getPriceOracleAggregator()
        let unitrollerIns = await getComptroller((await getUnitroller()).address)

        const { ReservesConfig, PriceOracleAggregator, ReserveAssets } = PublicConfig
        let reserves = Object.entries(ReservesConfig)
        // const reserveAssets = Object.entries(ReserveAssets[currNetwork])
        const oraclePrices = Object.entries(PriceOracleAggregator[currNetwork])
        // console.log('reserveAssets:',ReserveAssets[currNetwork]);
        // console.log('oraclePrices:',oraclePrices);

        //1. unitroller设置oracle
        if (currNetwork == 'hardhat') {
            let o = await getTestPriceOracle()
            await oracleIns.setPriceOracle(o.address)

            for (let [symbol, price] of oraclePrices) {
                let bprice = <BigNumber>price
                let decimal
                console.log(`${currNetwork} 设置${symbol},addr ${ReserveAssets[currNetwork][symbol]} 价格: ${price}`)

                if (symbol == "BUSD" || symbol == "DAI" || symbol == "UNI") {
                    decimal = 18
                } else if (symbol == "WBTC") {
                    decimal = 8
                } else if (symbol == "USDT") {
                    decimal = 6
                }
                console.log("decimal:", decimal);
                await o.setPrice(ReserveAssets[currNetwork][symbol], bprice.toString(), decimal)
            }
        } else {
            //对于真实的网络要配置价格种子，强哥提供，种子里面已经将每个币种的价格设置好了
            let seed = PriceOracleAggregator[currNetwork].ORACLESEED
            console.log('seed:', seed)
            // await oracleIns.setPriceOracle('0xD82aBeeD913fE077d6291DaA6bA989867492848a')
            await oracleIns.setPriceOracle(seed)
        }

        await unitrollerIns._setPriceOracle(oracleIns.address)
        console.log('unitrollerIns设置的oracle:'.yellow, await unitrollerIns.oracle());

        //2. unitroller设置清算奖励系数，表示清算人会额外获得到清算金额8%的收益
        await unitrollerIns._setLiquidationIncentive(createBigNumber18(1.08))

        //3. unitroller设置清算比例0.5，表示清算时会将抵押物的50%清算
        await unitrollerIns._setCloseFactor(createBigNumber18(0.5))
        let deployer = await getFirstSigner()

        //4. 部署平台币
        console.log('部署平台币')
        let pubIns = await deployPub(deployer.address, verify)
        await unitrollerIns.setPubAddress(pubIns.address)
        console.log(`Comptroller中PUB平台币: ${await unitrollerIns.getPubAddress()}`.yellow);

        //Comptroller中是没有平台币的，需要手动转币，交易挖矿，存取借还都有平台币奖励
        await pubIns.transfer(unitrollerIns.address, createBigNumber18(1000000))

        reserves = Object.entries(ReservesConfig)
        console.log("**************** 以下是对借贷进行初始化：增加市场，参数配置等***********")

        for (let [symbol, _] of reserves) {
            // const underlying = PublicConfig.ReserveAssets[localDRE.network.name][symbol]
            console.log(`********* 初始化: ${symbol} ************`.red.bold);

            //1. 获取pToken地址
            let pToken = await getPErc20Delegator(symbol)
            let token = await getStandardToken(symbol)
            console.log("underlying:", token.address);
            console.log("pToken :", pToken.address);

            //2. 添加markets
            console.log("添加到markets: _supportMarket");
            await unitrollerIns._supportMarket(pToken.address)

            //3. 设置平台币产生速率，参考链接：https://compound.finance/governance/proposals/35
            let speed = createBigNumber18(0.0195)

            console.log("unitroller设置compSpeed:", speed)
            unitrollerIns._setPubSpeed(pToken.address, speed)

            //4. 设置超额抵押率为0.8
            let collateralFactor_8 = new BigNumber(0.8).multipliedBy(oneEther).toFixed()
            console.log(`${symbol}设置抵押率setCollateralFactor:${collateralFactor_8} 0.8`.yellow);

            //可能报错：原因是对应币种的oracle价格未设置
            await unitrollerIns._setCollateralFactor(pToken.address, collateralFactor_8);
            console.log(`查看market[${symbol}]信息:`, (await unitrollerIns.markets(pToken.address)).toString());
        }

        console.log("********* 初始化结束 *********");
        console.log("借贷市场=> 所有supportMarktes:", await unitrollerIns.getAllMarkets());

    })