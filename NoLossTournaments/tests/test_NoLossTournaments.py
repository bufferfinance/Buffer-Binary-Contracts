import time
from enum import IntEnum

import brownie
from pyrsistent import s


class OptionType(IntEnum):
    ALL = 0
    PUT = 1
    CALL = 2
    NONE = 3


ONE_DAY = 86400
ADDRESS_0 = "0x0000000000000000000000000000000000000000"
bytes_0 = "0x0000000000000000000000000000000000000000000000000000000000000000"


class NoLossTournaments(object):
    def __init__(
        self,
        accounts,
        tournamentManager,
        ticketToken,
        rewardToken,
        tournamentId,
        total_reward,
        users,
        users_to_send_profit,
        winners,
        chain,
    ):
        self.tournamentManager = tournamentManager
        self.ticketToken = ticketToken
        self.rewardToken = rewardToken
        self.tournamentId = tournamentId
        self.accounts = accounts
        self.user = self.accounts[7]
        self.total_reward = total_reward
        self.users = users
        self.users_to_send_profit = users_to_send_profit
        self.owner = accounts[0]
        self.pool = accounts[9]
        self.winners = winners
        self.chain = chain

    def send_profit(self, user, profit):
        self.tournamentManager.mint(
            user, self.tournamentId, profit, {"from": self.pool}
        )

    def rank_list(self):
        cursor = self.tournamentManager.tournaments(self.tournamentId)[8]
        while cursor != bytes_0:
            # print("cursor", cursor)
            rank = self.tournamentManager.tournamentUserRank(cursor)
            print(rank[3], " => ", end=" ")
            cursor = rank[0]
            # break
        print("end")

    def update_rank(self, user):
        rank_update = self.tournamentManager.updateUserRank(
            user, self.tournamentId, {"from": self.pool}
        )
        id = rank_update.events["UpdateUserRank"]["id"]

        rank = self.tournamentManager.tournamentUserRank(id)
        print(user, rank[3])

    def claim_rewards(self, user):

        self.rewardToken.transfer(
            self.tournamentManager.address,
            self.total_reward,
            {"from": brownie.accounts[0]},
        )
        userReward = self.tournamentManager.getUserReward(user, self.tournamentId)
        initialRewardTokenBalance = self.rewardToken.balanceOf(user)
        self.tournamentManager.claimReward(self.tournamentId, {"from": user})
        finalRewardTokenBalance = self.rewardToken.balanceOf(user)
        assert (
            finalRewardTokenBalance - initialRewardTokenBalance == userReward
        ), "Wrong reward"

    def get_rewards(self, user):
        print(user, self.tournamentManager.getUserReward(user, self.tournamentId))

    def verify_tournamnet(self):
        assert (
            self.tournamentManager.nextTournamentId() - self.tournamentId == 1
        ), "wrong next id"

    def buy_ticket(self):
        tournament = self.tournamentManager.tournaments(self.tournamentId)

        self.ticketToken.transfer(
            self.user, tournament[3], {"from": brownie.accounts[0]}
        )
        self.ticketToken.approve(
            self.tournamentManager.address, tournament[3], {"from": self.user}
        )

        initialTicketCount = self.tournamentManager.tournamentUserTicketCount(
            self.tournamentId, self.user
        )
        initialTicketTokenBalance = self.ticketToken.balanceOf(
            self.tournamentManager.ticketFeeReceipient()
        )
        initialPlayTokenBalance = self.tournamentManager.balanceOf(
            self.user, self.tournamentId
        )
        buy = self.tournamentManager.buyTicket(self.tournamentId, {"from": self.user})
        finalTicketTokenBalance = self.ticketToken.balanceOf(
            self.tournamentManager.ticketFeeReceipient()
        )
        finalPlayTokenBalance = self.tournamentManager.balanceOf(
            self.user, self.tournamentId
        )
        finalTicketCount = self.tournamentManager.tournamentUserTicketCount(
            self.tournamentId, self.user
        )
        assert self.tournamentManager.tournamentUsers(
            self.tournamentId, self.user
        ), "User not added"
        assert abs(
            finalPlayTokenBalance - initialPlayTokenBalance == tournament[5]
        ), "Wrong play tokens minted"
        assert abs(finalTicketCount - initialTicketCount == 1), "Wrong ticket count"
        assert (
            abs(initialTicketTokenBalance - finalTicketTokenBalance) == tournament[3]
        ), "wrong ticket cost"

    def test_sorted_index(self, user, score):
        index = self.tournamentManager.getSortedPreviousRankIndex(
            user, self.tournamentId, score
        )
        print(index, score)
        return index

    def run_tournamnet(self):
        self.chain.sleep(
            (
                self.tournamentManager.tournaments(self.tournamentId)[1]
                - self.chain.time()
            )
            + 1000
        )
        for user in self.users:
            self.user = user
            self.verify_tournamnet()
            self.buy_ticket()
        print("Bought tickets")

        if self.tournamentId == 0:
            with brownie.reverts():  # Wrong role
                self.send_profit(
                    self.users_to_send_profit[0][0], self.users_to_send_profit[0][1]
                )
            LIQUIDITY_POOL_ROLE = self.tournamentManager.LIQUIDITY_POOL_ROLE()

            self.tournamentManager.grantRole(
                LIQUIDITY_POOL_ROLE,
                self.pool,
                {"from": self.owner},
            )

        for user in self.users_to_send_profit:
            self.send_profit(user[0], user[1])
            print("finding prev index")
            prev_index = self.tournamentManager.getSortedPreviousRankIndex(
                user[0],
                self.tournamentId,
                self.tournamentManager.getScore(user[0], self.tournamentId),
            )
            print("prev_index", prev_index)
            self.update_rank(user[0])
        print("Updated Rank")

        print("Ranks")
        self.rank_list()

        print("Winners")
        winners = self.tournamentManager.getWinners(self.tournamentId, 5)
        print(winners)
        assert list(winners) == self.winners, "Wrong winners"

        with brownie.reverts():  # Hasn't ended yet
            self.claim_rewards(self.users[0])

        self.chain.sleep(
            (
                self.tournamentManager.tournaments(self.tournamentId)[2]
                - self.chain.time()
            )
            + ONE_DAY
        )
        for user in self.users:
            self.claim_rewards(user)


