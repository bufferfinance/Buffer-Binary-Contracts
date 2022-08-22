import os

from brownie import Multicall, accounts, network

from .utility import deploy_contract


def main():
    # Check if the contract is already deployed https://github.com/makerdao/multicall
    bfr_admin = accounts.add(os.environ["BFR_PK"])

    deploy_contract(bfr_admin, network, Multicall, [])
