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
    getStandardToken, getTestPriceOracle, getAllAccounts, getPErc20DelegatorOption, getComptrollerOption, getStandardTokenOption
} from '../../helpers/contracts-getters'

import { SupportTokens, LoanType } from '../../helpers/types'
import { oneRay, oneEther, createBigNumber18, createBigNumber8, decimal8 } from '../../helpers/constants'

task("dev:creditloan", "test mint ")
    .addFlag('verify', 'Verify contracts at Etherscan')
    .setAction(async ({ verify }, localDRE) => {
        localDRE.run('set-DRE')
        let acc0 = await getAllAccounts(0)
        let acc1 = await getAllAccounts(1)
        let acc2 = await getAllAccounts(2)
        let acc3 = await getAllAccounts(3)
        let acc4 = await getAllAccounts(4)
        console.log(`acc1: ${acc1.address}, acc2:${acc2.address}`)

        let idMock  = 0;

        //背景：acc1, acc2 各持有1w个UNI和BUSD
        console.log(" ************* 1.测试信用贷款(doCreditLoanBorrow) ************** ".yellow)
        //1. 向资产BUSD添加白名单
        let pBUSD = await getPErc20Delegator(SupportTokens.BUSD)
        await pBUSD.setWhiteList(acc3.address, true)
        console.log(`acc3 是否添加: ${await pBUSD.whiteList(acc3.address)}`.green)
        console.log(`acc4 是否添加: ${await pBUSD.whiteList(acc4.address)}`.green)

        //2. acc3借款(从未抵押)
        console.log("pBUSD当前持有数量:".yellow, (await pBUSD.getCash()).toString())
        let busd = await getStandardToken(SupportTokens.BUSD)

        //未接先还会失败!
        // await busd.connect(acc3).approve(pBUSD.address, createBigNumber18(100))
        // await pBUSD.connect(acc3).doCreditLoanRepay(acc3.address, createBigNumber18(100), idMock, LoanType.MARGIN_SWAP_PROTOCOL)

        console.log("信用贷之前，acc3 BUSD数量:", (await busd.balanceOf(acc3.address)).toString());

        let r = await pBUSD.connect(acc3).doCreditLoanBorrow(acc3.address, createBigNumber18(1000), idMock, LoanType.MINNING_SWAP_PROTOCOL)
        // console.log(r);
        console.log("信用贷之后，acc3 BUSD数量:", (await busd.balanceOf(acc3.address)).toString());

        r = await pBUSD.connect(acc3).doCreditLoanBorrow(acc3.address, createBigNumber18(1000), idMock, LoanType.MINNING_SWAP_PROTOCOL)
        // console.log(r);
        console.log("信用贷之后，acc3 BUSD数量:", (await busd.balanceOf(acc3.address)).toString());

        let v = await pBUSD.connect(acc3).borrowBalanceStored(acc3.address, 0, LoanType.MINNING_SWAP_PROTOCOL)
        console.log("acc3信用贷接口信息(本息）：", v.toString());

        console.log(" ************* 2.测试信用贷款(doCreditLoanRepay) ************** ".yellow)
        //现授权
        await busd.connect(acc3).approve(pBUSD.address, createBigNumber18(100))
        await pBUSD.connect(acc3).doCreditLoanRepay(acc3.address, createBigNumber18(100), idMock, LoanType.MINNING_SWAP_PROTOCOL)
        // console.log(x, y);

        v = await pBUSD.connect(acc3).borrowBalanceStored(acc3.address, 0, LoanType.MINNING_SWAP_PROTOCOL)
        console.log("acc3信用贷接口信息(本息）：", v.toString());

        console.log("信用贷还款之后，acc3 BUSD数量:", (await busd.balanceOf(acc3.address)).toString());
    })