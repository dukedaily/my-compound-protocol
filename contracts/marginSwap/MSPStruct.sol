pragma solidity ^0.5.16;
import "../EIP20Interface.sol";

contract Operation {
    enum OperationType {
        //开仓
        OPEN_POSITION,
        //加仓
        MORE_POSITION,
        //一键提取
        CLOSE_POSITION,
        //增加保证金
        ADD_MARGIN,
        //赎回保证金
        REDEEM_MARGIN,
        //从钱包还款
        REPAY_FROM_WALLET,
        //从保证金还款
        REPAY_FROM_MARGIN,
        //存入借贷市场
        ENABLE_AND_DEPOSIT,
        //从借贷市场取出
        DISABLE_AND_WITHDRAW,
        //直接清算
        LIQUIDATIOIN_DIRECTLY,
        //偿还清算
        LIQUIDATIOIN_REPAY
    }
}

contract MSPStruct {
    /*************** 保证金相关 ****************/
    //保证金结构
    struct supplyConfig {
        string symbol;
        //保证金币种
        address supplyToken;
        //保证金数量
        uint256 supplyAmount;
        //兑换成pToken数量
        uint256 pTokenAmount;
    }

    struct BailConfig {
        mapping(address => supplyConfig) bailCfgContainer;
        address[] accountBailAddresses; //[USDTAddr, BUSDAddr]
    }

    /*************** 持仓结构相关 ****************/
    struct MSPConfig {
        //symbol1+symbol2组合
        string uniqueName;
        //持仓ID
        uint256 id;
        //本金数量
        uint256 supplyAmount;
        //杠杆倍数
        uint256 leverage;
        //借款数量
        uint256 borrowAmount;
        //兑换目标Token
        EIP20Interface swapToken; //存入保证金结构时，变成supplyToken
        //实际兑换数量
        uint256 actuallySwapAmount;
        //滑点
        uint256 amountOutMin;
        //是否自动存入资金池
        bool isAutoSupply;
        //当前记录是否存在
        bool isExist;
        //是否冻结
        bool isFreeze;
    }

    struct MarginSwapConfig {
        //所有建仓结构： 张三=>id=>配置
        mapping(address => mapping(uint256 => MSPConfig)) accountMspRecords;
        mapping(address => uint256[]) accountCurrentRecordIds;
    }
}
