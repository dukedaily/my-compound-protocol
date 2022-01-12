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
    getLiquidation,
    getPub,
} from '../../helpers/contracts-getters'

import { SupportTokens, LoanType} from '../../helpers/types'
import { oneRay, oneEther, createBigNumber18, trunkMatissa18, createBigNumber8, decimal8, ZERO_ADDRESS } from '../../helpers/constants'
import { deployMarginSwapPool, } from '../../helpers/contracts-deployments'

task("dev:mint-borrow-credit-pub", "test mint ")
    .addFlag('verify', 'Verify contracts at Etherscan')
    .setAction(async ({ verify }, localDRE) => {
        localDRE.run('set-DRE')
        let acc2 = await getAllAccounts(2)
        let acc3 = await getAllAccounts(3)
        let acc4 = await getAllAccounts(4)

        let pBUSD = await getPErc20Delegator(SupportTokens.BUSD)
        let pUNI = await getPErc20Delegator(SupportTokens.UNI)
        let pDAI = await getPErc20Delegator(SupportTokens.DAI)

        let BUSDADDR = await pBUSD.underlying()
        let UNIADDR = await pUNI.underlying()
        let DAIADDR = await pDAI.underlying()

        await pUNI.connect(acc4).mint(createBigNumber18(400))
        //用户2存入BUSD
        await pBUSD.connect(acc2).mint(createBigNumber18(40000))

        let pUniBalance = await pUNI.balanceOf(acc4.address)
        console.log('acc4存款后pUniAmount:', pUniBalance.toString()); //1000000000000 , decimal : 8, 10000个

        let m = await pUNI.getAccountSnapshot(acc4.address, 0, LoanType.NORMAL)
        console.log("getAccountSnapshot:".green, m.toString());

        //2. 取款
        console.log(" ************* 2. 测试取款redeem/redeemUnderlying ************** ".green)
        await pUNI.connect(acc4).redeemUnderlying(createBigNumber18(150))
        pUniBalance = await pUNI.balanceOf(acc4.address)
        console.log(`\n1. 按照underlying取款后剩余:${pUniBalance.toString()}`) //250000000000

        await pUNI.connect(acc4).redeem(createBigNumber8(10 * 50))
        pUniBalance = await pUNI.balanceOf(acc4.address)
        console.log(`\n2. 按照pToken取款后剩余:${pUniBalance.toString()}`) //200000000000

        //3. 借款：
        //b. acc4打开UNI抵押, 借款BUSD, comptroller 设置UNI抵押率 0.8, ok
        console.log(`acc4开启${pUNI.symbol()}抵押开关`);
        let u1 = await getUnitroller()
        let unitrollerIns0 = await getComptroller(u1.address)
        await unitrollerIns0.connect(acc4).enterMarkets([pUNI.address])
        console.log(acc4.address, " acc4已开启抵押:", await unitrollerIns0.getAssetsIn(acc4.address));

        //c. 借款
        console.log("\n************* 4. 测试借款borrow ************** ")
        let oracleIns0 = await getPriceOracleAggregator()
        let busdPrice = await oracleIns0.getUnderlyingPrice(pBUSD.address)
        let uniPrice = await oracleIns0.getUnderlyingPrice(pUNI.address)
        console.log(SupportTokens.BUSD, busdPrice[0].toString());
        console.log(SupportTokens.UNI, uniPrice[0].toString());

        let uniCash = await pUNI.getCash()
        console.log('uniCash', uniCash.toString());

        let aboutToBorrowMax = 4416 //4416

        let l = await unitrollerIns0.getAccountLiquidity(acc4.address)
        console.log("getAccountLiquidity:".blue, l.toLocaleString());
        // console.log("aboutToBorrowMax:", aboutToBorrowMax.toString());

        let busd0 = await getStandardToken(SupportTokens.BUSD)
        let busdBalance0 = await busd0.balanceOf(acc4.address)
        console.log(`acc4借款前，持有BUSD数量:${busdBalance0.toString()}`.yellow)

        await pBUSD.connect(acc4).borrow(createBigNumber18(aboutToBorrowMax))

        busdBalance0 = await busd0.balanceOf(acc4.address)
        console.log(`acc4借款后，持有BUSD数量:${busdBalance0.toString()}`.yellow)

        console.log("aac1存款BUSD".green)
        await pBUSD.connect(acc2).mint(createBigNumber18(1000))

        l = await unitrollerIns0.getAccountLiquidity(acc4.address)
        console.log("借款后getAccountLiquidity:".blue, l.toLocaleString());
        let borrowCurr = await pUNI.borrowBalanceCurrent(acc4.address, 0, LoanType.NORMAL)

        let l1 = await pUNI.getAccountSnapshot(acc4.address, 1, LoanType.NORMAL)
        console.log("getAccountSnapshot:", l1.toString());

        //d. 还款
        console.log("\n************* 4. 测试还款repay ************** ")
        await pBUSD.connect(acc4).repayBorrow(createBigNumber18(3000))
        busdBalance0 = await busd0.balanceOf(acc4.address)
        console.log(`acc4还款后，持有BUSD数量:${busdBalance0.toString()}`.yellow)

        let collateralTokens = await unitrollerIns0.getAssetsIn(acc4.address)
        console.log("acc4 打开质押开关的有:", collateralTokens);

        l = await unitrollerIns0.getAccountLiquidity(acc4.address)
        console.log("getAccountLiquidity:".blue, l.toLocaleString());

        l = await unitrollerIns0.getAccountLiquidity(acc4.address)
        console.log("getAccountLiquidity:".blue, l.toLocaleString());

        busdBalance0 = await busd0.balanceOf(acc4.address)
        console.log(`acc4存款后，持有BUSD数量:${busdBalance0.toString()}`.yellow)

        let pubConunt0 = await unitrollerIns0.getUnclaimedPub(acc4.address, LoanType.NORMAL)
        console.log("acc4 pubConunt:".yellow, pubConunt0.toString());

        pubConunt0 = await unitrollerIns0.getUnclaimedPub(acc2.address, LoanType.NORMAL)
        console.log("acc2 pubConunt:", pubConunt0.toString());

        await unitrollerIns0.connect(acc4).claimPubV1(acc4.address, LoanType.NORMAL)

        let pubIns = await getPub()
        console.log("acc4获取平台币数量：".green, (await pubIns.balanceOf(acc4.address)).toString())

        //背景：acc1, acc2 各持有1w个UNI和BUSD
        console.log(" ************* 1.测试信用贷款:开仓(openposition) ************** ".green)
        let repayAll = new BigNumber('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff', 16)
        // let repayAll = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        console.log('repayAll:', repayAll.toFixed())

        //1. 获取msp
        console.log("1. 获取msp".green)
        let msp = await getMarginSwapPool(SupportTokens.BUSD)
        let capital = await getCapital(SupportTokens.BUSD)
        // let mspname = await msp.mspstorage.name()
        let mspname = "MSPBUSD"
        console.log(`${mspname}:${msp.address}`);

        //2. acc2开仓
        let busd = await getStandardToken(SupportTokens.BUSD)
        let uni = await getStandardToken(SupportTokens.UNI)

        //设置白名单， 重要 //TODO
        await pUNI.setWhiteList(capital.address, true)

        console.log("第一步：对Capital授权".yellow);
        let x = await busd.connect(acc4).approve(capital.address, createBigNumber18(10000000));
        x = await busd.connect(acc3).approve(capital.address, createBigNumber18(10000000));
        x = await busd.connect(acc2).approve(capital.address, createBigNumber18(10000000));
        // console.log(await x.wait());

        console.log(`开仓之前，${mspname}持有BUSD数量: ${(await busd.balanceOf(capital.address)).toString()}`.yellow);
        console.log(`开仓之前，acc4  持有BUSD数量: ${(await busd.balanceOf(acc4.address)).toString()}`.yellow);
        console.log(`开仓之前，pBUSD 持有BUSD数量: ${(await busd.balanceOf(pBUSD.address)).toString()}`.yellow);

        console.log("_setOpenPositionPaused!".red.bold);

        let controller = await getController()
        console.log("controller:", controller.address);
        console.log("msp.address:", msp.address);

        let supplyAmt = createBigNumber18(100)
        await controller._setOpenPositionPaused(msp.address, false);
        console.log("授权成功,准备开仓, 用户提供本金:".yellow, trunkMatissa18(supplyAmt), "当前是unpasued状态".green);

        let ret1 = await msp.connect(acc4).openPosition(supplyAmt, 17, UNIADDR, 3) //TODO
        await msp.connect(acc2).openPosition(supplyAmt, 17, UNIADDR, 3) //TODO
        await msp.connect(acc4).openPosition(supplyAmt, 17, UNIADDR, 3) //TODO

        let r1 = await msp.connect(acc4).getAccountCurrRecordIds(acc4.address)
        console.log("r1:", r1);

        let snapshot1 = await pBUSD.getAccountSnapshot(acc4.address, r1[0], 1);
        console.log(`captial:${capital.address}, snapshot: ${snapshot1.toString()} 兑换后持有数量：`, (await uni.balanceOf(capital.address)).toString())

        let busdBalance = await busd.balanceOf(capital.address)
        let uniBalance = await uni.balanceOf(capital.address)
        console.log(`开仓之后，${mspname} capital 持有BUSD数量: ${busdBalance.toString()}`.yellow);
        console.log(`开仓之后，${mspname} capital 持有UNI数量: ${uniBalance.toString()}`.yellow);
        console.log(`开仓之后，acc4 持有BUSD数量: ${(await busd.balanceOf(acc4.address)).toString()}`.yellow);

        let r = await msp.connect(acc4).getAccountCurrRecordIds(acc4.address)
        console.log("r".yellow, r);

        let detailConfig = await msp.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        // let detailConfig = await msp.connect(acc4).getAccountConfigDetail(acc4.address, 2) //无效ID测试
        // msc.id,
        // msc.supplyInfo.supplyAmount,
        // msc.supplyInfo.pTokenAmount,
        // msc.acturallySwapAmount,
        // msc.pTokenSwapAmount
        console.log(`建仓之后, id: ${r[0]} detail: ${detailConfig}`)

        pubConunt0 = await unitrollerIns0.getUnclaimedPub(acc4.address, LoanType.MARGIN_SWAP_PROTOCOL)
        console.log("仅开仓之后，acc4 pubConunt:".yellow, pubConunt0.toString())

        console.log("从钱包还款，为了测试acc4的平台币获取情况!");
        let rx1 = await msp.getBondTokens(acc4.address, r[0])
        console.log("所有保证金详情:".yellow, rx1.toString());

        // await msp.connect(acc4).repayFromWallet(r[0], BUSDADDR, repayAll.toFixed(), 100)
        uni.connect(acc4).approve(capital.address, createBigNumber18(10000000))
        await msp.connect(acc4).repayFromWallet(r[0], BUSDADDR, createBigNumber18(500), 10)

        pubConunt0 = await unitrollerIns0.getUnclaimedPub(acc4.address, LoanType.MARGIN_SWAP_PROTOCOL)
        console.log("开仓&还款之后，acc4 pubConunt:".yellow, pubConunt0.toString())

        // console.log("disabledAndDoWithdraw".yellow);
        // await msp.connect(acc4).disabledAndDoWithdraw(r[0])
        await msp.connect(acc4).enabledAndDoDeposit(r[0])

        rx1 = await msp.getBondTokens(acc4.address, r[0])
        console.log("所有保证金详情:".yellow, rx1.toString());

        pubConunt0 = await unitrollerIns0.getUnclaimedPub(acc4.address, LoanType.MARGIN_SWAP_PROTOCOL)
        console.log("enabledAndDoDeposit之后pubConunt:".yellow, pubConunt0.toString())

        console.log(" ****** 再次建仓，执行加仓逻辑 ****** ".red.bold);
        ret1 = await msp.connect(acc4).openPosition(supplyAmt, 17, UNIADDR, 3) //TODO

        busdBalance = await busd.balanceOf(capital.address)
        uniBalance = await uni.balanceOf(capital.address)
        console.log(`开仓之后，${mspname} capital 持有BUSD数量: ${busdBalance.toString()}`.yellow);
        console.log(`开仓之后，${mspname} capital 持有UNI数量: ${uniBalance.toString()}`.yellow);
        console.log(`开仓之后，acc4 持有BUSD数量: ${(await busd.balanceOf(acc4.address)).toString()}`.yellow);

        r = await msp.connect(acc4).getAccountCurrRecordIds(acc4.address)
        console.log("acc4 ids:".yellow, r.toString());
        detailConfig = await msp.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        console.log(`建仓之后, id: ${r[0]} detail: ${detailConfig}`)

        let rx = await msp.getBondTokens(acc4.address, r[0])
        console.log("所有保证金详情:".yellow, rx.toString());

        console.log("换一个人进行开仓: acc3开仓");
        ret1 = await msp.connect(acc3).openPosition(supplyAmt, 17, UNIADDR, 3) //TODO
        console.log("acc3加仓");
        ret1 = await msp.connect(acc3).openPosition(supplyAmt, 17, UNIADDR, 3) //TODO

        let acc3RecordIds = await msp.connect(acc3).getAccountCurrRecordIds(acc3.address)
        console.log("acc3 ids:".yellow, acc3RecordIds.toString());
        detailConfig = await msp.connect(acc3).getAccountConfigDetail(acc3.address, acc3RecordIds[0])
        console.log(`acc3建仓之后, id: ${r[0]} detail: ${detailConfig}`)

        console.log("acc4再次加仓!");
        await msp.connect(acc4).openPosition(supplyAmt, 17, UNIADDR, 3) //TODO

        r = await msp.connect(acc4).getAccountCurrRecordIds(acc4.address)
        console.log("acc4 ids:".yellow, r.toString());
        detailConfig = await msp.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        console.log(`acc4加仓后, id: ${r[0]} detail: ${detailConfig}`)

        console.log("acc4开仓DAI新币种");
        await msp.connect(acc4).openPosition(supplyAmt, 17, DAIADDR, 3) //TODO
        r = await msp.connect(acc4).getAccountCurrRecordIds(acc4.address)
        console.log("acc4 ids:".yellow, r.toString());
        detailConfig = await msp.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        console.log(`acc4开仓DAI之后, id: ${r[0]} detail: ${detailConfig}`)

        console.log("************* 追加保证金 (add)****************".red.bold);
        await uni.connect(acc4).approve(capital.address, createBigNumber18(10000000));
        await msp.connect(acc4).addMargin(r[0], createBigNumber18(200), UNIADDR)

        await busd.connect(acc4).approve(capital.address, createBigNumber18(10000000));
        await msp.connect(acc4).addMargin(r[0], createBigNumber18(400), BUSDADDR)

        let addresses2 = await msp.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses2.toString()}`.yellow);

        for (let index = 0; index < addresses2.length; index++) {
            const element = addresses2[index];
            let detail = await msp.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情(已经enable，自动转换为pToken 约50倍):", detail.toString());
        }

        let u = await getUnitroller()
        let unitrollerIns = await getComptroller(u.address)

        let pubConunt = await unitrollerIns.getUnclaimedPub(capital.address, LoanType.MARGIN_SWAP_PROTOCOL)
        console.log("capital pubConunt:".blue, pubConunt.toString());

        rx = await msp.getBondTokens(acc4.address, r[0])
        console.log("所有保证金详情:".red, rx.toString());

        console.log(`************** 检查清算状态 ***************`.red);
        console.log(`---- 先修改价格!`);
        console.log("检查Controller.oracle:", await controller.oracle());
        
        let o1 = await getTestPriceOracle()
        console.log("IAssetPrice:", o1.address);

        let oracleIns1 = await getPriceOracleAggregator()
        await oracleIns1.setPriceOracle(o1.address)
        await o1.setPrice(uni.address, createBigNumber18(4), 18)

        // let res1 = await controller.getAccountLiquidity(acc4.address, msp.address, r[0], ZERO_ADDRESS,0)
        // console.log("清算信息:", res1.toString());

        console.log(`************** 转入后 开始直接清算(liquidateBorrowedDirectly) ***************`.green);
        let liquidation_busd = await getLiquidation(SupportTokens.BUSD)
        // await liquidation_busd.connect(acc2).liquidateBorrowedDirectly(acc4.address, r[0], 10)

        busdBalance = await busd.balanceOf(capital.address)
        uniBalance = await uni.balanceOf(capital.address)
        console.log(`当前状态，${mspname} capital 持有BUSD数量: ${trunkMatissa18(busdBalance.toString())} UNI数量:${trunkMatissa18(uniBalance.toString())}`.blue.bold);

        // await msp.connect(acc4).repayFromWallet(r[0], BUSDADDR, repayAll.toFixed(), 100)
        await msp.connect(acc4).repayFromWallet(r[0], UNIADDR, createBigNumber18(100), 100)

        console.log(`************ 杠杆交易：尝试加仓 ***************`.red);
        console.log(`存${trunkMatissa18(supplyAmt)}个BUSD, 2倍杠杆!`.green);
        await msp.connect(acc4).openPosition(supplyAmt, 20, UNIADDR, 3)

        console.log(`************** 存入后(enabledAndDoDeposit) 检查清算状态 ***************`.red);
        let res = await controller.getAccountLiquidity(acc4.address, msp.address, r[0], ZERO_ADDRESS, 0)
        console.log("清算信息:", res.toString());

        console.log("************* 允许存款并转入 (enabledAndDoDeposit)****************".red);

        let detailConfig1 = await msp.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        console.log(`enable转入资金池之后, detail: ${detailConfig1}`.green)

        let addresses = await msp.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await msp.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情(已经enable，自动转换为pToken 约50倍):".green, detail.toString());
        }

        r = await msp.connect(acc4).getAccountCurrRecordIds(acc4.address)
        let snapshotX = await pBUSD.getAccountSnapshot(acc4.address, r[0], 1);
        console.log("id:", r.toString(), "before snapshotX:".yellow, snapshotX.toString())


        console.log("************* 保证金还款RepayFromMargin ****************".red);
        addresses = await msp.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await msp.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情(已经enable，自动转换为pToken 约50倍):".green, detail.toString());
        }
        ret1 = await msp.connect(acc4).repayFromMargin(r[0], UNIADDR, createBigNumber18(6.5), 0)
        // function repayFromMargin(uint256 _id, address _bailToken, uint256 _amount, uint256 _slippageTolerance) public re

        r = await msp.connect(acc4).getAccountCurrRecordIds(acc4.address)
        snapshotX = await pBUSD.getAccountSnapshot(acc4.address, r[0], 1);
        console.log("id:", r.toString(), "after snapshotX:".yellow, snapshotX.toString())

        console.log("************* 平仓操作 (closePosition)****************".red.bold);
        let detailConfig0 = await msp.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        console.log("当前持仓情况：", detailConfig0.toString());

        busdBalance = await busd.balanceOf(acc4.address)
        uniBalance = await uni.balanceOf(acc4.address)
        console.log(`平仓前acc4持有BUSD：${busdBalance}, UNI: ${uniBalance}`.green.bold);

        //平仓 删除id，后续无法测试
        // await msp.connect(acc4).closePosition(r[0]) //TODO
        console.log('r[0]:', r[0]);

        busdBalance = await busd.balanceOf(acc4.address)
        uniBalance = await uni.balanceOf(acc4.address)
        console.log(`平仓后acc4持有BUSD：${busdBalance}, UNI: ${uniBalance}`.green.bold);

        busdBalance = await busd.balanceOf(capital.address)
        uniBalance = await uni.balanceOf(capital.address)
        console.log(`平仓之后，${mspname} capital 持有BUSD数量: ${trunkMatissa18(busdBalance.toString())} UNI数量:${trunkMatissa18(uniBalance.toString())}`.blue.bold);

        r = await msp.connect(acc4).getAccountCurrRecordIds(acc4.address)
        console.log("acc4当前所有持仓id:".yellow, r.toString());

        console.log(`************ 杠杆交易：加仓 ***************`.red);
        console.log(`存${trunkMatissa18(supplyAmt)}个BUSD, 2倍杠杆!`.green);

        await msp.connect(acc4).openPosition(supplyAmt, 20, UNIADDR, 3)

        busdBalance = await busd.balanceOf(capital.address)
        uniBalance = await uni.balanceOf(capital.address)
        console.log(`加仓之后，${mspname}持有BUSD数量: ${busdBalance.toString()} UNI数量:${trunkMatissa18(uniBalance.toString())}`.yellow);

        detailConfig1 = await msp.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        console.log(`加仓之后, detail: ${detailConfig1}`)

        uniBalance = await uni.balanceOf(capital.address)
        console.log(`enable后，UNI数量:${uniBalance.toString()}`.yellow);


        console.log("************* 加仓(openPosition)****************".red.bold);
        await msp.connect(acc4).openPosition(supplyAmt, 30, UNIADDR, 3)
        console.log("morePosition(openPosition) 成功!".blue.bold);

        console.log("测试风险值变化!");
        console.log("之前:".yellow, (await msp.getRisk(acc4.address, r[0], ZERO_ADDRESS, 0)).toString(), "%");
        console.log("之后:".yellow, (await msp.getRisk(acc4.address, r[0], DAIADDR, createBigNumber18(20))).toString(), "%");
        

        console.log(`************** 杠杆交易：提取保证金(redeemMargin) ***************`.red);
        console.log("提取前，当前风险值:".yellow, (await msp.getRisk(acc4.address, r[0], ZERO_ADDRESS, 0)).toString(), "%");
        await msp.connect(acc4).redeemMargin(r[0], createBigNumber18(140), UNIADDR)
        console.log(`当前保证金地址: ${addresses.toString()}`.yellow);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await msp.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情(已经enable，自动转换为pToken 约50倍):", detail.toString());
        }

        console.log("提取后，当前风险值:".yellow, (await msp.getRisk(acc4.address, r[0], ZERO_ADDRESS, 0)).toString(), "%");

        console.log("1111 检查Controller.oracle:", await controller.oracle());

        console.log("2222 检查Controller.oracle:", await controller.oracle());
        console.log(`************** 杠杆交易：再次加仓 ***************`.red);
        console.log("现在已经打开自动存款开关了!".yellow.bold);

        console.log(`存${trunkMatissa18(supplyAmt)}个BUSD, 3倍杠杆!`.green);

        await msp.connect(acc4).openPosition(supplyAmt, 30, UNIADDR, 3)
        console.log("morePosition(openPosition) 成功!".blue.bold);

        busdBalance = await busd.balanceOf(capital.address)
        uniBalance = await uni.balanceOf(capital.address)
        console.log(`加仓之后，${mspname}持有BUSD数量: ${trunkMatissa18(busdBalance.toString())} UNI数量:${trunkMatissa18(uniBalance.toString())}`.blue.bold);

        detailConfig1 = await msp.connect(acc4).getAccountConfigDetail(acc4.address, r[0])

        addresses = await msp.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await msp.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情(已经enable，自动转换为pToken 约50倍):", detail.toString());
        }
        // msc.id,
        // msc.supplyInfo.supplyAmount,
        // msc.supplyInfo.pTokenAmount,
        // msc.acturallySwapAmount,
        // msc.pTokenSwapAmount
        console.log(`加仓之后, detail: ${detailConfig1}`)


        console.log(`************** 转入后 开始偿还清算 ***************`.red);
        //acc4借款BUSD，兑换UNI，UNI贬值，触发清算条件，
        //现在第三人acc2想执行清算: 首先偿还债务BUSD(授权），然后获得UNI（pUNI）

        let b2 = await pUNI.balanceOf(acc2.address)
        console.log("清算前，pUNI acc2 balance:", b2.toString());
        await busd.connect(acc2).approve(capital.address, createBigNumber18(10000000))

        liquidation_busd = await getLiquidation(SupportTokens.BUSD)
        await liquidation_busd.connect(acc2).liquidateBorrowedRepayFirst(acc4.address, uni.address, createBigNumber18(60), r[0])

        console.log(`\n\n************** 清算后 检查清算状态 ***************`.red);
        res = await controller.getAccountLiquidity(acc4.address, msp.address, r[0], ZERO_ADDRESS, 0)
        console.log("清算信息:", res.toString());

        addresses = await msp.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await msp.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情:".green, detail.toString());
        }

        b2 = await pUNI.balanceOf(acc2.address)
        console.log("清算后，pUNI acc2 balance:", b2.toString());

        console.log("************* 禁止存入并转出 (disabledAndDoWithdraw)****************".red.bold);
        // await msp.connect(acc4).disabledAndDoWithdraw(r[0])
        detailConfig1 = await msp.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        console.log(`disabledAndDoWithdraw之后详情detail, detail: ${detailConfig1}`.blue.bold)

        addresses = await msp.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await msp.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情:".green, detail.toString());
        }

        console.log(`************** 转出后 检查清算状态 ***************`.red);
        console.log(`---- 先修改价格!`);
        let o = await getTestPriceOracle()

        let oracleIns = await getPriceOracleAggregator()
        await oracleIns.setPriceOracle(o.address)

        await o.setPrice(uni.address, createBigNumber18(12), 18)

        controller = await getController()
        console.log("controller:", controller.address);
        console.log("0000 检查Controller.oracle:", await controller.oracle());
        console.log("msp.address:", msp.address);
        console.log("r[0]:", r[0].toString());

        res = await controller.getAccountLiquidity(acc4.address, msp.address, r[0], ZERO_ADDRESS, 0)
        console.log("清算信息:", res.toString());

        addresses = await msp.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await msp.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情:".green, detail.toString());
        }

        console.log("************* 钱包还款(repayFromWallet)****************".red.bold);
        //当前欠款: 370
        busd.connect(acc4).approve(capital.address, createBigNumber18(10000000))
        console.log("还款300个:".yellow, -1);
        // await msp.connect(acc4).repay(r[0], createBigNumber18(300))
        await msp.connect(acc4).repayFromWallet(r[0], BUSDADDR, repayAll.toFixed(), 100)
        let detailConfig2 = await msp.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        console.log(`还款 (repay)之后, detail: ${detailConfig2}`.blue.bold)
        addresses = await msp.connect(acc4).getBailAddress(acc4.address, r[0])

        busdBalance = await busd.balanceOf(capital.address)
        uniBalance = await uni.balanceOf(capital.address)
        console.log(`还款之后，${mspname}持有BUSD数量: ${trunkMatissa18(busdBalance.toString())} UNI数量:${trunkMatissa18(uniBalance.toString())}`.blue.bold);

        addresses = await msp.connect(acc4).getBailAddress(acc4.address, r[0])
        console.log(`当前保证金地址: ${addresses.toString()}`);

        for (let index = 0; index < addresses.length; index++) {
            const element = addresses[index];
            let detail = await msp.connect(acc4).getBailConfigDetail(acc4.address, r[0], element)
            console.log("保证金详情:".green, detail.toString());
        }

        console.log("************* 平仓操作 (closePosition)****************".red.bold);
        detailConfig2 = await msp.connect(acc4).getAccountConfigDetail(acc4.address, r[0])
        console.log("当前持仓情况：", detailConfig2.toString());

        busdBalance = await busd.balanceOf(acc4.address)
        uniBalance = await uni.balanceOf(acc4.address)
        console.log(`平仓前acc4持有BUSD：${busdBalance}, UNI: ${uniBalance}`.green.bold);

        //平仓
        await msp.connect(acc4).closePosition(r[0]) //TODO

        busdBalance = await busd.balanceOf(acc4.address)
        uniBalance = await uni.balanceOf(acc4.address)
        console.log(`平仓后acc4持有BUSD：${busdBalance}, UNI: ${uniBalance}`.green.bold);

        busdBalance = await busd.balanceOf(capital.address)
        uniBalance = await uni.balanceOf(capital.address)
        console.log(`平仓之后，${mspname}持有BUSD数量: ${trunkMatissa18(busdBalance.toString())} UNI数量:${trunkMatissa18(uniBalance.toString())}`.blue.bold);

        r = await msp.connect(acc4).getAccountCurrRecordIds(acc4.address)
        console.log("acc4当前所有持仓id:".yellow, r.toString());

        console.log("************** 平仓之后再次建仓测试 ****************!".green.bold)
        await controller._setOpenPositionPaused(msp.address, false);

        ret1 = await msp.connect(acc4).openPosition(supplyAmt, 17, UNIADDR, 3)
        r = await msp.connect(acc4).getAccountCurrRecordIds(acc4.address)
        let snapshot = await pBUSD.getAccountSnapshot(acc4.address, r[0], 1);
        console.log("id:", r.toString(), "snapshot:".yellow, snapshot.toString());

        ret1 = await msp.connect(acc4).openPosition(supplyAmt, 17, DAIADDR, 3)
        r = await msp.connect(acc4).getAccountCurrRecordIds(acc4.address)
        snapshot = await pBUSD.getAccountSnapshot(acc4.address, r[1], 1);
        console.log("id:", r.toString(), "snapshot:".yellow, snapshot.toString());

        console.log("创建MSPUNI!".green.bold);
        let MSPUNI = await getMarginSwapPool(SupportTokens.UNI)

        let capital_uni = await getCapital(SupportTokens.UNI)
        await uni.connect(acc4).approve(capital_uni.address, createBigNumber18(10000000))

        ret1 = await MSPUNI.connect(acc4).openPosition(supplyAmt, 21, BUSDADDR, 3)
        r = await MSPUNI.connect(acc4).getAccountCurrRecordIds(acc4.address)
        snapshot = await pUNI.getAccountSnapshot(acc4.address, r[0], 1);
        console.log("id:", r.toString(), "snapshot:".yellow, snapshot.toString());

        ret1 = await MSPUNI.connect(acc4).openPosition(supplyAmt, 11, DAIADDR, 3)
        r = await MSPUNI.connect(acc4).getAccountCurrRecordIds(acc4.address)
        snapshot = await pUNI.getAccountSnapshot(acc4.address, r[1], 1);
        console.log("id:", r.toString(), "snapshot:".yellow, snapshot.toString());

        pubConunt = await unitrollerIns.getUnclaimedPub(acc4.address, LoanType.MARGIN_SWAP_PROTOCOL)
        console.log("acc4 getUnclaimedPub pubConunt:".yellow, pubConunt.toString());

        console.log("acc4 before claimPubV1 pUniAmount：".green, (await pubIns.balanceOf(acc4.address)).toString())

        await unitrollerIns0.connect(acc4).claimPubV1(acc4.address, LoanType.MARGIN_SWAP_PROTOCOL)

        console.log("acc4 after claimPubV1 pUniAmount：".green, (await pubIns.balanceOf(acc4.address)).toString())
    })