def test_NoLossTournaments(contracts, accounts, chain):
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
            "btc",
            "btc",
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
    total_reward = sum(rewards)
    users = [
        accounts[2],
        accounts[3],
        accounts[4],
        accounts[5],
        accounts[6],
        accounts[7],
        accounts[8],
    ]
    users_to_send_profit = [
        (accounts[2], 5000e18),
        (accounts[7], 6000e18),
        (accounts[7], 7000e18),
        (accounts[8], 8000e18),
        (accounts[2], 9000e18),
        (accounts[4], 10000e18),
        (accounts[3], 5000e18),
        (accounts[7], 12000e18),
        (accounts[4], 1000e18),
        (accounts[5], 1000e18),
    ]
    winners = [accounts[7], accounts[2], accounts[4], accounts[8], accounts[3]]

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

    nlt = NoLossTournaments(
        accounts,
        tournamentManager,
        ticketToken,
        rewardToken,
        tournament.return_value,
        total_reward,
        users,
        users_to_send_profit,
        winners,
        chain,
    )

    nlt.run_tournamnet()

    users = [
        accounts[2],
        accounts[3],
        accounts[4],
        accounts[5],
        accounts[6],
        accounts[7],
        accounts[8],
    ]
    users_to_send_profit = [
        (accounts[2], 5000e18),
        (accounts[8], 8000e18),
        (accounts[2], 9000e18),
        (accounts[4], 10000e18),
        (accounts[3], 1000e18),
        (accounts[7], 12000e18),
        (accounts[5], 5000e18),
    ]
    winners = [accounts[2], accounts[7], accounts[4], accounts[8], accounts[5]]

    # Creating tournament
    tournament = tournamentManager.createTournament(
        "Test",
        int(chain.time()),
        int(chain.time()) + ONE_DAY * 2,
        [0, 1],
        1e18,
        0,
        1000e18,
        rewards,
        1,
    )
    print(tournament.return_value, "created")

    nlt = NoLossTournaments(
        accounts,
        tournamentManager,
        ticketToken,
        rewardToken,
        tournament.return_value,
        total_reward,
        users,
        users_to_send_profit,
        winners,
        chain,
    )

    nlt.run_tournamnet()

    tournamnets = tournamentManager.bulkFetchTournaments(
        [i for i in range(tournament.return_value + 1)]
    )

    with brownie.reverts():  # Transfers not allowed
        tournamentManager.safeTransferFrom(
            accounts[4],
            accounts[2],
            tournament.return_value,
            1e18,
            "",
            {"from": accounts[4]},
        )
    nlt.send_profit(accounts[9], 2e18)
    tournamentManager.safeTransferFrom(
        accounts[9],
        accounts[2],
        tournament.return_value,
        1e18,
        "",
        {"from": accounts[9]},
    )
    tournamentManager.safeTransferFrom(
        accounts[4],
        accounts[9],
        tournament.return_value,
        1e18,
        "",
        {"from": accounts[4]},
    )
