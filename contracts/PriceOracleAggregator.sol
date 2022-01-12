pragma solidity ^0.5.16;

import "./PriceOracle.sol";
// import "./PErc20.sol";
import "./IAssetPrice.sol";
import "./PTokenInterfaces.sol";
import "./SafeMath.sol";
import "./IPublicsLoanInterface.sol";
import "hardhat/console.sol";

contract PriceOracleAggregator is PriceOracle {
    using SafeMath for uint256;
    address public admin;
    address public priceOracle;

    event PricePosted(address oldPriceFeed, address newPriceFeed);

    constructor() public {
        admin = msg.sender;
    }

    function setPriceOracle(address newPriceOracle) public {
        require(msg.sender == admin, "only admin can set price oracle");

        address oldPriceOracle = priceOracle;
        priceOracle = newPriceOracle;

        emit PricePosted(oldPriceOracle, newPriceOracle);
    }

    function getUnderlyingPrice(PTokenInterface pToken) public view returns (uint256, uint256) {
        address asset = address(IPublicsLoanInterface(address(pToken)).underlying());
        uint8 assetDecimal = IPublicsLoanInterface(address(pToken)).underlyingDecimal();
        console.log("asset:", asset, assetDecimal);
        (uint256 code, uint256 price) = IAssetPrice(priceOracle).getPriceUSDV2(asset, assetDecimal);
        require(code == 1, "code =1, price is invalid!");

        console.log("price:", price);
        if (assetDecimal == 6) {
            price = price.mul(1e24);
            assetDecimal = 30;
        } else if (assetDecimal == 8) {
            price = price.mul(1e20);
            assetDecimal = 28;
        } else if (assetDecimal == 18) {
            price = price;
        }

        console.log("price adjust:", price);
        return (price, assetDecimal);
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
