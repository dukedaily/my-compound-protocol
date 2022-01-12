pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "hardhat/console.sol";
import "../PTokenInterfaces.sol";
import "../SafeMath.sol";
import "../EIP20Interface.sol";
import "./interface/ICapitalInterface.sol";
import "./StorageImpl.sol";
import "./interface/IMSPInterface.sol";
import "./interface/ILiquidationInterface.sol";

contract Capital is ICapitalInterface, StorageImpl {
    using SafeMath for uint256;

    constructor(
        string memory _mspName,
        address _pTokenUnderlying,
        IControllerInterface _controller
    ) public {
        mspName = _mspName;
        pTokenUnderlying = _pTokenUnderlying;
        controller = _controller;
        
        assetUnderlying = PErc20Interface(_pTokenUnderlying).underlying();
        assetUnderlyingSymbol = EIP20Interface(assetUnderlying).symbol();
    }

    function depositSpecToken(
        address _account,
        uint256 _id,
        address _modifyToken,
        uint256 _amount
    ) public onlySuperList returns (uint256, uint256) {
        address pTokenCurrAsset = controller.getPToken(address(_modifyToken));
        require(pTokenCurrAsset != address(0), "pToken for swapToken address is address(0)");

        EIP20Interface(_modifyToken).approve(pTokenCurrAsset, _amount);

        //2. 调用redeem函数
        // 传入的是用户，付款的是proxy
        // return IPublicsLoanInterface(pTokenCurrAsset).mint(_amount);
        return IPublicsLoanInterface(pTokenCurrAsset).doCreditLoanMint(_account, _amount, LoanTypeBase.LoanType.MARGIN_SWAP_PROTOCOL);
    }

    function redeemUnderlying(
        address payable _account,
        uint256 _id,
        address _modifyToken,
        uint256 _amount
    )
        public onlySuperList
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        address pTokenCurrAsset = controller.getPToken(address(_modifyToken));
        require(pTokenCurrAsset != address(0), "pToken for swapToken address is address(0)");

        // return IPublicsLoanInterface(pTokenCurrAsset).redeemUnderlying(_amount);
        return IPublicsLoanInterface(pTokenCurrAsset).doCreditLoanRedeem(_account, _amount, 0, LoanTypeBase.LoanType.MARGIN_SWAP_PROTOCOL);
    }

    //允许存款并转入
    function enabledAndDoDeposit(
        address _account,
        uint256 _id
    ) public onlySuperList returns (uint256) {
        MSPStruct.MSPConfig memory mspconfig = getAccountMspConfig(_account, _id);
        require(!mspconfig.isAutoSupply, "auto supply already enabled!");

        // console.log("mspconfig.pTokenSwapAmount", mspconfig.pTokenSwapAmount);
        // console.log("mspconfig.acturallySwapAmount", mspconfig.acturallySwapAmount);
        // console.log("mspconfig.isAutoSupply", mspconfig.isAutoSupply);
        uint256 error = depositMarginsToPublicsInternal(_account, _id);
        if (error != 0) {
            return error;
        }

        mspconfig.isAutoSupply = true;
        setAccountMspConfig(_account, _id, mspconfig);
        return 0;
    }

    function depositMarginsToPublicsInternal(address _account, uint256 _id) internal returns (uint256) {
        //1.a. 用户追加的保证金，多种，需要遍历
        address[] memory bailAssests = getBailAddress(_account, _id);

        for (uint256 i = 0; i < bailAssests.length; i++) {
            address currAsset = bailAssests[i];
            MSPStruct.supplyConfig memory scs = getSupplyConfig(_account, _id, currAsset);

            //已经存储到池子了
            if (scs.supplyAmount == 0) {
                continue;
            }

            address pTokenCurrAsset = controller.getPToken(address(currAsset));
            require(pTokenCurrAsset != address(0), "pToken for swapToken address is address(0)");
            EIP20Interface(currAsset).approve(pTokenCurrAsset, scs.supplyAmount);

            // (uint256 error, uint256 actualMintAmt) = IPublicsLoanInterface(pTokenCurrAsset).mint(scs.supplyAmount);
            (uint256 error, uint256 actualMintAmt) = IPublicsLoanInterface(pTokenCurrAsset).doCreditLoanMint(_account, scs.supplyAmount, LoanTypeBase.LoanType.MARGIN_SWAP_PROTOCOL);
            if (error != 0) {
                return error;
            }

            // console.log("currAsset:", scs.symbol);
            // console.log("scs.supplyAmount:", scs.supplyAmount, "mint ptoken amount:", actualMintAmt);

            //存入之后，更新结构
            scs.supplyAmount = 0;
            scs.pTokenAmount = scs.pTokenAmount.add(actualMintAmt);
            setSupplyConfig(_account, _id, currAsset, scs);
        }

        return 0;
    }

    //禁止存入并转出
    function disabledAndDoWithdraw(
        address payable _account,
        uint256 _id
    ) public onlySuperList returns (uint256) {
        MSPStruct.MSPConfig memory mspconfig = getAccountMspConfig(_account, _id);
        require(mspconfig.isAutoSupply, "auto supply already disabled!");

        uint256 error = withdrawMarginsFromPublicsInternal(_account, _id);
        if (error != 0) {
            return error;
        }
        mspconfig.isAutoSupply = false;
        setAccountMspConfig(_account, _id, mspconfig);
        return 0;
    }

    function withdrawMarginsFromPublicsInternal(address payable _account, uint256 _id) internal returns (uint256) {
        address[] memory bailAssests = getBailAddress(_account, _id);

        for (uint256 i = 0; i < bailAssests.length; i++) {
            address currAsset = bailAssests[i];
            MSPStruct.supplyConfig memory scs = getSupplyConfig(_account, _id, currAsset);

            if (scs.pTokenAmount == 0) {
                //理论上不会为0, double check
                continue;
            }
            //1. 找到pToken
            address pTokenCurrAsset = controller.getPToken(address(currAsset));
            require(pTokenCurrAsset != address(0), "pToken for swapToken address is address(0)");
            // console.log("scs.pTokenAmount:", scs.pTokenAmount);

            //2. 调用redeem函数
            // (uint256 error, uint256 actualRedeemAmt, ) = IPublicsLoanInterface(pTokenCurrAsset).redeem(scs.pTokenAmount);
            (uint256 error, uint256 actualRedeemAmt, ) = IPublicsLoanInterface(pTokenCurrAsset).doCreditLoanRedeem(_account, 0, scs.pTokenAmount, LoanTypeBase.LoanType.MARGIN_SWAP_PROTOCOL);
            if (error != 0) {
                // console.log("redeem error:", error);
                return error;
            }
            //3. 取出之后更新结构
            scs.supplyAmount = actualRedeemAmt;
            scs.pTokenAmount = 0;
            setSupplyConfig(_account, _id, currAsset, scs);

            // console.log("withdrawMarginsFromPublicsInternal::currAsset:", scs.symbol, "redeem asset amount:", actualRedeemAmt);
        }

        return 0;
    }

    function doTransferIn(
        address from,
        address erc20token,
        uint256 amount
    ) public onlySuperList returns (uint256) {
        EIP20NonStandardInterface token = EIP20NonStandardInterface(erc20token);
        uint256 balanceBefore = EIP20Interface(erc20token).balanceOf(address(this));
        token.transferFrom(from, address(this), amount);

        bool success;
        assembly {
            switch returndatasize()
                case 0 {
                    // This is a non-standard ERC-20
                    success := not(0) // set success to true
                }
                case 32 {
                    // This is a compliant ERC-20
                    returndatacopy(0, 0, 32)
                    success := mload(0) // Set `success = returndata` of external call
                }
                default {
                    // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
        }
        require(success, "TOKEN_TRANSFER_IN_FAILED");

        // Calculate the amount that was *actually* transferred
        uint256 balanceAfter = EIP20Interface(erc20token).balanceOf(address(this));
        require(balanceAfter >= balanceBefore, "TOKEN_TRANSFER_IN_OVERFLOW");
        return balanceAfter - balanceBefore; // underflow already checked above, just subtract
    }

    function doTransferOut(
        address payable to,
        address erc20token,
        uint256 amount
    ) public onlySuperList {
        EIP20NonStandardInterface token = EIP20NonStandardInterface(erc20token);
        token.transfer(to, amount);

        bool success;
        assembly {
            switch returndatasize()
                case 0 {
                    // This is a non-standard ERC-20
                    success := not(0) // set success to true
                }
                case 32 {
                    // This is a complaint ERC-20
                    returndatacopy(0, 0, 32)
                    success := mload(0) // Set `success = returndata` of external call
                }
                default {
                    // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
        }
        require(success, "TOKEN_TRANSFER_OUT_FAILED");
    }

    /**
     *@notice 信用贷借款
     *@param _borrowAmount 借款数量
     *@return 错误码(0正确)
     */
    function doCreditLoanBorrowInternal(
        address payable _account,
        uint256 _borrowAmount,
        uint256 _id
    ) public onlySuperList returns (uint256) {
        require(pTokenUnderlying != address(0), "pTokenUnderlying address should not be 0");
        return IPublicsLoanInterface(pTokenUnderlying).doCreditLoanBorrow(_account, _borrowAmount, _id, LoanTypeBase.LoanType.MARGIN_SWAP_PROTOCOL);
    }

    /**
     *@notice 信用贷还款
     *@param _borrower 借款人
     *@param _repayAmount 还款数量，uint256(-1)全还
     *@return 错误码(0正确)，实际还款数量
     */
    function doCreditLoanRepayInternal(
        address _borrower,
        uint256 _repayAmount,
        uint256 _id
    ) public onlySuperList returns (uint256, uint256) {
        address assetUnderlying = PErc20Interface(pTokenUnderlying).underlying();
        require(pTokenUnderlying != address(0), "pTokenUnderlying address should not be 0");

        EIP20Interface(assetUnderlying).approve(pTokenUnderlying, _repayAmount);
        (uint256 error, uint256 acturallyRepayAmount) = IPublicsLoanInterface(pTokenUnderlying).doCreditLoanRepay(_borrower, _repayAmount, _id, LoanTypeBase.LoanType.MARGIN_SWAP_PROTOCOL);
        return (error, acturallyRepayAmount);
    }
    
    function getController() public view returns (address) {
        return address(controller);
    }
    
    function getAssetUnderlying() public view returns(address) {
        return address(assetUnderlying);
    }

    function getPTokenUnderlying() public view returns(address) {
        return address(pTokenUnderlying);
    }
    
    function getSymbol() public view returns(string memory) {
        return assetUnderlyingSymbol;
    }

    function getMSPName() public view returns(string memory) {
        return mspName;
    }
    
    function getLastId() public view returns(uint256) {
        return lastId;
    }
    
    function setController(IControllerInterface _newController) public onlyOwner {
        controller = _newController;
        msp.updateController();
        liquidation.updateController();
    }

    function setMSP(address _msp) public {
        require(msg.sender == _msp, "caller must be msp!");
        msp = IMSPInterface(_msp);
    }

    function setLiquidation(address _liquidation) public {
        require(msg.sender == _liquidation, "caller must be liquidation!");
        liquidation = ILiquidationInterface(_liquidation);
    }

    //平仓后关闭
    function clean(address _account, uint256 _id) public onlySuperList {
        MSPStruct.MSPConfig memory mspconfig = getAccountMspConfig(_account, _id);
        mspconfig.isExist = false;

        setAccountMspConfig(_account, _id, mspconfig);
        setAccountRecordExistId(_account, mspconfig.uniqueName, 0);
        deleteClosedAccountRecord(_account, _id);
    }

    //穿仓后冻结
    function freeze(address _account, uint256 _id) public onlySuperList {
        MSPStruct.MSPConfig memory mspconfig = getAccountMspConfig(_account, _id);
        mspconfig.isFreeze = true;
        setAccountMspConfig(_account, _id, mspconfig);
    }
}
