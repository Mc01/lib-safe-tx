# Lib Safe Tx
Library that allows to initiate Foundry scripts directly from Gnosis Safe multisig without moving the ownership

## Installation
```sh
npm i git+https://github.com/Mc01/lib-safe-tx.git
```

## Usage
```solidity
// transactions
bytes memory txs_; // Batch of all transactions
bytes memory tx_; // Latest transaction

// addresses
address safe_; // Gnosis Safe address
address erc20_; // Predicted address of ERC20

// salt
bytes32 salt_ = keccak256("seed");

// deploy contract
(tx_, erc20_) = SafeTx.createTx(
    type(ERC20).creationCode,
    abi.encode(name_, symbol_), // args
    salt_,
    safe_
);
txs_ = abi.encodePacked(txs_, tx_);
console.log("Predicted ERC20 address: ", erc20_);

// transfer function
tx_ = SafeTx.callTx(
    erc20_,
    0, // value
    abi.encodeWithSelector(
        IERC20.transfer.selector,
        recipient_,
        amount_
    )
);
txs_ = abi.encodePacked(txs_, tx_);

// send tx batch
console.log("Attempting to create ERC20 at predicted address and call transfer function within single block.");
(uint256 status_, bytes memory response_, ) = SafeTx.sendTxs(
    txs_,
    ISafe(safe_).nonce(),
    cosigner_, // valid cosigner for Safe
    safe_,
    vm // Foundry VM
);
console.log("Status: ", status_);
console.logString(string(response_));
```
