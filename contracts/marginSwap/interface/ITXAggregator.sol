pragma solidity ^0.5.16;

contract ITXAggregator {
    function swapExtractOut(
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadLine
    ) external returns (uint256);

    //针对B而言，A(100)-> B?
    function swapEstimateOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256);

    //针对A而言，A？-> B(100)
    function swapEstimateIn(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view returns (uint256);

    function setPToken(address _pTokenIn, address _pTokenOut) public;
}
