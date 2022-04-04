// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

// Implements: https://eips.ethereum.org/EIPS/eip-4494
abstract contract Permit is ERC721 {

    /// @dev Gets the current nonce for a token ID and then increments it, returning the original value
    function _getAndIncrementNonce(uint256 tokenId) internal virtual returns (uint256);

    /// @dev The hash of the name used in the permit signature verification
    bytes32 private immutable nameHash;

    /// @dev The hash of the version string used in the permit signature verification
    bytes32 private immutable versionHash;

    /// @notice Computes the nameHash and versionHash
    constructor(
        string memory name_,
        string memory symbol_,
        string memory version_
    ) ERC721(name_, symbol_) {
        nameHash = keccak256(bytes(name_));
        versionHash = keccak256(bytes(version_));
    }

    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    // keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')
                    0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
                    nameHash,
                    versionHash,
                    getChainId(),
                    address(this)
                )
            );
    }

    // TODO: finish implementing
    function permit(
        address spender,
        uint256 tokenId,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable override {
        require(block.timestamp <= deadline, 'ajna/permit-expired');

        bytes32 digest =
            keccak256(
                abi.encodePacked(
                    '\x19\x01',
                    DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, spender, tokenId, _getAndIncrementNonce(tokenId), deadline))
                )
            );
        address owner = ownerOf(tokenId);
        require(spender != owner, 'ERC721Permit: approval to current owner');
        
        // TODO: finish implementing
        // if (Address.isContract(owner)) {
        //     require(IERC1271(owner).isValidSignature(digest, abi.encodePacked(r, s, v)) == 0x1626ba7e, 'Unauthorized');
        // } else {
        //     address recoveredAddress = ecrecover(digest, v, r, s);
        //     require(recoveredAddress != address(0), 'Invalid signature');
        //     require(recoveredAddress == owner, 'Unauthorized');
        // }

        // _approve(spender, tokenId);
    }

    /// @dev Gets the current chain ID
    /// @return chainId The current chain ID
    function getChainId() internal pure returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }

}