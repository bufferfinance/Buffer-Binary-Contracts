import time
from enum import IntEnum
from random import randrange, uniform

import brownie
from click import option
from colorama import Fore, Style
from pyrsistent import s


class OptionType(IntEnum):
    ALL = 0
    PUT = 1
    CALL = 2
    NONE = 3


ONE_DAY = 86400
ADDRESS_0 = "0x0000000000000000000000000000000000000000"
bytes_0 = "0x0000000000000000000000000000000000000000000000000000000000000000"


def _amount(x):
    return x / 1e18


class NoLossTournaments(object):
    def __init__(
        self,
        accounts,
        tournamentManager,
        ticketToken,
        rewardToken,
        tournamentId,
        users,
        chain,
        binary_pool_atm,
        binary_european_options_atm,
        binary_options_config_atm,
        pp,
    ):
        self.tournamentManager = tournamentManager
        self.ticketToken = ticketToken
        self.rewardToken = rewardToken
        self.tournamentId = tournamentId
        self.accounts = accounts
        self.user = self.accounts[7]
        self.owner = accounts[0]
        self.pool = accounts[9]
        self.users = users
        self.chain = chain
        self.binary_pool_atm = binary_pool_atm
        self.binary_options_config_atm = binary_options_config_atm
        self.binary_european_options_atm = binary_european_options_atm
        self.period = 300
        self.pp = pp

    def buy_ticket(self):
        tournament = self.tournamentManager.tournaments(self.tournamentId)

        self.ticketToken.transfer(
            self.user, tournament[3], {"from": brownie.accounts[0]}
        )
        self.ticketToken.approve(
            self.tournamentManager.address, tournament[3], {"from": self.user}
        )
        initialTicketTokenBalanceUser = self.ticketToken.balanceOf(self.user)
        initialTicketTokenBalanceTicketFeeReceipient = self.ticketToken.balanceOf(
            self.tournamentManager.ticketFeeReceipient()
        )
        buy = self.tournamentManager.buyTicket(self.tournamentId, {"from": self.user})
        finalTicketTokenBalanceUser = self.ticketToken.balanceOf(self.user)
        finalTicketTokenBalanceTicketFeeReceipient = self.ticketToken.balanceOf(
            self.tournamentManager.ticketFeeReceipient()
        )
        assert (
            finalTicketTokenBalanceTicketFeeReceipient
            - initialTicketTokenBalanceTicketFeeReceipient
            == tournament[3]
            and initialTicketTokenBalanceUser - finalTicketTokenBalanceUser
            == tournament[3]
        ), "Wrong ticket token balance"

    def buy_option(self, user, isYes, isAbove, fee):

        initialPlayTokenBalance = self.tournamentManager.balanceOf(
            user, self.tournamentId
        )
        initialPoolPlayTokenBalance = self.tournamentManager.balanceOf(
            self.binary_pool_atm.address, self.tournamentId
        )
        print(
            "Buying option with ", _amount(initialPlayTokenBalance), "for", _amount(fee)
        )
        option_id = self.binary_european_options_atm.create(
            fee, self.period, isYes, isAbove, user, self.tournamentId, {"from": user}
        ).return_value
        (
            _,
            self.strike,
            self.amount,
            _locked_amount,
            _premium,
            _,
            _,
            _,
            _,
        ) = self.binary_european_options_atm.options(option_id)
        finalPlayTokenBalance = self.tournamentManager.balanceOf(
            user, self.tournamentId
        )
        finalPoolPlayTokenBalance = self.tournamentManager.balanceOf(
            self.binary_pool_atm.address, self.tournamentId
        )
        print("locked_amount", _locked_amount)
        assert initialPlayTokenBalance - finalPlayTokenBalance == fee, "Fee not burnt"
        assert (
            finalPoolPlayTokenBalance - initialPoolPlayTokenBalance == _locked_amount
        ), "Wrong pool tokens minted"
        return option_id

    def rank_list(self):
        cursor = self.tournamentManager.tournaments(self.tournamentId)[8]
        while cursor != bytes_0:
            # print("cursor", cursor)
            rank = self.tournamentManager.tournamentUserRank(cursor)
            print((rank[2], rank[3]), " => ", end=" ")
            cursor = rank[0]
            # break
        print("end")

    def claimReward(self, user, tournamentId, rewardToken):
        reward = self.tournamentManager.getUserReward(user, tournamentId)

        initialRewardTokenBalanceUser = rewardToken.balanceOf(user)
        initialRewardTokenBalanceManager = rewardToken.balanceOf(
            self.tournamentManager.address
        )
        claim_rewards = self.tournamentManager.claimReward(tournamentId, {"from": user})
        finalRewardTokenBalanceUser = rewardToken.balanceOf(user)
        finalRewardTokenBalanceManager = rewardToken.balanceOf(
            self.tournamentManager.address
        )
        print(user, reward)
        assert (
            finalRewardTokenBalanceUser - initialRewardTokenBalanceUser == reward
            and initialRewardTokenBalanceManager - finalRewardTokenBalanceManager
            == reward
        ), "Wrong reward token balance"

    def unlock_option(self, option_id):
        print("unlocking", option_id)
        (
            _,
            strike,
            amount,
            _locked_amount,
            _premium,
            expiration,
            _,
            _,
            _,
        ) = self.binary_european_options_atm.options(option_id)
        self.current_price = self.pp.getUsdPrice()
        print(self.current_price)
        print(
            f"{Fore.GREEN}time diff{Style.RESET_ALL} {expiration - self.chain.time()}"
        )
        if self.chain.time() < expiration:
            factor = uniform(0, 2)
            print(factor)
            self.pp.update(int(self.current_price * factor), {"from": self.accounts[0]})
            self.chain.sleep(expiration - self.chain.time() + 2)
        self.current_price = self.pp.getUsdPrice()
        self.chain.sleep(expiration - self.chain.time() + 1)
        self.pp.update(int(self.current_price), {"from": self.accounts[0]})
        print("Price updated")
        print(
            "Unlocking at ",
            f"{Fore.GREEN}ITM{Style.RESET_ALL}"
            if self.current_price > strike
            else f"{Fore.RED}OTM{Style.RESET_ALL}",
        )

        owner = self.binary_european_options_atm.ownerOf(option_id)
        try:
            self.binary_european_options_atm.unlock(option_id)
        except:
            print("Round id is not set")

            self.binary_european_options_atm.setRoundIDForExpiry(
                self.pp.latestRoundId(), option_id
            )
            print("round id set")
            self.binary_european_options_atm.unlock(option_id)
            print("unlocked", option_id)
        print(
            "play token balance",
            _amount(
                self.tournamentManager.balanceOf(
                    owner,
                    self.tournamentId,
                )
            ),
        )

    def run_tournamnet(self):
        self.chain.sleep(
            (
                self.tournamentManager.tournaments(self.tournamentId)[1]
                - self.chain.time()
            )
            + 1000
        )
        try:  # 0 play tokens

            option_id = self.buy_option(self.users[0], True, True, 100e18)
            print("created wrong option", option_id)
        except Exception as e:
            print("error caught")

        for user in self.users:
            self.user = user
            self.buy_ticket()
            playTokenBalance = self.tournamentManager.balanceOf(user, self.tournamentId)
            option_id = self.buy_option(
                user, True, True, int(playTokenBalance * uniform(0, 1))
            )
            print("created", option_id)
            self.chain.sleep(3)
        print("Bought tickets")
        for i in range(option_id - len(self.users) + 1, option_id + 1):
            self.unlock_option(i)

        print("Scores")
        for user in self.users:
            print(self.tournamentManager.getScore(user, self.tournamentId))

        print("Ranks")
        self.rank_list()


