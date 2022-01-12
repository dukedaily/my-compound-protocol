pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;
import "./IStorageInterface.sol";

contract ICapitalInterface is IStorageInterface {
    function depositSpecToken(
        address _account,
        uint256 _id,
        address _modifyToken,
        uint256 _amount
    ) public returns (uint256, uint256);

    function redeemUnderlying(
        address payable _account,
        uint256 _id,
        address _modifyToken,
        uint256 _amount
    )
        public
        returns (
            uint256,
            uint256,
            uint256
        );

    function doCreditLoanBorrowInternal(
        address payable _account,
        uint256 _borrowAmount,
        uint256 _id
    ) public returns (uint256);

    function doCreditLoanRepayInternal(
        address _borrower,
        uint256 _repayAmount,
        uint256 _id
    ) public returns (uint256, uint256);

    function doTransferIn(
        address from,
        address erc20token,
        uint256 amount
    ) public returns (uint256);

    function doTransferOut(
        address payable to,
        address erc20token,
        uint256 amount
    ) public;

    function enabledAndDoDeposit(
        address _account,
        uint256 _id
    ) public returns (uint256);

    function disabledAndDoWithdraw(
        address payable _account,
        uint256 _id
    ) public returns (uint256);

    function getController() public view returns (address);
    
    function getAssetUnderlying() public view returns(address);
    function getPTokenUnderlying() public view returns(address);
    function getSymbol() public view returns(string memory);
    function getMSPName() public view returns(string memory);
    
    function getLastId() public view returns(uint256);
    function setMSP(address _msp) public;
    function setLiquidation(address _liquidation) public;
    function clean(address _account, uint256 _id) public;
    function freeze(address _account, uint256 _id) public;
}
