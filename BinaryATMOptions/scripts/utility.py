def save_flat(container, name):
    if "BufferBNBPool" in container._build["dependencies"]:
        container._build["dependencies"].extend(
            ["IBNBLiquidityPool", "@openzeppelin/ERC20", "@openzeppelin/IERC20Metadata"]
        )
    code = container.get_verification_info()["flattened_source"]
    filename = f"flat_files/{name}Flat.sol"
    with open(filename, "w") as outfile:
        outfile.write(code)


def deploy_contract(_from, network, contract, args):
    publish_source = False
    deployed_contract = None
    # network.gas_price(10000000000)
    publish_networks = ["bsc-main", "bsc-test"]
    if network.show_active() not in publish_networks:
        deployed_contract = _from.deploy(
            contract,
            *args,
            allow_revert=True,
            publish_source=publish_source,
            gas_limit=10000000,
            gas_price=40e9
            # required_confs=2,
        )
    else:
        deployed_contract = contract.deploy(
            *args,
            {"from": _from},
            publish_source=publish_source,
        )
    return deployed_contract
