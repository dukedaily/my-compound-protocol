import { Liquidation } from './../typechain/Liquidation.d';
import {
    withSaveAndVerify,
    registerContractInJsonDb,
    insertContractAddressInDb,
} from './contracts-helpers'


import { eContractid } from './types'
import {
    Signer,
    utils,
    BigNumberish,
    Contract,
    BytesLike,
    ContractFactory,
    Overrides,
} from "ethers";

import { getFirstSigner } from './contracts-getters';
import {
    Unitroller__factory,
    Comptroller__factory,
    JumpRateModelV2__factory,
    PErc20Delegate__factory,
    PErc20Delegator__factory,
    // SimplePriceOracleChainlink__factory,
    // SimplePriceOracle__factory,
    // PEther__factory,
    StandardToken__factory,
    PriceOracleAggregator__factory,
    PubMiningRateModelImpl__factory,
    TestPriceOracle__factory,
    MarginSwapPool__factory,
    Controller__factory,
    MockTXAggregator__factory,
    StorageImpl__factory,
    Capital__factory,
    Liquidation__factory,
    Publ__factory,
} from '../typechain'

export const deployUnitroller = async (verify?: boolean) =>
    withSaveAndVerify(
        await new Unitroller__factory(await getFirstSigner()).deploy(),
        eContractid.Unitroller,
        '',
        [],
        verify
    );

export const deployComptroller = async (overrides?: Overrides, verify?: boolean) =>
    withSaveAndVerify(
        await new Comptroller__factory(await getFirstSigner()).deploy(overrides),
        eContractid.Comptroller,
        '',
        [],
        verify
    );


// export const deployCEther = async (
//     comptroller: string,
//     interestRateModel: string,
//     initialExchangeRateMantissa: BigNumberish,
//     name: string,
//     symbol: string,
//     decimals: BigNumberish,
//     admin: string,
//     verify?: boolean) =>
//     withSaveAndVerify(
//         await new CEther__factory(await getFirstSigner()).deploy(
//             comptroller,
//             interestRateModel,
//             initialExchangeRateMantissa,
//             name, symbol, decimals, admin
//         ),
//         eContractid.CEther,
//     );
export const deployPriceOracleAggregator = async (verify?: boolean) =>
    withSaveAndVerify(
        await new PriceOracleAggregator__factory(await getFirstSigner()).deploy(),
        eContractid.PriceOracleAggregator,
        '',
        [],
        verify
    );

export const deployTestPriceOracle = async (verify?: boolean) =>
    withSaveAndVerify(
        await new TestPriceOracle__factory(await getFirstSigner()).deploy(),
        eContractid.TestPriceOracle,
        '',
        [],
        verify
    );

export const deployJumpRateModelV2 = async (symbol: string, baseRatePerYear: BigNumberish, multiplierPerYear: BigNumberish,
    jumpMultiplierPerYear: BigNumberish, kink: BigNumberish, owner: string, verify?: boolean,) =>
    withSaveAndVerify(
        await new JumpRateModelV2__factory(await getFirstSigner()).deploy(
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink,
            owner
        ),
        eContractid.JumpRateModel,
        symbol,
        [baseRatePerYear.toString(), multiplierPerYear.toString(), jumpMultiplierPerYear.toString(), kink.toString(), owner],
        verify
    );

export const deployPErc20Delegate = async (symbol: string, overrides?: Overrides, verify?: boolean) =>
    withSaveAndVerify(
        await new PErc20Delegate__factory(await getFirstSigner()).deploy(overrides),
        eContractid.PErc20Delegate,
        symbol,
        [],
        verify
    );
