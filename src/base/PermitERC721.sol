// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { IERC1271 } from '@openzeppelin/contracts/interfaces/IERC1271.sol';
import { ERC721 }   from '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import { Address }  from '@openzeppelin/contracts/utils/Address.sol';

interface IPermit {
    function permit(
        address spender_, uint256 tokenId_, uint256 deadline_, uint8 v_, bytes32 r_, bytes32 s_
    ) external;
}

/**
 *  @notice https://soliditydeveloper.com/erc721-permit
 *  @notice Functionality to enable EIP-4494 permit calls as part of interactions with Position NFTs
 *  @dev    spender https://eips.ethereum.org/EIPS/eip-4494
 */
abstract contract PermitERC721 is ERC721, IPermit {

    /** @dev Gets the current nonce for a token ID and then increments it, returning the original value */
    function _getAndIncrementNonce(uint256 tokenId_) internal virtual returns (uint256);

    /** @dev The hash of the name used in the permit signature verification */
    bytes32 private immutable _nameHash;

    /** @dev The hash of the version string used in the permit signature verification */
    bytes32 private immutable _versionHash;

    /** @dev Value is equal to keccak256("Permit(address spender,uint256 tokenId,uint256 nonce,uint256 deadline)"); */
    bytes32 public constant PERMIT_TYPEHASH =
        0x49ecf333e5b8c95c40fdafc95c1ad136e8914a8fb55e9dc8bb01eaa83a2df9ad;

    /** @notice Computes the nameHash and versionHash based upon constructor input */
    constructor(
        string memory name_, string memory symbol_, string memory version_
    ) ERC721(name_, symbol_) {
        _nameHash    = keccak256(bytes(name_));
        _versionHash = keccak256(bytes(version_));
    }

    /**
     *  @notice Calculate the EIP-712 compliant DOMAIN_SEPERATOR for ledgible signature encoding
     *  @return The bytes32 domain separator of Position NFTs
     */
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    // keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')
                    0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
                    _nameHash,
                    _versionHash,
                    _chainId(),
                    address(this)
                )
            );
    }

    /**
     *  @notice Called by a NFT owner to enable a third party spender to interact with their NFT
     *  @param spender_  The address of the third party who will execute the transaction involving an owners NFT
     *  @param tokenId_  The id of the NFT being interacted with
     *  @param deadline_ The unix timestamp by which the permit must be called
     *  @param v_        Component of secp256k1 signature
     *  @param r_        Component of secp256k1 signature
     *  @param s_        Component of secp256k1 signature
     */
    function permit(
        address spender_, uint256 tokenId_, uint256 deadline_, uint8 v_, bytes32 r_, bytes32 s_
    ) external {
        require(block.timestamp <= deadline_, "ajna/nft-permit-expired");

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        spender_,
                        tokenId_,
                        _getAndIncrementNonce(tokenId_),
                        deadline_
                    )
                )
            )
        );
        address owner = ownerOf(tokenId_);
        require(spender_ != owner, "ERC721Permit: approval to current owner");

        if (Address.isContract(owner)) {
            // bytes4(keccak256("isValidSignature(bytes32,bytes)") == 0x1626ba7e
            require(
                IERC1271(owner).isValidSignature(digest, abi.encodePacked(r_, s_, v_)) == 0x1626ba7e,
                "ajna/nft-unauthorized"
            );
        } else {
            address recoveredAddress = ecrecover(digest, v_, r_, s_);
            require(recoveredAddress != address(0), "ajna/nft-invalid-signature");
            require(recoveredAddress == owner, "ajna/nft-unauthorized");
        }

        _approve(spender_, tokenId_);
    }

    /**
     *  @notice Called by an NFT owner to enable their NFT to be transferred by a spender address without making a seperate approve call
     *  @param  from_     The address of the current owner of the NFT
     *  @param  to_       The address of the new owner of the NFT
     *  @param  spender_  The address of the third party who will execute the transaction involving an owners NFT
     *  @param  tokenId_  The id of the NFT being interacted with
     *  @param  deadline_ The unix timestamp by which the permit must be called
     *  @param  v_        Component of secp256k1 signature
     *  @param  r_        Component of secp256k1 signature
     *  @param  s_        Component of secp256k1 signature
     */
    function safeTransferFromWithPermit(
        address from_, address to_, address spender_, uint256 tokenId_, uint256 deadline_, uint8 v_, bytes32 r_, bytes32 s_
    ) external {
        this.permit(spender_, tokenId_, deadline_, v_, r_, s_);
        safeTransferFrom(from_, to_, tokenId_);
    }

    /**
     *  @dev Gets the current chain ID
     *  @return chainId_ The current chain ID
     */
    function _chainId() internal view returns (uint256 chainId_) {
        assembly {
            chainId_ := chainid()
        }
    }

}
