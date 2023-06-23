// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import { ERC721 }           from '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import { ECDSA }            from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import { SignatureChecker } from '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';

/**
 *  @dev Interface for token permits for ERC-721
 */
interface IPermit {

    /**************/
    /*** Errors ***/
    /**************/

    /**
     * @notice User queried the nonces of a token that doesn't exist.
     */
    error NonExistentToken();

    /**
     * @notice Creator of permit signature is not authorized.
     */
    error NotAuthorized();

    /**
     * @notice User submitted a signature to permit for verification after it's deadline had passed.
     */
    error PermitExpired();

    /**************************/
    /*** External Functions ***/
    /**************************/

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /**
    *  @notice Allows to retrieve current nonce for token.
    *  @param  tokenId token id
    *  @return current token nonce
    */
    function nonces(uint256 tokenId) external view returns (uint256);

    /**
    *  @notice `EIP-4494` permit to approve by way of owner signature.
    */
    function permit(
        address spender_, uint256 tokenId_, uint256 deadline_, bytes memory signature_
    ) external;
}

/**
 *  @notice Functionality to enable `EIP-4494` permit calls as part of interactions with Position `NFT`s
 *  @dev    EIP-4494: https://eips.ethereum.org/EIPS/eip-4494
 *  @dev    References this implementation: https://github.com/dievardump/erc721-with-permits/blob/main/contracts/ERC721WithPermit.sol
 */
