pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;
import "../MSPStruct.sol";

// import "hardhat/console.sol";

contract IStorageInterface {
    /*************** 保证金相关 ****************/
    //获取保证金详情
    function getBailAddress(address _account, uint256 _id) public view returns (address[] memory);

    function setBailAddress(
        address _account,
        uint256 _id,
        address _address
    ) public;

    function deleteBailAddress(
        address _account,
        uint256 _id,
        address _remove
    ) public returns (bool);

    function getSupplyConfig(
        address _account,
        uint256 _id,
        address _supplyToken
    ) public view returns (MSPStruct.supplyConfig memory);

    function setSupplyConfig(
        address _account,
        uint256 _id,
        address _supplyToken,
        MSPStruct.supplyConfig memory _newScs
    ) public;

    /*************** 持仓结构相关 ****************/
    function getAccountRecordIds(address _account) public view returns (uint256[] memory);

    function setAccountRecordIds(address _account, uint256 _id) public;

    function deleteClosedAccountRecord(address _account, uint256 _id) public returns (bool);

    function getAccountMspConfig(address _account, uint256 _id) public view returns (MSPStruct.MSPConfig memory);

    function setAccountMspConfig(
        address _account,
        uint256 _id,
        MSPStruct.MSPConfig memory _newConfig
    ) public;


    function updateID() public;

    function getAccountRecordExistId(address _account, string memory _unique) public view returns (uint256);

    function setAccountRecordExistId(
        address _account,
        string memory _unique,
        uint256 _id
    ) public;

    /*************** MSP基础信息 ****************/
    function setSuperList(address _address, bool _flag) public;
}
