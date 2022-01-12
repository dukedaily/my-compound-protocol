pragma solidity ^0.5.16;
// pragma experimental ABIEncoderV2;

import "./PToken.sol";
import "./ErrorReporter.sol";
import "./PriceOracle.sol";
import "./ComptrollerInterface.sol";
import "./ComptrollerStorage.sol";
import "./Unitroller.sol";
import "./Governance/Publ.sol";
// import "hardhat/console.sol";

/**
 * @title Publics' Comptroller Contract
 * @author Publics
 */
contract Comptroller is ComptrollerV5Storage, ComptrollerInterface, ComptrollerErrorReporter, ExponentialNoError{
    /// @notice Emitted when an admin supports a market
    event MarketListed(PToken pToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(PToken pToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(PToken pToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(uint256 oldCloseFactorMantissa, uint256 newCloseFactorMantissa);

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(PToken pToken, uint256 oldCollateralFactorMantissa, uint256 newCollateralFactorMantissa);

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(uint256 oldLiquidationIncentiveMantissa, uint256 newLiquidationIncentiveMantissa);

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(PriceOracle oldPriceOracle, PriceOracle newPriceOracle);

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(PToken pToken, string action, bool pauseState);

    /// @notice Emitted when a new PUBL speed is calculated for a market
    event PubSpeedUpdated(PToken indexed pToken, uint256 newSpeed);

    /// @notice Emitted when a new PUBL speed is set for a contributor
    event ContributorPubSpeedUpdated(address indexed contributor, uint256 newSpeed);

    /// @notice Emitted when PUBL is distributed to a supplier
    event DistributedSupplierPub(LoanType loanType, PToken indexed pToken, address indexed supplier, uint256 pubDelta, uint256 pubSupplyIndex, uint256 supplierAccrued);

    /// @notice Emitted when PUBL is distributed to a borrower
    event DistributedBorrowerPub(PToken indexed pToken, address indexed borrower, uint256 pubDelta, uint256 pubBorrowIndex);

    /// @notice Emitted when borrow cap for a pToken is changed
    event NewBorrowCap(PToken indexed pToken, uint256 newBorrowCap);

    /// @notice Emitted when borrow cap guardian is changed
    event NewBorrowCapGuardian(address oldBorrowCapGuardian, address newBorrowCapGuardian);

    /// @notice Emitted when PUBL is granted by admin
    event PubGranted(address recipient, uint256 amount);

    /// @notice The initial PUBL index for a market
    uint224 public constant pubInitialIndex = 1e36;

    // closeFactorMantissa must be strictly greater than this value
    uint256 internal constant closeFactorMinMantissa = 0.05e18; // 0.05

    // closeFactorMantissa must not exceed this value
    uint256 internal constant closeFactorMaxMantissa = 0.9e18; // 0.9 //清算因子，表示清算比例，publics现在是0.5

    // No collateralFactorMantissa may exceed this value
    uint256 internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9 //抵押物质量，0 - 0.9之间

    constructor() public {
        admin = msg.sender;
    }

    /**
     * @notice Add the market to the markets mapping and set it as listed
     * @dev Admin function to set isListed and add support for the market
     * @param pToken The address of the market (token) to list
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _supportMarket(PToken pToken) external returns (uint256) {
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SUPPORT_MARKET_OWNER_CHECK);
        }

        if (markets[address(pToken)].isListed) {
            return fail(Error.MARKET_ALREADY_LISTED, FailureInfo.SUPPORT_MARKET_EXISTS);
        }

        pToken.isPToken(); // Sanity check to make sure its really a PToken

        // Note that isPubed is not in active use anymore
        markets[address(pToken)] = Market({ isListed: true, isPubed: false, collateralFactorMantissa: 0 });

        _addMarketInternal(address(pToken));

        emit MarketListed(pToken);

        return uint256(Error.NO_ERROR);
    }

    function _addMarketInternal(address pToken) internal {
        for (uint256 i = 0; i < allMarkets.length; i++) {
            require(allMarkets[i] != PToken(pToken), "market already added");
        }
        allMarkets.push(PToken(pToken));
    }

    /*** Assets You Are In ***/

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    //返回所有用户的pToken资产，在enterMarket的时候对数组进行push，说明可以当做抵押物的资产
    function getAssetsIn(address account) external view returns (PToken[] memory) {
        PToken[] memory assetsIn = accountAssets[account];

        return assetsIn;
    }

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param pToken The pToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    //查看一个用户地址是否参与了抵押
    function checkMembership(address account, PToken pToken) external view returns (bool) {
        return markets[address(pToken)].accountMembership[account];
    }

    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param pTokens The list of addresses of the pToken markets to be enabled
     * @return Success indicator for whether each corresponding market was entered
     */
    function enterMarkets(address[] memory pTokens) public returns (uint256[] memory) {
        uint256 len = pTokens.length;

        uint256[] memory results = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            PToken pToken = PToken(pTokens[i]);

            results[i] = uint256(addToMarketInternal(pToken, msg.sender));
        }

        return results;
    }

    /**
     * @notice Add the market to the borrower's "assets in" for liquidity calculations
     * @param pToken The market to enter
     * @param borrower The address of the account to modify
     * @return Success indicator for whether the market was entered
     */
    function addToMarketInternal(PToken pToken, address borrower) internal returns (Error) {
        Market storage marketToJoin = markets[address(pToken)];

        //先调用supportMarket之后，isListed才会变为true
        if (!marketToJoin.isListed) {
            // market is not listed, cannot join
            return Error.MARKET_NOT_LISTED;
        }

        if (marketToJoin.accountMembership[borrower] == true) {
            // already joined
            return Error.NO_ERROR;
        }

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        marketToJoin.accountMembership[borrower] = true;
        //只有参与借贷（作抵押）的pToken才会添加到accountAssets中，普通的存款不会添加进来
        accountAssets[borrower].push(pToken);

        emit MarketEntered(pToken, borrower);

        return Error.NO_ERROR;
    }

    /**
     * @notice Removes asset from sender's account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param pTokenAddress The address of the asset to be removed
     * @return Whether or not the account successfully exited the market
     */
    function exitMarket(address pTokenAddress) external returns (uint256) {
        PToken pToken = PToken(pTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the pToken */
        (uint256 oErr, uint256 tokensHeld, uint256 amountOwed, ) = pToken.getAccountSnapshot(msg.sender, 0, LoanType.NORMAL);
        require(oErr == 0, "exitMarket: getAccountSnapshot failed"); // semi-opaque error code

        /* Fail if the sender has a borrow balance */
        if (amountOwed != 0) {
            return fail(Error.NONZERO_BORROW_BALANCE, FailureInfo.EXIT_MARKET_BALANCE_OWED);
        }

        /* Fail if the sender is not permitted to redeem all of their tokens */
        uint256 allowed = redeemAllowedInternal(pTokenAddress, msg.sender, tokensHeld, LoanType.NORMAL);
        if (allowed != 0) {
            return failOpaque(Error.REJECTION, FailureInfo.EXIT_MARKET_REJECTION, allowed);
        }

        Market storage marketToExit = markets[address(pToken)];

        /* Return true if the sender is not already ‘in’ the market */
        if (!marketToExit.accountMembership[msg.sender]) {
            return uint256(Error.NO_ERROR);
        }

        /* Set pToken account membership to false */
        //首先从market内部删掉，保证当前account退出市场,返回false
        delete marketToExit.accountMembership[msg.sender];

        /* Delete pToken from the account’s list of assets */
        // load into memory for faster iteration
        PToken[] memory userAssetList = accountAssets[msg.sender];
        uint256 len = userAssetList.length;
        uint256 assetIndex = len;
        for (uint256 i = 0; i < len; i++) {
            if (userAssetList[i] == pToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);

        // copy last item in list to location of item to be removed, reduce length by 1
        PToken[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.length--;

        emit MarketExited(pToken, msg.sender);

        return uint256(Error.NO_ERROR);
    }

    /*** Policy Hooks ***/

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param pToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @return 0 if the mint is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function mintAllowed(
        address pToken,
        address minter,
        uint256 mintAmount, 
        LoanType loanType
    ) external returns (uint256) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!mintGuardianPaused[pToken], "mint is paused");

        // Shh - currently unused
        minter;
        mintAmount;

        if (!markets[pToken].isListed) {
            return uint256(Error.MARKET_NOT_LISTED);
        }

        // Keep the flywheel moving
        updatePubSupplyIndex(pToken);
        distributeSupplierPub(pToken, minter, loanType); 

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Validates mint and reverts on rejection. May emit logs.
     * @param pToken Asset being minted
     * @param minter The address minting the tokens
     * @param actualMintAmount The amount of the underlying asset being minted
     * @param mintTokens The number of tokens being minted
     */
    function mintVerify(
        address pToken,
        address minter,
        uint256 actualMintAmount,
        uint256 mintTokens
    ) external {
        // Shh - currently unused
        pToken;
        minter;
        actualMintAmount;
        mintTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param pToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of pTokens to exchange for the underlying asset in the market
     * @return 0 if the redeem is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function redeemAllowed(
        address pToken,
        address redeemer,
        uint256 redeemTokens,
        LoanType loanType
    ) external returns (uint256) {
        uint256 allowed = redeemAllowedInternal(pToken, redeemer, redeemTokens, loanType);
        if (allowed != uint256(Error.NO_ERROR)) {
            return allowed;
        }

        // Keep the flywheel moving
        updatePubSupplyIndex(pToken);
        distributeSupplierPub(pToken, redeemer, loanType);

        return uint256(Error.NO_ERROR);
    }

    function redeemAllowedInternal(
        address pToken,
        address redeemer,
        uint256 redeemTokens,
        LoanType loanType
    ) internal view returns (uint256) {
        if (!markets[pToken].isListed) {
            return uint256(Error.MARKET_NOT_LISTED);
        }

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        //如果没有添加到借贷市场，那么不存在抵押问题，也就可以直接允许赎回了，反之如果已经当做抵押了，就必须结合抵押数量来计算赎回情况
        if (!markets[pToken].accountMembership[redeemer]) {
            return uint256(Error.NO_ERROR);
        }

        if (LoanType.NORMAL == loanType) {
            /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
            //如果发现取款之后会导致清算，那么取款被拒绝
            (Error err, , uint256 shortfall) = getHypotheticalAccountLiquidityInternal(redeemer, PToken(pToken), redeemTokens, 0);

            if (err != Error.NO_ERROR) {
                return uint256(err);
            }
            if (shortfall > 0) {
                //shortfall是第三个参数，当shortfall >0时，说明要被清算了，即不允许redeem了
                return uint256(Error.INSUFFICIENT_LIQUIDITY);
            }
        }

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Validates redeem and reverts on rejection. May emit logs.
     * @param pToken Asset being redeemed
     * @param redeemer The address redeeming the tokens
     * @param redeemAmount The amount of the underlying asset being redeemed
     * @param redeemTokens The number of tokens being redeemed
     */
    function redeemVerify(
        address pToken,
        address redeemer,
        uint256 redeemAmount,
        uint256 redeemTokens
    ) external {
        // Shh - currently unused
        pToken;
        redeemer;

        // Require tokens is zero or amount is also zero
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert("redeemTokens zero");
        }
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param pToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     * @return 0 if the borrow is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function borrowAllowed(
        address pToken,
        address creditLoanBorrower,
        address borrower,
        uint256 borrowAmount,
        LoanType loanType
    ) external returns (uint256) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!borrowGuardianPaused[pToken], "borrow is paused");

        if (!markets[pToken].isListed) {
            return uint256(Error.MARKET_NOT_LISTED);
        }

        if (LoanType.NORMAL == loanType) {
            if (!markets[pToken].accountMembership[borrower]) {
                // only pTokens may call borrowAllowed if borrower not in market
                require(msg.sender == pToken, "sender must be pToken");

                // attempt to add borrower to the market
                Error err = addToMarketInternal(PToken(msg.sender), borrower);
                if (err != Error.NO_ERROR) {
                    return uint256(err);
                }

                // it should be impossible to break the important invariant
                assert(markets[pToken].accountMembership[borrower]);
            }
        }
        (uint256 price,) = oracle.getUnderlyingPrice(PToken(pToken));
        if (price == 0) {
            return uint256(Error.PRICE_ERROR);
        }

        //这个pToken能够被借出的最大值
        uint256 borrowCap = borrowCaps[pToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint256 totalBorrows = PToken(pToken).totalBorrows();
            uint256 nextTotalBorrows = add_(totalBorrows, borrowAmount);
            require(nextTotalBorrows < borrowCap, "market borrow cap reached");
        }

        //如果是信用贷，则不用执行
        if (LoanType.NORMAL == loanType) {
            //如果借款导致被清算，则借款被拒绝
            (Error err, , uint256 shortfall) = getHypotheticalAccountLiquidityInternal(borrower, PToken(pToken), 0, borrowAmount);

            if (err != Error.NO_ERROR) {
                return uint256(err);
            }

            //shortfall应该小于等于0才对
            if (shortfall > 0) {
                return uint256(Error.INSUFFICIENT_LIQUIDITY); //borrow时候报错了
            }
        }

        // Keep the flywheel moving
        Exp memory borrowIndex = Exp({ mantissa: PToken(pToken).borrowIndex() });
        updatePubBorrowIndex(pToken, borrowIndex);
        distributeBorrowerPub(pToken, borrower, borrowIndex, loanType);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Validates borrow and reverts on rejection. May emit logs.
     * @param pToken Asset whose underlying is being borrowed
     * @param borrower The address borrowing the underlying
     * @param borrowAmount The amount of the underlying asset requested to borrow
     */
    function borrowVerify(
        address pToken,
        address borrower,
        uint256 borrowAmount
    ) external {
        // Shh - currently unused
        pToken;
        borrower;
        borrowAmount;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param pToken The market to verify the repay against
     * @param payer The account which would repay the asset
     * @param borrower The account which would borrowed the asset
     * @param repayAmount The amount of the underlying asset the account would repay
     * @return 0 if the repay is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function repayBorrowAllowed(
        address pToken,
        address payer,
        address borrower,
        uint256 repayAmount,
        LoanType loanType
    ) external returns (uint256) {
        // Shh - currently unused
        // payer;
        // borrower;
        repayAmount;

        if (!markets[pToken].isListed) {
            return uint256(Error.MARKET_NOT_LISTED);
        }

        // Keep the flywheel moving
        Exp memory borrowIndex = Exp({ mantissa: PToken(pToken).borrowIndex()});
        updatePubBorrowIndex(pToken, borrowIndex);
        distributeBorrowerPub(pToken, borrower, borrowIndex, loanType);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Validates repayBorrow and reverts on rejection. May emit logs.
     * @param pToken Asset being repaid
     * @param payer The address repaying the borrow
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function repayBorrowVerify(
        address pToken,
        address payer,
        address borrower,
        uint256 actualRepayAmount,
        uint256 borrowerIndex
    ) external {
        // Shh - currently unused
        pToken;
        payer;
        borrower;
        actualRepayAmount;
        borrowerIndex;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param pTokenBorrowed Asset which was borrowed by the borrower
     * @param pTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     */
    function liquidateBorrowAllowed(
        address pTokenBorrowed, //pToken
        address pTokenCollateral, //抵押的pToken地址
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256) {
        // Shh - currently unused
        liquidator;


        if (!markets[pTokenBorrowed].isListed || !markets[pTokenCollateral].isListed) {
            return uint256(Error.MARKET_NOT_LISTED);
        }

        /* The borrower must have shortfall in order to be liquidatable */
        //查看是否可以被清算
        (Error err, , uint256 shortfall) = getAccountLiquidityInternal(borrower);

        if (err != Error.NO_ERROR) {
            return uint256(err);
        }

        if (shortfall == 0) {
            return uint256(Error.INSUFFICIENT_SHORTFALL); //ERROR  3
        }

        /* The liquidator may not repay more than what is allowed by the closeFactor */
        uint256 borrowBalance = PToken(pTokenBorrowed).borrowBalanceStored(borrower, 0, LoanType.NORMAL);
        uint256 maxClose = mul_ScalarTruncate(Exp({ mantissa: closeFactorMantissa }), borrowBalance);
        if (repayAmount > maxClose) {
            return uint256(Error.TOO_MUCH_REPAY); //error: 17
        }

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Validates liquidateBorrow and reverts on rejection. May emit logs.
     * @param pTokenBorrowed Asset which was borrowed by the borrower
     * @param pTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function liquidateBorrowVerify(
        address pTokenBorrowed,
        address pTokenCollateral,
        address liquidator,
        address borrower,
        uint256 actualRepayAmount,
        uint256 seizeTokens
    ) external {
        // Shh - currently unused
        pTokenBorrowed;
        pTokenCollateral;
        liquidator;
        borrower;
        actualRepayAmount;
        seizeTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param pTokenCollateral Asset which was used as collateral and will be seized
     * @param pTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeAllowed(
        address pTokenCollateral,
        address pTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external returns (uint256) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!seizeGuardianPaused, "seize is paused");

        // Shh - currently unused
        seizeTokens;

        if (!markets[pTokenCollateral].isListed || !markets[pTokenBorrowed].isListed) {
            return uint256(Error.MARKET_NOT_LISTED);
        }

        if (PToken(pTokenCollateral).comptroller() != PToken(pTokenBorrowed).comptroller()) {
            return uint256(Error.COMPTROLLER_MISMATCH);
        }

        // Keep the flywheel moving
        updatePubSupplyIndex(pTokenCollateral);
        distributeSupplierPub(pTokenCollateral, borrower, LoanType.NORMAL);
        distributeSupplierPub(pTokenCollateral, liquidator, LoanType.NORMAL);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Validates seize and reverts on rejection. May emit logs.
     * @param pTokenCollateral Asset which was used as collateral and will be seized
     * @param pTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeVerify(
        address pTokenCollateral,
        address pTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external {
        // Shh - currently unused
        pTokenCollateral;
        pTokenBorrowed;
        liquidator;
        borrower;
        seizeTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param pToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of pTokens to transfer
     * @return 0 if the transfer is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function transferAllowed(
        address pToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external returns (uint256) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!transferGuardianPaused, "transfer is paused");

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        uint256 allowed = redeemAllowedInternal(pToken, src, transferTokens, LoanType.NORMAL);
        if (allowed != uint256(Error.NO_ERROR)) {
            return allowed;
        }

        // Keep the flywheel moving
        updatePubSupplyIndex(pToken);
        distributeSupplierPub(pToken, src, LoanType.NORMAL);
        distributeSupplierPub(pToken, dst, LoanType.NORMAL);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Validates transfer and reverts on rejection. May emit logs.
     * @param pToken Asset being transferred
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of pTokens to transfer
     */
    function transferVerify(
        address pToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external {
        // Shh - currently unused
        pToken;
        src;
        dst;
        transferTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /*** Liquidity/Liquidation Calculations ***/

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *  Note that `pTokenBalance` is the number of pTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountLiquidityLocalVars {
        uint256 sumCollateral;
        uint256 sumBorrowPlusEffects;
        uint256 pTokenBalance;
        uint256 borrowBalance;
        uint256 exchangeRateMantissa;
        uint256 oraclePriceMantissa;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements(wrt: with regarding to 关于)
     * @return (possible error code (semi-opaque),
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    //单独调用，判断是否可以被清算
    function getAccountLiquidity(address account)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        (Error err, uint256 liquidity, uint256 shortfall) = getHypotheticalAccountLiquidityInternal(account, PToken(0), 0, 0);

        return (uint256(err), liquidity, shortfall);
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (possible error code,
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidityInternal(address account)
        internal
        view
        returns (
            Error,
            uint256,
            uint256
        )
    {
        return getHypotheticalAccountLiquidityInternal(account, PToken(0), 0, 0);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param pTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return (possible error code (semi-opaque),
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address pTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    )
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        (Error err, uint256 liquidity, uint256 shortfall) = getHypotheticalAccountLiquidityInternal(account, PToken(pTokenModify), redeemTokens, borrowAmount);

        return (uint256(err), liquidity, shortfall);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param pTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @dev Note that we calculate the exchangeRateStored for each collateral pToken using stored data,
     *  without calculating accumulated interest.
     * @return (possible error code,
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidityInternal(
        address account,
        PToken pTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    )
        internal
        view
        returns (
            Error,
            uint256,
            uint256
        )
    {
        AccountLiquidityLocalVars memory vars; // Holds all our calculation results
        uint256 oErr;

        // For each asset the account is in
        PToken[] memory assets = accountAssets[account]; //accountAssets存在于comptroller中
        for (uint256 i = 0; i < assets.length; i++) {
            PToken asset = assets[i];

            // Read the balances and exchange rate from the pToken
            //1. 获取当前这个account的资产状况: 持有的PToken，持有的underlying，ptoken兑换underlying的exchageRate
            (oErr, vars.pTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = asset.getAccountSnapshot(account, 0, LoanType.NORMAL);

            if (oErr != 0) {
                // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
                return (Error.SNAPSHOT_ERROR, 0, 0);
            }

            vars.collateralFactor = Exp({ mantissa: markets[address(asset)].collateralFactorMantissa }); //LTV: loan to value,最大能借的比例
            vars.exchangeRate = Exp({ mantissa: vars.exchangeRateMantissa }); //转成结构体

            // Get the normalized price of the asset
            (vars.oraclePriceMantissa,) = oracle.getUnderlyingPrice(asset);
            if (vars.oraclePriceMantissa == 0) {
                return (Error.PRICE_ERROR, 0, 0);
            }
            vars.oraclePrice = Exp({ mantissa: vars.oraclePriceMantissa });

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            vars.tokensToDenom = mul_(mul_(vars.collateralFactor, vars.exchangeRate), vars.oraclePrice);

            // sumCollateral += tokensToDenom * pTokenBalance
            vars.sumCollateral = mul_ScalarTruncateAddUInt(vars.tokensToDenom, vars.pTokenBalance, vars.sumCollateral);

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, vars.borrowBalance, vars.sumBorrowPlusEffects);

            // Calculate effects of interacting with pTokenModify
            //无论是赎回还是借款，都会使借款能力下降（可以等价看成sumBorrowPlusEffects变大）
            if (asset == pTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.tokensToDenom, redeemTokens, vars.sumBorrowPlusEffects);

                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, borrowAmount, vars.sumBorrowPlusEffects);
            }
        } //for

        // These are safe, as the underflow condition is checked first
        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            //liquidity = vars.sumCollateral - vars.sumBorrowPlusEffects
            //不清算
            return (Error.NO_ERROR, vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
        } else {
            //清算
            return (Error.NO_ERROR, 0, vars.sumBorrowPlusEffects - vars.sumCollateral);
        }
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in pToken.liquidateBorrowFresh)
     * @param pTokenBorrowed The address of the borrowed pToken
     * @param pTokenCollateral The address of the collateral pToken
     * @param actualRepayAmount The amount of pTokenBorrowed underlying to convert into pTokenCollateral tokens
     * @return (errorCode, number of pTokenCollateral tokens to be seized in a liquidation)
     */
    function liquidateCalculateSeizeTokens(
        address pTokenBorrowed,
        address pTokenCollateral,
        uint256 actualRepayAmount
    ) external view returns (uint256, uint256) {
        /* Read oracle prices for borrowed and collateral markets */
        (uint256 priceBorrowedMantissa,) = oracle.getUnderlyingPrice(PToken(pTokenBorrowed)); //传入pToken地址，会转换为对应underlying地址
        (uint256 priceCollateralMantissa,) = oracle.getUnderlyingPrice(PToken(pTokenCollateral));
        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            return (uint256(Error.PRICE_ERROR), 0);
        }

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint256 exchangeRateMantissa = PToken(pTokenCollateral).exchangeRateStored(); // Note: reverts on error
        uint256 seizeTokens;
        Exp memory numerator;
        Exp memory denominator;
        Exp memory ratio;

        numerator = mul_(
            Exp({ mantissa: liquidationIncentiveMantissa }),
            Exp({ mantissa: priceBorrowedMantissa })
        );
        denominator = mul_(Exp({ mantissa: priceCollateralMantissa }), Exp({ mantissa: exchangeRateMantissa }));
        ratio = div_(numerator, denominator);

        seizeTokens = mul_ScalarTruncate(ratio, actualRepayAmount);

        return (uint256(Error.NO_ERROR), seizeTokens);
    }

    /*** Admin Functions ***/

    /**
     * @notice Sets a new price oracle for the comptroller
     * @dev Admin function to set a new price oracle
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setPriceOracle(PriceOracle newOracle) public returns (uint256) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PRICE_ORACLE_OWNER_CHECK);
        }

        // Track the old oracle for the comptroller
        PriceOracle oldOracle = oracle;

        // Set comptroller's oracle to newOracle
        oracle = newOracle;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, newOracle);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Sets the closeFactor used when liquidating borrows
     * @dev Admin function to set closeFactor
     * @param newCloseFactorMantissa New close factor, scaled by 1e18
     * @return uint 0=success, otherwise a failure
     */
    //0.5，表示清算50%，无初始值, 需要自己手动设置
    function _setCloseFactor(uint256 newCloseFactorMantissa) external returns (uint256) {
        // Check caller is admin
        require(msg.sender == admin, "only admin can set close factor");

        uint256 oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Sets the collateralFactor for a market
     * @dev Admin function to set per-market collateralFactor
     * @param pToken The market to set the factor on
     * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
     * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
     */
    //需要手动调用: 800000000000000000， 表示0.8e18
    function _setCollateralFactor(PToken pToken, uint256 newCollateralFactorMantissa) external returns (uint256) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_COLLATERAL_FACTOR_OWNER_CHECK);
        }

        // Verify market is listed
        Market storage market = markets[address(pToken)];
        if (!market.isListed) {
            return fail(Error.MARKET_NOT_LISTED, FailureInfo.SET_COLLATERAL_FACTOR_NO_EXISTS);
        }

        Exp memory newCollateralFactorExp = Exp({ mantissa: newCollateralFactorMantissa });

        // Check collateral factor <= 0.9
        Exp memory highLimit = Exp({ mantissa: collateralFactorMaxMantissa });
        if (lessThanExp(highLimit, newCollateralFactorExp)) {
            return fail(Error.INVALID_COLLATERAL_FACTOR, FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION);
        }

        // If collateral factor != 0, fail if price == 0
        (uint256 price,) = oracle.getUnderlyingPrice(PToken(pToken));
        if (newCollateralFactorMantissa != 0 && price == 0) {
            return fail(Error.PRICE_ERROR, FailureInfo.SET_COLLATERAL_FACTOR_WITHOUT_PRICE);
        }

        // Set market's collateral factor to new collateral factor, remember old value
        uint256 oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(pToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Sets liquidationIncentive
     * @dev Admin function to set liquidationIncentive
     * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
     * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
     */
    //设置1.08，表示获得8%的奖励
    function _setLiquidationIncentive(uint256 newLiquidationIncentiveMantissa) external returns (uint256) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_LIQUIDATION_INCENTIVE_OWNER_CHECK);
        }

        // Save current value for use in log
        uint256 oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;

        // Set liquidation incentive to new incentive
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;

        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(oldLiquidationIncentiveMantissa, newLiquidationIncentiveMantissa);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Set the given borrow caps for the given pToken markets. Borrowing that brings total borrows to or above borrow cap will revert.
     * @dev Admin or borrowCapGuardian function to set the borrow caps. A borrow cap of 0 corresponds to unlimited borrowing.
     * @param pTokens The addresses of the markets (tokens) to change the borrow caps for
     * @param newBorrowCaps The new borrow cap values in underlying to be set. A value of 0 corresponds to unlimited borrowing.
     */
    //每个资产能够借出的上限
    function _setMarketBorrowCaps(PToken[] calldata pTokens, uint256[] calldata newBorrowCaps) external {
        require(msg.sender == admin || msg.sender == borrowCapGuardian, "only admin or borrow cap guardian can set borrow caps");

        uint256 numMarkets = pTokens.length;
        uint256 numBorrowCaps = newBorrowCaps.length;

        require(numMarkets != 0 && numMarkets == numBorrowCaps, "invalid input");

        for (uint256 i = 0; i < numMarkets; i++) {
            borrowCaps[address(pTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(pTokens[i], newBorrowCaps[i]);
        }
    }

    /**
     * @notice Admin function to change the Borrow Cap Guardian
     * @param newBorrowCapGuardian The address of the new Borrow Cap Guardian
     */
    function _setBorrowCapGuardian(address newBorrowCapGuardian) external {
        require(msg.sender == admin, "only admin can set borrow cap guardian");

        // Save current value for inclusion in log
        address oldBorrowCapGuardian = borrowCapGuardian;

        // Store borrowCapGuardian with value newBorrowCapGuardian
        borrowCapGuardian = newBorrowCapGuardian;

        // Emit NewBorrowCapGuardian(OldBorrowCapGuardian, NewBorrowCapGuardian)
        emit NewBorrowCapGuardian(oldBorrowCapGuardian, newBorrowCapGuardian);
    }

    /**
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _setPauseGuardian(address newPauseGuardian) public returns (uint256) {
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PAUSE_GUARDIAN_OWNER_CHECK);
        }

        // Save current value for inclusion in log
        address oldPauseGuardian = pauseGuardian;

        // Store pauseGuardian with value newPauseGuardian
        pauseGuardian = newPauseGuardian;

        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);

        return uint256(Error.NO_ERROR);
    }

    function _setMintPaused(PToken pToken, bool state) public returns (bool) {
        require(markets[address(pToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        mintGuardianPaused[address(pToken)] = state;
        emit ActionPaused(pToken, "Mint", state);
        return state;
    }

    function _setBorrowPaused(PToken pToken, bool state) public returns (bool) {
        require(markets[address(pToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        borrowGuardianPaused[address(pToken)] = state;
        emit ActionPaused(pToken, "Borrow", state);
        return state;
    }

    function _setTransferPaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    function _setSeizePaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    function _become(Unitroller unitroller) public {
        require(msg.sender == unitroller.admin(), "only unitroller admin can change brains");
        require(unitroller._acceptImplementation() == 0, "change not authorized");
    }

    /**
     * @notice Checks caller is admin, or this contract is becoming the new implementation
     */
    function adminOrInitializing() internal view returns (bool) {
        return msg.sender == admin || msg.sender == comptrollerImplementation;
    }

    /*** Publ Distribution ***/

    /**
     * @notice Set PUBL speed for a single market
     * @param pToken The market whose PUBL speed to update
     * @param pubSpeed New PUBL speed for market
     */
    function setPubSpeedInternal(PToken pToken, uint256 pubSpeed) internal {
        uint256 currentPubSpeed = pubSpeeds[address(pToken)];
        if (currentPubSpeed != 0) {
            // note that PUBL speed could be set to 0 to halt liquidity rewards for a market
            Exp memory borrowIndex = Exp({ mantissa: pToken.borrowIndex() });
            updatePubSupplyIndex(address(pToken));
            updatePubBorrowIndex(address(pToken), borrowIndex);
        } else if (pubSpeed != 0) {
            // Add the PUBL market
            Market storage market = markets[address(pToken)];
            require(market.isListed == true, "publ market is not listed");

            if (pubSupplyState[address(pToken)].index == 0 && pubSupplyState[address(pToken)].block == 0) {
                pubSupplyState[address(pToken)] = PubMarketState({ index: pubInitialIndex, block: safe32(getBlockNumber(), "block number exceeds 32 bits") });
            }

            if (pubBorrowState[address(pToken)].index == 0 && pubBorrowState[address(pToken)].block == 0) {
                pubBorrowState[address(pToken)] = PubMarketState({ index: pubInitialIndex, block: safe32(getBlockNumber(), "block number exceeds 32 bits") });
            }
        }

        if (currentPubSpeed != pubSpeed) {
            pubSpeeds[address(pToken)] = pubSpeed;
            emit PubSpeedUpdated(pToken, pubSpeed);
        }
    }

    /**
     * @notice Accrue PUBL to the market by updating the supply index
     * @param pToken The market whose supply index to update
     */
    function updatePubSupplyIndex(address pToken) internal {
        PubMarketState storage supplyState = pubSupplyState[pToken];
        uint256 supplySpeed = pubSpeeds[pToken];//先使用固定的 //TODO
        // to get the dynamic supply speed
        // uint256 supplySpeed = PToken(pToken).getSupplyPubSpeed();
        // console.log("updatePubSupplyIndex::supplySpeed:", supplySpeed);
        uint256 blockNumber = getBlockNumber();
        uint256 deltaBlocks = sub_(blockNumber, uint256(supplyState.block));
        if (deltaBlocks > 0 && supplySpeed > 0) {
            uint256 supplyTokens = PToken(pToken).totalSupply();
            uint256 pubAccrued = mul_(deltaBlocks, supplySpeed);
            // console.log("supplySpeed:", supplySpeed, "deltaBlocks:", deltaBlocks);
            Double memory ratio = supplyTokens > 0 ? fraction(pubAccrued, supplyTokens) : Double({ mantissa: 0 });
            // console.log("supplyTokens:", supplyTokens, "ratio:", ratio.mantissa);
            Double memory index = add_(Double({ mantissa: supplyState.index }), ratio);
            // console.log("index:", index.mantissa);
            pubSupplyState[pToken] = PubMarketState({ index: safe224(index.mantissa, "new index exceeds 224 bits"), block: safe32(blockNumber, "block number exceeds 32 bits") });
        } else if (deltaBlocks > 0) {
            supplyState.block = safe32(blockNumber, "block number exceeds 32 bits");
        }
    }

    /**
     * @notice Accrue PUBL to the market by updating the borrow index
     * @param pToken The market whose borrow index to update
     */
    function updatePubBorrowIndex(address pToken, Exp memory marketBorrowIndex) internal {
        PubMarketState storage borrowState = pubBorrowState[pToken];
        uint256 borrowSpeed = pubSpeeds[pToken]; //先使用固定的 //TODO
        // to get the dynamic borrow speed
        // uint256 borrowSpeed = PToken(pToken).getBorrowPubSpeed();
        // console.log("borrowSpeed:", borrowSpeed);
        uint256 blockNumber = getBlockNumber();
        uint256 deltaBlocks = sub_(blockNumber, uint256(borrowState.block));
        if (deltaBlocks > 0 && borrowSpeed > 0) {
            uint256 borrowAmount = div_(PToken(pToken).totalBorrows(), marketBorrowIndex);
            uint256 pubAccrued = mul_(deltaBlocks, borrowSpeed);
            Double memory ratio = borrowAmount > 0 ? fraction(pubAccrued, borrowAmount) : Double({ mantissa: 0 });
            // console.log("updatePubBorrowIndex ratio:", ratio.mantissa, ", borrowAmount:", borrowAmount);
            Double memory index = add_(Double({ mantissa: borrowState.index }), ratio);
            pubBorrowState[pToken] = PubMarketState({ index: safe224(index.mantissa, "new index exceeds 224 bits"), block: safe32(blockNumber, "block number exceeds 32 bits") });
        } else if (deltaBlocks > 0) {
            borrowState.block = safe32(blockNumber, "block number exceeds 32 bits");
        }
    }

    /**
     * @notice Calculate PUBL accrued by a supplier and possibly transfer it to them
     * @param pToken The market in which the supplier is interacting
     * @param supplier The address of the supplier to distribute PUBL to
     */
    function distributeSupplierPub(address pToken, address supplier, LoanType loanType) internal {
        PubMarketState storage supplyState = pubSupplyState[pToken];
        Double memory supplyIndex = Double({ mantissa: supplyState.index});

        Double memory supplierIndex = Double({ mantissa: pubSupplierIndex[pToken][uint256(loanType)][supplier]});
        pubSupplierIndex[pToken][uint256(loanType)][supplier] = supplyIndex.mantissa;
        uint256 supplierTokens = PToken(pToken).balanceOfCreditLoan(supplier, loanType);

        if (supplierIndex.mantissa == 0 && supplyIndex.mantissa > 0) {
            supplierIndex.mantissa = pubInitialIndex;
            // console.log("init supplierIndex.mantissa:", supplierIndex.mantissa);
        }

        // console.log("supplyIndex:" supplyIndex.mantissa, "supplierIndex:", supplierIndex.mantissa);
        Double memory deltaIndex = sub_(supplyIndex, supplierIndex); //新的-旧的
        uint256 supplierDelta = mul_(supplierTokens, deltaIndex);

        uint256 supplierAccrued = add_(pubAccrued[uint256(loanType)][supplier], supplierDelta);
        pubAccrued[uint256(loanType)][supplier] = supplierAccrued;

        emit DistributedSupplierPub(loanType, PToken(pToken), supplier, supplierDelta, supplyIndex.mantissa, supplierAccrued);
    }

    /**
     * @notice Calculate PUBL accrued by a borrower and possibly transfer it to them
     * @dev Borrowers will not begin to accrue until after the first interaction with the protocol.
     * @param pToken The market in which the borrower is interacting
     * @param borrower The address of the borrower to distribute PUBL to
     */
    function distributeBorrowerPub(
        address pToken,
        address borrower,
        Exp memory marketBorrowIndex,
        LoanType loanType
    ) internal {
        PubMarketState storage borrowState = pubBorrowState[pToken];
        Double memory borrowIndex = Double({ mantissa: borrowState.index });
        Double memory borrowerIndex = Double({ mantissa: pubBorrowerIndex[pToken][uint256(loanType)][borrower] });
        // console.log("borrowIndex:", borrowIndex.mantissa, ", borrowerIndex:",borrowerIndex.mantissa);
        pubBorrowerIndex[pToken][uint256(loanType)][borrower] = borrowIndex.mantissa;

        if (borrowerIndex.mantissa > 0) {
            Double memory deltaIndex = sub_(borrowIndex, borrowerIndex);
            // uint256 borrowerAmount = div_(PToken(pToken).borrowBalanceStored(borrower, id, loanType), marketBorrowIndex);
            //未计算借款产生的利息所产生的平台币，影响market市场和信用贷市场 //TODO
            uint256 borrowerAmount = div_(PToken(pToken).getAccountBorrowsCreditLoanTotal(borrower, loanType), marketBorrowIndex);
            uint256 borrowerDelta = mul_(borrowerAmount, deltaIndex);
            uint256 borrowerAccrued = add_(pubAccrued[uint256(loanType)][borrower], borrowerDelta);
            pubAccrued[uint256(loanType)][borrower] = borrowerAccrued;
            emit DistributedBorrowerPub(PToken(pToken), borrower, borrowerDelta, borrowIndex.mantissa);
        }
    }

    /**
     * @notice Calculate additional accrued PUBL for a contributor since last accrual
     * @param contributor The address to calculate contributor rewards for
     */
    function updateContributorRewards(address contributor) public {
        uint256 pubSpeed = pubContributorSpeeds[contributor];
        uint256 blockNumber = getBlockNumber();
        uint256 deltaBlocks = sub_(blockNumber, lastContributorBlock[contributor]);
        if (deltaBlocks > 0 && pubSpeed > 0) {
            uint256 newAccrued = mul_(deltaBlocks, pubSpeed);
            uint256 contributorAccrued = add_(pubAccrued[uint256(LoanType.NORMAL)][contributor], newAccrued);

            pubAccrued[uint256(LoanType.NORMAL)][contributor] = contributorAccrued;
            lastContributorBlock[contributor] = blockNumber;
        }
    }

    struct PubLocalVars {
        address holder;
        LoanType loanType;
        Double supplyIndex;
        Double deltaIndex;
        Exp marketBorrowIndex;
    }
    
    function getUnclaimedPub(address holder, LoanType loanType) public view returns (uint256) {
        uint256 unclaimed = pubAccrued[uint256(loanType)][holder];
        // console.log("unclaimed:", unclaimed);
        
        PubLocalVars memory vars;
        vars.holder = holder;
        vars.loanType = loanType;
        
        for (uint256 i = 0; i < allMarkets.length; i++) {
            PToken market = allMarkets[i];

            uint256 supplierTokens = market.balanceOfCreditLoan(holder, loanType);
            Double memory supplierIndex = Double({mantissa: pubSupplierIndex[address(market)][uint256(loanType)][holder]});
            // console.log("****** pToken:", address(market));

            if (supplierTokens > 0) {
                PubMarketState storage supplyState = pubSupplyState[address(market)];
                vars.supplyIndex = Double({ mantissa: supplyState.index });
                if (supplierIndex.mantissa == 0 && vars.supplyIndex.mantissa > 0) {
                    supplierIndex.mantissa = pubInitialIndex;
                }

                vars.deltaIndex = sub_(vars.supplyIndex, supplierIndex);
                uint256 supplierDelta = mul_(supplierTokens, vars.deltaIndex);
                unclaimed = add_(unclaimed, supplierDelta);
                // console.log("supplierTokens:", supplierTokens, "new supplierDelta:", supplierDelta);
                // console.log("supplierIndex:", supplierIndex.mantissa, "vars.supplyIndex:", vars.supplyIndex.mantissa);
                // console.log("unclaimed:", unclaimed);
            }

            vars.marketBorrowIndex = Exp({ mantissa: market.borrowIndex() });
            uint256 borrowerAmount = div_(market.getAccountBorrowsCreditLoanTotal(holder, loanType), vars.marketBorrowIndex);
            if (borrowerAmount > 0) {
                PubMarketState storage borrowState = pubBorrowState[address(market)];
                Double memory borrowIndex = Double({ mantissa: borrowState.index });
                Double memory borrowerIndex = Double({ mantissa: pubBorrowerIndex[address(market)][uint256(vars.loanType)][vars.holder] });

                if (borrowerIndex.mantissa > 0) {
                    Double memory deltaIndex = sub_(borrowIndex, borrowerIndex);
                    // console.log("borrow deltaIndex:", deltaIndex.mantissa);
                    uint256 borrowerDelta = mul_(borrowerAmount, deltaIndex);
                    unclaimed = add_(unclaimed, borrowerDelta);
                    // console.log("borrowerAmount:", borrowerAmount, "new borrowerDelta:", borrowerDelta);
                    // console.log("borrowerIndex:", borrowerIndex.mantissa, "borroweIndex:", borrowerIndex.mantissa);
                    // console.log("unclaimed:", unclaimed);
                }
            }    
            
        }
        
        return unclaimed;
    }

    /**
     * @notice Claim all the publ accrued by holder in all markets
     * @param holder The address to claim PUBL for
     */
    function claimPubV1(address holder, LoanType loanType) public {
        return claimPubV2(holder, allMarkets, loanType);
    }

    /**
     * @notice Claim all the publ accrued by holder in the specified markets
     * @param holder The address to claim PUBL for
     * @param pTokens The list of markets to claim PUBL in
     */
    function claimPubV2(address holder, PToken[] memory pTokens, LoanType loanType) public {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        claimPubV3(holders, pTokens, true, true, loanType);
    }

    /**
     * @notice Claim all publ accrued by the holders
     * @param holders The addresses to claim PUBL for
     * @param pTokens The list of markets to claim PUBL in
     * @param borrowers Whether or not to claim PUBL earned by borrowing
     * @param suppliers Whether or not to claim PUBL earned by supplying
     */
    function claimPubV3(
        address[] memory holders,
        PToken[] memory pTokens,
        bool borrowers,
        bool suppliers,
        LoanType loanType
    ) public {
        for (uint256 i = 0; i < pTokens.length; i++) {
            PToken pToken = pTokens[i];
            // console.log("------- pToken:", address(pToken));
            require(markets[address(pToken)].isListed, "market must be listed");
            if (borrowers == true) {
                Exp memory borrowIndex = Exp({ mantissa: pToken.borrowIndex() });
                updatePubBorrowIndex(address(pToken), borrowIndex);
                for (uint256 j = 0; j < holders.length; j++) {
                    distributeBorrowerPub(address(pToken), holders[j], borrowIndex, loanType);
                    // console.log("111 borrower j数量:", pubAccrued[uint256(loanType)][holders[j]]);
                    pubAccrued[uint256(loanType)][holders[j]] = grantPubInternal(holders[j], pubAccrued[uint256(loanType)][holders[j]]);
                }
            }
            if (suppliers == true) {
                updatePubSupplyIndex(address(pToken));
                for (uint256 j = 0; j < holders.length; j++) {
                    distributeSupplierPub(address(pToken), holders[j], loanType);
                    // console.log("222 suppliers j:", pubAccrued[uint256(loanType)][holders[j]]);
                    pubAccrued[uint256(loanType)][holders[j]] = grantPubInternal(holders[j], pubAccrued[uint256(loanType)][holders[j]]);
                }
            }
        }
    }

    /**
     * @notice Transfer PUBL to the user
     * @dev Note: If there is not enough PUBL, we do not perform the transfer all.
     * @param user The address of the user to transfer PUBL to
     * @param amount The amount of PUBL to (possibly) transfer
     * @return The amount of PUBL which was NOT transferred to the user
     */
    function grantPubInternal(address user, uint256 amount) internal returns (uint256) {
        Publ publ = Publ(getPubAddress());
        uint256 pubRemaining = publ.balanceOf(address(this));
        // console.log("amount:", amount, "pubRemaining:", pubRemaining);
        if (amount > 0 && amount <= pubRemaining) {
            publ.transfer(user, amount);
            return 0;
        }
        return amount;
    }

    /*** Publ Distribution Admin ***/

    /**
     * @notice Transfer PUBL to the recipient
     * @dev Note: If there is not enough PUBL, we do not perform the transfer all.
     * @param recipient The address of the recipient to transfer PUBL to
     * @param amount The amount of PUBL to (possibly) transfer
     */
    function _grantPub(address recipient, uint256 amount) public {
        require(adminOrInitializing(), "only admin can grant publ");
        uint256 amountLeft = grantPubInternal(recipient, amount);
        require(amountLeft == 0, "insufficient publ for grant");
        emit PubGranted(recipient, amount);
    }

    /**
     * @notice Set PUBL speed for a single market
     * @param pToken The market whose PUBL speed to update
     * @param pubSpeed New PUBL speed for market
     */
    function _setPubSpeed(PToken pToken, uint256 pubSpeed) public {
        require(adminOrInitializing(), "only admin can set publ speed");
        setPubSpeedInternal(pToken, pubSpeed);
    }

    /**
     * @notice Set PUBL speed for a single contributor
     * @param contributor The contributor whose PUBL speed to update
     * @param pubSpeed New PUBL speed for contributor
     */
    function _setContributorPubSpeed(address contributor, uint256 pubSpeed) public {
        require(adminOrInitializing(), "only admin can set publ speed");

        // note that PUBL speed could be set to 0 to halt liquidity rewards for a contributor
        updateContributorRewards(contributor);
        if (pubSpeed == 0) {
            // release storage
            delete lastContributorBlock[contributor];
        } else {
            lastContributorBlock[contributor] = getBlockNumber();
        }
        pubContributorSpeeds[contributor] = pubSpeed;

        emit ContributorPubSpeedUpdated(contributor, pubSpeed);
    }

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     * @return The list of market addresses
     */
    function getAllMarkets() public view returns (PToken[] memory) {
        return allMarkets;
    }

    function getBlockNumber() public view returns (uint256) {
        return block.number;
    }

    /**
     * @notice Return the address of the PUBL token
     * @return The address of PUBL
     */
    function getPubAddress() public view returns (address) {
        return pubAddress;
    }

    function setPubAddress(address _newAddr) public {
        require(adminOrInitializing(), "only admin can set pub address");
        pubAddress = _newAddr;
    }
}
