import time
from enum import IntEnum

import brownie


class OptionType(IntEnum):
    ALL = 0
    PUT = 1
    CALL = 2
    NONE = 3


ONE_DAY = 86400
ADDRESS_0 = "0x0000000000000000000000000000000000000000"


class BinaryATMOptionTesting(object):
    def __init__(
        self,
        accounts,
        options,
        generic_pool,
        total_fee,
        chain,
        tokenX,
        liquidity,
        options_config,
        bufferPp,
        period,
        is_yes,
        is_above,
    ):
        self.tokenX_options = options
        self.options_config = options_config
        self.generic_pool = generic_pool
        self.total_fee = total_fee
        self.option_holder = accounts[1]
        self.accounts = accounts
        self.owner = accounts[0]
        self.user_1 = accounts[1]
        self.user_2 = accounts[2]
        self.referrer = accounts[3]
        self.project_owner = accounts[7]
        self.option_id = 0
        self.liquidity = liquidity
        self.tokenX = tokenX
        self.chain = chain
        self.period = period
        self.pp = bufferPp
        self.is_yes = is_yes
        self.is_above = is_above

    def verify_owner(self):
        self.generic_pool.setProjectOwner(self.project_owner, {"from": self.owner})
        assert (
            self.tokenX_options.owner() == self.accounts[0]
        ), "The owner of the contract should be the account the contract was deployed by"

    def verify_creation(self):
        totalTokenXBalance = self.generic_pool.totalTokenXBalance()
        if totalTokenXBalance == 0:
            with brownie.reverts('O23'):
                self.tokenX_options.create(
                    self.total_fee,
                    self.period,
                    self.is_yes,
                    self.is_above,
                    self.user_1,
                    {"from": self.owner}
                )
            self.tokenX.transfer(self.user_2, self.liquidity, {"from": self.owner})
            self.tokenX.approve(
                self.generic_pool.address, self.liquidity, {"from": self.owner}
            )
            self.generic_pool.provide(self.liquidity, 0, {"from": self.owner})

        with brownie.reverts("O21"):
            self.tokenX_options.create(
                self.total_fee,
                120,
                self.is_yes,
                self.is_above,
                self.user_1,
                {"from": self.owner}
            )

        with brownie.reverts("O24"):
            self.tokenX_options.create(
                self.total_fee,
                87400,
                self.is_yes,
                self.is_above,
                self.user_1,
                {"from": self.owner}
            )
        with brownie.reverts("O25"):
            self.tokenX_options.create(
                int(1e18) / 5,
                self.period,
                self.is_yes,
                self.is_above,
                self.user_1,
                {"from": self.owner}
            )

        self.tokenX_options.approvePoolToTransferTokenX(
            {"from": self.owner},
        )

        initial_tokenX_balance_pool = self.tokenX.balanceOf(self.generic_pool.address)
        self.tokenX.approve(self.tokenX_options.address, self.total_fee*self.total_fee, {"from": self.owner})

        option = self.tokenX_options.create(
            self.total_fee,
            self.period,
            self.is_yes,
            self.is_above,
            self.user_1,
            {"from": self.owner}
        )

        create_events = option.events
        self.option_id = option.return_value
        (
            _,
            self.strike,
            self.amount,
            _locked_amount,
            _premium,
            _,
            _,
        ) = self.tokenX_options.options(self.option_id)

        final_tokenX_balance_pool = self.tokenX.balanceOf(self.generic_pool.address)
        unitFee, _, _ = self.tokenX_options.fees(
            self.period,
            int(1e18),
            self.strike,
            self.is_yes,
            self.is_above
        )
        assert self.amount == self.total_fee/unitFee
        assert self.total_fee ==  create_events["Create"]["totalFee"] 
        assert _premium ==  int(1e18) /2 
        assert self.amount ==  _locked_amount
        assert _premium ==  int(1e18) /2 
        assert final_tokenX_balance_pool - initial_tokenX_balance_pool == _premium
 
        return self.option_id

    def admin_function(self, round_id, expected_round_id):

        self.tokenX_options.setRoundIDForExpiry(
            round_id, self.option_id, {"from": self.accounts[0]}
        )
        _round_id = self.tokenX_options.expiryToRoundID(self.expiry)
        assert _round_id == expected_round_id

    def european_unlock(self, round_id):
        self.chain.snapshot()
        with brownie.reverts("O4"):
            self.tokenX_options.unlock(self.option_id, {"from": self.option_holder})

        self.chain.sleep(self.period + ONE_DAY)
        self.chain.mine(1)
        option_data = self.tokenX_options.options(self.option_id)
        initial_tokenX_balance_option_holder = self.tokenX.balanceOf(self.option_holder)
        unlock_option = self.tokenX_options.unlock(
            self.option_id, {"from": self.option_holder}
        )
        final_tokenX_balance_option_holder = self.tokenX.balanceOf(self.option_holder)
        print("unlocked", self.option_id)
        option_data = self.tokenX_options.options(self.option_id)

        unlock_events = unlock_option.events
        (_, price, _, _, _) = self.pp.getRoundData(round_id)

        if self.strike < price:
            expected_profit = self.amount

            assert unlock_events["Exercise"]["profit"] == expected_profit
            assert option_data["state"] == 2
            assert (
                final_tokenX_balance_option_holder
                - initial_tokenX_balance_option_holder
                == expected_profit
            )
        else:
            print("Expire")
            assert unlock_events["Expire"]["premium"] == option_data[4]
            assert option_data["state"] == 3
            assert (
                final_tokenX_balance_option_holder
                - initial_tokenX_balance_option_holder
                == 0
            )
        self.chain.revert()

    def european_exercise(self, round_id):
        self.chain.snapshot()
        with brownie.reverts("O4"):
            self.tokenX_options.exercise(self.option_id, {"from": self.option_holder})
        self.chain.sleep(self.period + ONE_DAY)
        self.chain.mine(1)
        (_, price, _, _, _) = self.pp.getRoundData(round_id)
        exerciser = self.user_2

        if self.strike <= price:
            initial_tokenX_balance_option_holder = self.tokenX.balanceOf(
                self.option_holder
            )
            initial_tokenX_balance_exerciser = self.tokenX.balanceOf(exerciser)
            expected_profit = self.amount

            exercise_option = self.tokenX_options.exercise(
                self.option_id, {"from": exerciser}
            )
            print("exercised", self.option_id)

            final_tokenX_balance_option_holder = self.tokenX.balanceOf(
                self.option_holder
            )
            final_tokenX_balance_exerciser = self.tokenX.balanceOf(exerciser)
            exercise_events = exercise_option.events

            assert exercise_events["Exercise"]["profit"] == expected_profit
            assert (
                final_tokenX_balance_option_holder
                - initial_tokenX_balance_option_holder
                == expected_profit
            )
            assert (
                final_tokenX_balance_exerciser - initial_tokenX_balance_exerciser == 0
            )
        else:
            with brownie.reverts("O17"):
                exercise_option = self.tokenX_options.exercise(
                    self.option_id, {"from": self.option_holder}
                )
        self.chain.revert()

    def test_european_changes(
        self, round_ids, expiration_dates, round_id, expected_round_id, strike
    ):
        self.chain.snapshot()

        for count, _round_id in enumerate(round_ids):
            self.pp.setRoundData(
                _round_id,
                expiration_dates[count],
                strike,
                {"from": self.accounts[0]},
            )
        self.admin_function(round_id, expected_round_id)
        self.european_unlock(expected_round_id)
        self.european_exercise(expected_round_id)
        self.chain.revert()

    def complete_flow_test(self):
        self.verify_owner()
        self.option_id = self.verify_creation()
        self.option_id = self.verify_creation()

        self.chain.snapshot()
        with brownie.reverts("O20"):
            self.chain.sleep(self.period + ONE_DAY)
            self.chain.mine(1)
            self.tokenX_options.unlock(
                self.option_id, {"from": self.option_holder}
            )
        self.chain.revert()



def test_BinaryATMOptions(contracts, accounts, chain):

    (
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
        binary_pool_atm,
        binary_options_config_atm,
        binary_european_options_atm
    ) = contracts
    total_fee = int(1e18)
    liquidity = int(100000 * 1e18)
    period = 60400
    isYes = True
    isAbove = True
    option = BinaryATMOptionTesting(
        accounts,
        binary_european_options_atm,
        binary_pool_atm,
        total_fee,
        chain,
        tokenX,
        liquidity,
        binary_options_config_atm,
        bufferPp,
        period,
        isYes,
        isAbove,
    )
    option.complete_flow_test()
