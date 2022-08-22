import os

from brownie import CustomPriceProvider, Faucet, accounts, network

from .utility import deploy_contract, save_flat


def main():
    # Check if the contract is already deployed https://github.com/makerdao/multicall
    if network.show_active() == "development":
        bfr_admin = accounts[0]
    else:
        bfr_admin = accounts.add(os.environ["BFR_PK"])
    print(bfr_admin, bfr_admin.balance() / 1e18)

    allow_revert = True
    assets = [
        "BTC-USD",
        "ETH-USD",
        "SOL-USD",
        "MATIC-USD",
        "BNB-USD",
    ]
    for asset in assets:
        pp = deploy_contract(bfr_admin, network, CustomPriceProvider, [])
        pp.setSymbol(asset, {"from": bfr_admin})

    save_flat(CustomPriceProvider, "CustomPriceProvider")


# 0xb6a3b49FA445Dd800c3D43d51Bf01615DD6912dd
# 0x11FE955f98790c15AB82c4c6164A79AeC136afE2
# 0xFcC14e7A728845E13a48461558630e89EA5030E3
# 0x8b34873a9a9b126adf8D8026c3EBacc48e9dE29C
# 0xd268833067d3C334e0888256b565648C81b045Fa
