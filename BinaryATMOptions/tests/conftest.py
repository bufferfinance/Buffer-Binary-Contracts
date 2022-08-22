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
    IBFR,
    FakePriceProvider,
    OptionMath,
    ABDKMath64x64,
    accounts,
    BufferIBFRPoolV2,
    OptionConfig,
    BufferUSDCTokenXOptions,
    BufferSecuredPutEuropeanOptions,
    FeeCalculator,
    USDC,
    WNEAR,
    BufferEuropeanUSDCTokenXOptions,
    OptionConfigBinary,
    BufferBinaryEuropeanTokenXOptions,
    TvlSlidingWindowOracle,
    FakeCToken,
    TvlOracle,
    WBTC,
    USDT,
    FakePriceProviderv2,
    BufferBinaryEuropeanKPIOptions,
    BufferBinaryIBFRPool,
    OptionMeta,
    BufferBinaryEuropeanATMOptions,
    BufferBinaryIBFRPoolBinary,
    OptionConfigBinaryV2,
    CustomPriceProvider,
    Router
):
    fixedStrike = int(395e8)
    fixedExpiry = int(time.time()) + ONE_DAY * 7

    ibfr_contract = IBFR.deploy({"from": accounts[0]})

    wnear_contract = WNEAR.deploy({"from": accounts[0]})
    usdc_contract = wnear_contract
    token_contract = ibfr_contract
    tokenX = token_contract

    ibfr_pool = BufferIBFRPoolV2.deploy(
        token_contract.address, fixedExpiry, {"from": accounts[0]}
    )
    pp = FakePriceProvider.deploy(int(400e8), {"from": accounts[0]})
    bufferPp = pp

    # Deploy libraries
    ABDKMath64x64.deploy({"from": accounts[0]})
    OptionMath.deploy({"from": accounts[0]})
    FeeCalculator.deploy({"from": accounts[0]})

    iv = 110e2
    options_config = OptionConfig.deploy(
        accounts[7],
        iv,
        fixedStrike,
        ibfr_pool.address,
        {"from": accounts[0]},
    )

    usdc_options = BufferUSDCTokenXOptions.deploy(
        token_contract.address,
        bufferPp.address,
        ibfr_pool.address,
        options_config.address,
        usdc_contract.address,
        {"from": accounts[0]},
    )
    OPTION_ISSUER_ROLE = ibfr_pool.OPTION_ISSUER_ROLE()
    ibfr_pool.grantRole(
        OPTION_ISSUER_ROLE,
        usdc_options.address,
        {"from": accounts[0]},
    )

    european_usdc_options = BufferEuropeanUSDCTokenXOptions.deploy(
        token_contract.address,
        bufferPp.address,
        ibfr_pool.address,
        options_config.address,
        usdc_contract.address,
        {"from": accounts[0]},
    )
    OPTION_ISSUER_ROLE = ibfr_pool.OPTION_ISSUER_ROLE()
    ibfr_pool.grantRole(
        OPTION_ISSUER_ROLE,
        european_usdc_options.address,
        {"from": accounts[0]},
    )

    usdc_contract = USDC.deploy({"from": accounts[0]})
    usdc_pool = BufferIBFRPoolV2.deploy(
        usdc_contract.address, fixedExpiry, {"from": accounts[0]}
    )
    OPTION_ISSUER_ROLE = usdc_pool.OPTION_ISSUER_ROLE()
    iv = 110e2

    secured_puts_options_config = OptionConfig.deploy(
        accounts[0],
        iv,
        fixedStrike,
        usdc_pool.address,
        {"from": accounts[0]},
    )
    usdc_secured_put_european_options = BufferSecuredPutEuropeanOptions.deploy(
        ibfr_contract.address,
        pp.address,
        usdc_pool.address,
        options_config.address,
        usdc_contract.address,
        {"from": accounts[0]},
    )
    usdc_pool.grantRole(
        OPTION_ISSUER_ROLE,
        usdc_secured_put_european_options.address,
        {"from": accounts[0]},
    )

    OPTION_ISSUER_ROLE = usdc_pool.OPTION_ISSUER_ROLE()
    iv = 110e2

    binary_pool = BufferBinaryIBFRPool.deploy(
        ibfr_contract.address, {"from": accounts[0]}
    )

    binary_options_config = OptionConfigBinary.deploy(
        accounts[0],
        iv,
        binary_pool.address,
        {"from": accounts[0]},
    )
    binary_european_options = BufferBinaryEuropeanTokenXOptions.deploy(
        ibfr_contract.address,
        pp.address,
        binary_pool.address,
        binary_options_config.address,
        {"from": accounts[0]},
    )
    OPTION_ISSUER_ROLE = binary_pool.OPTION_ISSUER_ROLE()
    binary_pool.grantRole(
        OPTION_ISSUER_ROLE,
        binary_european_options.address,
        {"from": accounts[0]},
    )

    print("############### KPI Options #################")

    usdt_contract = USDT.deploy({"from": accounts[0]})
    wbtc_contract = WBTC.deploy({"from": accounts[0]})
    wnear_contract = WNEAR.deploy({"from": accounts[0]})

    cash_wbtc = 41022738481
    cash_usdt = 261146631540360
    cash_wnear = 1022471258703175637581739910017
    cashs = [cash_wbtc, cash_usdt, cash_wnear]
    prices = [31330e8, 1e8, 8e8]
    decimals = [8, 6, 24]
    usdt_ctoken_contract = FakeCToken.deploy(
        usdt_contract.address, cash_usdt, {"from": accounts[0]}
    )
    wbtc_ctoken_contract = FakeCToken.deploy(
        wbtc_contract.address, cash_wbtc, {"from": accounts[0]}
    )
    wnear_ctoken_contract = FakeCToken.deploy(
        wnear_contract.address, cash_wnear, {"from": accounts[0]}
    )

    wbtc_pp = FakePriceProviderv2.deploy(int(31330e8), {"from": accounts[0]})
    usdt_pp = FakePriceProviderv2.deploy(int(1e8), {"from": accounts[0]})
    wnear_pp = FakePriceProviderv2.deploy(int(8e8), {"from": accounts[0]})

    usdBalances = []
    for i in range(len(cashs)):
        _usdBalance = (cashs[i] * prices[i]) // (10 ** decimals[i])
        usdBalances.append(_usdBalance)
    print(sum(usdBalances))
    total_expected_tvl = sum(usdBalances)

    tvl_oracle = TvlOracle.deploy(
        [
            usdt_ctoken_contract.address,
            wbtc_ctoken_contract.address,
            wnear_ctoken_contract.address,
        ],
        [
            usdt_contract.address,
            wbtc_contract.address,
            wnear_contract.address,
        ],
        [
            usdt_pp.address,
            wbtc_pp.address,
            wnear_pp.address,
        ],
        {"from": accounts[0]},
    )

    window_size = 86400
    period = 12

    tvl_twap = TvlSlidingWindowOracle.deploy(
        window_size,
        period,
        {"from": accounts[0]},
    )

    fixedExpiry = int(time.time()) + ONE_DAY * 2

    kpi_pool = BufferIBFRPoolV2.deploy(
        token_contract.address, fixedExpiry, {"from": accounts[0]}
    )
    PROJECT_OWNER_ROLE = kpi_pool.PROJECT_OWNER_ROLE()

    kpi_options_config = OptionConfig.deploy(
        accounts[7],
        iv,
        total_expected_tvl // 2,
        kpi_pool.address,
        {"from": accounts[0]},
    )
    kpi_options = BufferBinaryEuropeanKPIOptions.deploy(
        ibfr_contract.address,
        tvl_oracle.address,
        tvl_twap.address,
        pp.address,
        kpi_pool.address,
        kpi_options_config.address,
        {"from": accounts[0]},
    )
    kpi_pool.grantRole(
        OPTION_ISSUER_ROLE,
        kpi_options.address,
        {"from": accounts[0]},
    )
    kpi_pool.grantRole(
        PROJECT_OWNER_ROLE,
        accounts[7],
        {"from": accounts[0]},
    )

    option_meta = OptionMeta.deploy({"from": accounts[0]})
    cpp = CustomPriceProvider.deploy({"from": accounts[0]})

    print("############### Binary ATM Options #################")

    binary_pool_atm = BufferBinaryIBFRPoolBinary.deploy(
        ibfr_contract.address, {"from": accounts[0]}
    )

    binary_options_config_atm = OptionConfigBinaryV2.deploy(
        accounts[0],
        iv,
        binary_pool_atm.address,
        {"from": accounts[0]},
    )
    binary_european_options_atm = BufferBinaryEuropeanATMOptions.deploy(
        ibfr_contract.address,
        pp.address,
        binary_pool_atm.address,
        binary_options_config_atm.address,
        {"from": accounts[0]},
    )
    OPTION_ISSUER_ROLE = binary_pool_atm.OPTION_ISSUER_ROLE()
    binary_pool_atm.grantRole(
        OPTION_ISSUER_ROLE,
        binary_european_options_atm.address,
        {"from": accounts[0]},
    )
    router = Router.deploy(
        ibfr_contract.address,
        {"from": accounts[0]}
    )
    ROUTER_ROLE = binary_european_options_atm.ROUTER_ROLE()

    binary_european_options_atm.grantRole(
        ROUTER_ROLE,
        router.address,
        {"from": accounts[0]},
    )
    return (
        token_contract,
        pp,
        tokenX,
        options_config,
        ibfr_pool,
        usdc_options,
        usdc_contract,
        bufferPp,
        european_usdc_options,
        usdc_contract,
        usdc_pool,
        secured_puts_options_config,
        usdc_secured_put_european_options,
        binary_options_config,
        binary_european_options,
        tvl_oracle,
        tvl_twap,
        wnear_ctoken_contract,
        total_expected_tvl,
        kpi_options,
        kpi_options_config,
        kpi_pool,
        binary_pool,
        option_meta,
        binary_pool_atm,
        binary_options_config_atm,
        binary_european_options_atm,
        cpp,
        router
    )
