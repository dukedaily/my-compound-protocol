pragma solidity ^0.5.16;

import "../../SafeMath.sol";
import "../../Exponential.sol";
import "../../PriceOracleAggregator.sol";
import "../../EIP20Interface.sol";
import "../interface/ITXAggregator.sol";
import "hardhat/console.sol";

contract MockTXAggregator is Exponential{
    constructor() public {
        //uni
        pTokens[0x7c2C195CD6D34B8F845992d380aADB2730bB9C6F] = 0x1d80315fac6aBd3EfeEbE97dEc44461ba7556160;
        //busd
        pTokens[0x8858eeB3DfffA017D4BCE9801D340D36Cf895CCf] = 0xd15468525c35BDBC1eD8F2e09A00F8a173437f2f;
        //dai
        pTokens[0x0078371BDeDE8aAc7DeBfFf451B74c5EDB385Af7] = 0x3521eF8AaB0323004A6dD8b03CE890F4Ea3A13f5;
        //wbtc
        pTokens[0xf4e77E5Da47AC3125140c470c71cBca77B5c638c] = 0x58F132FBB86E21545A4Bace3C19f1C05d86d7A22;
        //usdt
        pTokens[0xf784709d2317D872237C4bC22f867d1BAe2913AB] = 0x5A0773Ff307Bf7C71a832dBB5312237fD3437f9F;
    }
    
    using SafeMath for uint256;
    uint256 MANTISSA18 = 1 ether;
    PriceOracleAggregator public oracle; //临时模拟
    
    PTokenInterface pTokenIn;
    PTokenInterface pTokenOut;

    function _setPriceOracle(address newOracle) public returns (uint256) {
        // Set comptroller's oracle to newOracle
        oracle = PriceOracleAggregator(newOracle);
        return 0;
    }
    //1. 转足够的钱进来，BUSD，UNI
    //2. 实现这三个接口，给接口使用，在MSP中直接使用真实接口
    //功能：给你In得到响应的out，你要把我的钱扣走

    function swapExtractOut(
        address tokenIn, 
        address tokenOut, 
        address recipient, 
        uint256 amountIn, 
        uint256 slippage,   //[0， 1w)，1w代表：100%
        uint256 deadLine //时间戳，在此之前可以兑换成功
    ) external returns (uint256) {
        uint256 actualAmt = doTransferIn(msg.sender, tokenIn, amountIn);
        console.log("MockTXAggregator::actual doTransferIn amount:", actualAmt);
        uint256 swapAmt = this.swapEstimateOut(tokenIn, tokenOut, amountIn);
        console.log("swapAmt:", swapAmt);

        address payable recipient_ = address(uint160(recipient));
        doTransferOut(recipient_, tokenOut, swapAmt);
        return swapAmt;
    }

    mapping(address => address) pTokens;
    //针对B而言，A(100)-> B?
    function swapEstimateOut(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256) {

        console.log("in swapEstimateOut!");
        //价格是有尾数的，而且不同资产的尾数不同，不可以直接使用除法来做倍数计算
        console.log("oracle:", address(oracle), "tokenIn:", tokenIn);
        (uint256 srcTokenPrice, uint256 decimal1) = oracle.getUnderlyingPrice(PTokenInterface(pTokens[tokenIn]));
        (uint256 dstTokenPrice, uint256 decimal2) = oracle.getUnderlyingPrice(PTokenInterface(pTokens[tokenOut]));

        console.log("srcTokenPrice:", srcTokenPrice, "decimal1:", decimal1);
        console.log("dstTokenPrice:", dstTokenPrice, "decimal2:", decimal2);

        ( , uint256 sumIn) = mulScalarTruncate(Exp({mantissa: amountIn}), srcTokenPrice);

        (,uint256 swapAmt) = divScalarByExpTruncate(sumIn, Exp({mantissa: dstTokenPrice}));
        console.log("swap::swapAmt: ", swapAmt);

        return swapAmt;
    }

    //针对A而言，A？-> B(100)
    function swapEstimateIn(address tokenIn, address tokenOut, uint256 amountOut) external view returns (uint256) {
        //TODO
    }

    function setPToken(address _pTokenIn, address _pTokenOut) public {
        pTokenIn = PTokenInterface(_pTokenIn);
        pTokenOut = PTokenInterface(_pTokenOut);
    }

    // **************** 内部使用 ****************
    function doTransferIn(address from, address erc20token, uint256 amount)
        internal
        returns (uint256)
    {
        EIP20Interface token = EIP20Interface(erc20token);
        uint256 balanceBefore =
            EIP20Interface(erc20token).balanceOf(address(this));
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
            EIP20Interface(erc20token).balanceOf(address(this));
        require(balanceAfter >= balanceBefore, "TOKEN_TRANSFER_IN_OVERFLOW");
        return balanceAfter - balanceBefore; // underflow already checked above, just subtract
    }

    function doTransferOut(address payable to, address erc20token, uint256 amount) internal {
        EIP20Interface token = EIP20Interface(erc20token);
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

}