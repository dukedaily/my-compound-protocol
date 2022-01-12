import { DRE, getDb } from './misc-utils'
import { Signer } from 'ethers'
import { Provider, TransactionRequest } from "@ethersproject/providers";
import { eContractid, tEthereumAddress } from './types';
import {
    Unitroller__factory,
    Comptroller__factory,
    // SimplePriceOracleChainlink__factory,
    // SimplePriceOracle__factory,
    // PEther__factory,
    PErc20Delegator__factory,
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

export const getFirstSigner = async () => (await DRE.ethers.getSigners())[0]
export const getAllAccounts = async (index: any) => (await DRE.ethers.getSigners())[index]

export const getUnitroller = async (address?: tEthereumAddress) =>
    await Unitroller__factory.connect(
        address || (await getDb().get(`${eContractid.Unitroller}.${DRE.network.name}`).value()),
        await getFirstSigner()
    );

export const getComptroller = async (address?: tEthereumAddress) =>
    await Comptroller__factory.connect(
        address || (await getDb().get(`${eContractid.Comptroller}.${DRE.network.name}`).value()),
        await getFirstSigner()
    );

export const getComptrollerOption = async (signerOrProvider: Signer | Provider, address?: tEthereumAddress) =>
    await Comptroller__factory.connect(
        address || (await getDb().get(`${eContractid.Comptroller}.${DRE.network.name}`).value()),
        signerOrProvider
    );
export const getPriceOracleAggregator = async (address?: tEthereumAddress) =>
    await PriceOracleAggregator__factory.connect(
        address || (await getDb().get(`${eContractid.PriceOracleAggregator}.${DRE.network.name}`).value()),
        await getFirstSigner()
    )

export const getTestPriceOracle = async (address?: tEthereumAddress) =>
    await TestPriceOracle__factory.connect(
        address || (await getDb().get(`${eContractid.TestPriceOracle}.${DRE.network.name}`).value()),
        await getFirstSigner()
    )

// export const getSimpleOracleChainlink = async (address?: tEthereumAddress) =>
//     await SimplePriceOracleChainlink__factory.connect(
//         address || (await getDb().get(`${eContractid.Comptroller}.${DRE.network.name}`).value()).address,
//         await getFirstSigner()
//     )

// export const getCEther = async (address?: tEthereumAddress) =>
//     await PEther__factory.connect(
//         address || (await getDb().get(`${eContractid.CEther}.${DRE.network.name}`).value()).address,
//         await getFirstSigner()
//     )

export const getPErc20Delegator = async (symbol: string, address?: tEthereumAddress) =>
    await PErc20Delegator__factory.connect(
        address || (await getDb().get(`${eContractid.PERC20Delegator}.${DRE.network.name}`).value())[symbol],
        await getFirstSigner()
    )

export const getPErc20DelegatorOption = async (symbol: string, signerOrProvider: Signer | Provider, address?: tEthereumAddress) =>
    await PErc20Delegator__factory.connect(
        address || (await getDb().get(`${eContractid.PERC20Delegator}.${DRE.network.name}`).value())[symbol],
        signerOrProvider
    )


export const getStandardToken = async (symbol: string, address?: tEthereumAddress) =>
    await StandardToken__factory.connect(
        address || (await getDb().get(`${eContractid.NewAssetsToken}.${DRE.network.name}`).value())[symbol],
        await getFirstSigner()
    )

export const getStandardTokenOption = async (symbol: string, signerOrProvider: Signer | Provider, address?: tEthereumAddress) =>
    await StandardToken__factory.connect(
        address || (await getDb().get(`${eContractid.NewAssetsToken}.${DRE.network.name}`).value())[symbol],
        signerOrProvider
    )

export const getPubMiningRateModelImpl = async (address?: tEthereumAddress) =>
    await PubMiningRateModelImpl__factory.connect(
        address || (await getDb().get(`${eContractid.PubMiningRateModel}.${DRE.network.name}`).value()),
        await getFirstSigner()
    )

export const getMSPStorageImpl = async (symbol: string, address?: tEthereumAddress) =>
    await StorageImpl__factory.connect(
        address || (await getDb().get(`${eContractid.MSPStorage}.${DRE.network.name}`).value())[symbol],
        await getFirstSigner()
    )

export const getCapital = async (symbol: string, address?: tEthereumAddress) =>
    await Capital__factory.connect(
        address || (await getDb().get(`${eContractid.Capital}.${DRE.network.name}`).value())[symbol],
        await getFirstSigner()
    )

export const getMarginSwapPool = async (symbol: string, address?: tEthereumAddress) =>
    await MarginSwapPool__factory.connect(
        address || (await getDb().get(`${eContractid.MarginSwapPool}.${DRE.network.name}`).value())[symbol],
        await getFirstSigner()
    )
export const getLiquidation = async (symbol: string, address?: tEthereumAddress) =>
    await Liquidation__factory.connect(
        address || (await getDb().get(`${eContractid.Liquidation}.${DRE.network.name}`).value())[symbol],
        await getFirstSigner()
    )

export const getController = async (address?: tEthereumAddress) =>
    Controller__factory.connect(
        address || (await getDb().get(`${eContractid.Controller}.${DRE.network.name}`).value()),
        await getFirstSigner()
    )

export const getMockTXAggregator = async (address?: tEthereumAddress) =>
    MockTXAggregator__factory.connect(
        address || (await getDb().get(`${eContractid.MockTXAggregator}.${DRE.network.name}`).value()),
        await getFirstSigner()
    )
export const getPub = async (address?: tEthereumAddress) =>
    Publ__factory.connect(
        address || (await getDb().get(`${eContractid.PUB}.${DRE.network.name}`).value()),
        await getFirstSigner()
    )