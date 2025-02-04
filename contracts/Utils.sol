pragma solidity 0.8.25;

/**************************************

    Library for custom string formatting

 **************************************/

library Formatter {
    // -----------------------------------------------------------------------
    //                              Constants
    // -----------------------------------------------------------------------

    bytes16 private constant _ALPHABET = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 20;

    // -----------------------------------------------------------------------
    //                              Functions
    // -----------------------------------------------------------------------

    /// @dev Convert bytes to human readable string
    /// @param _data Input bytes
    /// @return String representation of input
    function formatBytes(
        bytes memory _data
    ) public pure returns (string memory) {
        // declare string buffer
        bytes memory buffer_ = new bytes(2 + _data.length * 2);

        // initialize 0x
        buffer_[0] = "0";
        buffer_[1] = "x";

        // convert input to its human readable representation
        for (uint i = 0; i < _data.length; i++) {
            buffer_[2 + i * 2] = _ALPHABET[uint(uint8(_data[i] >> 4))];
            buffer_[3 + i * 2] = _ALPHABET[uint(uint8(_data[i] & 0x0f))];
        }

        // return string
        return string(buffer_);
    }

    /// @dev Convert address to human readable string
    /// @param _addr Input address
    /// @return Lowercase string representation
    function formatAddress(address _addr) private pure returns (string memory) {
        // store input address as integer
        uint256 value_ = uint256(uint160(_addr));

        // declare string buffer
        bytes memory buffer_ = new bytes(2 * _ADDRESS_LENGTH);

        // convert input address to its human readable representation
        for (int256 i = 2 * int256(uint256(_ADDRESS_LENGTH)) - 1; i > -1; --i) {
            buffer_[uint256(i)] = _ALPHABET[value_ & 0xf];
            value_ >>= 4;
        }

        // return stringx
        return string(buffer_);
    }

    /// @dev Convert address to human readable string (in checksum format)
    /// @param _src Input address
    /// @return Checksum string representation
    function formatChecksum(
        address _src
    ) internal pure returns (string memory) {
        // get address as bytes
        bytes32 srcBytes_ = bytes32(bytes20(_src));

        // compute hash from address value
        bytes32 hash_ = keccak256(abi.encodePacked(formatAddress(_src)));

        // declare string buffer
        string memory buffer_ = new string(40);

        // convert input address to its human readable representation
        assembly {
            let resPtr := add(buffer_, 32)
            let shiftRightAmount := 256
            for {
                let hexIndex := 0
            } lt(hexIndex, 40) {
                hexIndex := add(hexIndex, 1)
            } {
                shiftRightAmount := sub(shiftRightAmount, 4)
                let selectedAddressHex := and(
                    shr(shiftRightAmount, srcBytes_),
                    0xf
                )
                switch gt(selectedAddressHex, 9)
                case 1 {
                    let selectedHashHex := and(
                        shr(shiftRightAmount, hash_),
                        0xf
                    )
                    switch gt(selectedHashHex, 7)
                    case 1 {
                        mstore8(
                            add(resPtr, hexIndex),
                            add(selectedAddressHex, 55)
                        )
                    }
                    case 0 {
                        mstore8(
                            add(resPtr, hexIndex),
                            add(selectedAddressHex, 87)
                        )
                    }
                }
                case 0 {
                    mstore8(add(resPtr, hexIndex), add(selectedAddressHex, 48))
                }
            }
        }

        // return string
        return buffer_;
    }
}
