import { task } from 'hardhat/config'

task("deploy:lending", "Deploy compound protocol on kovan")
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

        console.log("\n\n === 任务 6: 初始化pToken市场（full:PubLoanInitialize） ===".red.bold);
        await DRE.run("full:PubLoanInitialize", { verify });
    })