pragma solidity ^0.5.16;
import "../../IAssetPrice.sol";

contract TestPriceOracle is IAssetPrice{
    mapping(address=>PriceMap) public prices;
    struct PriceMap {
        uint256 price;
        uint8 decimal;
    }

    function setPrice(address _token, uint256 _price, uint8 _decimal) public {
        PriceMap memory p = PriceMap({price: _price, decimal: _decimal});
        prices[_token] = p;
    }

    function getPriceV1(address tokenQuote, address tokenBase) external view returns (uint8, uint256, uint8) {
        return (0,0,0);
    }
    
    function getPriceV2(address tokenQuote, address tokenBase, uint8 decimal) external view returns (uint8, uint256) {
        return (0,0);
    }

    function getPriceUSDV1(address token) external view returns (uint8, uint256, uint8){
        return (1,prices[token].price, prices[token].decimal);
    }
    
    function getPriceUSDV2(address token, uint8 decimal) external view returns (uint8, uint256){
        return (1, prices[token].price);
    }


    function decimal(address tokenQuote, address tokenBase) external view returns (uint8){
        return 18;
    }

    function getUSDV1(address token, uint256 amount) external view returns (uint8, uint256, uint8){
        return (0,0,0);
    }
    
    function getUSDV2(address token, uint256 amount, uint8 decimal) external view returns (uint8, uint256){
        return (0,0);
    }
}