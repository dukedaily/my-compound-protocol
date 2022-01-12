pragma solidity ^0.5.16;

import "./SafeMath.sol";
import "./PubMiningRateModel.sol";

contract PubMiningRateModelImpl is PubMiningRateModel {
    using SafeMath for uint;

    event NewKink(uint kink);
    event NewSupplyParams(uint baseSpeed, uint g0, uint g1, uint g2);
    event NewBorrowParams(uint baseSpeed, uint g0, uint g1, uint g2);

    address public owner;

    // all params below scaled by 1e18
    uint public kink;

    uint public supplyBaseSpeed;
    uint public supplyG0;
    uint public supplyG1;
    uint public supplyG2;

    uint public borrowBaseSpeed;
    uint public borrowG0;
    uint public borrowG1;
    uint public borrowG2;

    constructor(
        uint kink_,
        uint supplyBaseSpeed_,
        uint supplyG0_,
        uint supplyG1_,
        uint supplyG2_,
        uint borrowBaseSpeed_,
        uint borrowG0_,
        uint borrowG1_,
        uint borrowG2_,
        address owner_) public {
            owner = owner_;

            updateKinkInternal(kink_);
            updateSupplyParamsInternal(supplyBaseSpeed_, supplyG0_, supplyG1_, supplyG2_);
            updateBorrowParamsInternal(borrowBaseSpeed_, borrowG0_, borrowG1_, borrowG2_);
    }

    function updateKink(uint kink_) external {
        require(msg.sender == owner, "only the owner may call this function.");

        updateKinkInternal(kink_);
    }

    function updateSupplyParams(uint baseSpeed, uint g0, uint g1, uint g2) external {
        require(msg.sender == owner, "only the owner may call this function.");

        updateSupplyParamsInternal(baseSpeed, g0, g1, g2);
    }

    function updateBorrowParams(uint baseSpeed, uint g0, uint g1, uint g2) external {
        require(msg.sender == owner, "only the owner may call this function.");

        updateBorrowParamsInternal(baseSpeed, g0, g1, g2);
    }

    function updateKinkInternal(uint kink_) internal {
        require(kink <= 1e18, "require kink <= 1e18");
        
        kink = kink_;

        emit NewKink(kink);
    }

    function updateSupplyParamsInternal(uint baseSpeed, uint g0, uint g1, uint g2) internal {
        require(g0 <= 1e18, "require g0 <= 1e18");
        require(g1 <= 1e18, "require g1 <= 1e18");
        require(g1 <= (uint(1e18).sub(g0)), "require g1 <= (1e18 - g0)");
        require(g2 <= (uint(1e18).sub(g0).sub(g1)), "require g2 <= (1e18 - g0 - g1)");

        supplyBaseSpeed = baseSpeed;
        supplyG0 = g0;
        supplyG1 = g1;
        supplyG2 = g2;

        emit NewSupplyParams(supplyBaseSpeed, supplyG0, supplyG1, supplyG2);
    }

    function updateBorrowParamsInternal(uint baseSpeed, uint g0, uint g1, uint g2) internal {
        require(g0 <= 1e18, "require g0 <= 1e18");
        require(g1 <= 1e18, "require g1 <= 1e18");
        
        borrowBaseSpeed = baseSpeed;
        borrowG0 = g0;
        borrowG1 = g1;
        borrowG2 = g2;

        emit NewBorrowParams(borrowBaseSpeed, borrowG0, borrowG1, borrowG2);
    }

    function getBorrowSpeed(uint utilizationRate) external view returns (uint) {
        uint g;
        if (utilizationRate < kink) {
            uint temp = utilizationRate.mul(borrowG1).div(kink);
            g = uint(1e18).sub(borrowG0).sub(temp);
        } else {
            uint temp = utilizationRate.sub(kink).mul(borrowG2).div(uint(1e18).sub(kink));
            g = uint(1e18).sub(borrowG0).sub(borrowG1).sub(temp);
        }
        
        return borrowBaseSpeed.mul(g).div(1e18);
    }

    function getSupplySpeed(uint utilizationRate) external view returns (uint) {
        uint g; 
        if (utilizationRate < kink) {
            uint temp = utilizationRate.mul(supplyG1).div(kink);
            g = supplyG0.add(temp);
        } else {
            uint temp = utilizationRate.sub(kink).mul(supplyG2).div(uint(1e18).sub(kink));
            g = supplyG0.add(supplyG1).add(temp);
        }
        
        return supplyBaseSpeed.mul(g).div(1e18);
    }
}
