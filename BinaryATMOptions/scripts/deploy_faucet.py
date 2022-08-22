import os

from brownie import USDC, Faucet, accounts, network

from .utility import deploy_contract, save_flat


def main():
    # Check if the contract is already deployed https://github.com/makerdao/multicall
    bfr_admin = accounts.add(os.environ["BFR_PK"])
    allow_revert = True
    if network.show_active() == "bsc-test":
        token = "0xF5b58390c124bc8C1Cd84E9CFCF076d076869276"
    if network.show_active() == "polygon-test":
        token = "0x5E351f387F790815e1874da4e2C669fC0Aa66C75"
    if network.show_active() == "nervos-test":
        token = "0x79ADf1146B730A034a147C3290C72f32b084d6f2"
    if network.show_active() == "meter":
        token = "0xe78Ed74064e99E7B1AFB5d2F7f96f10a94a890FC"
    if network.show_active() == "cube-test":
        token = "0x25e6af490d8Ba66F4a93e27765af965a13ad38E8"
    if network.show_active() == "startdust-testnet":
        token = "0xAb4df8Aaa1F54E84C469f4bc0e513436088C9B86"

    token_contract = USDC.at(token)
    fee_receipient = "0xFbEA9559AE33214a080c03c68EcF1D3AF0f58A7D"
    # faucet = Faucet.at("0xEDb2510a98b2CCcc9042073D9059e49924fb842f")
    faucet = deploy_contract(bfr_admin, network, Faucet, [token, fee_receipient])
    amount = faucet.amount() * 2
    token_contract.transfer(
        faucet.address,
        amount,
        {"from": bfr_admin, "allow_revert": allow_revert},
    )
    print(token_contract.balanceOf(faucet.address))

    save_flat(Faucet, "Faucet")
