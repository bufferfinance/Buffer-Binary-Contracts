#!/usr/bin/python3

import time
from enum import IntEnum

import pytest

ONE_DAY = 86400


class OptionType(IntEnum):
    ALL = 0
    PUT = 1
    CALL = 2
    NONE = 3


@pytest.fixture(scope="function", autouse=True)
def isolate(fn_isolation):
    # perform a chain rewind after completing each test, to ensure proper isolation
    # https://eth-brownie.readthedocs.io/en/v1.10.3/tests-pytest-intro.html#isolation-fixtures
    pass


@pytest.fixture(scope="module")
def contracts(
    accounts,
    TournamentManager,
    BufferBinaryIBFRPoolBinary,
    OptionConfigBinaryV2,
    BufferBinaryEuropeanATMOptions,
    CustomPriceProvider,
    IBFR,
    BUSD,
    USDC,
    WBNB,
):
    iv = 110e2

    ibfr_contract = IBFR.deploy({"from": accounts[0]})
    busd_contract = BUSD.deploy({"from": accounts[0]})
    usdc_contract = USDC.deploy({"from": accounts[0]})
    wbnb_contract = WBNB.deploy({"from": accounts[0]})
    pp = CustomPriceProvider.deploy({"from": accounts[0]})

    tournamentManager = TournamentManager.deploy(
        accounts[1],
        {"from": accounts[0]},
    )

    binary_pool_atm = BufferBinaryIBFRPoolBinary.deploy(
        tournamentManager.address, {"from": accounts[0]}
    )

    binary_options_config_atm = OptionConfigBinaryV2.deploy(
        accounts[0],
        iv,
        binary_pool_atm.address,
        {"from": accounts[0]},
    )
    binary_european_options_atm = BufferBinaryEuropeanATMOptions.deploy(
        "BTC-USD",
        pp.address,
        binary_pool_atm.address,
        binary_options_config_atm.address,
        {"from": accounts[0]},
    )
    OPTION_ISSUER_ROLE = binary_pool_atm.OPTION_ISSUER_ROLE()
    LIQUIDITY_POOL_ROLE = tournamentManager.LIQUIDITY_POOL_ROLE()
    binary_pool_atm.grantRole(
        OPTION_ISSUER_ROLE,
        binary_european_options_atm.address,
        {"from": accounts[0]},
    )
    tournamentManager.grantRole(
        LIQUIDITY_POOL_ROLE,
        binary_pool_atm.address,
        {"from": accounts[0]},
    )
    return (
        tournamentManager,
        ibfr_contract,
        busd_contract,
        usdc_contract,
        wbnb_contract,
        binary_pool_atm,
        binary_european_options_atm,
        binary_options_config_atm,
        pp,
    )
