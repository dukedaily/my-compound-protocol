pragma solidity ^0.5.16;
import "../../EIP20Interface.sol";
import "../../IPublicsLoanInterface.sol";
import "../../PriceOracleAggregator.sol";
import "./IMSPInterface.sol";
import "./ITXAggregator.sol";

contract ControllerStorage {
    //支持的资产
    mapping(address => bool) public supplyTokenWhiteList;
    //swapToken whitelist
    mapping(address => bool) public swapTokenWhiteList;
    //token=>pToken
    mapping(address => address) assetToPTokenList;
    //保证金白名单
    mapping(address => bool) public bailTokenWhiteList;
    //杠杆倍数
    struct Leverage {
        uint256 leverageMin;
        uint256 leverageMax;
    }
    mapping(address => Leverage) leverage;
    //保证金种类上限
    uint8 public bailTypeMax;

    //清算相关
    mapping(address => uint256) public collateralFactorMantissaContainer; //token质押率 0.8
    //清算比例 100%
    uint256 public closeFactorMantissa;
    //清算收益1.08
    uint256 public liquidationIncentiveMantissa;
    // 0.9 //抵押物质量，0 - 0.9之间
    uint256 internal constant collateralFactorMaxMantissa = 0.9e18;
    //预言机
    PriceOracleAggregator public oracle;
    //ITXAggregator
    ITXAggregator public txAggregator;
    //所有msp集合
    IMSPInterface[] public allMspMarkets;
    //暂停市场
    address public pauseGuardian;
    mapping(address => bool) public openGuardianPaused;
    //直接清算开关
    bool directlyLiquidationState = false;
    //清算人（直接清算)收益比例
    uint256 public liquidatorRatioMantissa = 0.8e18;
    //清算人（直接清算)收益比例最大值
    uint256 internal constant liquidatorRatioMaxMantissa = 1e18;
}

contract IControllerInterface {
    //是否允许兑换
    function isSwapTokenAllowed(address _token) public view returns (bool);

    //获取pToken
    function getPToken(address _token) public view returns (address);

    //是否允许当做保证金
    function isBailTokenAllowed(address _token, uint256 _currentNum) public view returns (bool);

    //获取聚合交易
    function getTxAggregator() public view returns (ITXAggregator);

    //获取杠杆倍数
    function getLeverage(address _msp) public view returns (uint256 _min, uint256 _max);

    //获取oracle
    function getOracle() public view returns (PriceOracleAggregator);

    //检查清算状态
    function getAccountLiquidity(
        address _account,
        IMSPInterface _msp,
        uint256 _id,
        address _supplyToken,
        uint256 _supplyAmnt
    )
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        );

    //是否允许清算
    function liquidateBorrowAllowed(
        address msp,
        address pTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 repayAmount,
        uint256 _id
    ) public view returns (uint256);

    //清算人可获取数量
    function liquidateCalculateSeizeTokens(
        address pTokenBorrowed,
        address pTokenCollateral,
        uint256 actualRepayAmount,
        bool isAutoSupply
    ) external view returns (uint256, uint256);

    //直接清算获取利益
    function seizeBenifit(uint256 borrowBalance) external view returns (uint256);

    //是否允许开仓
    function openPositionAllowed(address _msp) external returns (uint256);

    //是否允许赎回
    function redeemAllowed(
        address _redeemer,
        IMSPInterface _msp,
        uint256 _id,
        address _modifyToken,
        uint256 _redeemTokens
    ) public view returns (uint256);

    //是否允许直接清算
    function isDirectlyLiquidationAllowed() public view returns (bool);

    //清算人（直接清算)收益
    function benifitToLiquidator(uint256 _benifts) external view returns (uint256);
}
