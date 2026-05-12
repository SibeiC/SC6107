# Routing Engine & DEX Adapters (Person B)

## Overview
This module handles all pathfinding and interactions with decentralized exchanges. It wraps different AMMs (like Uniswap V2 and V3) under a unified `IDexAdapter` interface, allowing the routing engine to smoothly pull quotes and execute swaps regardless of the underlying protocol.

## Contents
- **`IDexAdapter.sol`**: A standard interface for all DEX interactions.
- **`IRouter.sol`**: The interface defining what the router looks like to the executor.
- **Adapters**: Coming soon.
- **Router logic**: Coming soon.

## Usage
The central contract here is the Router. Other modules will call `bestRoute` to find arbitrage opportunities, and `execute` to actually perform the swaps once the flash loan is drawn.