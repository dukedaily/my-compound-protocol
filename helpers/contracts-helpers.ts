import { Contract, Signer, utils, ethers, BigNumberish } from 'ethers';
import { signTypedData_v4 } from 'eth-sig-util';
import { fromRpcSig, ECDSASignature } from 'ethereumjs-util';
import BigNumber from 'bignumber.js';
import { getDb, DRE, waitForTx } from './misc-utils';
import {
    tEthereumAddress,
    eContractid,
    tStringTokenSmallUnits,
    eEthereumNetwork,
    iParamsPerNetwork,
    eNetwork,
    iEthereumParamsPerNetwork,
} from './types';
import { verifyContract } from './etherscan-verification';
// import { getIErc20Detailed } from './contracts-getters';
// import { usingTenderly } from './tenderly-utils';
// import { MintableERC20 } from '../types/MintableERC20';


export const registerContractInJsonDb = async (contractId: string, contractInstance: Contract, name: string) => {
    const currentNetwork = DRE.network.name;
    const MAINNET_FORK = process.env.MAINNET_FORK === 'true';
    if (MAINNET_FORK || (currentNetwork !== 'hardhat' && !currentNetwork.includes('coverage'))) {
        console.log(`duke:*** ${contractId} ***duke\n`);
        console.log(`Network: ${currentNetwork}`);
        console.log(`tx: ${contractInstance.deployTransaction.hash}`);
        console.log(`contract address: ${contractInstance.address}`);
        console.log(`deployer address: ${contractInstance.deployTransaction.from}`);
        console.log(`gas price: ${contractInstance.deployTransaction.gasPrice}`);
        console.log(`gas used: ${contractInstance.deployTransaction.gasLimit}`);
        console.log(`${contractId}  存储完毕!`);
        console.log(`\n******`);
    }

    let  path = `${contractId}.${currentNetwork}`
    if (name != '') {
        path = path + `.${name}`
    }

    console.log("path:", path)
    await getDb().set(path, contractInstance.address).write();
};

export const insertContractAddressInDb = async (id: eContractid, address: tEthereumAddress) =>
    await getDb()
        .set(`${id}.${DRE.network.name}`, {
            address,
        })
        .write();

export const rawInsertContractAddressInDb = async (id: string, address: tEthereumAddress) =>
    await getDb()
        .set(`${id}.${DRE.network.name}`, {
            address,
        })
        .write();

export const getEthersSigners = async (): Promise<Signer[]> =>
    await Promise.all(await DRE.ethers.getSigners());

export const getEthersSignersAddresses = async (): Promise<tEthereumAddress[]> =>
    await Promise.all((await DRE.ethers.getSigners()).map((signer) => signer.getAddress()));

export const getCurrentBlock = async () => {
    return DRE.ethers.provider.getBlockNumber();
};

export const decodeAbiNumber = (data: string): number =>
    parseInt(utils.defaultAbiCoder.decode(['uint256'], data).toString());

export const deployContract = async <ContractType extends Contract>(
    contractName: string,
    args: any[]
): Promise<ContractType> => {
    const contract = (await (await DRE.ethers.getContractFactory(contractName)).deploy(
        ...args
    )) as ContractType;
    await waitForTx(contract.deployTransaction);
    // console.log("in deployContract call registerContractInJsonDb");

    await registerContractInJsonDb(<eContractid>contractName, contract, '');
    return contract;
};

export const withSaveAndVerify = async <ContractType extends Contract>(
    instance: ContractType,
    id: string,
    name: string,
    args : (string | string[])[],
    verify ?: boolean
): Promise<ContractType> => {
    console.log("in withSaveAndVerify");
    await waitForTx(instance.deployTransaction);
    await registerContractInJsonDb(id, instance, name);
    if (verify) {
        await verifyContract(instance.address, args);
    }
    return instance;
};

export const getContract = async <ContractType extends Contract>(
    contractName: string,
    address: string
): Promise<ContractType> => (await DRE.ethers.getContractAt(contractName, address)) as ContractType;

export const getParamPerNetwork = <T>(param: iParamsPerNetwork<T>, network: eNetwork) => {
    const {
        main,
        ropsten,
        kovan,
    } = param as iEthereumParamsPerNetwork<T>;
    const MAINNET_FORK = process.env.MAINNET_FORK === 'true';
    if (MAINNET_FORK) {
        console.log("网络切换为主网!");
        return main;
    }

    switch (network) {
        case eEthereumNetwork.kovan:
            return kovan;
        case eEthereumNetwork.ropsten:
            console.log("duke:eEthereumNetwork.ropsten!");
            return ropsten;
        case eEthereumNetwork.main:
            return main;
    }
};

