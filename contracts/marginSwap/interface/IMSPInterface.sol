pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;
import "../../EIP20Interface.sol";
import "./IStorageInterface.sol";
import "./ICapitalInterface.sol";
import "./IControllerInterface.sol";

contract IMSPInterface {
    uint256 BASE10 = 10;
    bool _notEntered = true;
    bool public constant isMSP = true;

    // IStorageInterface public mspstorage;
    IControllerInterface public controller;
    ICapitalInterface public capital;

    address public assetUnderlying;
    address public pTokenUnderlying;
    string public assetUnderlyingSymbol;
    string public mspName;

    //建仓
    function openPosition(
        uint256 _supplyAmount,
        uint256 _leverage,
        EIP20Interface _swapToken,
        uint256 _amountOutMin
    ) public;

    // // 一键平仓，保留
    // function closePositionForce(uint256 _id) public returns (uint256);
    // event ClosePositionEvent(uint256 _id, uint256 _needToPay, uint256 _backToAccountAmt);

    // 平仓
    function closePosition(uint256 _id) public;

    //追加保证金
    function addMargin(
        uint256 _id,
        uint256 _amount,
        address _bailToken
    ) public;

    //提取保证金
    function redeemMargin(
        uint256 _id,
        uint256 _amount,
        address _modifyToken
    ) public;

    //钱包还款
    function repayFromWallet(uint256 _id, address _repayToken, uint256 _repayAmount, uint256 _amountOutMin) public returns (uint256, uint256);
    //临时
    function repay(uint256 _id, uint256 _repayAmount) public returns (uint256, uint256);

    //保证金还款
    function repayFromMargin(
        uint256 _id,
        address _bailToken,
        uint256 _amount,
        uint256 _amountOutMin
    ) public returns (uint256);

    //允许存款并转入
    function enabledAndDoDeposit(uint256 _id) public;

    //禁止存入并转出
    function disabledAndDoWithdraw(uint256 _id) public;

    //获取风险值
    function getRisk(address _account, uint256 _id, address _supplyToken, uint256 _supplyAmnt) public view returns (uint256);

    //获取当前所有持仓id
    function getAccountCurrRecordIds(address _account) public view returns (uint256[] memory);

    //获取开仓信息
    function getAccountConfigDetail(address _account, uint256 _id)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            address,
            uint256,
            bool,
            bool
        );

    //获取保证金地址
    function getBailAddress(address _account, uint256 _id) public view returns (address[] memory);

    //获取保证金详情
    function getBailConfigDetail(
        address _account,
        uint256 _id,
        address _bailToken
    )
        public
        view
        returns (
            string memory,
            uint256,
            uint256
        );

    function updateController() public;
}
