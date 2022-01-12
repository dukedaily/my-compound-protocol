pragma solidity ^0.5.16;

import "../SafeMath.sol";
import "./utils/ErrorReporter.sol";
import "../ExponentialNoError.sol";
import "./utils/Ownable.sol";
import "./interface/IControllerInterface.sol";
import "./interface/ILiquidationInterface.sol";
import "hardhat/console.sol";

contract Controller is Ownable, ControllerStorage, IControllerInterface, ExponentialNoError, ErrorReporter, ControllerErrorReporter, LoanTypeBase {
    using SafeMath for uint256;
    //增加新msp市场
    event MSPListed(address newAddress, bool isCollateral, bool isVisable);
    //清算合约
    event NewMSPLiquidation(address _msp, address _liquidation);
    //添加新兑换资产
    event NewSwapToken(address token, bool flag);
    //设置token到pToken对应
    event NewAssetToPToken(address token, address pToken);
    //增加保证金币种
    event NewBailToken(address token, bool flag);
    //设置聚合交易
    event NewTxAggregator(address oldTxAggregator, address txAggregator);
    //设置杠杆倍数限制
    event NewLeverage(address msp, uint256 min, uint256 max);
    //设置oracle
    event NewPriceOracle(PriceOracleAggregator oldPriceOracle, PriceOracleAggregator newPriceOracle);
    //设置清算比例
    event NewCloseFactor(uint256 oldCloseFactorMantissa, uint256 newCloseFactorMantissa);
    //设置质押率
    event NewCollateralFactor(PTokenInterface pToken, uint256 oldCollateralFactorMantissa, uint256 newCollateralFactorMantissa);
    //设置清算奖励
    event NewLiquidationIncentive(uint256 oldLiquidationIncentiveMantissa, uint256 newLiquidationIncentiveMantissa);
    //设置暂停管理员
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);
    //对msp进行控制
    event ActionPaused(IMSPInterface msp, string action, bool pauseState);
    //直接清算开关
    event NewDirectlyLiquidationStateEvent(bool oldState, bool newState);
    //保证金种类上限
    event NewBailTypeMaxEvent(uint8 oldMax, uint8 newMax);
    //直接清算收益比例
    event NewLiquidatorRatioMantissaEvent(uint256 oldRatioMantissa, uint256 liquidatorRatioMantissa);

    //添加新的MSP市场
    function _supportMspMarket(IMSPInterface _msp, ILiquidationInterface _liquidation, bool isCollateral) external onlyOwner returns (uint256) {
        supplyTokenWhiteList[_msp.assetUnderlying()] = true;
        console.log("_msp:", address(_msp));
        require(_msp.isMSP(),"invalid msp input!");
        require(_liquidation.isLiquidation(),"invalid liquidation input!");

        _addMarketInternal(address(_msp));
        emit MSPListed(address(_msp), isCollateral, true);
        emit NewMSPLiquidation(address(_msp), address(_liquidation));
        return uint256(Error.NO_ERROR);
    }

    //更改抵押状态
    function _changeMspMarketState(IMSPInterface _msp, bool isCollateral, bool isVisable) external onlyOwner {
       emit MSPListed(address(_msp), isCollateral, isVisable);
    }

    //统计所有MSP市场
    function _addMarketInternal(address _msp) internal {
        for (uint256 i = 0; i < allMspMarkets.length; i++) {
            require(allMspMarkets[i] != IMSPInterface(_msp), "market already added");
        }
        allMspMarkets.push(IMSPInterface(_msp));
    }

    //swapToken白名单
    function setSwapTokenWhiteList(address _token, bool _flag) public onlyOwner {
        require(_token != address(0), "invalid address");

        swapTokenWhiteList[_token] = _flag;
        emit NewSwapToken(_token, _flag);
    }

    //能否做swapToken
    function isSwapTokenAllowed(address _token) public view returns (bool) {
        return swapTokenWhiteList[_token];
    }

    //token资产地址=>pToken地址
    function setAssetToPTokenList(EIP20Interface _token, PTokenInterface _pToken) public onlyOwner {
        require(address(_token) != address(0), "invalid address");
        require(address(_pToken) != address(0), "invalid address");

        assetToPTokenList[address(_token)] = address(_pToken);
        emit NewAssetToPToken(address(_token), address(_pToken));
    }

    //获取pToken
    function getPToken(address _token) public view returns (address) {
        return assetToPTokenList[_token];
    }

    //保证金白名单
    function setBailTokenWhiteList(EIP20Interface _token, bool _flag) public onlyOwner {
        require(address(_token) != address(0), "invalid address");

        bailTokenWhiteList[address(_token)] = _flag;
        emit NewBailToken(address(_token), _flag);
    }

    //是否能做保证金
    function isBailTokenAllowed(address _token, uint256 _currentNum) public view returns (bool) {
        require(_currentNum <= bailTypeMax, "bail type limit reached!");
        return bailTokenWhiteList[_token];
    }

    //设置聚合交易
    function setTxAggregator(address _txAggregator) external onlyOwner {
        require(_txAggregator != address(0), "invalid dex tx aggregator address!");

        address oldTxAggregator = address(_txAggregator);
        txAggregator = ITXAggregator(_txAggregator);

        emit NewTxAggregator(oldTxAggregator, address(txAggregator));
    }

    //设置杠杆倍数
    function setLeverage(
        address _msp,
        uint256 _min,
        uint256 _max
    ) external onlyOwner {
        require(IMSPInterface(_msp).isMSP(),"invalid msp input!");
        require(supplyTokenWhiteList[IMSPInterface(_msp).assetUnderlying()], "msp is not support yet!");
        Leverage storage l = leverage[_msp];
        l.leverageMin = _min;
        l.leverageMax = _max;
        emit NewLeverage(_msp, l.leverageMin, l.leverageMax);
    }

    //设置保证金种类上限
    function setBailTypeMax(uint8 _newMax) public onlyOwner {
        uint8 oldMax = bailTypeMax;
        bailTypeMax = _newMax;
        emit NewBailTypeMaxEvent(oldMax, bailTypeMax);
    }

    //获取杠杆倍数
    function getLeverage(address _msp) public view returns (uint256, uint256) {
        return (leverage[_msp].leverageMin, leverage[_msp].leverageMax);
    }

    function _setPriceOracle(PriceOracleAggregator newOracle) public onlyOwner returns (uint256) {
        // Track the old oracle for the comptroller
        PriceOracleAggregator oldOracle = oracle;

        // Set comptroller's oracle to newOracle
        oracle = newOracle;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, newOracle);

        return uint256(Error.NO_ERROR);
    }

    function getOracle() public view returns (PriceOracleAggregator) {
        require(address(oracle) != address(0), "oracle is address(0)");
        return oracle;
    }

    //清算相关
    //0.5，表示清算50%，无初始值, 需要自己手动设置
    function _setCloseFactor(uint256 newCloseFactorMantissa) external onlyOwner returns (uint256) {
        uint256 oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);

        return uint256(Error.NO_ERROR);
    }

    //需要手动调用: 800000000000000000， 表示0.8e18
    //TODO 注意是Ptoken
    function _setCollateralFactor(PTokenInterface pToken, uint256 newCollateralFactorMantissa) external onlyOwner returns (uint256) {
        Exp memory newCollateralFactorExp = Exp({mantissa: newCollateralFactorMantissa});

        // Check collateral factor <= 0.9
        Exp memory highLimit = Exp({mantissa: collateralFactorMaxMantissa});
        if (lessThanExp(highLimit, newCollateralFactorExp)) {
            return fail(Error.INVALID_COLLATERAL_FACTOR, FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION);
        }

        // If collateral factor != 0, fail if price == 0
        (uint256 price,)= oracle.getUnderlyingPrice(pToken);
        if (newCollateralFactorMantissa != 0 && price == 0) {
            return fail(Error.PRICE_ERROR, FailureInfo.SET_COLLATERAL_FACTOR_WITHOUT_PRICE);
        }

        uint256 oldCollateralFactorMantissa = collateralFactorMantissaContainer[address(pToken)];
        collateralFactorMantissaContainer[address(pToken)] = newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(pToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);

        return uint256(Error.NO_ERROR);
    }

    //设置1.08，表示获得8%的奖励
    function _setLiquidationIncentive(uint256 newLiquidationIncentiveMantissa) external onlyOwner returns (uint256) {
        // Save current value for use in log
        uint256 oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;

        // Set liquidation incentive to new incentive
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;

        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(oldLiquidationIncentiveMantissa, newLiquidationIncentiveMantissa);

        return uint256(Error.NO_ERROR);
    }

    function _setPauseGuardian(address newPauseGuardian) public onlyOwner returns (uint256) {
        // Save current value for inclusion in log
        address oldPauseGuardian = pauseGuardian;

        // Store pauseGuardian with value newPauseGuardian
        pauseGuardian = newPauseGuardian;

        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);

        return uint256(Error.NO_ERROR);
    }

    /// @notice 开仓功能暂停
    function _setOpenPositionPaused(IMSPInterface _msp, bool _state) public {
        require(msg.sender == pauseGuardian || msg.sender == owner(), "only pause guardian and admin can pause");

        openGuardianPaused[address(_msp)] = _state;
        emit ActionPaused(_msp, "OpenPosition", _state);
    }

    // 设置直接清算开关

    struct AccountLiquidityLocalVars {
        uint256 positionId;
        IMSPInterface msp;
        EIP20Interface tokenModify;
        uint256 redeemTokens;
        EIP20Interface supplyToken;
        uint256 supplyAmnt;
        uint256 sumCollateral; //抵押物总额
        uint256 sumBorrowPlusEffects; //effect财务（利息）借款总额+利息
        uint256 holdBalance; //持有的pToken或者Token的数量
        uint256 borrowBalance; //借出的underlying数量
        uint256 exchangeRateMantissa; //交换率（尾数）
        uint256 oraclePriceMantissa; //预言机价格（尾数）
        Exp collateralFactor; //抵押物因子
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom; //denom：
        uint256 oErr;
        address account;
    }

    //核心函数，遍历资产，得到shortfall
    //存储(完成）和未存(完成)需要分别处理，两种情况
    function getHypotheticalAccountLiquidityInternal(
        address _account,
        IMSPInterface _msp,
        uint256 _id,
        EIP20Interface _tokenModify,
        uint256 _redeemTokens,
        EIP20Interface _supplyToken,
        uint256 _supplyAmnt
    )
        internal
        view
        returns (
            Error,
            uint256,
            uint256,
            uint256
        )
    {
        // console.log("_id:", _id);
        (, , , , , ,, bool isAutoSupply) = _msp.getAccountConfigDetail(_account, _id);
        // console.log("isAutoSupply:", isAutoSupply);

        AccountLiquidityLocalVars memory vars;
        vars.account = _account;
        vars.tokenModify = _tokenModify;
        vars.redeemTokens = _redeemTokens;
        vars.msp = _msp;
        vars.positionId = _id;
        vars.supplyToken = _supplyToken;
        vars.supplyAmnt = _supplyAmnt;

        PTokenInterface debtPToken = PTokenInterface(_msp.pTokenUnderlying());

        //统计债务
        (vars.oErr, , vars.borrowBalance, ) = debtPToken.getAccountSnapshot(vars.account, vars.positionId, LoanType.MARGIN_SWAP_PROTOCOL);
        if (vars.oErr != 0) {
            return (Error.SNAPSHOT_ERROR, 0, 0, 0);
        }

        if (vars.borrowBalance != 0) {
            console.log("统计债务:", vars.borrowBalance, "debtPToken:", address(debtPToken));
            (vars.oraclePriceMantissa,) = oracle.getUnderlyingPrice(debtPToken);
            if (vars.oraclePriceMantissa == 0) {
                return (Error.PRICE_ERROR, 0, 0, 0);
            }

            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});
            vars.sumBorrowPlusEffects = mul_ScalarTruncate(vars.oraclePrice, vars.borrowBalance);
        }

        console.log("准备统计保证金!");

        //统计资产
        address[] memory bailAssests = vars.msp.getBailAddress(vars.account, vars.positionId);

        for (uint256 i = 0; i < bailAssests.length; i++) {
            address currAsset = bailAssests[i];

            (string memory symbol, uint256 supplyAmount, uint256 pTokenAmount) = vars.msp.getBailConfigDetail(vars.account, vars.positionId, currAsset);
            PTokenInterface assetPToken = PTokenInterface(getPToken(currAsset));
            // console.log("currAsset:", symbol);
            // console.log("supplyAmount:", supplyAmount, "pTokenAmount:", pTokenAmount);

            // Get the normalized price of the asset
            (vars.oraclePriceMantissa,) = oracle.getUnderlyingPrice(assetPToken);
            if (vars.oraclePriceMantissa == 0) {
                return (Error.PRICE_ERROR, 0, 0, 0);
            }

            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});
            (vars.oErr, , vars.borrowBalance, vars.exchangeRateMantissa) = assetPToken.getAccountSnapshot(vars.account, vars.positionId, LoanType.MARGIN_SWAP_PROTOCOL);

            if (vars.oErr != 0) {
                return (Error.SNAPSHOT_ERROR, 0, 0, 0);
            }

            //注意，这里使用的是pToken而不是token，是在设置质押率的时候限制的，需要改变 //TODO
            vars.collateralFactor = Exp({mantissa: collateralFactorMantissaContainer[address(assetPToken)]}); //LTV: loan to value,最大能借的比例

            if (isAutoSupply) {
                vars.holdBalance = pTokenAmount; //pTokenAmount不是^18，而是^8
                vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa}); //转成结构体
                vars.tokensToDenom = mul_(mul_(vars.collateralFactor, vars.exchangeRate), vars.oraclePrice);

                // console.log("isAutoSupply true");
                //累加所有的保证金，到质押物中
                vars.sumCollateral = mul_ScalarTruncateAddUInt(vars.tokensToDenom, vars.holdBalance, vars.sumCollateral);
            } else {
                vars.holdBalance = supplyAmount; //未存入借贷市场时使用
                vars.tokensToDenom = mul_(vars.collateralFactor, vars.oraclePrice);

                // console.log("isAutoSupply false");
                //累加所有的保证金，到质押物中
                vars.sumCollateral = mul_ScalarTruncateAddUInt(vars.tokensToDenom, vars.holdBalance, vars.sumCollateral);
            }

            console.log("vars.collateralFactor:", vars.collateralFactor.mantissa);
            console.log("vars.exchangeRate:", vars.exchangeRate.mantissa);
            console.log("vars.oraclePrice:", vars.oraclePrice.mantissa);
            console.log("vars.tokensToDenom:", vars.tokensToDenom.mantissa);
            console.log("vars.sumCollateral:", vars.sumCollateral);
            console.log("vars.sumBorrowPlusEffects:", vars.sumBorrowPlusEffects);
            console.log(" ----------------------------------------------------------------");

            //提取保证金时计算风险率
            if (currAsset == address(vars.tokenModify)) {
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, vars.redeemTokens, vars.sumBorrowPlusEffects);
            }
        } //for
        // } //isAutoSupply
        console.log("统计结束!");

        //保证金还款时计算风险率变化
        if (address(vars.supplyToken) != address(0) && vars.supplyAmnt != 0) {
            PTokenInterface assetPToken = PTokenInterface(getPToken(address(vars.supplyToken)));
            vars.collateralFactor = Exp({mantissa: collateralFactorMantissaContainer[address(assetPToken)]}); 
            (vars.oraclePriceMantissa,) = oracle.getUnderlyingPrice(assetPToken);
            if (vars.oraclePriceMantissa == 0) {
                return (Error.PRICE_ERROR, 0, 0, 0);
            }

            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});
            vars.tokensToDenom = mul_(vars.collateralFactor, vars.oraclePrice);
            vars.sumCollateral = mul_ScalarTruncateAddUInt(vars.tokensToDenom, vars.supplyAmnt, vars.sumCollateral); 
            console.log("vars.sumCollateral更新:", vars.sumCollateral);
        }

        uint256 risk;
        if (vars.sumBorrowPlusEffects != 0 && vars.collateralFactor.mantissa != 0) {
            //借款也需要同比例缩小
            uint sumBorrowPlusEffectsScale = mul_ScalarTruncate(Exp({mantissa: vars.sumBorrowPlusEffects}), vars.collateralFactor.mantissa);
            console.log("sumBorrowPlusEffects:", vars.sumBorrowPlusEffects);
            console.log("sumBorrowPlusEffectsScale:", sumBorrowPlusEffectsScale);
            risk = vars.sumCollateral.div((sumBorrowPlusEffectsScale.div(100)));
        } else if (vars.sumCollateral != 0 && vars.sumBorrowPlusEffects == 0) {
            risk = 100000;
        }

        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            //liquidity = vars.sumCollateral - vars.sumBorrowPlusEffects
            //不清算, 还有多少富裕的抵押品
            console.log("无需被清算，安全！risk: ", risk, "%");
            return (Error.NO_ERROR, vars.sumCollateral - vars.sumBorrowPlusEffects, risk, 0);
        } else {
            //清算，只关注第三个参数，已经有多少不足了
            console.log("需要被清算，危险！risk: ", risk, "%");
            return (Error.NO_ERROR, 0, risk, vars.sumBorrowPlusEffects - vars.sumCollateral);
        }
    }

    //单独调用，判断是否可以被清算
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
        )
    {
        (Error err, uint256 liquidity, uint256 risk, uint256 shortfall) = getHypotheticalAccountLiquidityInternal(_account, _msp, _id, EIP20Interface(0), 0, EIP20Interface(_supplyToken), _supplyAmnt);
        return (uint256(err), liquidity, risk, shortfall);
    }

    //清算前需要确认一下是否可以被清算：
    //1. 是否资不抵债
    //2. 是否清算比例过高
    function liquidateBorrowAllowed(
        address msp,
        address pTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 repayAmount,
        uint256 id
    ) public view returns (uint256) {
        // Shh - currently unused
        // liquidator;

        //TODO
        // if (
        //     !markets[pTokenBorrowed].isListed ||
        //     !markets[pTokenCollateral].isListed
        // ) {
        //     return uint256(Error.MARKET_NOT_LISTED);
        // }

        // The borrower must have shortfall in order to be liquidatable
        //查看是否可以被清算
        (uint256 err, , , uint256 shortfall) = getAccountLiquidity(borrower, IMSPInterface(msp), id, address(0), 0);
        // console.log("shortfall: ", shortfall);

        if (err != uint256(Error.NO_ERROR)) {
            return uint256(err);
        }

        if (shortfall == 0) {
            return uint256(Error.INSUFFICIENT_SHORTFALL); //ERROR  3
        }

        //The liquidator may not repay more than what is allowed by the closeFactor
        //当前用户借款数量
        //注意，borroweBalance对应的都是underlying的数量
        uint256 borrowBalance = PTokenInterface(pTokenBorrowed).borrowBalanceStored(borrower, id, LoanType.MARGIN_SWAP_PROTOCOL);

        //由closeFactor限制，publics是限定为1
        uint256 maxClose = mul_ScalarTruncate(Exp({mantissa: closeFactorMantissa}), borrowBalance);
        // console.log("borrowBalance:", borrowBalance);
        // console.log("maxClose:", maxClose);

        if (repayAmount > maxClose) {
            return uint256(Error.TOO_MUCH_REPAY); //error: 17
        }

        return uint256(Error.NO_ERROR);
    }

    function liquidateCalculateSeizeTokens(
        address pTokenBorrowed,
        address pTokenCollateral,
        uint256 actualRepayAmount,
        bool isAutoSupply
    ) external view returns (uint256, uint256) {
        /* Read oracle prices for borrowed and collateral markets */
        // console.log("in liquidateCalculateSeizeTokens");
        (uint256 priceBorrowedMantissa,) = oracle.getUnderlyingPrice(PTokenInterface(pTokenBorrowed)); //传入pToken地址，会转换为对应underlying地址
        (uint256 price,) = oracle.getUnderlyingPrice(PTokenInterface(pTokenCollateral));
        uint256 priceCollateralMantissa = price;
        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            return (uint256(Error.PRICE_ERROR), 0);
        }

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        // console.log("priceBorrowedMantissa:", priceBorrowedMantissa);
        // console.log("priceCollateralMantissa:", priceCollateralMantissa);
        uint256 exchangeRateMantissa;
        uint256 seizeTokens;
        Exp memory numerator; //分子
        Exp memory denominator; //分母
        Exp memory ratio; //比例

        if (isAutoSupply) {
            exchangeRateMantissa = PTokenInterface(pTokenCollateral).exchangeRateStored(); // Note: reverts on error
            denominator = mul_(Exp({mantissa: priceCollateralMantissa}), Exp({mantissa: exchangeRateMantissa}));
        } else {
            denominator = Exp({mantissa: priceCollateralMantissa});
            // console.log("未存入借贷市场!");
        }

        // console.log("exchangeRateMantissa:", exchangeRateMantissa);
        //下面这几个参数是需要调用函数设置的: liquidationIncentiveMantissa
        numerator = mul_(
            Exp({mantissa: liquidationIncentiveMantissa}), //清算激励，奖励
            Exp({mantissa: priceBorrowedMantissa})
        );

        ratio = div_(numerator, denominator);
        seizeTokens = mul_ScalarTruncate(ratio, actualRepayAmount);

        return (uint256(Error.NO_ERROR), seizeTokens);
    }

    function seizeAllowed(
        address pTokenCollateral,
        address pTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external view returns (uint256) {
        // Pausing is a very serious situation - we revert to sound the alarms
        // require(!seizeGuardianPaused, "seize is paused");

        // Shh - currently unused
        seizeTokens;

        // if (!markets[pTokenCollateral].isListed || !markets[pTokenBorrowed].isListed) {
        //     return uint256(Error.MARKET_NOT_LISTED);
        // }

        // if (PToken(pTokenCollateral).comptroller() != PToken(pTokenBorrowed).comptroller()) {
        //     return uint256(Error.COMPTROLLER_MISMATCH);
        // }

        // // Keep the flywheel moving
        // updatePubSupplyIndex(pTokenCollateral);
        // distributeSupplierPub(pTokenCollateral, borrower);
        // distributeSupplierPub(pTokenCollateral, liquidator);

        return uint256(Error.NO_ERROR);
    }

    function getTxAggregator() public view returns (ITXAggregator) {
        require(address(txAggregator) != address(0), "txAggregator is address(0)");
        return txAggregator;
    }

    function getAllMspMarkets() public view returns (IMSPInterface[] memory) {
        return allMspMarkets;
    }

    function openPositionAllowed(address _msp) external returns (uint256) {
        require(!openGuardianPaused[_msp], "openPosition is paused");
        return uint256(Error.NO_ERROR);
    }

    //确保赎回不会导致清算
    function redeemAllowed(
        address _redeemer,
        IMSPInterface _msp,
        uint256 _id,
        address _modifyToken,
        uint256 _redeemTokens
    ) public view returns (uint256) {
        (Error err, , , uint256 shortfall) = getHypotheticalAccountLiquidityInternal(_redeemer, _msp, _id, EIP20Interface(_modifyToken), _redeemTokens, EIP20Interface(0), 0);
        if (err != Error.NO_ERROR) {
            console.log("redeemAllowed err:", uint256(err));
            return uint256(err);
        }

        if (shortfall > 0) {
            //shortfall是第三个参数，当shortfall >0时，说明要被清算了，即不允许redeem了
            return uint256(Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint256(Error.NO_ERROR);
    }

    //直接清算获取0.08利润
    function seizeBenifit(uint256 borrowBalance) external view returns (uint256) {
        Exp memory benift = Exp({mantissa: liquidationIncentiveMantissa - 1e18});
        uint256 seizeTokens = mul_ScalarTruncate(benift, borrowBalance);
        return seizeTokens;
    }

    function benifitToLiquidator(uint256 _benifits) external view returns (uint256) {
        Exp memory ratio = Exp({mantissa: liquidatorRatioMantissa});
        uint256 seizeTokens = mul_ScalarTruncate(ratio, _benifits);
        return seizeTokens;
    }

    //是否允许直接清算
    function isDirectlyLiquidationAllowed() public view returns (bool) {
        return directlyLiquidationState;
    }

    //设置直接清算允许开关
    function setDirectlyLiquidationState(bool _newState) public onlyOwner {
        bool oldState = directlyLiquidationState;
        directlyLiquidationState = _newState;

        emit NewDirectlyLiquidationStateEvent(oldState, directlyLiquidationState);
    } 

    //设置清算人（直接清算)收益比例
    function setLiquidatorRatioMantissa(uint256 _newRatioMantissa) public {
        require(_newRatioMantissa <= liquidatorRatioMaxMantissa, "liquidatorRatioMaxMantissa reached!");
        uint256 oldRatioMantissa = liquidatorRatioMantissa;
        liquidatorRatioMantissa = _newRatioMantissa;

        emit NewLiquidatorRatioMantissaEvent(oldRatioMantissa, liquidatorRatioMantissa);
    }

    //获取清算人（直接清算)收益比例
    function getLiquidatorRatioMantissa() public view returns (uint256) {
        return liquidatorRatioMantissa;
    }
}
