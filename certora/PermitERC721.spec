// PermitERC721.spec

using Auxiliar as aux
using SignerMock as signer

methods {
    getApproved(uint256) returns (address) envfree
    ownerOf(uint256) returns (address) envfree
    nonces(uint256) returns (uint96) envfree
    DOMAIN_SEPARATOR() returns (bytes32) envfree
    PERMIT_TYPEHASH() returns (bytes32) envfree
    aux.call_ecrecover(bytes32, uint8, bytes32, bytes32) returns (address) envfree
    aux.computeDigest(bytes32, bytes32, address, uint256, uint256, uint256) returns (bytes32) envfree
    aux.signatureToVRS(bytes) returns (uint8, bytes32, bytes32) envfree
    aux.isContract(address) returns (bool) envfree
    isValidSignature(bytes32, bytes) returns (bytes4) => DISPATCHER(true)
}

// Verify that allowance behaves correctly on permit
rule permit(address spender, address tokenId, uint256 deadline, bytes signature) {
    env e;

    uint8 v; bytes32 r; bytes32 s;
    v, r, s = aux.signatureToVRS(signature);

    permit(e, spender, tokenId, deadline, v, r, s);

    assert(getApproved(tokenId) == spender, "assert1 failed");
}

// Verify revert rules on permit
rule permit_revert(address spender, uint256 tokenId, uint256 deadline, bytes signature) {
    env e;

    uint8 v; bytes32 r; bytes32 s;
    v, r, s = aux.signatureToVRS(signature);

    uint256 tokenIdNonce = nonces(tokenId);
    address owner = ownerOf(tokenId);

    bytes32 digest = aux.computeDigest(
                        DOMAIN_SEPARATOR(),
                        PERMIT_TYPEHASH(),
                        spender,
                        tokenId,
                        tokenIdNonce,
                        deadline
                    );

    address ownerRecover = aux.call_ecrecover(digest, v, r, s);
    bytes32 returnedSig = signer.isValidSignature(e, digest, signature);
    bool isContract = aux.isContract(owner);

    permit@withrevert(e, spender, tokenId, deadline, v, r, s);

    bool revert1 = e.msg.value > 0;
    bool revert2 = e.block.timestamp > deadline;
    bool revert3 = owner == 0;
    bool revert4 = owner == spender;
    bool revert5 = isContract  && returnedSig  != 0x1626ba7e00000000000000000000000000000000000000000000000000000000;
    bool revert6 = !isContract && ownerRecover == 0;
    bool revert7 = !isContract && ownerRecover != owner;
    bool revert8 = tokenIdNonce == max_uint96;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");
    assert(revert4 => lastReverted, "revert4 failed");
    assert(revert5 => lastReverted, "revert5 failed");
    assert(revert6 => lastReverted, "revert6 failed");
    assert(revert7 => lastReverted, "revert7 failed");
    assert(revert8 => lastReverted, "revert8 failed");

    assert(lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5 || revert6 ||
                           revert7 || revert8, "Revert rules are not covering all the cases");
}
