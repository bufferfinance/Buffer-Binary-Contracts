import os

from brownie import OptionMeta, accounts, network

from .utility import deploy_contract, save_flat


def main():
    bfr_admin = accounts.add(os.environ["BFR_PK"])
    print(bfr_admin)
    option_meta = deploy_contract(bfr_admin, network, OptionMeta, [])
    # option_meta = OptionMeta.at("0x8b1dD3Eeeb14c197dC072d690009D14fDD13270f")
    print(
        option_meta.get_price_at_timestamp_type2(
            "0xe1d8d762954f82DE5180d261d0D46E6e4B51c796", 1660892917
        )
    )
    save_flat(OptionMeta, "OptionMeta")
