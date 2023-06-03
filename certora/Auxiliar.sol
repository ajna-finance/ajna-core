pragma solidity 0.8.14;

contract Auxiliar {    
    function computeDigest(
        bytes32 domain_separator,
        bytes32 permit_typehash,
        address spender,
        uint256 tokenId,
        uint256 nonce,
        uint256 deadline
    ) public pure returns (bytes32 digest){
        digest =
        keccak256(
            abi.encodePacked(
                "\x19\x01",
                domain_separator,
                keccak256(
                    abi.encode(
                        permit_typehash,
                        spender,
                        tokenId,
                        nonce,
                        deadline
                ))
        ));
    }

    function call_ecrecover(
        bytes32 digest,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public pure returns (address signer) {
        signer = ecrecover(digest, v, r, s);
    }

    function signatureToVRS(bytes memory signature) public returns (uint8 v, bytes32 r, bytes32 s) {
        if (signature.length == 65) {
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
        }
    }

    function isContract(address owner) public returns (bool) {
        return owner.code.length > 0;
    }
}
