pragma solidity ^0.5.16;
import "../../EIP20Interface.sol";
import "./IStorageInterface.sol";
import "./ICapitalInterface.sol";
import "./IControllerInterface.sol";
import "../utils/ErrorReporter.sol";

contract ILiquidationInterface {
    IMSPInterface public msp;
    IControllerInterface public controller;
    ICapitalInterface public capital;

    address public assetUnderlying;
    address public pTokenUnderlying;
    string public assetUnderlyingSymbol;

    bool public constant isLiquidation = true;

    //直接清算
    function liquidateBorrowedDirectly(
        address payable _borrower,
        uint256 _id,
        uint256 _amountOutMin
    ) public returns (uint256);

    //偿还清算
    //_repayAmount : 债务标的的数量，不是抵押品
    function liquidateBorrowedRepayFirst(
        address _borrower,
        EIP20Interface _tokenCollateral,
        uint256 _repayAmount,
        uint256 _id
    ) public;

    function updateController() public;
}
