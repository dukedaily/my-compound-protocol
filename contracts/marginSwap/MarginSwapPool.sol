pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "hardhat/console.sol";
import "../PTokenInterfaces.sol";
import "../ExponentialNoError.sol";
import "../IPublicsLoanInterface.sol";
import "../SafeMath.sol";
import "../Exponential.sol";

import "./MSPStruct.sol";
import "./utils/tools.sol";
import "./utils/ErrorReporter.sol";
import "./utils/Ownable.sol";

import "./interface/IStorageInterface.sol";
import "./interface/IControllerInterface.sol";
import "./interface/ICapitalInterface.sol";
import "./interface/IMSPInterface.sol";

contract MarginSwapPool is IMSPInterface, Tools, Ownable, Exponential, ErrorReporter {
    //开仓
    event OpenPositionEvent(address _account, uint256 _id, uint256 _supplyTotalAmount, uint256 _swapActuallyAmount);
    //加仓
    event MorePositionEvent(address _account, uint256 _id, uint256 _supplyTotalAmount, uint256 _swapActuallyAmount);
    // event MorePositionEvent(uint256 _id, uint256 _supplyAmount, uint256 _borrowAmount, address _swapToken, uint256 _acturallySwapAmount, uint256 _amountOutMin);
    //增加保证金
    event AddMarginEvent(uint256 _id, uint256 _amount, address _bailToken);
    //赎回保证金
    event ReedeemMarginEvent(uint256 _id, uint256 _amount, address _modifyToken);
    //从钱包偿还
    event RepayEvent(uint256 _id, uint256 _amount, uint256);
    //从保证金还款
    event RepayFromMarginEvent(uint256 id, address bailToken, uint256 amount);
    //统一事件
    // event NewPositionEvent(address _account, uint256 _id, Operation.OperationType _opType, uint256 _borrowAmnt, address _swapToken, address[] bondTokens, uint256[] bondAmounts);
    event NewPositionEvent(address _account, uint256 _id, Operation.OperationType _opType, uint256 supplyAmount, uint256 swapAmount, uint256 _borrowAmnt, address _swapToken, address[] bondTokens, uint256[] bondAmounts);
    using SafeMath for uint256;

    constructor(ICapitalInterface _capital) public {
        capital = _capital;
        assetUnderlying = capital.getAssetUnderlying();
        pTokenUnderlying = capital.getPTokenUnderlying();
        mspName = capital.getMSPName();
        assetUnderlyingSymbol = capital.getSymbol();
        capital.setMSP(address(this));
        updateController();
    }

    function updateController() public {
        controller = IControllerInterface(capital.getController());
    }

    modifier nonReentrant() {
        require(_notEntered, "re-entered");
        _notEntered = false;
        _;
        _notEntered = true; // get a gas-refund post-Istanbul
    }

    struct posLocalVars {
        uint256 currentId;
        EIP20Interface swapToken;
        string uniqueName;
        uint256 borrowAmount;
        uint256 acturallySwapAmount;
        uint256 tryToRepayAmount;
        uint256 err0;
        uint256 existId;
    }

    /**
     * @notice 开仓
     * @param _supplyAmount 用户提供的本金
     * @param _leverage 杠杆倍数
     * @param _swapToken 兑换资产
     * @param _amountOutMin 可兑换回目标资产最小值
     */
    function openPosition(
        uint256 _supplyAmount,
        uint256 _leverage,
        EIP20Interface _swapToken,
        uint256 _amountOutMin
    ) public nonReentrant {
        require(controller.isSwapTokenAllowed(address(_swapToken)), "swap token is not in white list");
        require(address(_swapToken) != assetUnderlying, "cannot swap self token type");

        (uint256 lmin, uint256 lmax) = controller.getLeverage(address(this));
        require(_leverage >= lmin && _leverage <= lmax, "invalid leverage!");

        posLocalVars memory vars;
        vars.swapToken = _swapToken;
        vars.borrowAmount = _supplyAmount.div(BASE10).mul(_leverage - BASE10);
        require(vars.borrowAmount <= PTokenInterface(pTokenUnderlying).getCash(), "borrow too much, pToken market money insufficient!");

        string memory swapTokenSymbol = EIP20Interface(vars.swapToken).symbol();
        vars.uniqueName = Tools.strConcat(assetUnderlyingSymbol, swapTokenSymbol);
        vars.existId = capital.getAccountRecordExistId(msg.sender, vars.uniqueName);

        if (vars.existId != 0) {
            return morePosition(vars.existId, _supplyAmount, vars.borrowAmount, vars.swapToken, _amountOutMin);
        }

        capital.updateID();
        vars.currentId = capital.getLastId();
        vars.err0 = controller.openPositionAllowed(address(this));
        require(vars.err0 == 0, "this msp is paused!");

        vars.acturallySwapAmount = borrowAndSwapInternal(_supplyAmount, vars.borrowAmount, vars.swapToken, vars.currentId, _amountOutMin);

        MSPStruct.MSPConfig memory mspconfig =
            MSPStruct.MSPConfig({
                uniqueName: vars.uniqueName,
                id: vars.currentId,
                supplyAmount: _supplyAmount,
                leverage: _leverage,
                borrowAmount: vars.borrowAmount,
                swapToken: vars.swapToken,
                actuallySwapAmount: vars.acturallySwapAmount,
                amountOutMin: _amountOutMin,
                isAutoSupply: false,
                isExist: true,
                isFreeze:false
            });

        capital.setAccountMspConfig(msg.sender, mspconfig.id, mspconfig);
        capital.setAccountRecordIds(msg.sender, mspconfig.id);

        MSPStruct.supplyConfig memory scs = MSPStruct.supplyConfig({
            symbol: EIP20Interface(vars.swapToken).symbol(), 
            supplyToken: address(vars.swapToken),
            supplyAmount: vars.acturallySwapAmount, 
            pTokenAmount: 0});

        capital.setSupplyConfig(msg.sender, mspconfig.id, address(vars.swapToken), scs);
        capital.setBailAddress(msg.sender, mspconfig.id, address(vars.swapToken));
        capital.setAccountRecordExistId(msg.sender, vars.uniqueName, vars.currentId);

        uint256 totalSupply = _supplyAmount.add(vars.borrowAmount);
        (,, address[] memory bondTokens, uint256[] memory bondAmounts) = getBondTokens(msg.sender, vars.currentId);

        emit NewPositionEvent(msg.sender, vars.currentId, Operation.OperationType.OPEN_POSITION, totalSupply, vars.acturallySwapAmount, vars.borrowAmount, address(vars.swapToken), bondTokens, bondAmounts);
    }

    /**
     * @notice 加仓
     * @param _id 持仓id
     * @param _supplyAmount 用户提供的本金
     * @param _borrowAmount 借款数量
     * @param _swapToken 兑换资产
     * @param _amountOutMin 可兑换回目标资产最小值
     */
    function morePosition(
        uint256 _id,
        uint256 _supplyAmount,
        uint256 _borrowAmount,
        EIP20Interface _swapToken,
        uint256 _amountOutMin
    ) internal {
        MSPStruct.MSPConfig memory mspconfig = capital.getAccountMspConfig(msg.sender, _id);
        require(!mspconfig.isFreeze, "this account is freezed, pls repay first!");

        //3. 转账并swap目标token
        uint256 acturallySwapAmount = borrowAndSwapInternal(_supplyAmount, _borrowAmount, _swapToken, _id, _amountOutMin);

        //4. 是否存入到借贷池
        depositAndUpdateInternal(msg.sender, _id, acturallySwapAmount, address(_swapToken), mspconfig.isAutoSupply);

        //5. 数据更新到记录
        uint256 currDebt = PTokenInterface(pTokenUnderlying).borrowBalanceCurrent(msg.sender, _id, LoanTypeBase.LoanType.MARGIN_SWAP_PROTOCOL);
        mspconfig.supplyAmount = mspconfig.supplyAmount.add(_supplyAmount);
        mspconfig.actuallySwapAmount = mspconfig.actuallySwapAmount.add(acturallySwapAmount);
        mspconfig.borrowAmount = currDebt.add(_borrowAmount);
        capital.setAccountMspConfig(msg.sender, _id, mspconfig);

        (uint256 borrow, address swapToken, address[] memory bondTokens, uint256[] memory bondAmounts) = getBondTokens(msg.sender, _id);
        // emit MorePositionEvent(_id, _supplyAmount, _borrowAmount, address(_swapToken), acturallySwapAmount, _amountOutMin);

        emit NewPositionEvent(msg.sender, _id, Operation.OperationType.MORE_POSITION, mspconfig.supplyAmount, mspconfig.actuallySwapAmount, mspconfig.borrowAmount, address(_swapToken), bondTokens, bondAmounts);
    }

    /**
     * @notice 借款并接入聚合交易进行兑换，得到资产直接转入capital合约
     * @param _supplyAmount 用户提供的本金
     * @param _borrowAmount 借款数量
     * @param _swapToken 兑换资产
     * @param _id 持仓id
     * @param _amountOutMin 可兑换回目标资产最小值
     */
    function borrowAndSwapInternal(
        uint256 _supplyAmount,
        uint256 _borrowAmount,
        EIP20Interface _swapToken,
        uint256 _id,
        uint256 _amountOutMin
    ) internal returns (uint256) {
        require(_supplyAmount != 0, "invalid supply amount input!");
        capital.doTransferIn(msg.sender, assetUnderlying, _supplyAmount);

        uint256 supplyAmount = _supplyAmount;
        if (_borrowAmount > 0) {
            uint256 borrowError = capital.doCreditLoanBorrowInternal(msg.sender, _borrowAmount, _id);
            require(borrowError == 0, "doCreditLoanBorrow failed!");
            supplyAmount = supplyAmount.add(_borrowAmount);
        }
        return swapAndDepositBack(assetUnderlying, supplyAmount, address(_swapToken), _amountOutMin);
    }

    /**
     * @notice 兑换成目标资产并转入capital
     * @param _fromToken 提供币种
     * @param _supplyAmount 提供数量
     * @param _swapToken 兑换资产
     * @param _amountOutMin 可兑换回目标资产最小值
     */
    function swapAndDepositBack(
        address _fromToken,
        uint256 _supplyAmount,
        address _swapToken,
        uint256 _amountOutMin
    ) internal returns (uint256) {
        ITXAggregator txAggregator = ITXAggregator(controller.getTxAggregator());
        address payable wallet = address(uint160(address(this)));
        capital.doTransferOut(wallet, _fromToken, _supplyAmount);
        EIP20Interface(_fromToken).approve(address(txAggregator), _supplyAmount);

        uint256 deadline = block.timestamp + 60;
        uint256 acturallySwapAmt = txAggregator.swapExtractOut(_fromToken, _swapToken, address(capital), _supplyAmount, _amountOutMin, deadline); //TODO deadline
        require(acturallySwapAmt >= _amountOutMin, "amountOutMin not satisfied!");
        return acturallySwapAmt;
    }

    /**
     * @notice 增加保证金
     * @param _id 持仓id
     * @param _amount 提供数量
     * @param _supplyToken 提供保证金币种
     */
    function addMargin(
        uint256 _id,
        uint256 _amount,
        address _supplyToken
    ) public nonReentrant {
        uint256 currNum = capital.getBailAddress(msg.sender,_id).length;
        require(controller.isBailTokenAllowed(_supplyToken, currNum), "bail token not in white list!");
        require(_amount != 0, "invalid supply amount input!");

        capital.doTransferIn(msg.sender, _supplyToken, _amount);
        MSPStruct.MSPConfig memory mspconfig = capital.getAccountMspConfig(msg.sender, _id);
        depositAndUpdateInternal(msg.sender, _id, _amount, _supplyToken, mspconfig.isAutoSupply);

        (uint256 borrow,, address[] memory bondTokens, uint256[] memory bondAmounts) = getBondTokens(msg.sender, _id);
        emit AddMarginEvent(_id, _amount, _supplyToken);
        emit NewPositionEvent(msg.sender, _id, Operation.OperationType.ADD_MARGIN, 0, 0, borrow, address(mspconfig.swapToken), bondTokens, bondAmounts);
    }

    /**
     * @notice 将资产存入到借贷市场，并且更新storage中用户数据结构
     * @param _account 用户地址
     * @param _id 持仓id
     * @param _amount 存入借贷市场数量
     * @param _supplyToken 兑换资产
     * @param _isAutoSupply 是否自动存储到借贷市场
     */
    function depositAndUpdateInternal(
        address _account,
        uint256 _id,
        uint256 _amount,
        address _supplyToken,
        bool _isAutoSupply
    ) internal {
        MSPStruct.supplyConfig memory scs = capital.getSupplyConfig(_account, _id, _supplyToken);

        if (_isAutoSupply) {
            (uint256 error, uint256 mintPToken) = capital.depositSpecToken(_account, _id, _supplyToken, _amount);
            require(error == 0, "capital.depositSpecToken error!");
            scs.pTokenAmount = scs.pTokenAmount.add(mintPToken);
        } else {
            scs.supplyAmount = scs.supplyAmount.add(_amount);
        }

        if (scs.supplyToken == address(0)) {
            scs.supplyToken = _supplyToken;
            scs.symbol = EIP20Interface(_supplyToken).symbol();
            capital.setBailAddress(_account, _id, _supplyToken);
        }
        capital.setSupplyConfig(_account, _id, _supplyToken, scs);
    }
    
    /**
     * @notice 指定币种提取保证金
     * @param _id 持仓id
     * @param _amount 提取数量
     * @param _redeemToken 提取保证金币种
     */
    function redeemMargin(
        uint256 _id,
        uint256 _amount,
        address _redeemToken
    ) public nonReentrant {
        require(_amount != 0, "invalid supply amount input!");
        uint256 allowed = controller.redeemAllowed(msg.sender, this, _id, _redeemToken, _amount);
        require(allowed == 0, "redeem amount will cause liquidation, denied!");

        MSPStruct.MSPConfig memory mspconfig = capital.getAccountMspConfig(msg.sender, _id);
        MSPStruct.supplyConfig memory scs = capital.getSupplyConfig(msg.sender, _id, _redeemToken);

        if (mspconfig.isAutoSupply) {
            (uint256 error,, uint256 actualPToken) = capital.redeemUnderlying(msg.sender, _id, _redeemToken, _amount);
            require(error == 0, "capital.redeemUnderlying error!");
            scs.pTokenAmount = scs.pTokenAmount.sub(actualPToken);
        } else {
            scs.supplyAmount = scs.supplyAmount.sub(_amount);
        }

        capital.doTransferOut(msg.sender, _redeemToken, _amount);
        //如果全部取出，则删除记录
        if (scs.supplyAmount == 0 && scs.pTokenAmount == 0) {
            capital.deleteBailAddress(msg.sender, _id, _redeemToken);
        }

        // 4. 更新保证金结构
        capital.setSupplyConfig(msg.sender, _id, _redeemToken, scs);
        (uint256 borrow,, address[] memory bondTokens, uint256[] memory bondAmounts) = getBondTokens(msg.sender, _id);
        // console.log("borrow:", borrow, "borrowAmount",mspconfig.borrowAmount);

        emit ReedeemMarginEvent(_id, _amount, _redeemToken);
        emit NewPositionEvent(msg.sender, _id, Operation.OperationType.REDEEM_MARGIN, 0, 0, mspconfig.borrowAmount, address(mspconfig.swapToken), bondTokens, bondAmounts);
    }
    
    struct repayLoacalVars {
        uint256 id;
        uint256 currDebt;
        uint256 tryToRepayAmount;
        uint256 left;
    }

    /**
     * @notice 还款1: 从钱包还款(可以指定还款币种，合约内部自动进行兑换)
     * @param _id 持仓id
     * @param _repayToken 还款币种
     * @param _repayAmount 当前还款币种的数量
     * @param _amountOutMin 可兑换回目标资产最小值
     */
    function repayFromWallet(uint256 _id, address _repayToken, uint256 _repayAmount, uint256 _amountOutMin) public returns (uint256, uint256) {
        MSPStruct.MSPConfig memory mspconfig = capital.getAccountMspConfig(msg.sender, _id);
        
        repayLoacalVars memory vars;
        vars.id = _id;
        vars.currDebt = PTokenInterface(pTokenUnderlying).borrowBalanceCurrent(msg.sender, vars.id, LoanTypeBase.LoanType.MARGIN_SWAP_PROTOCOL);
        require(vars.currDebt != 0, "borrow amount is 0, no need to repay");

        //我们就是按照用户输入的数量进行兑换的: A->B
        if (_repayToken != assetUnderlying) {
            capital.doTransferIn(msg.sender, _repayToken, _repayAmount);
            vars.tryToRepayAmount = swapAndDepositBack(_repayToken, _repayAmount, assetUnderlying, _amountOutMin);
            // console.log("其他币种还款:", _repayToken, "tryToRepayAmount:", vars.tryToRepayAmount);
            require(vars.tryToRepayAmount >= _amountOutMin, "swap amount error!");
        } else {
            if (_repayAmount == uint256(-1)) {
                vars.tryToRepayAmount = vars.currDebt;
            } else {
                vars.tryToRepayAmount = _repayAmount;
            }
            capital.doTransferIn(msg.sender, assetUnderlying, vars.tryToRepayAmount);
        }

        //1.b 如果输入小于余额但是大于债务，更新还款数字为债务值(还款合约内部处理了)
        (uint256 err, uint256 actualAmt) = capital.doCreditLoanRepayInternal(msg.sender, vars.tryToRepayAmount, _id);
        console.log("repayFromWallet err:", err);
        require(err == 0, "repay failed!");

        uint256 left = vars.tryToRepayAmount.sub(actualAmt);
        if (left > 0) {
            // console.log("left:", left);
            capital.doTransferOut(msg.sender, assetUnderlying, left);
        }

        //2. 更新结构
        mspconfig.borrowAmount = vars.currDebt.sub(actualAmt);

        //3. 如果债务偿还完毕，进行解冻
        if (mspconfig.borrowAmount == 0 && mspconfig.isFreeze) {
            mspconfig.isFreeze = false;
        }

        capital.setAccountMspConfig(msg.sender, _id, mspconfig);
        (,, address[] memory bondTokens, uint256[] memory bondAmounts) = getBondTokens(msg.sender, vars.id);

        emit RepayEvent(vars.id, actualAmt, uint256(Error1.BAD_INPUT));
        emit NewPositionEvent(msg.sender, vars.id, Operation.OperationType.REPAY_FROM_WALLET, 0, 0, mspconfig.borrowAmount, address(mspconfig.swapToken), bondTokens, bondAmounts);
    }

    /**
     * @notice 还款1: 从钱包还款(临时的，无法选择还款币种，仅限债务币种)
     * @param _id 持仓id
     * @param _repayAmount 当前还款币种的数量
     */
    function repay(uint256 _id, uint256 _repayAmount) public returns (uint256, uint256) {
        MSPStruct.MSPConfig memory mspconfig = capital.getAccountMspConfig(msg.sender, _id);

        uint256 currDebt = PTokenInterface(pTokenUnderlying).borrowBalanceCurrent(msg.sender, _id, LoanTypeBase.LoanType.MARGIN_SWAP_PROTOCOL);
        require(currDebt != 0, "borrow amount is 0, no need to repay");
        // console.log("uint256(-1):", uint256(-1));

        if (_repayAmount == uint256(-1)) {
            _repayAmount = currDebt;
        }
        capital.doTransferIn(msg.sender, assetUnderlying, _repayAmount);
        //1.b 如果输入小于余额但是大于债务，更新还款数字为债务值(还款合约内部处理了)
        (uint256 err, uint256 actualAmt) = capital.doCreditLoanRepayInternal(msg.sender, _repayAmount, _id);
        require(err == 0, "repay failed!");

        uint256 left = _repayAmount.sub(actualAmt);
        if (left > 0) {
            capital.doTransferOut(msg.sender, assetUnderlying, left);
        }

        //2. 更新结构
        //config中的数据只是用户借的，偿还的时候有可能包含了利息
        mspconfig.borrowAmount = currDebt.sub(actualAmt);

        //3. 如果债务偿还完毕，进行解冻
        if (mspconfig.borrowAmount == 0 && mspconfig.isFreeze) {
            mspconfig.isFreeze = false;
        }

        capital.setAccountMspConfig(msg.sender, _id, mspconfig);
        (uint256 borrow, address swapToken, address[] memory bondTokens, uint256[] memory bondAmounts) = getBondTokens(msg.sender, _id);

        emit RepayEvent(_id, _repayAmount, uint256(Error1.BAD_INPUT));
        emit NewPositionEvent(msg.sender, _id, Operation.OperationType.REPAY_FROM_WALLET, 0, 0, mspconfig.borrowAmount, address(mspconfig.swapToken), bondTokens, bondAmounts);
    }

    struct RepayVars {
        uint256 id;
        uint256 oraclePriceMantissa;
        uint256 exchangeRateMantissa;
        address bailToken;
        uint256 borrowBalance;
        uint256 holdAmount;
        uint256 acturallySwapAmt;
        uint256 oErr;
        uint256 amount;
        Exp oraclePrice;
        Exp exchangeRate;
        uint256 actualAmt;
        uint256 actualPToken;
    }

    /**
     *@notice 还款2: 从用户指定保证金还款，常规平仓(多余的会返回)
     *@param _id: 持仓id
     *@param _bailToken: 用于还款的保证金币种
     *@param _amount: 保证金还款数量
     *@param _amountOutMin 可兑换回目标资产最小值
     *@return (uint256) 0:succeed
     */
    function repayFromMargin(
        uint256 _id,
        address _bailToken,
        uint256 _amount,
        uint256 _amountOutMin
    ) public returns (uint256) {
        RepayVars memory vars;
        vars.id = _id;
        vars.bailToken = _bailToken;
        vars.amount = _amount;

        // 1. 校验参数
        MSPStruct.supplyConfig memory scs = capital.getSupplyConfig(msg.sender, vars.id, vars.bailToken);
        require(scs.supplyToken != address(0), "invalid address input!");

        uint256 error1 = PTokenInterface(pTokenUnderlying).accrueInterest();
        if (error1 != uint256(Error1.NO_ERROR)) {
            return fail(Error1(error1), FailureInfo1.LIQUIDATE_ACCRUE_COLLATERAL_INTEREST_FAILED);
        }

        //确保计算用户输入的数量是否小于等于实际持有的数量
        (vars.oErr, , vars.borrowBalance, vars.exchangeRateMantissa) = PTokenInterface(pTokenUnderlying).getAccountSnapshot(msg.sender, vars.id, LoanTypeBase.LoanType.MARGIN_SWAP_PROTOCOL);
        if (vars.oErr != 0) {
            return vars.oErr;
        }

        MSPStruct.MSPConfig memory mspconfig = capital.getAccountMspConfig(msg.sender, vars.id);
        if (mspconfig.isAutoSupply) {
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa}); //转成结构体
            vars.holdAmount = mul_ScalarTruncate(vars.exchangeRate, scs.pTokenAmount);
        }
        require(scs.supplyAmount >= vars.amount || vars.holdAmount >= vars.amount, "not enough amount to repay!");

        if (mspconfig.isAutoSupply) {
            (vars.oErr, vars.actualAmt, vars.actualPToken) = capital.redeemUnderlying(msg.sender, vars.id, _bailToken, vars.amount);
            require(vars.oErr == 0, "capital.redeemUnderlying error!");
            require(vars.actualAmt == vars.amount, "redeemUnderlying error!");
        }

        //我们就是按照用户输入的数量进行兑换的: A->B
        if (_bailToken != assetUnderlying) {
            vars.acturallySwapAmt = swapAndDepositBack(_bailToken, vars.amount, assetUnderlying, _amountOutMin);
        } else {
            vars.acturallySwapAmt = vars.amount;
        }

        //2. 偿还债务 借了20个，可能兑换：10个或30个
        //债务大于还款，全部还掉
        uint256 repayAmnt = vars.borrowBalance >= vars.acturallySwapAmt ? vars.acturallySwapAmt : vars.borrowBalance;
        (uint256 err, uint256 actualRepay) = capital.doCreditLoanRepayInternal(msg.sender, repayAmnt, vars.id);
        require(err == 0, "repayFromMargin::credit loan repay failed!");

        //更新结构MSP结构
        mspconfig.borrowAmount = mspconfig.borrowAmount.sub(actualRepay);
        capital.setAccountMspConfig(msg.sender, vars.id, mspconfig);

        //更新swapToken结构
        uint256 left = vars.acturallySwapAmt.sub(actualRepay);
        if (left > 0) {
            //如果还多了，直接作为保证金了
            // depositAndUpdateInternal(msg.sender, vars.id, left, address(assetUnderlying), mspconfig.isAutoSupply);
            capital.doTransferOut(msg.sender, address(assetUnderlying), left);
        }

        //更新_bailToken结构
        if (mspconfig.isAutoSupply) {
            scs.pTokenAmount = scs.pTokenAmount.sub(vars.actualPToken);
        } else {
            scs.supplyAmount = scs.supplyAmount.sub(vars.amount);
        }
        capital.setSupplyConfig(msg.sender, vars.id, vars.bailToken, scs);

        if (scs.supplyAmount == 0 && scs.pTokenAmount == 0) {
            capital.deleteBailAddress(msg.sender, vars.id, vars.bailToken);
        }

        (uint256 borrow, address swapToken, address[] memory bondTokens, uint256[] memory bondAmounts) = getBondTokens(msg.sender, vars.id);

        emit RepayFromMarginEvent(vars.id, vars.bailToken, vars.amount);
        emit NewPositionEvent(msg.sender, vars.id, Operation.OperationType.REPAY_FROM_MARGIN, 0, 0, mspconfig.borrowAmount, address(mspconfig.swapToken), bondTokens, bondAmounts);
        return 0;
    }

    /**
     *@notice 一键提取保证金，需要用户已经手动完成了所有的还款，确保没有借款
     *@param _id: 持仓id
     */
    function closePosition(uint256 _id) public {
        uint256 currDebt = PTokenInterface(pTokenUnderlying).borrowBalanceCurrent(msg.sender, _id, LoanTypeBase.LoanType.MARGIN_SWAP_PROTOCOL);
        require(currDebt == 0, "need to repay all borrowed balance first!");

        MSPStruct.MSPConfig memory mspconfig = capital.getAccountMspConfig(msg.sender, _id);
        if (mspconfig.isAutoSupply) {
            uint256 error = capital.disabledAndDoWithdraw(msg.sender, _id);
            require(error == 0, "closePosition::disabledAndDoWithdraw error!");
        }

        address[] memory bailAssests = getBailAddress(msg.sender, _id);
        for (uint256 i = 0; i < bailAssests.length; i++) {
            address currAsset = bailAssests[i];
            MSPStruct.supplyConfig memory scs = capital.getSupplyConfig(msg.sender, _id, currAsset);

            if (scs.supplyAmount > 0) {
                capital.doTransferOut(msg.sender, currAsset, scs.supplyAmount);
            }
            //bailAssests 不需要删除，最后config isExist设置为false即可! //TODO
        }
        capital.clean(msg.sender, _id);

        address[] memory zero1;
        uint256[] memory zero2;
        emit NewPositionEvent(msg.sender, _id, Operation.OperationType.CLOSE_POSITION, 0, 0, 0, address(mspconfig.swapToken), zero1, zero2);
    }

     /**
     *@notice  当前资产全部转入借贷市场，并且打开自动存储开关，后续资金会自动转入借贷市场
     *@param _id: 持仓id
     */
    function enabledAndDoDeposit(uint256 _id) public {
        uint256 error = capital.enabledAndDoDeposit(msg.sender, _id);
        require(error == 0, "enabledAndDoDeposit error!");

        (uint256 borrow, address swapToken, address[] memory bondTokens, uint256[] memory bondAmounts) = getBondTokens(msg.sender, _id);
        emit NewPositionEvent(msg.sender, _id, Operation.OperationType.ENABLE_AND_DEPOSIT, 0, 0, borrow, swapToken, bondTokens, bondAmounts);
    }
     /**
     *@notice  从借贷市场将资产转出，并关闭自动转入开关，后续资产不会自动转入借贷市场
     *@param _id: 持仓id
     */
    function disabledAndDoWithdraw(uint256 _id) public {
        uint256 error = capital.disabledAndDoWithdraw(msg.sender, _id);
        require(error == 0, "disabledAndDoWithdraw error!");

        (uint256 borrow, address swapToken, address[] memory bondTokens, uint256[] memory bondAmounts) = getBondTokens(msg.sender, _id);
        emit NewPositionEvent(msg.sender, _id, Operation.OperationType.DISABLE_AND_WITHDRAW, 0, 0, borrow, swapToken, bondTokens, bondAmounts);
    }

     /**
     *@notice 获取当前持仓风险率，后面两个参数用于计算还款时风险率动态变化
     *@param _account: 持仓用户
     *@param _id: 持仓id
     *@param _supplyToken: 用户假设存入的币种
     *@param _supplyAmnt: 用户假设存入的数量
     *@return (uint256) 风险率
     */
    function getRisk(address _account, uint256 _id, address _supplyToken, uint256 _supplyAmnt) public view returns (uint256) {
        (uint256 err, , uint256 risk, ) = controller.getAccountLiquidity(_account, this, _id, _supplyToken, _supplyAmnt);
        if (err != uint256(Error1.NO_ERROR)) {
            return uint256(err);
        }
        return risk;
    }

     /**
     *@notice 查看指定用户的持仓id集合
     *@param _account: 持仓用户
     *@return (uint256[]) id数组
     */
    function getAccountCurrRecordIds(address _account) public view returns (uint256[] memory) {
        return capital.getAccountRecordIds(_account);
    }

     /**
     *@notice 获取指定持仓结构详细信息
     *@param _account: 持仓用户
     *@param _id: 持仓id
     *@return (uint256, uint256, uint256, uint256, address, uint256, bool)
     * 持仓id，建仓提供资金数量，杠杆倍数，借款数量（含利息），兑换目标资产，最小兑换数量，是否自动存入借贷市场）
     */
    function getAccountConfigDetail(address _account, uint256 _id) public view returns ( uint256, uint256, uint256, uint256, address, uint256, bool, bool) {
        MSPStruct.MSPConfig memory msc = capital.getAccountMspConfig(_account, _id);
        (, , uint256 borrowBalance, ) = PTokenInterface(pTokenUnderlying).getAccountSnapshot(_account, _id, LoanTypeBase.LoanType.MARGIN_SWAP_PROTOCOL);
        return (msc.id, msc.supplyAmount, msc.leverage, borrowBalance, address(msc.swapToken), msc.amountOutMin, msc.isFreeze, msc.isAutoSupply);
    }

     /**
     *@notice 获取所有保证金地址
     *@param _account: 持仓用户
     *@param _id: 持仓id
     *@return (address[]) 保证金数组
     */
    function getBailAddress(address _account, uint256 _id) public view returns (address[] memory) {
        return capital.getBailAddress(_account, _id);
    }

     /**
     *@notice 获取指定保证金的数据结构，token和pToken必定有一个为0
     *@param _account: 持仓用户
     *@param _id: 持仓id
     *@return (string, uint256, uint256) 符号，token数量，pToken数量
     */
    function getBailConfigDetail(address _account, uint256 _id, address _bailToken) public view returns ( string memory, uint256, uint256) {
        MSPStruct.supplyConfig memory scs = capital.getSupplyConfig(_account, _id, _bailToken);
        return (scs.symbol, scs.supplyAmount, scs.pTokenAmount);
    }

    /**
     *@notice 获取所有的保证金， 对应的Token数量
     *@param _account: 持仓用户
     *@param _id: 持仓id
     *@return (uint256, address, address[], uint256[]) ：借款数量（含利息），兑换资产，所有保证金数组，所有保证金数组数量
     */
    function getBondTokens(address _account, uint256 _id) public view returns (uint256, address, address[] memory, uint256[] memory) {
        address[] memory bondTokens = getBailAddress(_account, _id);
        uint256[] memory bondAmounts = new uint256[](bondTokens.length);
        MSPStruct.MSPConfig memory mspconfig = capital.getAccountMspConfig(_account, _id);
        (,,uint256 borrowBalance, uint256 exchangeRateMantissa) = PTokenInterface(pTokenUnderlying).getAccountSnapshot(_account, _id, LoanTypeBase.LoanType.MARGIN_SWAP_PROTOCOL);

        for (uint8 i = 0; i < bondTokens.length; i++) {
            (, uint256 tokenAmount, uint256 pTokenAmnt) = getBailConfigDetail(_account, _id, bondTokens[i]);
            if (mspconfig.isAutoSupply) {
                Exp memory exchangeRate = Exp({mantissa: exchangeRateMantissa}); //转成结构体
                tokenAmount = mul_ScalarTruncate(exchangeRate, pTokenAmnt);
            }
            bondAmounts[i] = tokenAmount;
        }
        return (borrowBalance, address(mspconfig.swapToken), bondTokens, bondAmounts);
    }
}