def test_Options(contracts, accounts, chain):
    for i in range(len(accounts)):
        print("account", accounts[i])
    (
        tournamentManager,
        ibfr_contract,
        busd_contract,
        usdc_contract,
        wbnb_contract,
        binary_pool_atm,
        binary_european_options_atm,
        binary_options_config_atm,
        pp,
    ) = contracts

    users = [
        accounts[2],
        accounts[3],
        accounts[4],
        accounts[5],
        accounts[6],
        accounts[7],
        accounts[8],
    ]
    pp.update(int(23813e8), {"from": accounts[0]})

    # Adding Tradable Assets
    tournamentManager.addNewTradableAsset(
        ("ibfr", "ibfr", 18, ibfr_contract.address), {"from": accounts[0]}
    )
    tournamentManager.addNewTradableAsset(
        ("usdc", "usdc", 18, usdc_contract.address), {"from": accounts[0]}
    )

    # Adding Underlying Assets
    tournamentManager.addNewUnderlyingAsset(
        (
            binary_european_options_atm.asset(),
            binary_european_options_atm.asset(),
            18,
        ),
        {"from": accounts[0]},
    )
    tournamentManager.addNewUnderlyingAsset(
        (
            "eth",
            "eth",
            18,
        ),
        {"from": accounts[0]},
    )
    for i in range(1):
        print(tournamentManager.underlyingAssets(i))
    for i in range(2):
        print(tournamentManager.tradableAssets(i))

    ticketToken = ibfr_contract
    rewardToken = usdc_contract
    rewards = [500e18, 250e18, 100e18]

    # Creating tournament
    with brownie.reverts():  # Wrong role
        tournament = tournamentManager.createTournament(
            "Test",
            int(chain.time()),
            int(chain.time()) + ONE_DAY * 2,
            [0, 1],
            1e18,
            0,
            5000e18,
            rewards,
            1,
            {"from": accounts[4]},
        )
    # tournaments
    for _ in range(2):
        tournament = tournamentManager.createTournament(
            "Test",
            int(chain.time()),
            int(chain.time()) + ONE_DAY * 2,
            [0, 1],
            1e18,
            0,
            5000e18,
            rewards,
            1,
        )

        print(f"{Fore.YELLOW}Tournament {tournament.return_value}{Style.RESET_ALL}")
        nlt = NoLossTournaments(
            accounts,
            tournamentManager,
            ticketToken,
            rewardToken,
            tournament.return_value,
            users,
            chain,
            binary_pool_atm,
            binary_european_options_atm,
            binary_options_config_atm,
            pp,
        )
        nlt.run_tournamnet()
        chain.sleep(3600)

    for id in range(tournament.return_value + 1):
        print(f"{Fore.MAGENTA}Winners for tournament {id} {Style.RESET_ALL}")
        winners = tournamentManager.getWinners(id, 5)
        print(winners)

        print(
            f"{Fore.LIGHTCYAN_EX}Distribute rewards for tournament {id} {Style.RESET_ALL}"
        )
        closing_time = tournamentManager.tournaments(id)[2]
        print(closing_time - chain.time())
        with brownie.reverts():  # Tournament hasnt ended yet
            tournamentManager.claimReward(id, {"from": users[0]})

        chain.sleep(closing_time - chain.time())

        rewardToken.transfer(
            tournamentManager.address, sum(rewards), {"from": accounts[0]}
        )
        for user in users:
            nlt.claimReward(user, id, rewardToken)