export const deployPErc20Delegator = async (
    symbol: string, //token symbol
    underlying: string,
    assetDecimal: BigNumberish,
    comptroller: string,
    interestRateModel: string,
    pubMiningRateModel: string,
    initialExchangeRateMantissa: BigNumberish,
    name: string,
    psymbol: string, //pToken symbol
    decimals: BigNumberish,
    admin: string,
    implementation: string,
    becomeImplementationData: BytesLike,
    verify?: boolean) =>
    withSaveAndVerify(
        await new PErc20Delegator__factory(await getFirstSigner()).deploy(
            underlying, assetDecimal, comptroller, interestRateModel, pubMiningRateModel, initialExchangeRateMantissa,
            name, psymbol, decimals, admin, implementation, becomeImplementationData
        ),
        eContractid.PERC20Delegator,
        symbol,
        [underlying, assetDecimal.toString(), comptroller, interestRateModel, pubMiningRateModel, initialExchangeRateMantissa.toString(),
            name, psymbol, decimals.toString(), admin, implementation, becomeImplementationData.toString()],
        verify
    );

export const deployStandardToken = async (
    _initialAmount: BigNumberish,
    _tokenName: string,
    _decimalUnits: BigNumberish,
    _tokenSymbol: string, verify?: boolean) =>
    withSaveAndVerify(
        await new StandardToken__factory(await getFirstSigner()).deploy(
            _initialAmount,
            _tokenName,
            _decimalUnits,
            _tokenSymbol
        ),
        eContractid.NewAssetsToken,
        _tokenSymbol,
        [_initialAmount.toString(), _tokenName, _decimalUnits.toString(), _tokenSymbol],
        verify
    );

export const deployPubMiningRateModelImpl = async (
    kink_: BigNumberish,
    supplyBaseSpeed_: BigNumberish,
    supplyG0_: BigNumberish,
    supplyG1_: BigNumberish,
    supplyG2_: BigNumberish,
    borrowBaseSpeed_: BigNumberish,
    borrowG0_: BigNumberish,
    borrowG1_: BigNumberish,
    borrowG2_: BigNumberish,
    owner_: string,
    verify?: boolean) =>
    withSaveAndVerify(
        await new PubMiningRateModelImpl__factory(await getFirstSigner()).deploy(
            kink_,
            supplyBaseSpeed_,
            supplyG0_,
            supplyG1_,
            supplyG2_,
            borrowBaseSpeed_,
            borrowG0_,
            borrowG1_,
            borrowG2_,
            owner_,
        ),
        eContractid.PubMiningRateModel,
        '',
        [kink_.toString(),
            supplyBaseSpeed_.toString(),
            supplyG0_.toString(),
            supplyG1_.toString(),
            supplyG2_.toString(),
            borrowBaseSpeed_.toString(),
            borrowG0_.toString(),
            borrowG1_.toString(),
            borrowG2_.toString(),
            owner_],
        verify
    );

export const deployCapital = async (symbol :string, mspname: string, pToken: string, controller: string, verify?: boolean) =>
    withSaveAndVerify(
        await new Capital__factory(await getFirstSigner()).deploy(mspname, pToken, controller),
        eContractid.Capital,
        symbol,
        [mspname, pToken, controller],
        verify
    );

export const deployMarginSwapPool = async (symbol: string, capital :string, verify?: boolean) =>
    withSaveAndVerify(
        await new MarginSwapPool__factory(await getFirstSigner()).deploy(capital),
        eContractid.MarginSwapPool,
        symbol,
        [capital],
        verify
    );

export const deployLiquidation = async (symbol: string, msp :string, verify?: boolean) =>
    withSaveAndVerify(
        await new Liquidation__factory(await getFirstSigner()).deploy(msp),
        eContractid.Liquidation,
        symbol,
        [msp],
        verify
    );

export const deployController = async (verify?: boolean) =>
    withSaveAndVerify(
        await new Controller__factory(await getFirstSigner()).deploy(),
        eContractid.Controller,
        '',
        [],
        verify
    );

export const deployMockAggregator = async (verify?: boolean) =>
    withSaveAndVerify(
        await new MockTXAggregator__factory(await getFirstSigner()).deploy(),
        eContractid.MockTXAggregator,
        '',
        [],
        verify
    );
export const deployPub = async (admin: string, verify?: boolean) =>
    withSaveAndVerify(
        await new Publ__factory(await getFirstSigner()).deploy(admin),
        eContractid.PUB,
        '',
        [admin],
        verify
    );