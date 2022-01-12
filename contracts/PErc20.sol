pragma solidity ^0.5.16;

import "./PToken.sol";

/**
 * @title Publics' PErc20 Contract
 * @notice PTokens which wrap an EIP-20 underlying
 * @author Publics
 */
contract PErc20 is PToken, PErc20Interface {
    /**
     * @notice Initialize the new money market
     * @param underlying_ The address of the underlying asset
     * @param underlyingDecimal_ ERC-20 decimal precision of this token
     * @param comptroller_ The address of the Comptroller
     * @param interestRateModel_ The address of the interest rate model
     * @param pubMiningRateModel_ The address of the pubming rate model
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param decimals_ ERC-20 decimal precision of this token
     */
    function initialize(
        address underlying_,
        uint8 underlyingDecimal_,
        ComptrollerInterface comptroller_,
        InterestRateModel interestRateModel_,
        PubMiningRateModel pubMiningRateModel_,
        uint256 initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) public {
        // PToken initialize does the bulk of the work
        super.initialize(
            comptroller_,
            interestRateModel_,
            pubMiningRateModel_,
            initialExchangeRateMantissa_,
            name_,
            symbol_,
            decimals_
        );

        // Set underlying and sanity check it
        underlying = underlying_;
        underlyingDecimal = underlyingDecimal_;
        EIP20Interface(underlying).totalSupply();
    }

    /*** User Interface ***/

    /**
     * @notice Sender supplies assets into the market and receives pTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     * @return (uint256 error, uint256 pTokenAmt) 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function mint(uint256 mintAmount) external returns (uint256, uint256) {
        (uint256 err, uint256 pTokenAmt) = mintInternal(mintAmount);
        return (err, pTokenAmt);
    }

    /**
     * @notice Sender redeems pTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemTokens The number of pTokens to redeem into underlying
     * @return (uint256 error, uint256 assetAmt) 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeem(uint256 redeemTokens) external returns (uint256, uint256, uint256) {
        return redeemInternal(redeemTokens);
    }

    /**
     * @notice Sender redeems pTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemAmount The amount of underlying to redeem
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    //这个是根据价值赎回，需要配合rate计算
    //redeem是根数数量赎回，这是两者区别
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256, uint256, uint256) {
        return redeemUnderlyingInternal(redeemAmount);
    }

    /**
     * @notice Sender borrows assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function borrow(uint256 borrowAmount) external returns (uint256) {
        return borrowInternal(borrowAmount);
    }

    /**
     * @notice Sender repays their own borrow
     * @param repayAmount The amount to repay
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function repayBorrow(uint256 repayAmount) external returns (uint256) {
        uint256 callerBalance = EIP20Interface(underlying).balanceOf(msg.sender);

        if (repayAmount > callerBalance &&  repayAmount != uint256(-1)) {
            // console.log("还款失败!");
            return fail(Error.BAD_INPUT, FailureInfo.REPAY_BORROW_FRESHNESS_CHECK);
        }

        (uint256 err, ) = repayBorrowInternal(repayAmount);
        return err;
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    //帮助别人偿还
    function repayBorrowBehalf(address borrower, uint256 repayAmount)
        external
        returns (uint256)
    {
        uint256 callerBalance = EIP20Interface(underlying).balanceOf(msg.sender);

        if (repayAmount > callerBalance && repayAmount != uint256(-1)) {
            return fail(Error.BAD_INPUT, FailureInfo.REPAY_BORROW_FRESHNESS_CHECK);
        }

        (uint256 err, ) = repayBorrowBehalfInternal(borrower, repayAmount);
        return err;
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this pToken to be liquidated
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param pTokenCollateral The market in which to seize collateral from the borrower
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        PTokenInterface pTokenCollateral /*被查封的资产*/
    ) external returns (uint256) {
        (uint256 err, ) =
            liquidateBorrowInternal(borrower, repayAmount, pTokenCollateral);
        return err;
    }

    /**
     * @notice A public function to sweep accidental ERC-20 transfers to this contract. Tokens are sent to admin (timelock)
     * @param token The address of the ERC-20 token to sweep
     */
    //管理员的意外收获，这些钱会转给管理员
    //非当前pToken相关的erc20 token，转给admin
    function sweepToken(EIP20NonStandardInterface token) external {
        require(
            address(token) != underlying,
            "PErc20::sweepToken: can not sweep underlying token"
        );
        uint256 balance = token.balanceOf(address(this));
        token.transfer(admin, balance);
    }

    /**
     * @notice The sender adds to reserves.
     * @param addAmount The amount of underlying token to add as reserves
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _addReserves(uint256 addAmount) external returns (uint256) {
        return _addReservesInternal(addAmount);
    }

    /*** Safe Token ***/

    /**
     * @notice Gets balance of this contract in terms of the underlying
     * @dev This excludes the value of the current message, if any
     * @return The quantity of underlying tokens owned by this contract
     */
    //获取这个cToken合约拥有的underlying的balance
    function getCashPrior() internal view returns (uint256) {
        EIP20Interface token = EIP20Interface(underlying);
        return token.balanceOf(address(this));
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False result from `transferFrom` and reverts in that case.
     *      This will revert due to insufficient balance or insufficient allowance.
     *      This function returns the actual amount received,
     *      which may be less than `amount` if there is a fee attached to the transfer.
     *
     *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     *            See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    //对unserlying资产操作，从from往当前合约转token
    function doTransferIn(address from, uint256 amount)
        internal
        returns (uint256)
    {
        EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
        uint256 balanceBefore = EIP20Interface(underlying).balanceOf(address(this));
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
        uint256 balanceAfter =
            EIP20Interface(underlying).balanceOf(address(this));
        require(balanceAfter >= balanceBefore, "TOKEN_TRANSFER_IN_OVERFLOW");
        return balanceAfter - balanceBefore; // underflow already checked above, just subtract
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False success from `transfer` and returns an explanatory
     *      error code rather than reverting. If caller has not called checked protocol's balance, this may revert due to
     *      insufficient cash held in this contract. If caller has checked protocol's balance prior to this call, and verified
     *      it is >= amount, this should not revert in normal conditions.
     *
     *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     *            See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function doTransferOut(address payable to, uint256 amount) internal {
        EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
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

    function setWhiteList(address trustList, bool _state) public {
        setWhiteListInternal(trustList, _state);
    }

    function doCreditLoanBorrow(
        address payable _borrower,
        uint256 _borrowAmount,
        uint256 _id,
        LoanType _loanType
    ) public returns (uint256) {
        return doCreditLoanBorrowInternal(_borrower, _borrowAmount, _id, _loanType);
    }

    function doCreditLoanRepay(
        address _payer,
        uint256 _repayAmount,
        uint256 _id,
        LoanType _loanType
    ) public returns (uint256, uint256) {
        //如果输入大于余额，直接返回失败
        uint256 callerBalance = EIP20Interface(underlying).balanceOf(msg.sender);
        if (_repayAmount > callerBalance &&  _repayAmount != uint256(-1)) {
            // console.log("还款失败，输入金额大于钱包余额!");
            return (uint256(Error.BAD_INPUT), 0);
        }

        return doCreditLoanRepayInternal(_payer, _repayAmount, _id, _loanType);
    }

    function doCreditLoanMint(
        address _minter,
        uint256 _mintAmount,
        LoanType _loanType
    ) public returns (uint256, uint256) {
        return doCreditLoanMintInternal(_minter, _mintAmount, _loanType);
    }

    function doCreditLoanRedeem(
        address payable _redeemer,
        uint256 _redeemAmount,
        uint256 _redeemTokensAmount,
        LoanType _loanType
    ) public returns (uint256, uint256, uint256) {
        return doCreditLoanRedeemInternal(_redeemer, _redeemAmount, _redeemTokensAmount, _loanType);
    }
}
