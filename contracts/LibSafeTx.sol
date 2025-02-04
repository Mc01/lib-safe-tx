pragma solidity ^0.8.0;

// Foundry imports
import { Vm } from "forge-std/Test.sol";

// Safe imports
import { CreateCall } from "safe/contracts/libraries/CreateCall.sol";
import { MultiSend } from "safe/contracts/libraries/MultiSend.sol";
import { Enum } from "safe/contracts/libraries/Enum.sol";
import { ISafe } from "safe/contracts/interfaces/ISafe.sol";

// Surl imports
import { Surl } from "surl/src/Surl.sol";

// Strings imports
import { strings } from "stringutils/strings.sol";

// OpenZeppelin imports
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

// Local imports
import { Formatter } from "./Utils.sol";

/**************************************

    Library for building tx with Safe

**************************************/

library LibSafeTx {
    // libs
    using strings for *;

    // -----------------------------------------------------------------------
    //                              Structs
    // -----------------------------------------------------------------------

    struct TxParams {
        address to;
        uint256 value;
        bytes data;
        uint8 operation;
        uint256 safeTxGas;
        uint256 baseGas;
        uint256 gasPrice;
        address gasToken;
        address refundReceiver;
    }

    // -----------------------------------------------------------------------
    //                              Constants
    // -----------------------------------------------------------------------

    uint8 internal constant OP_CALL = 0;
    uint8 internal constant OP_DELEGATE_CALL = 1;
    address internal constant LIB_CREATE_CALL =
        address(0x7cbB62EaA69F79e6873cD1ecB2392971036cFAa4);
    address internal constant LIB_MULTI_SEND =
        address(0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761);

    // -----------------------------------------------------------------------
    //                              Errors
    // -----------------------------------------------------------------------

    error AddressAlreadyTaken(address);
    error UnsupportedNetwork(uint256);

    // -----------------------------------------------------------------------
    //                              Functions
    // -----------------------------------------------------------------------

    /// @dev Build and return create2 tx with address of new contract.
    /// @param _contractBytecode Creation code of smart contract
    /// @param _args Output of abi.encode() of all arguments for constructor
    /// @param _salt Number used for addresses generation
    /// @param _safe Address of Gnosis Safe multisig
    /// @return Tx payload with predicted address of contract
    function createTx(
        bytes memory _contractBytecode,
        bytes memory _args,
        bytes32 _salt,
        address _safe
    ) internal view returns (bytes memory, address) {
        // build bytecode
        bytes memory computedBytecode_ = abi.encodePacked(
            _contractBytecode,
            _args
        );

        // build payload
        bytes memory payload_ = abi.encodeWithSelector(
            CreateCall.performCreate2.selector,
            0, // value
            computedBytecode_,
            _salt
        );

        // predict address
        address predictedAddress_ = Create2.computeAddress(
            _salt,
            keccak256(computedBytecode_),
            _safe
        );
        if (predictedAddress_.code.length > 0) {
            revert AddressAlreadyTaken(predictedAddress_);
        }

        // build tx
        bytes memory tx_ = abi.encodePacked(
            OP_DELEGATE_CALL,
            LIB_CREATE_CALL,
            uint256(0), // value
            payload_.length,
            payload_
        );

        // return
        return (tx_, predictedAddress_);
    }

    /// @dev Build and return call tx.
    /// @param _recipient Address to be called
    /// @param _value Amount of ETH passed to call
    /// @param _payload Encoded selector with arguments for function call
    /// @return Tx payload
    function callTx(
        address _recipient,
        uint256 _value,
        bytes memory _payload
    ) internal pure returns (bytes memory) {
        // build and return tx
        return
            abi.encodePacked(
                OP_CALL,
                _recipient,
                _value,
                _payload.length,
                _payload
            );
    }

    /// @dev Multi send bulk transactions as one.
    /// @param _txs Concatenated bulk transactions
    /// @param _nonce Nonce for multisig
    /// @param _cosigner One of cosigners from multisig
    /// @param _safe Address of multisig
    /// @param _vm Virtual machine
    /// @return status_ Status of response
    /// @return response_ Content of response
    /// @return request_ Content of request
    function sendTxs(
        bytes memory _txs,
        uint256 _nonce,
        uint256 _cosigner,
        address _safe,
        Vm _vm
    )
        internal
        returns (
            uint256 status_,
            bytes memory response_,
            string memory request_
        )
    {
        return sendTxs(_txs, 0, _nonce, _cosigner, _safe, _vm);
    }

    /// @dev Multi send bulk transactions as one.
    /// @param _txs Concatenated bulk transactions
    /// _value Amount of ETH passed to txs
    /// @param _nonce Nonce for multisig
    /// @param _cosigner One of cosigners from multisig
    /// @param _safe Address of multisig
    /// @param _vm Virtual machine
    /// @return status_ Status of response
    /// @return response_ Content of response
    /// @return request_ Content of request
    function sendTxs(
        bytes memory _txs,
        uint256 _value,
        uint256 _nonce,
        uint256 _cosigner,
        address _safe,
        Vm _vm
    )
        internal
        returns (
            uint256 status_,
            bytes memory response_,
            string memory request_
        )
    {
        // multi send
        TxParams memory tx_ = TxParams(
            LIB_MULTI_SEND,
            _value, // value
            abi.encodeWithSelector(MultiSend.multiSend.selector, _txs),
            OP_DELEGATE_CALL,
            0, // safe tx gas
            0, // base gas
            0, // gas price
            address(0), // gas token
            msg.sender
        );

        // compute tx hash
        bytes32 txHash_ = ISafe(_safe).getTransactionHash(
            tx_.to,
            tx_.value,
            tx_.data,
            Enum.Operation(tx_.operation),
            tx_.safeTxGas,
            tx_.baseGas,
            tx_.gasPrice,
            tx_.gasToken,
            tx_.refundReceiver,
            _nonce
        );

        // sign tx hash
        (uint8 v_, bytes32 r_, bytes32 s_) = _vm.sign(
            _cosigner, // signer id
            txHash_ // message hash
        );

        // convert vrs to unified signature
        bytes memory signature_ = bytes.concat(r_, s_, bytes1(v_));

        // compute checksums
        string memory safeChecksum_ = strings.toSlice("0x").concat(
            strings.toSlice(Formatter.formatChecksum(_safe))
        );
        string memory senderChecksum_ = strings.toSlice("0x").concat(
            strings.toSlice(Formatter.formatChecksum(msg.sender))
        );
        string memory receiverChecksum_ = strings.toSlice("0x").concat(
            strings.toSlice(Formatter.formatChecksum(tx_.to))
        );
        string memory zeroChecksum_ = strings.toSlice("0x").concat(
            strings.toSlice(Formatter.formatChecksum(address(0)))
        );

        // build safe proposal url
        string memory url_;
        if (block.chainid == 11155111) {
            // sepolia
            url_ = "https://safe-transaction-sepolia.safe.global/api/v1/safes/";
        } else if (block.chainid == 84532) {
            // base sepolia
            url_ = "https://safe-transaction-base-sepolia.safe.global/api/v1/safes/";
        } else if (block.chainid == 1) {
            // mainnet
            url_ = "https://safe-transaction-mainnet.safe.global/api/v1/safes/";
        } else if (block.chainid == 56) {
            // bnb
            url_ = "https://safe-transaction-bsc.safe.global/api/v1/safes/";
        } else if (block.chainid == 137) {
            // polygon
            url_ = "https://safe-transaction-polygon.safe.global/api/v1/safes/";
        } else if (block.chainid == 43114) {
            // avalanche
            url_ = "https://safe-transaction-avalanche.safe.global/api/v1/safes/";
        } else if (block.chainid == 8453) {
            // base
            url_ = "https://safe-transaction-base.safe.global/api/v1/safes/";
        } else if (block.chainid == 42161) {
            // arbitrum
            url_ = "https://safe-transaction-arbitrum.safe.global/api/v1/safes/";
        } else {
            revert UnsupportedNetwork(block.chainid);
        }
        url_ = url_.toSlice().concat(strings.toSlice(safeChecksum_));
        url_ = url_.toSlice().concat(
            strings.toSlice("/multisig-transactions/")
        );

        // build headers
        string[] memory headers_ = new string[](2);
        headers_[0] = "Accept: application/json";
        headers_[1] = "Content-Type: application/json";

        // build request
        request_ = '{"safe": "';
        request_ = request_.toSlice().concat(strings.toSlice(safeChecksum_));
        request_ = request_.toSlice().concat(strings.toSlice('", "to": "'));
        request_ = request_.toSlice().concat(
            strings.toSlice(receiverChecksum_)
        );
        request_ = request_.toSlice().concat(strings.toSlice('", "value": "'));
        request_ = request_.toSlice().concat(
            strings.toSlice(Strings.toString(tx_.value))
        );
        request_ = request_.toSlice().concat(strings.toSlice('", "data": "'));
        request_ = request_.toSlice().concat(
            strings.toSlice(Formatter.formatBytes(tx_.data))
        );
        request_ = request_.toSlice().concat(
            strings.toSlice('", "operation": "')
        );
        request_ = request_.toSlice().concat(
            strings.toSlice(Strings.toString(tx_.operation))
        );
        request_ = request_.toSlice().concat(
            strings.toSlice('", "gasToken": "')
        );
        request_ = request_.toSlice().concat(strings.toSlice(zeroChecksum_));
        request_ = request_.toSlice().concat(
            strings.toSlice('", "safeTxGas": "')
        );
        request_ = request_.toSlice().concat(
            strings.toSlice(Strings.toString(0))
        );
        request_ = request_.toSlice().concat(
            strings.toSlice('", "baseGas": "')
        );
        request_ = request_.toSlice().concat(
            strings.toSlice(Strings.toString(0))
        );
        request_ = request_.toSlice().concat(
            strings.toSlice('", "gasPrice": "')
        );
        request_ = request_.toSlice().concat(
            strings.toSlice(Strings.toString(0))
        );
        request_ = request_.toSlice().concat(
            strings.toSlice('", "refundReceiver": "')
        );
        request_ = request_.toSlice().concat(strings.toSlice(senderChecksum_));
        request_ = request_.toSlice().concat(strings.toSlice('", "nonce": "'));
        request_ = request_.toSlice().concat(
            strings.toSlice(Strings.toString(_nonce))
        );
        request_ = request_.toSlice().concat(
            strings.toSlice('", "contractTransactionHash": "')
        );
        request_ = request_.toSlice().concat(
            strings.toSlice(Formatter.formatBytes(abi.encodePacked(txHash_)))
        );
        request_ = request_.toSlice().concat(strings.toSlice('", "sender": "'));
        request_ = request_.toSlice().concat(strings.toSlice(senderChecksum_));
        request_ = request_.toSlice().concat(
            strings.toSlice('", "signature": "')
        );
        request_ = request_.toSlice().concat(
            strings.toSlice(Formatter.formatBytes(signature_))
        );
        request_ = request_.toSlice().concat(strings.toSlice('", "origin": "'));
        request_ = request_.toSlice().concat(strings.toSlice(senderChecksum_));
        request_ = request_.toSlice().concat(strings.toSlice('"}'));

        // perform post
        (status_, response_) = Surl.post(url_, headers_, request_);

        // return
        return (status_, response_, request_);
    }
}