abstract contract PermitERC721 is ERC721, IPermit {

    /***************/
    /*** Mapping ***/
    /***************/

    /**
    * @dev Mapping of nonces per tokenId
    * @dev Nonces are used to make sure the signature can't be replayed
    * @dev tokenId => nonce
    */
    mapping(uint256 => uint256) internal _nonces;

    /*****************/
    /*** Constants ***/
    /*****************/

    /** @dev Value is equal to keccak256("Permit(address spender,uint256 tokenId,uint256 nonce,uint256 deadline)"); */
    bytes32 public constant PERMIT_TYPEHASH =
        0x49ecf333e5b8c95c40fdafc95c1ad136e8914a8fb55e9dc8bb01eaa83a2df9ad;

    /******************/
    /*** Immutables ***/
    /******************/

    // this are saved as immutable for cheap access
    // the chainId is also saved to be able to recompute domainSeparator
    // in the case of a fork
    bytes32 private immutable _domainSeparator;
    uint256 private immutable _domainChainId;

    /** @dev The hash of the name used in the permit signature verification */
    bytes32 private immutable _nameHash;

    /** @dev The hash of the version string used in the permit signature verification */
    bytes32 private immutable _versionHash;

    /*******************/
    /*** Constructor ***/
    /*******************/

    /** @notice Computes the `nameHash` and `versionHash` based upon constructor input */
    constructor(
        string memory name_, string memory symbol_, string memory version_
    ) ERC721(name_, symbol_) {
        _nameHash    = keccak256(bytes(name_));
        _versionHash = keccak256(bytes(version_));

        // save gas by storing the chainId and DomainSeparator in the state on deployment
        _domainChainId   = block.chainid;
        _domainSeparator = _calculateDomainSeparator(_domainChainId);
    }

    /************************/
    /*** Public Functions ***/
    /************************/

    /**
     *  @notice Calculate the `EIP-712` compliant `DOMAIN_SEPERATOR` for ledgible signature encoding.
     *  @dev    The chainID is not set as a constant, to ensure that the chainId will change in the event of a chain fork.
     *  @return The `bytes32` domain separator of Position `NFT`s.
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _getDomainSeparator();
    }

    /**
     *  @notice Retrieves the current nonce for a given `NFT`.
     *  @param tokenId_ The id of the `NFT` being queried.
     *  @return The current nonce for the `NFT`.
     */
    function nonces(uint256 tokenId_) external view returns (uint256) {
        if (!_exists(tokenId_)) revert NonExistentToken();
        return _nonces[tokenId_];
    }

    /**
     *  @notice Called by a `NFT` owner to enable a third party spender to interact with their `NFT`.
     *  @param spender_   The address of the third party who will execute the transaction involving an owners `NFT`.
     *  @param tokenId_   The id of the `NFT` being interacted with.
     *  @param deadline_  The unix timestamp by which the permit must be called.
     *  @param signature_ The owner's permit signature to verify.
     */
    function permit(
        address spender_,
        uint256 tokenId_,
        uint256 deadline_,
        bytes memory signature_
    ) external {
        // check that the permit's deadline hasn't passed
        if (block.timestamp > deadline_) revert PermitExpired();

        // calculate signature digest
        bytes32 digest = _buildDigest(
            // owner,
            spender_,
            tokenId_,
            _nonces[tokenId_],
            deadline_
        );

        // check the address recovered from the signature matches the spender
        (address recoveredAddress, ) = ECDSA.tryRecover(digest, signature_);
        if (!_checkSignature(digest, signature_, recoveredAddress, tokenId_)) revert NotAuthorized();

        // approve the spender for accessing the tokenId
        _approve(spender_, tokenId_);
    }

    /**
     *  @notice Query if a contract implements an interface.
     *  @param  interfaceId The interface identifier.
     *  @return `true` if the contract implements `interfaceId` and `interfaceId` is not 0xffffffff, `false` otherwise
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == type(IPermit).interfaceId || // 0x5604e225
            super.supportsInterface(interfaceId);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Builds the permit digest to sign.
     *  @param spender_  The token spender.
     *  @param tokenId_  The tokenId.
     *  @param nonce_    The nonce to make a permit for.
     *  @param deadline_ The deadline before when the permit can be used.
     *  @return The digest (following `EIP-712`) to sign.
     */
    function _buildDigest(
        address spender_,
        uint256 tokenId_,
        uint256 nonce_,
        uint256 deadline_
    ) internal view returns (bytes32) {
        return
            ECDSA.toTypedDataHash(
                _getDomainSeparator(),
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        spender_,
                        tokenId_,
                        nonce_,
                        deadline_
                    )
                )
            );
    }

    /**
     *  @notice Calculate the `EIP-712` compliant `DOMAIN_SEPERATOR` for ledgible signature encoding.
     *  @dev    The chainID is not set as a constant, to ensure that the chainId will change in the event of a chain fork.
     *  @return The `bytes32` domain separator of Position `NFT`s.
     */
    function _getDomainSeparator() internal view returns (bytes32) {
        return (block.chainid == _domainChainId) ? _domainSeparator : _calculateDomainSeparator(block.chainid);
    }

    /**
     *  @notice Calculates the `EIP-712` compliant `DOMAIN_SEPERATOR` for ledgible signature encoding.
     *  @param chainId_ The chainId of the network the `NFT` is being interacted with on.
     *  @return The `bytes32` domain separator of Position `NFT`s.
     */
    function _calculateDomainSeparator(uint256 chainId_) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    // keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')
                    0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
                    _nameHash,
                    _versionHash,
                    chainId_,
                    address(this)
                )
            );
    }

    /**
     * @notice Checks if the recovered address from the signature matches the spender.
     * @param digest_           The digest signed by the owner.
     * @param signature_        The owner's signature to check.
     * @param recoveredAddress_ The address recovered from the signature.
     * @param tokenId_          The id of the `NFT` being interacted with.
     * @return isValidPermit_   `true` if the recovered address matches the spender, otherwise `false`.
     */
    function _checkSignature(
        bytes32 digest_,
        bytes memory signature_,
        address recoveredAddress_,
        uint256 tokenId_
    ) internal view returns (bool isValidPermit_) {
        // verify if the recovered address is owner or approved on tokenId
        // and make sure recoveredAddress is not address(0), else getApproved(tokenId) might match
        bool isOwnerOrApproved =
            (recoveredAddress_ != address(0) && _isApprovedOrOwner(recoveredAddress_, tokenId_));

        // else try to recover the signature using SignatureChecker
        // this also allows the verifier to recover signatures made via contracts
        bool isValidSignature =
            SignatureChecker.isValidSignatureNow(
                ownerOf(tokenId_),
                digest_,
                signature_
            );

        isValidPermit_ = (isOwnerOrApproved || isValidSignature);
    }

    /**
     * @notice Increments the nonce for a given `NFT`.
     * @param tokenId The id of the `NFT` to increment the nonce for.
     */
    function _incrementNonce(uint256 tokenId) internal {
        _nonces[tokenId]++;
    }

    /**
     * @notice _transfer override to be able to increment the permit nonce
     * @inheritdoc ERC721
     */
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        // increment the permit nonce of this tokenId to ensure it can't be reused
        _incrementNonce(tokenId);

        // transfer the NFT to the to address
        super._transfer(from, to, tokenId);
    }

}
