import json
import os
import time

import requests
from brownie import (BUSD, IBFR, USDC, WBNB, WNEAR, ABDKMath64x64,
                     BufferBinaryEuropeanATMOptions,
                     BufferBinaryEuropeanTokenXOptions, BufferBinaryIBFRPool,
                     BufferEuropeanUSDCTokenXOptions, BufferIBFRPoolV2,
                     CustomPriceProvider, FeeCalculator, OptionConfig,
                     OptionConfigBinary, OptionConfigBinaryV2, OptionMath,
                     PriceProvider, Router, accounts, network)

from .utility import deploy_contract, save_flat

ONE_DAY = 86400


def main():

    gas_limit = 10000000
    allow_revert = False

    # Initializing the variables, If these variables are not reassigned in the Configurations section
    # then their corresponsding contracts are deployed otherwise directly address is used
    price_provider_address = None
    option_config_address = None
    usdc_contract_address = None
    pool_address = None
    token_contract_address = None
    decimals = 18
    options_address = None
    router_contract_address = None
    ########### Configurations ###########

    if network.show_active() == "bsc-test":
        pool_admin = accounts.add(os.environ["POOL_PK"])
        admin = accounts.add(os.environ["BFR_PK"])
        project_owner = accounts.add(os.environ["PROJECT_OWNER_PK"])
        staking_address = accounts.add(os.environ["STAKING_PK"])
        # bnb = "0x0000000000000000000000000000000000000000"
        pp = "0x2514895c72f50d8bd4b4f9b1110f0d6bd2c97526"

        iv = 150e2

        price_provider_address = "0x5563487F1E5aBe578D6Fb41a5cBb96940D89a459"
        # usdc_contract_address = "0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee"
        pool_address = "0x33B301A3f3780e12b2D73817af1884faa3cba4F4"
        option_config_address = "0x59Da3F556BCd51F20a07131ee7E912F1bD274d75"
        token_contract_address = "0xF5b58390c124bc8C1Cd84E9CFCF076d076869276"

    # if network.show_active() == "bsc-main":
    #     pool_admin = accounts.add(os.environ["POOL_PK"])
    #     admin = accounts.add(os.environ["BFR_PK"])
    #     project_owner = accounts.add(os.environ["PROJECT_OWNER_PK"])
    #     staking_address = accounts.add(os.environ["STAKING_PK"])

    #     fixedStrike = 0.14e8
    #     iv = 150e2

    #     usdc_contract_address = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56"
    #     token_contract_address = "0xa296aD1C47FE6bDC133f39555C1D1177BD51fBc5"
    #     token0 = token_contract_address
    #     token1 = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"
    #     twap = "0x348db2821c991f2cDbECeBA27562F6Bdf133312f"
    #     tokenX_address = token_contract_address
    #     bnb_pp = "0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE"
    #     # pool_address = ""
    #     # price_provider_address = "0x348db2821c991f2cDbECeBA27562F6Bdf133312f"

    if network.show_active() == "aurora-test":
        network.gas_limit(gas_limit)
        allow_revert = True
        pool_admin = accounts.add(os.environ["POOL_PK"])
        admin = accounts.add(os.environ["BFR_PK"])
        project_owner = accounts.add(os.environ["PROJECT_OWNER_PK"])
        staking_address = accounts.add(os.environ["STAKING_PK"])

        fixedStrike = 15e8
        iv = 120e2
        decimals = 24

        token_contract_address = "0xD669989A63303A30c45665Bc86C2C82d5fA03122"
        pp = "0x0a13BC1F3C441BCB165e8925Fe3E27d18d1Cd66C"
        price_provider_address = "0x2514895c72f50d8bd4b4f9b1110f0d6bd2c97526"
        pool_address = "0x16F24640a1409B6d9Ab85F59b01348E36862312f"
        option_config_address = "0x02e62fa9274973940Dc7D5F7b5475acaF4b19bCE"

    if network.show_active() == "aurora-main":
        network.gas_limit(gas_limit)
        allow_revert = True
        pool_admin = accounts.add(os.environ["POOL_PK"])
        admin = accounts.add(os.environ["BFR_PK"])
        project_owner = accounts.add(os.environ["PROJECT_OWNER_PK"])
        staking_address = accounts.add(os.environ["STAKING_PK"])

        fixedStrike = 16e8
        iv = 120e2
        decimals = 24

        token_contract_address = "0xC42C30aC6Cc15faC9bD938618BcaA1a1FaE8501d"
        pp = "0x0a9A9cF9bDe10c861Fc1e45aCe4ea097eaa268eD"
        # price_provider_address = "0x2514895c72f50d8bd4b4f9b1110f0d6bd2c97526"
        # pool_address = "0x1d2b8dE85506a9a38b1c861ec08EbE68386792AA"
        # option_config_address = "0x02e62fa9274973940Dc7D5F7b5475acaF4b19bCE"

    if network.show_active() == "polygon-test":
        network.gas_limit(gas_limit)
        allow_revert = True
        pool_admin = accounts.add(os.environ["POOL_PK"])
        admin = accounts.add(os.environ["BFR_PK"])
        project_owner = accounts.add(os.environ["PROJECT_OWNER_PK"])
        staking_address = accounts.add(os.environ["STAKING_PK"])
        # pp = "0x252Dc8D47d0fB05fdf28D3931B264Ca174D2Ace1"
        iv = 120e2
        decimals = 18

        token_contract_address = "0x5E351f387F790815e1874da4e2C669fC0Aa66C75"
        pool_address = "0x4234EA7197758Ab4DF96f3AcC561f1a05e80E741"
        price_provider_address = "0x11FE955f98790c15AB82c4c6164A79AeC136afE2"
        router_contract_address = "0xFE3fFA509B6a219D9acb588d47b2CFb32D0CFc51"
        # option_config_address = "0x8C2bAcDa46C05a9c5f5b42aC09924bdbee144f4a"
        # options_address = "0xe1d8d762954f82DE5180d261d0D46E6e4B51c796"

    if network.show_active() == "arbitrum-test":
        network.gas_limit(gas_limit)
        allow_revert = True
        pool_admin = accounts.add(os.environ["POOL_PK"])
        admin = accounts.add(os.environ["BFR_PK"])
        project_owner = accounts.add(os.environ["PROJECT_OWNER_PK"])
        staking_address = accounts.add(os.environ["STAKING_PK"])
        pp = "0x0c9973e7a27d00e656B9f153348dA46CaD70d03d"
        iv = 150e2
        decimals = 18

        token_contract_address = "0xF24e81D63af36942afC02068fC44F29d64972D98"
        # pp = "0x0a9A9cF9bDe10c861Fc1e45aCe4ea097eaa268eD"
        # price_provider_address = "0x4a587148d8E6E5d8E1c585d66C078e2E4C517304"
        # pool_address = "0xc6ab069311d5E59f6f3E3b85B38639e231BaefCA"
        # option_config_address = "0xB6b34CD394e2cc914a69f721217EA9E300a53693"

    print(pool_admin, admin, staking_address, project_owner)
    print(pool_admin.balance() / 1e18, admin.balance() / 1e18)

    ########### Get TokenX ###########

    if not token_contract_address:
        token_contract = deploy_contract(
            admin,
            network,
            USDC,
            [],
        )
        token_contract_address = token_contract.address


    ########### Router ###########

    if not router_contract_address:
        router_contract = deploy_contract(
            admin,
            network,
            Router,
            [token_contract_address],
        )
        router_contract_address = router_contract.address

    ########### Deploy pool ###########

    if pool_address:
        pool = BufferBinaryIBFRPool.at(pool_address)
    else:
        print("deploying pool", token_contract_address)
        ibfr_pool = deploy_contract(
            pool_admin,
            network,
            BufferBinaryIBFRPool,
            [token_contract_address],
        )
        pool = ibfr_pool
        pool_address = pool.address

        ########### Set Project Owner ###########

        ibfr_pool.setProjectOwner(
            project_owner,
            {"from": pool_admin, "allow_revert": allow_revert},
        )

        assert pool.tokenX() == token_contract_address
        assert pool.maxLiquidity() == 5000000 * (10**decimals)
        assert pool.owner() == pool_admin

    ########### Get Price Provider ###########

    if price_provider_address:
        price_provider = CustomPriceProvider.at(price_provider_address)
    else:
        price_provider = deploy_contract(
            admin,
            network,
            PriceProvider,
            [pp],
        )

    ########### Get Options Config ###########

    if option_config_address:
        option_config = OptionConfigBinaryV2.at(option_config_address)
    else:
        print(
            staking_address,
            iv,
            pool_address,
        )
        option_config = deploy_contract(
            admin,
            network,
            OptionConfigBinaryV2,
            [
                staking_address,
                iv,
                pool_address,
            ],
        )

        assert option_config.settlementFeeRecipient() == staking_address
        assert option_config.impliedVolRate() == iv
        assert option_config.pool() == pool

    ########### Deploy Options ###########
    if options_address:
        options = BufferBinaryEuropeanATMOptions.at(options_address)

    else:
        # deploy_contract(admin, network, ABDKMath64x64, [])
        # deploy_contract(admin, network, OptionMath, [])
        # deploy_contract(admin, network, FeeCalculator, [])
        options = deploy_contract(
            admin,
            network,
            BufferBinaryEuropeanATMOptions,
            [
                token_contract_address,
                price_provider.address,
                pool_address,
                option_config.address,
            ],
        )
        assert options.tokenX() == token_contract_address
        assert options.priceProvider() == price_provider.address
        assert options.pool() == pool

    ########### Grant Roles ###########

    OPTION_ISSUER_ROLE = pool.OPTION_ISSUER_ROLE()
    pool.grantRole(
        OPTION_ISSUER_ROLE,
        options.address,
        {"from": pool_admin, "allow_revert": allow_revert},
    )
    ROUTER_ROLE = options.ROUTER_ROLE()

    options.grantRole(
        ROUTER_ROLE,
        router_contract_address,
        {"from": admin},
    )
    ########### Approve the max amount ###########

    options.approvePoolToTransferTokenX(
        {"from": admin, "allow_revert": allow_revert},
    )

    ########### Flat Files ###########

    save_flat(BufferBinaryEuropeanATMOptions, "BufferBinaryEuropeanATMOptions")
    save_flat(BufferBinaryIBFRPool, "BufferBinaryIBFRPool")
    save_flat(OptionConfigBinary, "OptionConfigBinary")
    save_flat(OptionMath, "OptionMath")
    save_flat(FeeCalculator, "FeeCalculator")
