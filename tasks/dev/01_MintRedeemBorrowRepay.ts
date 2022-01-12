import { task } from 'hardhat/config'
import {
    Overrides,
    CallOverrides,
} from "ethers";
import BigNumber from 'bignumber.js';
import {
    getPriceOracleAggregator,
    getPErc20Delegator,
    getComptroller,
    getUnitroller, getFirstSigner,
    getStandardToken, getTestPriceOracle, getPubMiningRateModelImpl, getAllAccounts, getPErc20DelegatorOption, getComptrollerOption, getStandardTokenOption, getPub
} from '../../helpers/contracts-getters'

import { PublicConfig } from '../../config';
import { SupportTokens, LoanType } from '../../helpers/types'
import { oneRay, oneEther, createBigNumber18, createBigNumber8, decimal8 } from '../../helpers/constants'

task("dev:mint-redeem-borrow-repay", "test mint ")
    .addFlag('verify', 'Verify contracts at Etherscan')
    .setAction(async ({ verify }, localDRE) => {
        localDRE.run('set-DRE')

        let acc0 = await getAllAccounts(0)
        let acc1 = await getAllAccounts(1)
        let acc2 = await getAllAccounts(2)
        let acc3 = await getAllAccounts(3)
        let acc4 = await getAllAccounts(4)
        let acc5 = await getAllAccounts(5)
        let acc6 = await getAllAccounts(6)
        console.log(`acc1: ${acc1.address}, acc2:${acc2.address}`)

        let oracleIns = await getPriceOracleAggregator()
        let unitrollerIns = await getComptroller((await getUnitroller()).address)

        // const { ReservesConfig, PriceOracleAggregator, ReserveAssets } = PublicConfig
        // let reserves = Object.entries(ReservesConfig)

        // for (let [symbol, _] of reserves) {

        //     //1. 获取pToken地址
        //     let pToken = await getPErc20Delegator(symbol)
        //     let token = await getStandardToken(symbol)
        //     console.log('token:', token.address)

        //     //a. acc0事先存入1000个BUSD
        //     let preDeposit = 1000000
        //     console.log(`acc0预先向'p${symbol}'中存入${preDeposit}`.yellow, symbol);
        //     console.log("acc0 balance: ".yellow, await token.balanceOf(acc0.address))

        //     await token.approve(pToken.address, createBigNumber18(preDeposit))
        //     console.log("allowance acc0:", (await token.allowance(acc0.address, pToken.address)).toString());
        //     console.log("acc0数量：".yellow, (await token.balanceOf(acc0.address)).toString());

        //     let tenThounsands: any
        //     //usdt精度是6，wbtc精度是8，这里统一使用8来简单处理
        //     if (symbol == "USDT" || symbol == "WBTC") {
        //         tenThounsands = createBigNumber8(preDeposit)
        //         //默认是account0向当前pToken存款，等价于：await pToken.connect(deployer).mint(createBigNumber8(preDeposit))
        //         await pToken.mint(createBigNumber8(preDeposit))
        //     } else {
        //         await pToken.mint(createBigNumber18(preDeposit))
        //         tenThounsands = createBigNumber18(preDeposit)
        //     }

        //     //3. 给每个地址转账，便于后续测试
        //     await token.connect(acc0).transfer(acc1.address, tenThounsands)
        //     await token.connect(acc0).transfer(acc2.address, tenThounsands)
        //     await token.connect(acc0).transfer(acc3.address, tenThounsands)
        //     await token.connect(acc0).transfer(acc4.address, tenThounsands)
        //     await token.connect(acc0).transfer(acc5.address, tenThounsands)
        //     await token.connect(acc0).transfer(acc6.address, tenThounsands)

        //     console.log(`acc0给acc1:${acc1.address}转${symbol}数量:${await token.balanceOf(acc1.address)} 1w`.yellow);
        //     console.log(`acc0给acc2:${acc2.address}转${symbol}数量:${await token.balanceOf(acc2.address)} 1w`.yellow);
        //     console.log(`acc0给acc3:${acc3.address}转${symbol}数量:${await token.balanceOf(acc3.address)} 1w`.yellow);
        //     console.log(`acc0给acc4:${acc4.address}转${symbol}数量:${await token.balanceOf(acc4.address)} 1w`.yellow);
        //     console.log(`acc0给acc5:${acc5.address}转${symbol}数量:${await token.balanceOf(acc5.address)} 1w`.yellow);
        //     console.log(`acc0给acc6:${acc6.address}转${symbol}数量:${await token.balanceOf(acc6.address)} 1w`.yellow);

        //     //3. approve
        //     let y = createBigNumber18(1000000000)
        //     await token.connect(acc0).approve(pToken.address, y)
        //     await token.connect(acc1).approve(pToken.address, y)
        //     await token.connect(acc2).approve(pToken.address, y)
        //     await token.connect(acc3).approve(pToken.address, y)
        //     await token.connect(acc4).approve(pToken.address, y)
        //     await token.connect(acc5).approve(pToken.address, y)
        //     await token.connect(acc6).approve(pToken.address, y)
        //     console.log(`acc0授权数量: ${await token.allowance(acc0.address, pToken.address)}`.yellow)
        //     console.log(`acc1授权数量: ${await token.allowance(acc1.address, pToken.address)}`.yellow)
        //     console.log(`acc2授权数量: ${await token.allowance(acc2.address, pToken.address)}`.yellow)
        //     console.log(`acc3授权数量: ${await token.allowance(acc3.address, pToken.address)}`.yellow)
        //     console.log(`acc4授权数量: ${await token.allowance(acc4.address, pToken.address)}`.yellow)
        //     console.log(`acc5授权数量: ${await token.allowance(acc5.address, pToken.address)}`.yellow)
        //     console.log(`acc6授权数量: ${await token.allowance(acc6.address, pToken.address)}`.yellow)

        //     //4. 查询价格
        //     let price = await oracleIns.getUnderlyingPrice(pToken.address)
        //     console.log(`${symbol}的价格为:`, price.toString());
        //     console.log("deployer(acc0)持有数量:", (await token.balanceOf(acc0.address)).toString());

        //     //设置平台币产生速率，参考链接：https://compound.finance/governance/proposals/35
        //     let speed = createBigNumber18(0.0195)

        //     console.log("unitroller设置compSpeed:", speed)
        //     unitrollerIns._setPubSpeed(pToken.address, speed)
        // }

        //背景：acc1, acc2 各持有1w个UNI和BUSD
        console.log(" ************* 1.测试存款mint ************** ".green)
        //1. 存取: acc1存入200个UNI，取回100个UNI
        let pUNI = await getPErc20Delegator(SupportTokens.UNI)
        let pBUSD = await getPErc20Delegator(SupportTokens.BUSD)

        //用户1存入UNI，借BUSD
        let r = await pUNI.connect(acc1).mint(createBigNumber18(400))
        //用户2存入BUSD
        r = await pBUSD.connect(acc2).mint(createBigNumber18(40000))

        let pUniBalance = await pUNI.balanceOf(acc1.address)
        console.log('acc1存款后pUniAmount:', pUniBalance.toString()); //1000000000000 , decimal : 8, 10000个

        let r1 = await pUNI.getAccountSnapshot(acc1.address, 0, LoanType.NORMAL)
        console.log("getAccountSnapshot:".green, r1.toString());

        //2. 取款
        console.log(" ************* 2. 测试取款redeem/redeemUnderlying ************** ".green)
        r = await pUNI.connect(acc1).redeemUnderlying(createBigNumber18(150))
        pUniBalance = await pUNI.balanceOf(acc1.address)
        console.log(`\n1. 按照underlying取款后剩余:${pUniBalance.toString()}`) //250000000000

        r = await pUNI.connect(acc1).redeem(createBigNumber8(10 * 50))
        pUniBalance = await pUNI.balanceOf(acc1.address)
        console.log(`\n2. 按照pToken取款后剩余:${pUniBalance.toString()}`) //200000000000

        //3. 借款：
        //b. acc1打开UNI抵押, 借款BUSD, comptroller 设置UNI抵押率 0.8, ok
        console.log(`acc1开启${pUNI.symbol()}抵押开关`);
        // let u = await getUnitroller()
        // let unitrollerIns = await getComptroller(u.address)
        await unitrollerIns.connect(acc1).enterMarkets([pUNI.address])
        console.log(acc1.address, " acc1已开启抵押:", await unitrollerIns.getAssetsIn(acc1.address));

        //c. 借款
        console.log("\n************* 4. 测试借款borrow ************** ")
        // let oracleIns = await getPriceOracleAggregator()
        let busdPrice = await oracleIns.getUnderlyingPrice(pBUSD.address)
        let uniPrice = await oracleIns.getUnderlyingPrice(pUNI.address)
        console.log(SupportTokens.BUSD, busdPrice[0].toString());
        console.log(SupportTokens.UNI, uniPrice[0].toString());

        let uniCash = await pUNI.getCash()
        console.log('uniCash', uniCash.toString());

        //200000000000, 当前存:40个UNI
        //UNI/BUSD
        // let aboutToBorrowMax = pUniBalance.div(decimal8.toString()).mul(uniPrice[0].div(busdPrice[0])).mul(8).div(10).div(times)
        let aboutToBorrowMax = 4416 //4416
        // console.log("aboutToBorrowMax:", aboutToBorrowMax.toString());

        // let aboutToBorrow = new 
        // let aboutToBorrow = 40 * 23 * 0.8 / 1 * 0.5
        let l = await unitrollerIns.getAccountLiquidity(acc1.address)
        console.log("getAccountLiquidity:".blue, l.toLocaleString());
        // console.log("aboutToBorrowMax:", aboutToBorrowMax.toString());

        let busd = await getStandardToken(SupportTokens.BUSD)
        let busdBalance = await busd.balanceOf(acc1.address)
        console.log(`acc1借款前，持有BUSD数量:${busdBalance.toString()}`.yellow)

        r = await pBUSD.connect(acc1).borrow(createBigNumber18(aboutToBorrowMax))

        busdBalance = await busd.balanceOf(acc1.address)
        console.log(`acc1借款后，持有BUSD数量:${busdBalance.toString()}`.yellow)

        console.log("aac1存款BUSD".green)
        await pBUSD.connect(acc2).mint(createBigNumber18(1000))

        l = await unitrollerIns.getAccountLiquidity(acc1.address)
        console.log("借款后getAccountLiquidity:".blue, l.toLocaleString());
        let borrowCurr = await pUNI.borrowBalanceCurrent(acc1.address, 0, LoanType.NORMAL)

        let l1 = await pUNI.getAccountSnapshot(acc1.address, 1, LoanType.NORMAL)
        console.log("getAccountSnapshot:", l1.toString());

        //d. 还款
        console.log("\n************* 4. 测试还款repay ************** ")
        await pBUSD.connect(acc1).repayBorrow(createBigNumber18(3000))
        busdBalance = await busd.balanceOf(acc1.address)
        console.log(`acc1还款后，持有BUSD数量:${busdBalance.toString()}`.yellow)

        let collateralTokens = await unitrollerIns.getAssetsIn(acc1.address)
        console.log("acc1 打开质押开关的有:", collateralTokens);

        l = await unitrollerIns.getAccountLiquidity(acc1.address)
        console.log("getAccountLiquidity:".blue, l.toLocaleString());

        l = await unitrollerIns.getAccountLiquidity(acc1.address)
        console.log("getAccountLiquidity:".blue, l.toLocaleString());

        busdBalance = await busd.balanceOf(acc1.address)
        console.log(`acc1存款后，持有BUSD数量:${busdBalance.toString()}`.yellow)

        // let pubConunt = await unitrollerIns.getUnclaimedPub(acc1.address)
        // console.log("acc1 pubConunt:", pubConunt.toString());

        // pubConunt = await unitrollerIns.getUnclaimedPub(acc2.address)
        // console.log("acc2 pubConunt:", pubConunt.toString());

        // await unitrollerIns.connect(acc1).claimPubV1(acc1.address)

        let pubIns = await getPub()
        console.log("acc1获取平台币数量：".green, (await pubIns.balanceOf(acc1.address)).toString())
    })