# token-mix

A bare-bones implementation of the Ethereum [ERC-20 standard](https://eips.ethereum.org/EIPS/eip-20), written in [Solidity](https://github.com/ethereum/solidity).

For [Vyper](https://github.com/vyperlang/vyper), check out [`vyper-token-mix`](https://github.com/brownie-mix/vyper-token-mix).

## Installation

1. [Install Brownie](https://eth-brownie.readthedocs.io/en/stable/install.html), if you haven't already.

2. Download the mix.

    ```bash
    brownie bake token
    ```

## Basic Use

This mix provides a [simple template](contracts/Token.sol) upon which you can build your own token, as well as unit tests providing 100% coverage for core ERC20 functionality.

To interact with a deployed contract in a local environment, start by opening the console:

```bash
brownie console
```

Next, deploy a test token:

```python
>>> token = Token.deploy("Test Token", "TST", 18, 1e21, {'from': accounts[0]})

Transaction sent: 0x4a61edfaaa8ba55573603abd35403cf41291eca443c983f85de06e0b119da377
  Gas price: 0.0 gwei   Gas limit: 12000000
  Token.constructor confirmed - Block: 1   Gas used: 521513 (4.35%)
  Token deployed at: 0xd495633B90a237de510B4375c442C0469D3C161C
```

You now have a token contract deployed, with a balance of `1e21` assigned to `accounts[0]`:

```python
>>> token
<Token Contract '0xd495633B90a237de510B4375c442C0469D3C161C'>

>>> token.balanceOf(accounts[0])
1000000000000000000000

>>> token.transfer(accounts[1], 1e18, {'from': accounts[0]})
Transaction sent: 0xb94b219148501a269020158320d543946a4e7b9fac294b17164252a13dce9534
  Gas price: 0.0 gwei   Gas limit: 12000000
  Token.transfer confirmed - Block: 2   Gas used: 51668 (0.43%)

<Transaction '0xb94b219148501a269020158320d543946a4e7b9fac294b17164252a13dce9534'>
```

## Testing

To run the tests:

```bash
brownie test
```

The unit tests included in this mix are very generic and should work with any ERC20 compliant smart contract. To use them in your own project, all you must do is modify the deployment logic in the [`tests/conftest.py::token`](tests/conftest.py) fixture.

## Adding Networks

```

brownie networks add Binance binance-test2 host=https://data-seed-prebsc-1-s1.binance.org:8545/ chainid=97 explorer=https:/testnet.bscscan.com/
brownie networks add Polygon mumbai-test host=https://rpc-mumbai.maticvigil.com/ chainid=80001 explorer=https://mumbai.polygonscan.com/
brownie networks add Avalanche fuji-test host=https://api.avax-test.network/ext/bc/C/rpc chainid=43113 explorer=https://testnet.snowtrace.io/
brownie networks add Aurora aurora-test host=https://testnet.aurora.dev/ chainid=1313161555 explorer=https://explorer.testnet.aurora.dev/
brownie networks add Aurora aurora-main host=https://mainnet.aurora.dev/13gvrutJ1W53h8tAmcjtY7xjDLGzSwZ5FnLKHYF9aone chainid=1313161554 explorer=https://explorer.mainnet.aurora.dev/
brownie networks add Arbitrum arbitrum-test host=https://rinkeby.arbitrum.io/rpc chainid=421611 explorer=https://rinkeby-explorer.arbitrum.io/#/
brownie networks add Fantom fantom-test host=https://rpc.testnet.fantom.network/ chainid=4002 explorer=https://testnet.ftmscan.com/
brownie networks add Optimistic optimism-kovan host=https://kovan.optimism.io chainid=69 explorer=https://kovan-optimistic.etherscan.io
brownie networks add Avalanche avalanche-mainnet host=https://api.avax.network/ext/bc/C/rpc chainid=43114 explorer=https://snowtrace.io/
brownie networks add ETH ropsten-eth host=https://ropsten.infura.io/v3/409a281621734f66a517ec8a9ee0d12f chainid=3 explorer=https://ropsten.etherscan.io/
brownie networks add CUBE cube-test host=https://http-testnet.cube.network chainid=1819 explorer=https://testnet.cubescan.network/en-us/
brownie networks add METIS startdust-testnet host=https://stardust.metis.io/ chainid=588 explorer=https://stardust-explorer.metis.io/
```

## Resources

To get started with Brownie:

-   Check out the other [Brownie mixes](https://github.com/brownie-mix/) that can be used as a starting point for your own contracts. They also provide example code to help you get started.
-   ["Getting Started with Brownie"](https://medium.com/@iamdefinitelyahuman/getting-started-with-brownie-part-1-9b2181f4cb99) is a good tutorial to help you familiarize yourself with Brownie.
-   For more in-depth information, read the [Brownie documentation](https://eth-brownie.readthedocs.io/en/stable/).

Any questions? Join our [Gitter](https://gitter.im/eth-brownie/community) channel to chat and share with others in the community.

## License

This project is licensed under the [MIT license](LICENSE).
