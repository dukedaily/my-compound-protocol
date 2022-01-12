pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../PErc20.sol";
import "../PToken.sol";
import "../PriceOracle.sol";
import "../EIP20Interface.sol";
import "../Governance/GovernorAlpha.sol";
import "../Governance/Publ.sol";

interface ComptrollerLensInterface {
    function markets(address) external view returns (bool, uint256);

    function oracle() external view returns (PriceOracle);

    function getAccountLiquidity(address)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function getAssetsIn(address) external view returns (PToken[] memory);

    function claimPubV1(address) external;

    function pubAccrued(address) external view returns (uint256);
}

interface GovernorBravoInterface {
    struct Receipt {
        bool hasVoted;
        uint8 support;
        uint96 votes;
    }
    struct Proposal {
        uint256 id;
        address proposer;
        uint256 eta;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool executed;
    }

    function getActions(uint256 proposalId)
        external
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        );

    function proposals(uint256 proposalId) external view returns (Proposal memory);

    function getReceipt(uint256 proposalId, address voter) external view returns (Receipt memory);
}

contract PublicsLens is LoanTypeBase{
    struct PTokenMetadata {
        address pToken;
        uint256 exchangeRateCurrent;
        uint256 supplyRatePerBlock;
        uint256 borrowRatePerBlock;
        uint256 reserveFactorMantissa;
        uint256 totalBorrows;
        uint256 totalReserves;
        uint256 totalSupply;
        uint256 totalCash;
        bool isListed;
        uint256 collateralFactorMantissa;
        address underlyingAssetAddress;
        uint256 pTokenDecimals;
        uint256 underlyingDecimals;
    }

    function pTokenMetadata(PToken pToken) public returns (PTokenMetadata memory) {
        uint256 exchangeRateCurrent = pToken.exchangeRateCurrent();
        ComptrollerLensInterface comptroller = ComptrollerLensInterface(address(pToken.comptroller()));
        (bool isListed, uint256 collateralFactorMantissa) = comptroller.markets(address(pToken));
        address underlyingAssetAddress;
        uint256 underlyingDecimals;

        if (compareStrings(pToken.symbol(), "cETH")) {
            underlyingAssetAddress = address(0);
            underlyingDecimals = 18;
        } else {
            PErc20 cErc20 = PErc20(address(pToken));
            underlyingAssetAddress = cErc20.underlying();
            underlyingDecimals = EIP20Interface(cErc20.underlying()).decimals();
        }

        return
            PTokenMetadata({
                pToken: address(pToken),
                exchangeRateCurrent: exchangeRateCurrent,
                supplyRatePerBlock: pToken.supplyRatePerBlock(),
                borrowRatePerBlock: pToken.borrowRatePerBlock(),
                reserveFactorMantissa: pToken.reserveFactorMantissa(),
                totalBorrows: pToken.totalBorrows(),
                totalReserves: pToken.totalReserves(),
                totalSupply: pToken.totalSupply(),
                totalCash: pToken.getCash(),
                isListed: isListed,
                collateralFactorMantissa: collateralFactorMantissa,
                underlyingAssetAddress: underlyingAssetAddress,
                pTokenDecimals: pToken.decimals(),
                underlyingDecimals: underlyingDecimals
            });
    }

    function pTokenMetadataAll(PToken[] calldata pTokens) external returns (PTokenMetadata[] memory) {
        uint256 pTokenCount = pTokens.length;
        PTokenMetadata[] memory res = new PTokenMetadata[](pTokenCount);
        for (uint256 i = 0; i < pTokenCount; i++) {
            res[i] = pTokenMetadata(pTokens[i]);
        }
        return res;
    }

    struct PTokenBalances {
        address pToken;
        uint256 balanceOf;
        uint256 borrowBalanceCurrent;
        uint256 balanceOfUnderlying;
        uint256 tokenBalance;
        uint256 tokenAllowance;
    }

    function pTokenBalances(PToken pToken, address payable account) public returns (PTokenBalances memory) {
        uint256 balanceOf = pToken.balanceOf(account);
        uint256 borrowBalanceCurrent = pToken.borrowBalanceCurrent(account, 0, LoanType.NORMAL);
        uint256 balanceOfUnderlying = pToken.balanceOfUnderlying(account);
        uint256 tokenBalance;
        uint256 tokenAllowance;

        if (compareStrings(pToken.symbol(), "cETH")) {
            tokenBalance = account.balance;
            tokenAllowance = account.balance;
        } else {
            PErc20 cErc20 = PErc20(address(pToken));
            EIP20Interface underlying = EIP20Interface(cErc20.underlying());
            tokenBalance = underlying.balanceOf(account);
            tokenAllowance = underlying.allowance(account, address(pToken));
        }

        return
            PTokenBalances({
                pToken: address(pToken),
                balanceOf: balanceOf,
                borrowBalanceCurrent: borrowBalanceCurrent,
                balanceOfUnderlying: balanceOfUnderlying,
                tokenBalance: tokenBalance,
                tokenAllowance: tokenAllowance
            });
    }

    function pTokenBalancesAll(PToken[] calldata pTokens, address payable account) external returns (PTokenBalances[] memory) {
        uint256 pTokenCount = pTokens.length;
        PTokenBalances[] memory res = new PTokenBalances[](pTokenCount);
        for (uint256 i = 0; i < pTokenCount; i++) {
            res[i] = pTokenBalances(pTokens[i], account);
        }
        return res;
    }

    struct PTokenUnderlyingPrice {
        address pToken;
        uint256 underlyingPrice;
    }

    function pTokenUnderlyingPrice(PToken pToken) public returns (PTokenUnderlyingPrice memory) {
        ComptrollerLensInterface comptroller = ComptrollerLensInterface(address(pToken.comptroller()));
        PriceOracle priceOracle = comptroller.oracle();
        (uint256 price,) = priceOracle.getUnderlyingPrice(pToken);
        return PTokenUnderlyingPrice({ pToken: address(pToken), underlyingPrice: price});
    }

    function pTokenUnderlyingPriceAll(PToken[] calldata pTokens) external returns (PTokenUnderlyingPrice[] memory) {
        uint256 pTokenCount = pTokens.length;
        PTokenUnderlyingPrice[] memory res = new PTokenUnderlyingPrice[](pTokenCount);
        for (uint256 i = 0; i < pTokenCount; i++) {
            res[i] = pTokenUnderlyingPrice(pTokens[i]);
        }
        return res;
    }

    struct AccountLimits {
        PToken[] markets;
        uint256 liquidity;
        uint256 shortfall;
    }

    function getAccountLimits(ComptrollerLensInterface comptroller, address account) public returns (AccountLimits memory) {
        (uint256 errorCode, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(account);
        require(errorCode == 0);

        return AccountLimits({ markets: comptroller.getAssetsIn(account), liquidity: liquidity, shortfall: shortfall });
    }

    struct GovReceipt {
        uint256 proposalId;
        bool hasVoted;
        bool support;
        uint96 votes;
    }

    function getGovReceipts(
        GovernorAlpha governor,
        address voter,
        uint256[] memory proposalIds
    ) public view returns (GovReceipt[] memory) {
        uint256 proposalCount = proposalIds.length;
        GovReceipt[] memory res = new GovReceipt[](proposalCount);
        for (uint256 i = 0; i < proposalCount; i++) {
            GovernorAlpha.Receipt memory receipt = governor.getReceipt(proposalIds[i], voter);
            res[i] = GovReceipt({ proposalId: proposalIds[i], hasVoted: receipt.hasVoted, support: receipt.support, votes: receipt.votes });
        }
        return res;
    }

    struct GovBravoReceipt {
        uint256 proposalId;
        bool hasVoted;
        uint8 support;
        uint96 votes;
    }

    function getGovBravoReceipts(
        GovernorBravoInterface governor,
        address voter,
        uint256[] memory proposalIds
    ) public view returns (GovBravoReceipt[] memory) {
        uint256 proposalCount = proposalIds.length;
        GovBravoReceipt[] memory res = new GovBravoReceipt[](proposalCount);
        for (uint256 i = 0; i < proposalCount; i++) {
            GovernorBravoInterface.Receipt memory receipt = governor.getReceipt(proposalIds[i], voter);
            res[i] = GovBravoReceipt({ proposalId: proposalIds[i], hasVoted: receipt.hasVoted, support: receipt.support, votes: receipt.votes });
        }
        return res;
    }

    struct GovProposal {
        uint256 proposalId;
        address proposer;
        uint256 eta;
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        bool canceled;
        bool executed;
    }

    function setProposal(
        GovProposal memory res,
        GovernorAlpha governor,
        uint256 proposalId
    ) internal view {
        (, address proposer, uint256 eta, uint256 startBlock, uint256 endBlock, uint256 forVotes, uint256 againstVotes, bool canceled, bool executed) = governor.proposals(proposalId);
        res.proposalId = proposalId;
        res.proposer = proposer;
        res.eta = eta;
        res.startBlock = startBlock;
        res.endBlock = endBlock;
        res.forVotes = forVotes;
        res.againstVotes = againstVotes;
        res.canceled = canceled;
        res.executed = executed;
    }

    function getGovProposals(GovernorAlpha governor, uint256[] calldata proposalIds) external view returns (GovProposal[] memory) {
        GovProposal[] memory res = new GovProposal[](proposalIds.length);
        for (uint256 i = 0; i < proposalIds.length; i++) {
            (address[] memory targets, uint256[] memory values, string[] memory signatures, bytes[] memory calldatas) = governor.getActions(proposalIds[i]);
            res[i] = GovProposal({
                proposalId: 0,
                proposer: address(0),
                eta: 0,
                targets: targets,
                values: values,
                signatures: signatures,
                calldatas: calldatas,
                startBlock: 0,
                endBlock: 0,
                forVotes: 0,
                againstVotes: 0,
                canceled: false,
                executed: false
            });
            setProposal(res[i], governor, proposalIds[i]);
        }
        return res;
    }

    struct GovBravoProposal {
        uint256 proposalId;
        address proposer;
        uint256 eta;
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool executed;
    }

    function setBravoProposal(
        GovBravoProposal memory res,
        GovernorBravoInterface governor,
        uint256 proposalId
    ) internal view {
        GovernorBravoInterface.Proposal memory p = governor.proposals(proposalId);

        res.proposalId = proposalId;
        res.proposer = p.proposer;
        res.eta = p.eta;
        res.startBlock = p.startBlock;
        res.endBlock = p.endBlock;
        res.forVotes = p.forVotes;
        res.againstVotes = p.againstVotes;
        res.abstainVotes = p.abstainVotes;
        res.canceled = p.canceled;
        res.executed = p.executed;
    }

    function getGovBravoProposals(GovernorBravoInterface governor, uint256[] calldata proposalIds) external view returns (GovBravoProposal[] memory) {
        GovBravoProposal[] memory res = new GovBravoProposal[](proposalIds.length);
        for (uint256 i = 0; i < proposalIds.length; i++) {
            (address[] memory targets, uint256[] memory values, string[] memory signatures, bytes[] memory calldatas) = governor.getActions(proposalIds[i]);
            res[i] = GovBravoProposal({
                proposalId: 0,
                proposer: address(0),
                eta: 0,
                targets: targets,
                values: values,
                signatures: signatures,
                calldatas: calldatas,
                startBlock: 0,
                endBlock: 0,
                forVotes: 0,
                againstVotes: 0,
                abstainVotes: 0,
                canceled: false,
                executed: false
            });
            setBravoProposal(res[i], governor, proposalIds[i]);
        }
        return res;
    }

    struct PubBalanceMetadata {
        uint256 balance;
        uint256 votes;
        address delegate;
    }

    function getPubBalanceMetadata(Publ publ, address account) external view returns (PubBalanceMetadata memory) {
        return PubBalanceMetadata({ balance: publ.balanceOf(account), votes: uint256(publ.getCurrentVotes(account)), delegate: publ.delegates(account) });
    }

    struct PubBalanceMetadataExt {
        uint256 balance;
        uint256 votes;
        address delegate;
        uint256 allocated;
    }

    function getPubBalanceMetadataExt(
        Publ publ,
        ComptrollerLensInterface comptroller,
        address account
    ) external returns (PubBalanceMetadataExt memory) {
        uint256 balance = publ.balanceOf(account);
        comptroller.claimPubV1(account);
        uint256 newBalance = publ.balanceOf(account);
        uint256 accrued = comptroller.pubAccrued(account);
        uint256 total = add(accrued, newBalance, "sum publ total");
        uint256 allocated = sub(total, balance, "sub allocated");

        return PubBalanceMetadataExt({ balance: balance, votes: uint256(publ.getCurrentVotes(account)), delegate: publ.delegates(account), allocated: allocated });
    }

    struct PubVotes {
        uint256 blockNumber;
        uint256 votes;
    }

    function getPubVotes(
        Publ publ,
        address account,
        uint32[] calldata blockNumbers
    ) external view returns (PubVotes[] memory) {
        PubVotes[] memory res = new PubVotes[](blockNumbers.length);
        for (uint256 i = 0; i < blockNumbers.length; i++) {
            res[i] = PubVotes({ blockNumber: uint256(blockNumbers[i]), votes: uint256(publ.getPriorVotes(account, blockNumbers[i])) });
        }
        return res;
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function add(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }
}