// export const convertToCurrencyDecimals = async (tokenAddress: tEthereumAddress, amount: string) => {
//     const token = await getIErc20Detailed(tokenAddress);
//     let decimals = (await token.decimals()).toString();

//     return ethers.utils.parseUnits(amount, decimals);
// };

// export const convertToCurrencyUnits = async (tokenAddress: string, amount: string) => {
//     const token = await getIErc20Detailed(tokenAddress);
//     let decimals = new BigNumber(await token.decimals());
//     const currencyUnit = new BigNumber(10).pow(decimals);
//     const amountInCurrencyUnits = new BigNumber(amount).div(currencyUnit);
//     return amountInCurrencyUnits.toFixed();
// };

// export const buildPermitParams = (
//     chainId: number,
//     token: tEthereumAddress,
//     revision: string,
//     tokenName: string,
//     owner: tEthereumAddress,
//     spender: tEthereumAddress,
//     nonce: number,
//     deadline: string,
//     value: tStringTokenSmallUnits
// ) => ({
//     types: {
//         EIP712Domain: [
//             { name: 'name', type: 'string' },
//             { name: 'version', type: 'string' },
//             { name: 'chainId', type: 'uint256' },
//             { name: 'verifyingContract', type: 'address' },
//         ],
//         Permit: [
//             { name: 'owner', type: 'address' },
//             { name: 'spender', type: 'address' },
//             { name: 'value', type: 'uint256' },
//             { name: 'nonce', type: 'uint256' },
//             { name: 'deadline', type: 'uint256' },
//         ],
//     },
//     primaryType: 'Permit' as const,
//     domain: {
//         name: tokenName,
//         version: revision,
//         chainId: chainId,
//         verifyingContract: token,
//     },
//     message: {
//         owner,
//         spender,
//         value,
//         nonce,
//         deadline,
//     },
// });

export const getSignatureFromTypedData = (
    privateKey: string,
    typedData: any // TODO: should be TypedData, from eth-sig-utils, but TS doesn't accept it
): ECDSASignature => {
    const signature = signTypedData_v4(Buffer.from(privateKey.substring(2, 66), 'hex'), {
        data: typedData,
    });
    return fromRpcSig(signature);
};

export const buildLiquiditySwapParams = (
    assetToSwapToList: tEthereumAddress[],
    minAmountsToReceive: BigNumberish[],
    swapAllBalances: BigNumberish[],
    permitAmounts: BigNumberish[],
    deadlines: BigNumberish[],
    v: BigNumberish[],
    r: (string | Buffer)[],
    s: (string | Buffer)[],
    useEthPath: boolean[]
) => {
    return ethers.utils.defaultAbiCoder.encode(
        [
            'address[]',
            'uint256[]',
            'bool[]',
            'uint256[]',
            'uint256[]',
            'uint8[]',
            'bytes32[]',
            'bytes32[]',
            'bool[]',
        ],
        [
            assetToSwapToList,
            minAmountsToReceive,
            swapAllBalances,
            permitAmounts,
            deadlines,
            v,
            r,
            s,
            useEthPath,
        ]
    );
};

export const buildRepayAdapterParams = (
    collateralAsset: tEthereumAddress,
    collateralAmount: BigNumberish,
    rateMode: BigNumberish,
    permitAmount: BigNumberish,
    deadline: BigNumberish,
    v: BigNumberish,
    r: string | Buffer,
    s: string | Buffer,
    useEthPath: boolean
) => {
    return ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint256', 'uint256', 'uint256', 'uint256', 'uint8', 'bytes32', 'bytes32', 'bool'],
        [collateralAsset, collateralAmount, rateMode, permitAmount, deadline, v, r, s, useEthPath]
    );
};

export const buildFlashLiquidationAdapterParams = (
    collateralAsset: tEthereumAddress,
    debtAsset: tEthereumAddress,
    user: tEthereumAddress,
    debtToCover: BigNumberish,
    useEthPath: boolean
) => {
    return ethers.utils.defaultAbiCoder.encode(
        ['address', 'address', 'address', 'uint256', 'bool'],
        [collateralAsset, debtAsset, user, debtToCover, useEthPath]
    );
};
