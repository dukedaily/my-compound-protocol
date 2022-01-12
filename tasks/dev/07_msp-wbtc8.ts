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
    getStandardToken, getTestPriceOracle,
    getAllAccounts,
    getMarginSwapPool,
    getController,
    getCapital,
} from '../../helpers/contracts-getters'

import { SupportTokens } from '../../helpers/types'
import { oneRay, oneEther, createBigNumber18, trunkMatissa18, createBigNumber8, trunkMatissa8, ZERO_ADDRESS } from '../../helpers/constants'
import { deployMarginSwapPool, } from '../../helpers/contracts-deployments'

task("dev:wbtcMSP-wbtc", "test mint ")
    .addFlag('verify', 'Verify contracts at Etherscan')
    .setAction(async ({ verify }, localDRE) => {
        localDRE.run('set-DRE')
        let acc2 = await getAllAccounts(2)
        let acc4 = await getAllAccounts(4)

        console.log(" ************* 1.测试信用贷款:开仓(openposition) ************** ".green)
        //1. 获取msp
        console.log("1. 获取msp".green)
        let wbtcMSP = await getMarginSwapPool(SupportTokens.WBTC)
        let capital = await getCapital(SupportTokens.WBTC)
        // let mspname = await wbtcMSP.name()
        let mspname = "MSP-WBTC"
        console.log(`${mspname}:${wbtcMSP.address}`);

        //2. acc2开仓
        let wbtc = await getStandardToken(SupportTokens.WBTC)
        let uni = await getStandardToken(SupportTokens.UNI)
        await wbtc.connect(acc4).approve(capital.address, createBigNumber8(10000000));

        let pWBTC = await getPErc20Delegator(SupportTokens.WBTC)
        let pUNI = await getPErc20Delegator(SupportTokens.UNI)
        console.log(`开仓之前，${mspname}持有WBTC数量: ${(await wbtc.balanceOf(capital.address)).toString()}`.yellow);
        console.log(`开仓之前，acc4  持有WBTC数量: ${(await wbtc.balanceOf(acc4.address)).toString()}`.yellow);
        console.log(`开仓之前，pWBTC 持有WBTC数量: ${(await wbtc.balanceOf(pWBTC.address)).toString()}`.yellow);

        let UNIADDR = await pUNI.underlying()
        let WBTCADDR = await pWBTC.underlying()
        console.log('UNIADDR:', UNIADDR);
        console.log('WBTCADDR:', WBTCADDR);

        let supplyAmt = createBigNumber8(100)
        console.log("授权成功,准备开仓, 用户提供本金:".yellow, trunkMatissa8(supplyAmt));
        await wbtcMSP.connect(acc4).openPosition(supplyAmt, 17, UNIADDR, 3)

        let wbtcBalance = await wbtc.balanceOf(capital.address)
        let uniBalance = await uni.balanceOf(capital.address)
        console.log(`开仓之后，${mspname}持有WBTC数量: ${wbtcBalance.toString()}`.yellow);
        console.log(`开仓之后，${mspname}持有UNI数量: ${uniBalance.toString()}`.yellow);
        console.log(`开仓之后，acc4 持有WBTC数量: ${(await wbtc.balanceOf(acc4.address)).toString()}`.yellow);

        let r = await wbtcMSP.connect(acc4).getAccountCurrRecordIds(acc4.address)
        console.log("r".yellow, r);

        let detailConfig = await wbtcMSP.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        // msc.id,
        // msc.supplyInfo.supplyAmount,
        // msc.supplyInfo.pTokenAmount,
        // msc.acturallySwapAmount,
        // msc.pTokenSwapAmount
        console.log(`建仓之后, id: ${r[0]} detail: ${detailConfig}`)

        let addresses1 = await wbtcMSP.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses1.toString()}`);

        for (let index = 0; index < addresses1.length; index++) {
            const element = addresses1[index];
            let detail = await wbtcMSP.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情(未自动转换为pToken 约50倍):".green, detail.toString());
        }

        console.log(" ****** 再次建仓，执行加仓逻辑 ****** ".red.bold);
        await wbtcMSP.connect(acc4).openPosition(supplyAmt, 17, UNIADDR, 3)

        wbtcBalance = await wbtc.balanceOf(capital.address)
        uniBalance = await uni.balanceOf(capital.address)
        console.log(`开仓之后，${mspname}持有WBTC数量: ${wbtcBalance.toString()}`.yellow);
        console.log(`开仓之后，${mspname}持有UNI数量: ${uniBalance.toString()}`.yellow);
        console.log(`开仓之后，acc4 持有WBTC数量: ${(await wbtc.balanceOf(acc4.address)).toString()}`.yellow);

        r = await wbtcMSP.connect(acc4).getAccountCurrRecordIds(acc4.address)
        console.log("r".yellow, r);

        detailConfig = await wbtcMSP.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        // msc.id,
        // msc.supplyInfo.supplyAmount,
        // msc.supplyInfo.pTokenAmount,
        // msc.acturallySwapAmount,
        // msc.pTokenSwapAmount
        console.log(`建仓之后, id: ${r[0]} detail: ${detailConfig}`)

        addresses1 = await wbtcMSP.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses1.toString()}`);

        for (let index = 0; index < addresses1.length; index++) {
            const element = addresses1[index];
            let detail = await wbtcMSP.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情(未自动转换为pToken 约50倍):".green, detail.toString());
        }

        console.log(`************** 杠杆交易：加仓 ***************`.red);
        console.log(`存${trunkMatissa8(supplyAmt)}个WBTC, 2倍杠杆!`.green);

        // await wbtcMSP.connect(acc4).morePosition(r[0], supplyAmt, 2, UNIADDR, 3)

        wbtcBalance = await wbtc.balanceOf(capital.address)
        uniBalance = await uni.balanceOf(capital.address)
        console.log(`加仓之后，${mspname}持有WBTC数量: ${wbtcBalance.toString()} UNI数量:${trunkMatissa8(uniBalance.toString())}`.yellow);

        let detailConfig1 = await wbtcMSP.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        console.log(`加仓之后, detail: ${detailConfig1}`)

        console.log("************* 允许存款并转入 (enabledAndDoDeposit)****************".red);
        // let ret = await wbtcMSP.connect(acc4).enabledAndDoDeposit(r[0])

        detailConfig1 = await wbtcMSP.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        console.log(`enable转入资金池之后, detail: ${detailConfig1}`.green)

        let addresses = await wbtcMSP.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await wbtcMSP.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情(已经enable，自动转换为pToken 约50倍):".green, detail.toString());
        }

        uniBalance = await uni.balanceOf(capital.address)
        console.log(`enable后，UNI数量:${uniBalance.toString()}`.yellow);

        console.log("************* 追加保证金 (add)****************".red.bold);
        //两种
        await uni.connect(acc4).approve(capital.address, createBigNumber18(10000000));
        // await wbtcMSP.connect(acc4).addMargin(r[0], createBigNumber18(200), UNIADDR)

        console.log("!!!!!!!!!!!");

        await wbtc.connect(acc4).approve(capital.address, createBigNumber8(10000000));
        console.log("账户4 wbtc数量：", (await wbtc.balanceOf(acc4.address)).toString());
        await wbtcMSP.connect(acc4).addMargin(r[0], createBigNumber8(400), WBTCADDR)

        addresses = await wbtcMSP.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await wbtcMSP.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情(已经enable，自动转换为pToken 约50倍):", detail.toString());
        }

        console.log(`************** 杠杆交易：再次加仓 ***************`.red);
        console.log("现在已经打开自动存款开关了!".yellow.bold);

        console.log(`存${trunkMatissa8(supplyAmt)}个WBTC, 2倍杠杆!`.green);
        // console.log("acc2第三次扮演dex角色向msp转入UNI:", 8695652173913043478)
        // await uni.connect(acc2).transfer(wbtcMSP.address, createBigNumber18(8.695652173913043000)) //给msp转uni
        // await uni.connect(acc2).transfer(wbtcMSP.address, createBigNumber18(0.000000000000000478)) //给msp转uni

        // await wbtcMSP.connect(acc4).morePosition(r[0], supplyAmt, 3, UNIADDR, 3)

        console.log("morePosition 成功!".blue.bold);
        // await wbtc.connect(acc2).transferFrom(wbtcMSP.address, acc2.address, wbtcBalance.toString()) //从msp取busd

        wbtcBalance = await wbtc.balanceOf(capital.address)
        uniBalance = await uni.balanceOf(capital.address)
        console.log(`加仓之后，${mspname}持有WBTC数量: ${trunkMatissa8(wbtcBalance.toString())} UNI数量:${trunkMatissa18(uniBalance.toString())}`.blue.bold);

        detailConfig1 = await wbtcMSP.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        // msc.id,
        // msc.supplyInfo.supplyAmount,
        // msc.supplyInfo.pTokenAmount,
        // msc.acturallySwapAmount,
        // msc.pTokenSwapAmount
        console.log(`加仓之后, detail: ${detailConfig1}`)

        console.log(`************** 存入后 检查清算状态 ***************`.red);
        console.log(`---- 先修改价格!`);
        let o = await getTestPriceOracle()

        let oracleIns = await getPriceOracleAggregator()
        await oracleIns.setPriceOracle(o.address)

        await o.setPrice(uni.address, createBigNumber18(10), 18)

        let controller = await getController()
        console.log("controller:", controller.address);
        console.log("wbtcMSP.address:", wbtcMSP.address);
        console.log("r[0]:", r[0]);

        let res = await controller.getAccountLiquidity(acc4.address, wbtcMSP.address, r[0], ZERO_ADDRESS, 0)
        console.log("清算信息:", res.toString());

        console.log(`************** 转入后 开始偿还清算 ***************`.red);
        //acc4借款WBTC，兑换UNI，UNI贬值，触发清算条件，
        //现在第三人acc2想执行清算: 首先偿还债务WBTC(授权），然后获得UNI（pUNI）

        let b2 = await pUNI.balanceOf(acc2.address)
        console.log("清算前，pUNI acc2 balance:", b2.toString());
        await wbtc.connect(acc2).approve(capital.address, createBigNumber8(10000000))
        // await wbtcMSP.connect(acc2).liquidateBorrowedRepayFirst(acc4.address, uni.address, createBigNumber8(60), r[0] )

        console.log(`\n\n************** 清算后 检查清算状态 ***************`.red);
        res = await controller.getAccountLiquidity(acc4.address, wbtcMSP.address, r[0], ZERO_ADDRESS, 0)
        console.log("清算信息:", res.toString());

        addresses = await wbtcMSP.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await wbtcMSP.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情:".green, detail.toString());
        }

        b2 = await pUNI.balanceOf(acc2.address)
        console.log("清算后，pUNI acc2 balance:", b2.toString());

        console.log("************* 禁止存入并转出 (disabledAndDoWithdraw)****************".red.bold);
        // await wbtcMSP.connect(acc4).disabledAndDoWithdraw(r[0])
        detailConfig1 = await wbtcMSP.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        console.log(`disabledAndDoWithdraw之后详情detail, detail: ${detailConfig1}`.blue.bold)

        addresses = await wbtcMSP.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await wbtcMSP.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情:".green, detail.toString());
        }

        console.log(`************** 转出后 检查清算状态 ***************`.red);
        console.log(`---- 先修改价格!`);
        o = await getTestPriceOracle()

        oracleIns = await getPriceOracleAggregator()
        await oracleIns.setPriceOracle(o.address)

        await o.setPrice(uni.address, createBigNumber18(10), 18)

        controller = await getController()
        console.log("controller:", controller.address);
        console.log("wbtcMSP.address:", wbtcMSP.address);
        console.log("r[0]:", r[0]);

        res = await controller.getAccountLiquidity(acc4.address, wbtcMSP.address, r[0], ZERO_ADDRESS, 0)
        console.log("清算信息:", res.toString());

        addresses = await wbtcMSP.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await wbtcMSP.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情:".green, detail.toString());
        }

        console.log("************* 还款 (repay)****************".red.bold);
        //当前欠款: 370
        wbtc.connect(acc4).approve(capital.address, createBigNumber8(10000000))
        console.log("还款300个".yellow);
         await wbtcMSP.connect(acc4).repayFromWallet(r[0], WBTCADDR, createBigNumber8(100), 100)
        let detailConfig2 = await wbtcMSP.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        console.log(`还款 (repay)之后, detail: ${detailConfig2}`.blue.bold)
        addresses = await wbtcMSP.connect(acc4).getBailAddress(acc4.address, r[0])

        wbtcBalance = await wbtc.balanceOf(capital.address)
        uniBalance = await uni.balanceOf(capital.address)
        console.log(`还款之后，${mspname}持有WBTC数量: ${trunkMatissa8(wbtcBalance.toString())} UNI数量:${trunkMatissa18(uniBalance.toString())}`.blue.bold);

        addresses = await wbtcMSP.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await wbtcMSP.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情:".green, detail.toString());
        }

        console.log("************* 平仓操作 (closePosition)****************".red.bold);

        wbtcBalance = await wbtc.balanceOf(acc4.address)
        uniBalance = await uni.balanceOf(acc4.address)
        console.log(`平仓前acc4持有WBTC：${wbtcBalance}, UNI: ${uniBalance}`.green.bold);

        //平仓
        // await wbtcMSP.connect(acc4).closePosition(r[0]) //TODO

        wbtcBalance = await wbtc.balanceOf(capital.address)
        uniBalance = await uni.balanceOf(capital.address)
        console.log(`平仓之后，${mspname}持有WBTC数量: ${wbtcBalance.toString()} UNI数量:${uniBalance.toString()}`.blue.bold);

        wbtcBalance = await wbtc.balanceOf(acc4.address)
        uniBalance = await uni.balanceOf(acc4.address)
        console.log(`平仓后acc4持有WBTC：${wbtcBalance}, UNI: ${uniBalance}`.green.bold);

        wbtcBalance = await wbtc.balanceOf(capital.address)
        uniBalance = await uni.balanceOf(capital.address)
        console.log(`平仓之后，${mspname}持有WBTC数量: ${trunkMatissa8(wbtcBalance.toString())} UNI数量:${trunkMatissa18(uniBalance.toString())}`.blue.bold);

        r = await wbtcMSP.connect(acc4).getAccountCurrRecordIds(acc4.address)
        console.log(r.toString());
    })