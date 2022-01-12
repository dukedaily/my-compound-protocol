import { task } from 'hardhat/config'
import {
    getPErc20Delegator,
    getStandardToken,
    getAllAccounts,
    getCapital
} from '../../helpers/contracts-getters'
import { SupportTokens } from '../../helpers/types'

task("dev:marginswap-creditloan", "test mint ")
    .addFlag('verify', 'Verify contracts at Etherscan')
    .setAction(async ({ verify }, localDRE) => {
        localDRE.run('set-DRE')
        let acc0 = await getAllAccounts(0)
        let acc1 = await getAllAccounts(1)
        let acc2 = await getAllAccounts(2)
        let acc3 = await getAllAccounts(3)
        let acc4 = await getAllAccounts(4)
        console.log(`acc1: ${acc1.address}, acc2:${acc2.address}`)

        //背景：acc1, acc2 各持有1w个UNI和BUSD
        console.log(" ************* 1.测试信用贷款:借款(capital::doCreditLoanBorrow) ************** ".green)
        // let capital = await getMarginSwapPool(SupportTokens.BUSD)
        let capital = await getCapital(SupportTokens.BUSD)

        //2. 向资产PBUSD添加白名单
        console.log("2. 向资产PBUSD添加白名单".green)
        let pBUSD = await getPErc20Delegator(SupportTokens.BUSD)
        await pBUSD.setWhiteList(capital.address, true)

        // let capitalname = await capital.name()
        let capitalname = "capital-BUSD";
        console.log(`${capitalname} 是否添加: ${await pBUSD.whiteList(capital.address)}`.green)
        console.log(`acc4 是否添加: ${await pBUSD.whiteList(acc4.address)}`.green)

        //3. 借款(从未抵押)
        console.log("3. 借款(从未抵押)".green)
        console.log("pBUSD当前持有BUSD数量:".yellow, (await pBUSD.getCash()).toString())

        let busd = await getStandardToken(SupportTokens.BUSD)
        console.log(`信用贷之前，${capitalname}持有BUSD数量: ${(await busd.balanceOf(capital.address)).toString()}`.yellow);

        console.log("4. 为capital设置ptoken:".green, pBUSD.address)
        // await capital.setUnderlyPTokenAddress(pBUSD.address)

        let borrowAmnt = 10
        let repayAmnt = 3
        console.log(`5. 执行信用贷，准备借${borrowAmnt}`.green)
        // let r = await capital.connect(acc3).doCreditLoanBorrowInternal(createBigNumber18(borrowAmnt))
        // console.log(r);

        console.log(`信用贷之后，${capitalname}持有BUSD数量: ${(await busd.balanceOf(capital.address)).toString()}`.yellow);
        console.log(`信用贷之后，${acc3.address}持有BUSD数量: ${(await busd.balanceOf(acc3.address)).toString()}`.yellow);

        console.log(" ************* 2.测试信用贷款:还款(capital::doCreditLoanRepay) ************** ".yellow)
        console.log("需要capital给PToken合约授权".yellow);
        // await busd.approve(capital.address, createBigNumber18(50))

        console.log("准备信用贷还款");
        //capital是BUSD的capital
        // await capital.connect(acc3).doCreditLoanRepayInternal(acc3.address,createBigNumber18(repayAmnt))
        console.log(`信用贷还款${repayAmnt}个之后，${capitalname}持有BUSD数量: ${(await busd.balanceOf(capital.address)).toString()}`.yellow);
        console.log("信用贷还款之后，acc3 BUSD数量:", (await busd.balanceOf(acc3.address)).toString());
    })