pragma solidity ^0.5.16;

import "./PTokenInterfaces.sol";

contract IPublicsLoanInterface is LoanTypeBase {
    /**
     *@notice 获取依赖资产地址
     *@return (address): 地址
     */
    function underlying() public view returns (address);

    /**
     *@notice 依赖资产精度
     *@return (uint8): 精度
     */
    function underlyingDecimal() public view returns (uint8);

    /**
     *@notice 真实借款数量（本息)
     *@param _account:实际借款人地址
     *@param _loanType:借款类型
     *@return (uint256): 错误码(0表示正确)
     */
    function borrowBalanceCurrent(address _account, uint256 id, LoanType _loanType) external returns (uint256);

    /**
     *@notice 用户存款
     *@param _mintAmount: 存入金额
     *@return (uint256, uint256): 错误码(0表示正确), 获取pToken数量
     */
    function mint(uint256 _mintAmount) external returns (uint256, uint256);

    /**
     *@notice 用户指定pToken取款
     *@param _redeemTokens: pToken数量
     *@return (uint256, uint256): 错误码(0表示正确), 获取Token数量，对应pToken数量
     */
    function redeem(uint256 _redeemTokens) external returns (uint256, uint256, uint256);

    /**
     *@notice 用户指定Token取款
     *@param _redeemAmount: Token数量
     *@return (uint256, uint256, uint256): 错误码(0表示正确), 获取Token数量，对应pToken数量
     */
    function redeemUnderlying(uint256 _redeemAmount) external returns (uint256, uint256, uint256);

    /**
     *@notice 获取用户的资产快照信息
     *@param _account: 用户地址
     *@param _id: 仓位id
     *@param _loanType: 借款类型
     *@return (uint256, uint256, uint256,uint256): 错误码(0表示正确), pToken数量, 借款(快照)数量, 兑换率
     */
    function getAccountSnapshot(address _account, uint256 _id, LoanType _loanType) external view returns (uint256, uint256, uint256,uint256);

    /**
     *@notice 信用贷借款
     *@param _borrower:实际借款人的地址
     *@param _borrowAmount:实际借款数量
     *@param _id: 仓位id
     *@param _loanType:借款类型
     *@return (uint256): 错误码
     */
    function doCreditLoanBorrow( address payable _borrower, uint256 _borrowAmount, uint256 _id, LoanType _loanType) public returns (uint256);

    /**
     *@notice 信用贷还款
     *@param _payer:实际还款人的地址
     *@param _repayAmount:实际还款数量
     *@param _id: 仓位id
     *@param _loanType:借款类型
     *@return (uint256, uint256): 错误码, 实际还款数量
     */
    function doCreditLoanRepay(address _payer, uint256 _repayAmount, uint256 _id, LoanType _loanType) public returns (uint256, uint256);

    /**
     *@notice 信用贷存款
     *@param _minter:存款人
     *@param _mintAmount:存款数量(含精度)
     *@param _loanType:存款类型
     *@return (uint256, uint256): 错误码, 存款得到pToken数量
     */
    function doCreditLoanMint(address _minter, uint256 _mintAmount, LoanType _loanType) public returns (uint256, uint256);

     /**
     *@notice 信用贷取款，_redeemAmount 或 _redeemTokensAmount必须有一个为0
     *@param _redeemer:取款人
     *@param _redeemAmount:取款数量(函数精度)
     *@param _redeemTokensAmount:取款pToken数量(函数精度)
     *@param _loanType:存款类型
     *@return (uint256, uint256, uint256, uint256): 错误码, token数量， pToken数量
     */
    function doCreditLoanRedeem(address payable _redeemer, uint256 _redeemAmount, uint256 _redeemTokensAmount, LoanType _loanType) public returns (uint256 ,uint256, uint256);
}
