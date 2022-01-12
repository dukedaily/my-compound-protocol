import { task } from 'hardhat/config'

task("dev:msp", "Deploy compound protocol on kovan")
    .addFlag('verify', 'Verify contracts at Etherscan')
    .setAction(async ({ verify }, DRE) => {
        console.log("verify:", verify);
        let network = DRE.network.name

        console.log("\n\n === 任务 0: 部署支持市场（deploy underlying assets）===".red.bold);
        await DRE.run("full:deploy-new-assets", { verify })

        console.log("\n\n === 任务 1: 部署平台币经济模型（deploy pubMiningRateModel) ===".red.bold);
        await DRE.run("full:deploy-pubMiningRateModel", { verify })

        console.log("\n\n === 任务 2: 部署代理控制器（deploy full:deploy-unitroller) ===".red.bold);
        await DRE.run("full:deploy-unitroller", { verify })

        console.log("\n\n === 任务 3: 部署控制器implementation（run full:deploy-comptroller） ===".red.bold);
        await DRE.run("full:deploy-comptroller", { verify });

        console.log("\n\n === 任务 4: 部署oracle聚合器（run full:deploy-oracle） ===".red.bold);
        await DRE.run("full:deploy-oracle", { verify });

        console.log("\n\n === 任务 5: 部署pToken（full:deploy-PERC20Delegator） ===".red.bold);
        await DRE.run("full:deploy-PERC20Delegator", { verify });

        console.log("\n\n === 任务 6: 初始化借贷市场（full:PubLoanInitialize） ===".red.bold);
        await DRE.run("full:PubLoanInitialize", { verify });

        console.log("\n\n === 任务 7: 初始化杠杆交易市场（full:PubMspInitialize ===".red.bold);
        await DRE.run("full:PubMspInitialize", { verify });

        await DRE.run("dev:initialize", { verify });

        console.log("\n === step 8: run dev:creditloan ===".red.bold);
        await DRE.run("dev:creditloan", { verify });

        console.log("\n\n === step 9: run dev:marginswap-creditloan ===".red.bold);
        await DRE.run("dev:marginswap-creditloan", { verify });

        console.log("\n\n === step 10: run dev:msp-open ===".red.bold);
        await DRE.run("dev:msp-open", { verify });

        /*
        console.log("\n\n === step 11: 测试开仓还款后平台币增长情况 ===".red.bold);
        await DRE.run("dev:mint-borrow-credit-pub", { verify });

        console.log("\n\n === step 11: run dev:usdtMSP-usdt ===".red.bold);
        await DRE.run("dev:usdtMSP-usdt", { verify });

        console.log("\n\n === step 12: run dev:wbtcMSP-wbtc ===".red.bold);
        await DRE.run("dev:wbtcMSP-wbtc", { verify });
        */
    })