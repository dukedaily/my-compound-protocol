pragma solidity ^0.5.16;

import "./PErc20Delegate.sol";

interface PubLike {
    function delegate(address delegatee) external;
}

/**
 * @title Publics' PPubLikeDelegate Contract
 * @notice PTokens which can 'delegate votes' of their underlying ERC-20
 * @author Publics
 */
contract PPubLikeDelegate is PErc20Delegate {
    /**
     * @notice Construct an empty delegate
     */
    constructor() public PErc20Delegate() {}

    /**
     * @notice Admin call to delegate the votes of the PUBL-like underlying
     * @param pubLikeDelegatee The address to delegate votes to
     */
    function _delegatePubLikeTo(address pubLikeDelegatee) external {
        require(msg.sender == admin, "only the admin may set the publ-like delegate");
        PubLike(underlying).delegate(pubLikeDelegatee);
    }
}
