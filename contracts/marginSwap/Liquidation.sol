pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "hardhat/console.sol";
import "../IPublicsLoanInterface.sol";
import "../ExponentialNoError.sol";
import "../SafeMath.sol";
import "../Exponential.sol";
import "../CarefulMath.sol";
import "../PTokenInterfaces.sol";

import "./interface/IStorageInterface.sol";
import "./interface/IMSPInterface.sol";
import "./interface/IControllerInterface.sol";
import "./interface/ILiquidationInterface.sol";
import "./interface/ICapitalInterface.sol";

import "./utils/ErrorReporter.sol";
import "./utils/tools.sol";
import "./MSPStruct.sol";
import "./utils/Ownable.sol";

contract Liquidation is ILiquidationInterface, Ownable, Tools, ErrorReporter, CarefulMath {
    //直接清算
    event LiquidateBorrowedDirectlyEvent(address _account, uint256 _id);
    //偿还清算
    event LiquidateBorrowedRepayFirstEvent(address _account, uint256 _id);
    //执行清算，内部事件
    event LiquidateBorrow(address liquidator, address borrower, uint256 repayAmount, address pTokenCollateral, uint256 seizeTokens);
    //清算转移资产
    event Transfer(address indexed from, address indexed to, uint256 amount);
    using SafeMath for uint256;

    constructor(IMSPInterface _msp) public {
        msp = _msp;
        capital = msp.capital();
        assetUnderlying = capital.getAssetUnderlying();
        pTokenUnderlying = capital.getPTokenUnderlying();
        assetUnderlyingSymbol = capital.getSymbol();
        capital.setLiquidation(address(this));
        updateController();
    }

    function updateController() public {
        controller = IControllerInterface(capital.getController());
    }

    //直接清算
    function liquidateBorrowedDirectly(
        address payable _borrower,
        uint256 _id,
        uint256 _amountOutMin
    ) public returns (uint256) {
        require(controller.isDirectlyLiquidationAllowed(), "directly liquidation is paused!");
        require(msg.sender != _borrower, "can not liquidate youself!");

        uint256 error = PTokenInterface(pTokenUnderlying).accrueInterest();
        if (error != uint256(Error1.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted liquidation failed
            return fail(Error1(error), FailureInfo1.LIQUIDATE_ACCRUE_BORROW_INTEREST_FAILED);
        }

        liquidateBorrowDrectlyFresh(msg.sender, _borrower, _id, _amountOutMin);
        emit LiquidateBorrowedDirectlyEvent(_borrower, _id);
    }

    struct LiquidationVars {
        address liquidator;
        address borrower;
        uint256 id;
        uint256 amountOutMin;
        address currAsset;
        uint256 totalAsset;
        uint256 acturallySwapAmt;
        uint256 needToPayback;
        uint256 backToAccountAmt;
        uint256 benifits;
        uint256 remains;
    }

    function liquidateBorrowDrectlyFresh(
        address _liquidator,
        address payable _borrower,
        uint256 _id,
        uint256 _amountOutMin
    ) internal returns (uint256) {
        LiquidationVars memory vars;
        vars.id = _id;
        vars.amountOutMin = _amountOutMin;

        (uint256 err, , , uint256 shortfall) = controller.getAccountLiquidity(_borrower, IMSPInterface(msp), vars.id, address(0), 0);
        console.log("shortfall: ", shortfall);

        if (err != uint256(Error1.NO_ERROR)) {
            return uint256(err);
        }

        require(shortfall != 0, "no need to liquidation");
        MSPStruct.MSPConfig memory mspconfig = capital.getAccountMspConfig(_borrower, vars.id);

        //可以被清算
        if (mspconfig.isAutoSupply) {
            uint256 error = capital.disabledAndDoWithdraw(_borrower, vars.id);
            require(error == 0, "disabledAndDoWithdraw error!");
        }
        console.log("准备遍历保证金，进行兑换成债务资产!");

        //2. 将全部资产卖掉，得到债务资产，偿还债务，获得债务8%的奖励
        address[] memory bailAssests = capital.getBailAddress(_borrower, vars.id);

        //1. 遍历所有的保证金(包括兑换回来的UNI，空的BUSD，以及后续追加资产)
        for (uint256 i = 0; i < bailAssests.length; i++) {
            vars.currAsset = bailAssests[i];
            MSPStruct.supplyConfig memory scs = capital.getSupplyConfig(_borrower, vars.id, vars.currAsset);
            console.log("currAsset:", vars.currAsset);

            //兑换的token直接转给capital了
            if (assetUnderlying == vars.currAsset) {
                vars.totalAsset = vars.totalAsset.add(scs.supplyAmount);
            } else {
                require(vars.currAsset != address(0), "invalid currAsset: vars.currAsset is address(0)");
                ITXAggregator txAggregator = ITXAggregator(controller.getTxAggregator());

                address payable wallet = address(uint160(address(this)));
                capital.doTransferOut(wallet, vars.currAsset, scs.supplyAmount);

                EIP20Interface(vars.currAsset).approve(address(txAggregator), scs.supplyAmount);
                console.log("授权txAggregator成功!");

                uint256 deadline = block.timestamp + 30;
                vars.acturallySwapAmt = txAggregator.swapExtractOut(vars.currAsset, assetUnderlying, address(capital), scs.supplyAmount, vars.amountOutMin, deadline); //TODO deadline
                require(vars.acturallySwapAmt >= vars.amountOutMin, "amountOutMin not satisfied!");
                vars.totalAsset = vars.totalAsset.add(vars.acturallySwapAmt);
            }

            console.log("totalAsset:", vars.totalAsset);

            scs.supplyAmount = 0;
            capital.setSupplyConfig(_borrower, vars.id, vars.currAsset, scs);
            // capital.deleteBailAddress(_borrower, vars.id, vars.currAsset);
        }

        // 3. 偿还BUSD，得到剩余的BUSD（本金）,
        vars.needToPayback = PTokenInterface(pTokenUnderlying).borrowBalanceCurrent(_borrower, vars.id, LoanTypeBase.LoanType.MARGIN_SWAP_PROTOCOL);
        // require(vars.totalAsset >= vars.needToPayback, "money insufficient, should be liquidated!");

        console.log("final totalAsset:", vars.totalAsset);
        console.log("needToPayback:", vars.needToPayback);

        // 1. 先将债务0.08拿走
        vars.benifits = controller.seizeBenifit(vars.needToPayback);
        require(vars.totalAsset >= vars.benifits, "no insufficient money to pay benifits");
        console.log("0.08 benifits:", vars.benifits);

        uint256 toLiquidatorAmt = controller.benifitToLiquidator(vars.benifits);
        address payable liquidator = address(uint160(_liquidator));
        capital.doTransferOut(liquidator, assetUnderlying, toLiquidatorAmt);
        console.log("toLiquidatorAmt:", toLiquidatorAmt);

        address payable owner = address(uint160(owner()));
        capital.doTransferOut(owner, assetUnderlying, vars.benifits.sub(toLiquidatorAmt));
        console.log("toOwner:", vars.benifits.sub(toLiquidatorAmt));

        //2. 从剩余的中扣除债务部分
        vars.remains = vars.totalAsset.sub(vars.benifits);

        if (vars.remains < vars.needToPayback) {
            (uint256 err1, uint256 actualAmt) = capital.doCreditLoanRepayInternal(_borrower, vars.remains, vars.id);
            require(err1 == 0, "closePosition::credit loan repay failed!");
            console.log("还款后无剩余actualAmt:", actualAmt, "vars.needToPayback:", vars.needToPayback);

            capital.freeze(_borrower, vars.id);
        } else {
            //3. 如果还有剩余，返回给用户
            (uint256 err1, uint256 actualAmt) = capital.doCreditLoanRepayInternal(_borrower, vars.needToPayback, vars.id);
            vars.backToAccountAmt = vars.remains.sub(actualAmt);
            console.log("还款后有剩余vars.backToAccountAmt:", vars.backToAccountAmt);

            if (vars.backToAccountAmt > 0) {
                address payable borrower = address(uint160(_borrower));
                capital.doTransferOut(borrower, assetUnderlying, vars.backToAccountAmt);
            }

            capital.clean(_borrower, vars.id);
        }
    }

    //偿还清算
    function liquidateBorrowedRepayFirst(
        address _borrower,
        EIP20Interface _tokenCollateral,
        uint256 _repayAmount,
        uint256 _id
    ) public {
        require(msg.sender != _borrower, "can not liquidate youself!");
        liquidateBorrowInternal(_borrower, _repayAmount, _tokenCollateral, _id);
        emit LiquidateBorrowedRepayFirstEvent(_borrower, _id);
    }

    function liquidateBorrowInternal(
        address _borrower,
        uint256 _repayAmount,
        EIP20Interface _tokenCollateral,
        uint256 _id
    ) internal returns (uint256, uint256) {
        // ) internal nonReentrant returns (uint256, uint256) {  //TODO

        uint256 error = PTokenInterface(pTokenUnderlying).accrueInterest();
        if (error != uint256(Error1.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted liquidation failed
            return (fail(Error1(error), FailureInfo1.LIQUIDATE_ACCRUE_BORROW_INTEREST_FAILED), 0);
        }

        PTokenInterface pTokenCollateral = PTokenInterface(controller.getPToken(address(_tokenCollateral)));
        error = pTokenCollateral.accrueInterest();
        if (error != uint256(Error1.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted liquidation failed
            return (fail(Error1(error), FailureInfo1.LIQUIDATE_ACCRUE_COLLATERAL_INTEREST_FAILED), 0);
        }

        return liquidateBorrowFresh(msg.sender, _borrower, _repayAmount, pTokenCollateral, _id);
    }

    struct LiquidateLocalVars {
        address liquidator;
        address borrower;
        uint256 repayAmount;
        PTokenInterface pTokenCollateral;
        uint256 positionId;
        uint256 amountSeizeError;
        uint256 seizeTokens;
        uint256 supplyAmount;
        uint256 pTokenAmount;
        address pTokenCollateralTmp;
        address collateralUnderlying;
    }

    //入口:清算函数
    function liquidateBorrowFresh(
        address payable _liquidator,
        address _borrower,
        uint256 _repayAmount,
        PTokenInterface _pTokenCollateral,
        uint256 _id
    ) internal returns (uint256, uint256) {
        LiquidateLocalVars memory vars;

        vars.liquidator = _liquidator;
        vars.borrower = _borrower;
        vars.repayAmount = _repayAmount;
        vars.pTokenCollateral = _pTokenCollateral;
        vars.positionId = _id;

        //Fail if liquidate not allowed
        //1. 确保borrower真的抵押不足了
        uint256 allowed = controller.liquidateBorrowAllowed(address(msp), pTokenUnderlying, vars.liquidator, vars.borrower, vars.repayAmount, vars.positionId);

        if (allowed != 0) {
            return (failOpaque(Error1.COMPTROLLER_REJECTION, FailureInfo1.LIQUIDATE_COMPTROLLER_REJECTION, allowed), 0);
        }

        //Fail if borrower = liquidator
        if (vars.borrower == vars.liquidator) {
            return (fail(Error1.INVALID_ACCOUNT_PAIR, FailureInfo1.LIQUIDATE_LIQUIDATOR_IS_BORROWER), 0);
        }

        // Fail if repayAmount = 0
        if (vars.repayAmount == 0) {
            return (fail(Error1.INVALID_CLOSE_AMOUNT_REQUESTED, FailureInfo1.LIQUIDATE_CLOSE_AMOUNT_IS_ZERO), 0);
        }

        // Fail if repayAmount = -1
        if (vars.repayAmount == uint256(-1)) {
            return (fail(Error1.INVALID_CLOSE_AMOUNT_REQUESTED, FailureInfo1.LIQUIDATE_CLOSE_AMOUNT_IS_UINT_MAX), 0);
        }

        //2. 清算人向MSP转账，由MSP去偿还信用贷(需要先授权)
        capital.doTransferIn(msg.sender, assetUnderlying, vars.repayAmount);
        // console.log("vars.repayAmount:", vars.repayAmount);

        (uint256 err, uint256 actualAmt) = capital.doCreditLoanRepayInternal(_borrower, vars.repayAmount, vars.positionId);
        // console.log("信用贷还款actualAmt:", actualAmt);
        if (Error1(err) != Error1.NO_ERROR) {
            return (err, 0);
        }

        //3. 清算人获得收益
        // MSPStruct.MSPConfig memory mspconfig = MSPStruct.msConfig.accountMarginSwapRecords[_borrower][_id];
        MSPStruct.MSPConfig memory mspconfig = capital.getAccountMspConfig(_borrower, _id);

        (vars.amountSeizeError, vars.seizeTokens) = controller.liquidateCalculateSeizeTokens(pTokenUnderlying, address(vars.pTokenCollateral), actualAmt, mspconfig.isAutoSupply);
        require(vars.amountSeizeError == uint256(Error1.NO_ERROR), "LIQUIDATE_COMPTROLLER_CALCULATE_AMOUNT_SEIZE_FAILED");

        // Revert if borrower collateral token balance < seizeTokens
        //应该查看在MSP中记录了_borrower有多少个pToken
        vars.pTokenCollateralTmp = address(vars.pTokenCollateral);
        vars.collateralUnderlying = PErc20Interface(vars.pTokenCollateralTmp).underlying();
        (, uint256 supplyAmount, uint256 pTokenAmount) = msp.getBailConfigDetail(_borrower, _id, vars.collateralUnderlying);

        // console.log("seizeTokens:", vars.seizeTokens);
        // console.log("borrower持有的：pTokenAmount:", pTokenAmount, "supplyAmount", supplyAmount);
        if (mspconfig.isAutoSupply) {
            require(pTokenAmount >= vars.seizeTokens, "LIQUIDATE_SEIZE_TOO_MUCH");
        } else {
            require(supplyAmount >= vars.seizeTokens, "LIQUIDATE_SEIZE_TOO_MUCH");
        }

        address payable liquidator_ = address(uint160(address(vars.liquidator)));
        // 每个用户持有的pToken都是在MSP中记录的
        uint256 seizeError = seizeInternal(msg.sender, liquidator_, vars.borrower, vars.seizeTokens, vars.positionId, vars.collateralUnderlying, mspconfig.isAutoSupply); //TODO

        // Revert if seize tokens fails (since we cannot be sure of side effects)
        require(seizeError == uint256(Error1.NO_ERROR), "token seizure failed");

        //偿还清算不能进行关掉仓位，因为只是清算了其中一个资产，还有其他的
        // We emit a LiquidateBorrow event
        emit LiquidateBorrow(vars.liquidator, vars.borrower, actualAmt, address(vars.pTokenCollateral), vars.seizeTokens);
        return (uint256(Error1.NO_ERROR), actualAmt);
    }

    struct SeizeLocalVars {
        uint256 borrowerTokensNew;
        MathError mathErr;
    }

    //将被清算的pToken转给清算人
    function seizeInternal(
        address _seizerToken,
        address payable _liquidator,
        address _borrower,
        uint256 _seizeTokens,
        uint256 _id,
        address _collateralUnderlying,
        bool _isAutoSupply
    ) internal returns (uint256) {
        SeizeLocalVars memory vars;
        //2. Fail if borrower = liquidator
        if (_borrower == _liquidator) {
            return fail(Error1.INVALID_ACCOUNT_PAIR, FailureInfo1.LIQUIDATE_SEIZE_LIQUIDATOR_IS_BORROWER);
        }

        //3. 转移borrower的部分pToken给清算人
        MSPStruct.supplyConfig memory borrowerSC = capital.getSupplyConfig(_borrower, _id, _collateralUnderlying);
        // console.log("borrower持有pTokenAmount:",borrowerScs.pTokenAmount, "supplyAmount:",borrowerScs.supplyAmount);

        if (_isAutoSupply) {
            (vars.mathErr, vars.borrowerTokensNew) = subUInt(borrowerSC.pTokenAmount, _seizeTokens);
            if (vars.mathErr != MathError.NO_ERROR) {
                return failOpaque(Error1.MATH_ERROR, FailureInfo1.LIQUIDATE_SEIZE_BALANCE_DECREMENT_FAILED, uint256(vars.mathErr));
            }

            //4. 转移资产了，只是账户间的转移，不存在整体token数量的变化，因此无需修改totalBorrows和totalReserves
            borrowerSC.pTokenAmount = vars.borrowerTokensNew;

            //5. 清算人直接获得pToken到钱包
            address pTokenCollateral = controller.getPToken(_collateralUnderlying);
            capital.doTransferOut(_liquidator, pTokenCollateral, _seizeTokens);
        } else {
            (vars.mathErr, vars.borrowerTokensNew) = subUInt(borrowerSC.supplyAmount, _seizeTokens);
            if (vars.mathErr != MathError.NO_ERROR) {
                return failOpaque(Error1.MATH_ERROR, FailureInfo1.LIQUIDATE_SEIZE_BALANCE_DECREMENT_FAILED, uint256(vars.mathErr));
            }

            //4. 转移资产了，只是账户间的转移，不存在整体token数量的变化，因此无需修改totalBorrows和totalReserves
            borrowerSC.supplyAmount = vars.borrowerTokensNew;

            //5. 清算人直接获得Token到钱包
            capital.doTransferOut(_liquidator, _collateralUnderlying, _seizeTokens);
        }

        //勿忘更新!
        capital.setSupplyConfig(_borrower, _id, _collateralUnderlying, borrowerSC);
        if (borrowerSC.pTokenAmount == 0 && borrowerSC.supplyAmount == 0) {
            capital.deleteBailAddress(_borrower, _id, _collateralUnderlying);
        }

        //Emit a Transfer event
        emit Transfer(_borrower, _liquidator, _seizeTokens);

        return uint256(Error1.NO_ERROR);
    }
}
