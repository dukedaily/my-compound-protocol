pragma solidity ^0.5.16;

import "./PToken.sol";
import "./PTokenInterfaces.sol";
import "./PriceOracle.sol";
// import "./LoanTypeBase.sol";

contract UnitrollerAdminStorage {
    /**
     * @notice Administrator for this contract
     */
    address public admin;

    /**
     * @notice Pending administrator for this contract
     */
    address public pendingAdmin;

    /**
     * @notice Active brains of Unitroller
     */
    address public comptrollerImplementation;

    /**
     * @notice Pending brains of Unitroller
     */
    address public pendingComptrollerImplementation;
}

contract ComptrollerV1Storage is UnitrollerAdminStorage {
    /**
     * @notice Oracle which gives the price of any given asset
     */
    PriceOracle public oracle;

    /**
     * @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
     */
    uint256 public closeFactorMantissa;

    /**
     * @notice Multiplier representing the discount on collateral that a liquidator receives
     */
    //代表清算人收到的抵押品折扣的乘数,publics 是1.08表示获得8%的收益
    uint256 public liquidationIncentiveMantissa;

    /**
     * @notice Max number of assets a single account can participate in (borrow or use as collateral)
     */
    uint256 public maxAssets;

    /**
     * @notice Per-account mapping of "assets you are in", capped by maxAssets
     */
    mapping(address => PToken[]) public accountAssets;
}

contract ComptrollerV2Storage is ComptrollerV1Storage {
    struct Market {
        /// @notice Whether or not this market is listed
        bool isListed;
        /**
         * @notice Multiplier representing the most one can borrow against their collateral in this market.
         *  For instance, 0.9 to allow borrowing 90% of collateral value.
         *  Must be between 0 and 1, and stored as a mantissa.
         */
        uint256 collateralFactorMantissa;
        /// @notice Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;
        /// @notice Whether or not this market receives PUBL
        bool isPubed;
    }

    /**
     * @notice Official mapping of pTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => Market) public markets;

    /**
     * @notice The Pause Guardian can pause certain actions as a safety mechanism.
     *  Actions which allow users to remove their own assets cannot be paused.
     *  Liquidation / seizing / transfer can only be paused globally, not by market.
     */
    address public pauseGuardian;
    bool public _mintGuardianPaused;
    bool public _borrowGuardianPaused;
    bool public transferGuardianPaused;
    bool public seizeGuardianPaused;
    mapping(address => bool) public mintGuardianPaused;
    mapping(address => bool) public borrowGuardianPaused;
}

contract ComptrollerV3Storage is ComptrollerV2Storage {
    struct PubMarketState {
        /// @notice The market's last updated pubBorrowIndex or pubSupplyIndex
        uint224 index;
        /// @notice The block number the index was last updated at
        uint32 block;
    }

    /// @notice A list of all markets
    PToken[] public allMarkets;

    /// @notice The rate at which the flywheel distributes PUBL, per block
    uint256 public pubRate;

    /// @notice The portion of pubRate that each market currently receives
    mapping(address => uint256) public pubSpeeds;

    /// @notice The PUBL market supply state for each market
    mapping(address => PubMarketState) public pubSupplyState;

    /// @notice The PUBL market borrow state for each market
    mapping(address => PubMarketState) public pubBorrowState;

    /// @notice The PUBL borrow index for each market for each supplier as of the last time they accrued PUBL
    // mapping(address => mapping(address => uint256)) public pubSupplierIndex;

    //market =》 type =》account =》amount
    mapping(address => mapping(uint256 => mapping(address => uint256))) public pubSupplierIndex;
    // mapping(address => mapping(address => mapping(uint256 => uint256))) public pubSupplierIndexMining;

    /// @notice The PUBL borrow index for each market for each borrower as of the last time they accrued PUBL
    mapping(address => mapping(uint256 => mapping(address => uint256))) public pubBorrowerIndex;

    /// @notice The PUBL accrued but not yet transferred to each user
    mapping(uint256 =>mapping(address =>  uint256)) public pubAccrued;
}

contract ComptrollerV4Storage is ComptrollerV3Storage {
    // @notice The borrowCapGuardian can set borrowCaps to any number for any market. Lowering the borrow cap could disable borrowing on the given market.
    address public borrowCapGuardian;

    // @notice Borrow caps enforced by borrowAllowed for each pToken address. Defaults to zero which corresponds to unlimited borrowing.
    mapping(address => uint256) public borrowCaps;
}

contract ComptrollerV5Storage is ComptrollerV4Storage {
    /// @notice The portion of PUBL that each contributor receives per block
    mapping(address => uint256) public pubContributorSpeeds;

    /// @notice Last block at which a contributor's PUBL rewards have been allocated
    mapping(address => uint256) public lastContributorBlock;
}
