pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

// import "./interface/IStorageInterface.sol";
import "./utils/Ownable.sol";
import "./interface/IControllerInterface.sol";
import "./MSPStruct.sol";
import "./interface/IMSPInterface.sol";
import "./interface/ILiquidationInterface.sol";

contract StorageImpl is Ownable {
    // 资产地址: BUSD
    address public assetUnderlying;

    // pToken地址 : pBUSD
    address public pTokenUnderlying;

    // 资产符号
    string public assetUnderlyingSymbol;

    // 当前杠杆交易合约名字: MSP BUSD
    string public mspName;

    // 配置管理
    IControllerInterface public controller;

    // MSP
    IMSPInterface public msp;

    // Liquidation
    ILiquidationInterface public liquidation;

    //所有用户&所有持仓结构
    MSPStruct.MarginSwapConfig msConfig;

    //持仓id
    uint256 public lastId;

    //记录用户持仓id标识
    mapping(address => mapping(string => uint256)) accountRecordExist;

    //资金使用白名单
    mapping(address => bool) public superList;

    //所有用户&所有保证金, 张三=>id=>保证金结构
    mapping(address => mapping(uint256 => MSPStruct.BailConfig)) bailConfigs;
    
    function getBailAddress(address _account, uint256 _id) public view returns (address[] memory) {
        checkId(_account, _id);
        return bailConfigs[_account][_id].accountBailAddresses;
    }

    function setBailAddress(
        address _account,
        uint256 _id,
        address _address
    ) public onlySuperList {
        checkId(_account, _id);
        MSPStruct.BailConfig storage bailConfig = bailConfigs[_account][_id];
        bailConfig.accountBailAddresses.push(_address);
    }

    function deleteBailAddress(
        address _account,
        uint256 _id,
        address _remove
    ) public onlySuperList returns (bool) {
        address[] storage myArray = bailConfigs[_account][_id].accountBailAddresses;

        bool f = false;
        uint256 pos;

        for (uint256 i = 0; i <= myArray.length - 1; i++) {
            if (myArray[i] == _remove) {
                pos = i;
                f = true;
                break;
            }
        }

        // console.log(f, pos);
        if (f) {
            myArray[pos] = myArray[myArray.length - 1];
            myArray.length--;
        }
        return f;
    }

    function getSupplyConfig(
        address _account,
        uint256 _id,
        address _supplyToken
    ) public view returns (MSPStruct.supplyConfig memory) {
        checkId(_account, _id);
        return bailConfigs[_account][_id].bailCfgContainer[_supplyToken];
    }

    function setSupplyConfig(
        address _account,
        uint256 _id,
        address _supplyToken,
        MSPStruct.supplyConfig memory _config
    ) public onlySuperList {
        checkId(_account, _id);
        MSPStruct.BailConfig storage bailConfig = bailConfigs[_account][_id];
        bailConfig.bailCfgContainer[_supplyToken] = _config;
    }

    /*************** 持仓结构相关 ****************/
    function getAccountRecordIds(address _account) public view returns (uint256[] memory) {
        return msConfig.accountCurrentRecordIds[_account];
    }

    function setAccountRecordIds(address _account, uint256 _id) public onlySuperList {
        checkId(_account, _id);
        msConfig.accountCurrentRecordIds[_account].push(_id);
    }

    function deleteClosedAccountRecord(address _account, uint256 _id) public onlySuperList returns (bool) {
        uint256[] storage myArray = msConfig.accountCurrentRecordIds[_account];

        bool f = false;
        uint256 pos;

        for (uint256 i = 0; i <= myArray.length - 1; i++) {
            if (myArray[i] == _id) {
                pos = i;
                f = true;
                break;
            }
        }

        // console.log(f, pos);
        if (f) {
            myArray[pos] = myArray[myArray.length - 1];
            myArray.length--;
        }

        return f;
    }

    function checkId(address _account, uint256 _id) internal view {
        require(msConfig.accountMspRecords[_account][_id].isExist, "invalid id!");
    }

    function getAccountMspConfig(address _account, uint256 _id) public view returns (MSPStruct.MSPConfig memory) {
        checkId(_account, _id);
        return msConfig.accountMspRecords[_account][_id];
    }

    function setAccountMspConfig(
        address _account,
        uint256 _id,
        MSPStruct.MSPConfig memory _newConfig
    ) public onlySuperList {
        msConfig.accountMspRecords[_account][_id] = _newConfig;
    }

    function updateID() public onlySuperList {
        lastId++;
    }

    function getAccountRecordExistId(address _account, string memory _unique) public view returns (uint256) {
        return accountRecordExist[_account][_unique];
    }

    function setAccountRecordExistId(
        address _account,
        string memory _unique,
        uint256 _id
    ) public onlySuperList {
        accountRecordExist[_account][_unique] = _id;
    }

    /*************** MSP基础信息 ****************/
    //资金白名单
    function setSuperList(address _address, bool _flag) public onlyOwner {
        superList[_address] = _flag;
    }

    modifier onlySuperList() {
        require(superList[msg.sender], "caller not in white list");
        _;
    }
}
