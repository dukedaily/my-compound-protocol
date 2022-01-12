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
import { oneRay, oneEther, createBigNumber18,trunkMatissa18, createBigNumber6, trunkMatissa6,ZERO_ADDRESS} from '../../helpers/constants'
import { deployMarginSwapPool, } from '../../helpers/contracts-deployments'

task("dev:usdtMSP-usdt", "test mint ")
    .addFlag('verify', 'Verify contracts at Etherscan')
    .setAction(async ({ verify }, localDRE) => {
        localDRE.run('set-DRE')
        let acc2 = await getAllAccounts(2)
        let acc4 = await getAllAccounts(4)

        console.log(" ************* 1.测试信用贷款:开仓(openposition) ************** ".green)
        //1. 获取msp
        console.log("1. 获取msp".green)
        let usdtMSP = await getMarginSwapPool(SupportTokens.USDT)
        let capital = await getCapital(SupportTokens.USDT)
        // let mspname = await usdtMSP.name()
        let mspname = "MSP-USDT";
        console.log(`${mspname}:${usdtMSP.address}`);

        //2. acc2开仓
        let usdt = await getStandardToken(SupportTokens.USDT)
        let uni = await getStandardToken(SupportTokens.UNI)
        await usdt.connect(acc4).approve(capital.address, createBigNumber6(10000000));

        let pUSDT = await getPErc20Delegator(SupportTokens.USDT)
        let pUNI = await getPErc20Delegator(SupportTokens.UNI)
        console.log(`开仓之前，${mspname}持有USDT数量: ${(await usdt.balanceOf(usdtMSP.address)).toString()}`.yellow);
        console.log(`开仓之前，acc4  持有USDT数量: ${(await usdt.balanceOf(acc4.address)).toString()}`.yellow);
        console.log(`开仓之前，pUSDT 持有USDT数量: ${(await usdt.balanceOf(pUSDT.address)).toString()}`.yellow);

        let UNIADDR = await pUNI.underlying()
        let USDTADDR = await pUSDT.underlying()
        console.log('UNIADDR:', UNIADDR);
        console.log('USDTADDR:', USDTADDR);
        
        let supplyAmt = createBigNumber6(100)
        console.log("授权成功,准备开仓, 用户提供本金:".yellow, trunkMatissa6(supplyAmt));
        await usdtMSP.connect(acc4).openPosition(supplyAmt, 17, UNIADDR, 3)

        let usdtBalance = await usdt.balanceOf(usdtMSP.address)
        let uniBalance = await uni.balanceOf(usdtMSP.address)
        let capiBalance = await uni.balanceOf(capital.address)
        console.log(`开仓之后，${mspname}持有USDT数量: ${usdtBalance.toString()}`.yellow);
        console.log(`开仓之后，${mspname}持有UNI数量: ${uniBalance.toString()}`.yellow);
        console.log(`开仓之后，${mspname} capital持有UNI数量: ${capiBalance.toString()}`.yellow);
        console.log(`开仓之后，acc4 持有USDT数量: ${(await usdt.balanceOf(acc4.address)).toString()}`.yellow);

        let r = await usdtMSP.connect(acc4).getAccountCurrRecordIds(acc4.address)
        console.log("r".yellow, r);

        let detailConfig = await usdtMSP.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        // msc.id,
        // msc.supplyInfo.supplyAmount,
        // msc.supplyInfo.pTokenAmount,
        // msc.acturallySwapAmount,
        // msc.pTokenSwapAmount
        console.log(`建仓之后, id: ${r[0]} detail: ${detailConfig}`)

        let addresses1 = await usdtMSP.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses1.toString()}`);

        for (let index = 0; index < addresses1.length; index++) {
            const element = addresses1[index];
            let detail = await usdtMSP.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情(未自动转换为pToken 约50倍):".green, detail.toString());
        }

        console.log(" ****** 再次建仓，执行加仓逻辑 ****** ".red.bold);
        await usdtMSP.connect(acc4).openPosition(supplyAmt, 17, UNIADDR, 3)

        usdtBalance = await usdt.balanceOf(usdtMSP.address)
        uniBalance = await uni.balanceOf(usdtMSP.address)
        console.log(`开仓之后，${mspname}持有USDT数量: ${usdtBalance.toString()}`.yellow);
        console.log(`开仓之后，${mspname}持有UNI数量: ${uniBalance.toString()}`.yellow);
        console.log(`开仓之后，acc4 持有USDT数量: ${(await usdt.balanceOf(acc4.address)).toString()}`.yellow);

        r = await usdtMSP.connect(acc4).getAccountCurrRecordIds(acc4.address)
        console.log("r".yellow, r);

        detailConfig = await usdtMSP.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        // msc.id,
        // msc.supplyInfo.supplyAmount,
        // msc.supplyInfo.pTokenAmount,
        // msc.acturallySwapAmount,
        // msc.pTokenSwapAmount
        console.log(`建仓之后, id: ${r[0]} detail: ${detailConfig}`)

        addresses1 = await usdtMSP.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses1.toString()}`);

        for (let index = 0; index < addresses1.length; index++) {
            const element = addresses1[index];
            let detail = await usdtMSP.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情(未自动转换为pToken 约50倍):".green, detail.toString());
        }

        console.log(`************** 杠杆交易：加仓 ***************`.red);
        console.log(`存${trunkMatissa6(supplyAmt)}个USDT, 2倍杠杆!`.green);

        // await usdtMSP.connect(acc4).morePosition(r[0], supplyAmt, 2, UNIADDR, 3)

        usdtBalance = await usdt.balanceOf(usdtMSP.address)
        uniBalance = await uni.balanceOf(usdtMSP.address)
        console.log(`加仓之后，${mspname}持有USDT数量: ${usdtBalance.toString()} UNI数量:${trunkMatissa6(uniBalance.toString())}`.yellow);

        let detailConfig1 = await usdtMSP.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        console.log(`加仓之后, detail: ${detailConfig1}`)

        console.log("************* 允许存款并转入 (enabledAndDoDeposit)****************".red);
        // let ret = await usdtMSP.connect(acc4).enabledAndDoDeposit(r[0])

        detailConfig1 = await usdtMSP.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        console.log(`enable转入资金池之后, detail: ${detailConfig1}`.green)

        let addresses = await usdtMSP.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await usdtMSP.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情(已经enable，自动转换为pToken 约50倍):".green, detail.toString());
        }

        uniBalance = await uni.balanceOf(usdtMSP.address)
        console.log(`enable后，UNI数量:${uniBalance.toString()}`.yellow);

        console.log("************* 追加保证金 (add)****************".red.bold);
        //两种
        await uni.connect(acc4).approve(capital.address, createBigNumber18(10000000));
        await usdtMSP.connect(acc4).addMargin(r[0], createBigNumber18(200), UNIADDR)
        
        console.log("!!!!!!!!!!!");
        
        await usdt.connect(acc4).approve(capital.address, createBigNumber6(10000000));
        console.log("账户4 usdt数量：",  (await usdt.balanceOf(acc4.address)).toString());
        await usdtMSP.connect(acc4).addMargin(r[0], createBigNumber6(400), USDTADDR)

        addresses = await usdtMSP.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);
        
        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await usdtMSP.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情(已经enable，自动转换为pToken 约50倍):", detail.toString());
        }
        
        console.log(`************** 杠杆交易：再次加仓 ***************`.red);
        console.log("现在已经打开自动存款开关了!".yellow.bold);

        console.log(`存${trunkMatissa6(supplyAmt)}个USDT, 2倍杠杆!`.green);

        // await usdtMSP.connect(acc4).morePosition(r[0], supplyAmt, 3, UNIADDR, 3)

        console.log("morePosition 成功!".blue.bold);
        // await usdt.connect(acc2).transferFrom(usdtMSP.address, acc2.address, usdtBalance.toString()) //从msp取busd

        usdtBalance = await usdt.balanceOf(usdtMSP.address)
        uniBalance = await uni.balanceOf(usdtMSP.address)
        console.log(`加仓之后，${mspname}持有USDT数量: ${trunkMatissa6(usdtBalance.toString())} UNI数量:${trunkMatissa18(uniBalance.toString())}`.blue.bold);

        detailConfig1 = await usdtMSP.connect(acc4).getAccountConfigDetail(acc4.address,r[0])
        // msc.id,
        // msc.supplyInfo.supplyAmount,
        // msc.supplyInfo.pTokenAmount,
        // msc.acturallySwapAmount,
        // msc.pTokenSwapAmount
        console.log(`加仓之后, detail: ${detailConfig1}`)

        console.log("当前风险值:".yellow.bold, (await usdtMSP.getRisk(acc4.address, r[0], ZERO_ADDRESS, 0)).toString(), "%");

        console.log(`************** 存入后 检查清算状态 ***************`.red);
        console.log(`---- 先修改价格!`);
        let o = await getTestPriceOracle()

        let oracleIns = await getPriceOracleAggregator()
        await oracleIns.setPriceOracle(o.address)

        await o.setPrice(uni.address, createBigNumber18(10), 18)

        let controller = await getController()
        console.log("controller:", controller.address);
        console.log("usdtMSP.address:", usdtMSP.address);
        console.log("r[0]:", r[0]);

        let res = await controller.getAccountLiquidity(acc4.address, usdtMSP.address, r[0],ZERO_ADDRESS,0)
        console.log("清算信息:", res.toString());

        console.log(`************** 转入后 开始偿还清算 ***************`.red);
        //acc4借款USDT，兑换UNI，UNI贬值，触发清算条件，
        //现在第三人acc2想执行清算: 首先偿还债务USDT(授权），然后获得UNI（pUNI）

        let b2 = await pUNI.balanceOf(acc2.address)
        console.log("清算前，pUNI acc2 balance:", b2.toString());
        await usdt.connect(acc2).approve(capital.address, createBigNumber6(10000000))
        // await usdtMSP.connect(acc2).liquidateBorrowedRepayFirst(acc4.address, uni.address, createBigNumber6(60), r[0] )
        
        console.log(`\n\n************** 清算后 检查清算状态 ***************`.red);
        res = await controller.getAccountLiquidity(acc4.address, usdtMSP.address, r[0],ZERO_ADDRESS,0)
        console.log("清算信息:", res.toString());
        
        addresses = await usdtMSP.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await usdtMSP.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情:".green, detail.toString());
        }

        b2 = await pUNI.balanceOf(acc2.address)
        console.log("清算后，pUNI acc2 balance:", b2.toString());
        
        console.log("************* 禁止存入并转出 (disabledAndDoWithdraw)****************".red.bold);
        // await usdtMSP.connect(acc4).disabledAndDoWithdraw(r[0])
        detailConfig1 = await usdtMSP.connect(acc4).getAccountConfigDetail(acc4.address,r[0])
        console.log(`disabledAndDoWithdraw之后详情detail, detail: ${detailConfig1}`.blue.bold)

        addresses = await usdtMSP.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await usdtMSP.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
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
        console.log("usdtMSP.address:", usdtMSP.address);
        console.log("r[0]:", r[0]);

        res = await controller.getAccountLiquidity(acc4.address, usdtMSP.address, r[0],ZERO_ADDRESS,0)
        console.log("清算信息:", res.toString());

        addresses = await usdtMSP.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await usdtMSP.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情:".green, detail.toString());
        }

        /*
        console.log("************* 还款 (repay)****************".red.bold);
        //当前欠款: 370
        usdt.connect(acc4).approve(capital.address, createBigNumber18(10000000))
        console.log("还款300个".yellow);
        await usdtMSP.connect(acc4).repay(r[0], createBigNumber18(300))
        let detailConfig2 = await usdtMSP.connect(acc4).getAccountConfigDetail(acc4.address,r[0])
        console.log(`还款 (repay)之后, detail: ${detailConfig2}`.blue.bold)
        addresses = await usdtMSP.connect(acc4).getBailAddress(acc4.address, r[0])

        usdtBalance = await usdt.balanceOf(usdtMSP.address)
        uniBalance = await uni.balanceOf(usdtMSP.address)
        console.log(`还款之后，${mspname}持有USDT数量: ${trunkMatissa18(usdtBalance.toString())} UNI数量:${trunkMatissa18(uniBalance.toString())}`.blue.bold);

        */
        addresses = await usdtMSP.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await usdtMSP.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情:".green, detail.toString());
        }

        console.log("************* 平仓操作 (closePosition)****************".red.bold);

        usdtBalance = await usdt.balanceOf(acc4.address)
        uniBalance = await uni.balanceOf(acc4.address)
        console.log(`平仓前acc4持有USDT：${usdtBalance}, UNI: ${uniBalance}`.green.bold);
        
        //平仓
        // await usdtMSP.connect(acc4).closePosition(r[0]) //TODO

        usdtBalance = await usdt.balanceOf(usdtMSP.address)
        uniBalance = await uni.balanceOf(usdtMSP.address)
        console.log(`平仓之后，${mspname}持有USDT数量: ${usdtBalance.toString()} UNI数量:${uniBalance.toString()}`.blue.bold);

        usdtBalance = await usdt.balanceOf(acc4.address)
        uniBalance = await uni.balanceOf(acc4.address)
        console.log(`平仓后acc4持有USDT：${usdtBalance}, UNI: ${uniBalance}`.green.bold);

        usdtBalance = await usdt.balanceOf(usdtMSP.address)
        uniBalance = await uni.balanceOf(usdtMSP.address)
        console.log(`平仓之后，${mspname}持有USDT数量: ${trunkMatissa6(usdtBalance.toString())} UNI数量:${trunkMatissa18(uniBalance.toString())}`.blue.bold);

        r = await usdtMSP.connect(acc4).getAccountCurrRecordIds(acc4.address)
        console.log(r.toString());
    })