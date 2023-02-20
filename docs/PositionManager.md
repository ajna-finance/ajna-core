# Position Manager

## Position Manager interactions

#### Mint position NFT
* Any LP owner or 3rd party address can mint the Position NFT by calling `PositionManager.mint` function and passing the lender and pool address.

#### Approve PositionManager contract as LPs Manager
* LP owner calls `Pool.approveLPsManager` and gives `PositionManager` contract the rights of managing LPs at a given indexes (from now on only `PositionManager` is allowed to remove itself as a manager by calling `Pool.revokeLPsManager` function). Following deposit related actions (that could affect LP balance at index) are disallowed for LP owner as long as the manager is set to `PositionManager`:
  - approve a different position manager by calling `Pool.approveLPsManager` for same index
  - `Pool.moveQuoteToken` at index
  - `Pool.removeQuoteToken` at index
  - `Pool.kickWithDeposit` at index
  - `ERC20Pool.removeCollateral` at index
  - `ERC721Pool.mergeOrRemoveCollateral` using index

#### Track positions in PositionManager contract
* LP owner calls `PositionManager.trackPositions` and provides the NFT id and indexes to track. `PositionManager` reverts if it's not manager of those indexes or if the index is already tracked (by same or another position NFT in pool and lender scope), otherwise records tracked indexes. That's different than current implementation in the way that `PositionManager` won't track the amounts anymore but rather only the indexes (it's assumed positions are frozen per point above as long as `PositionManager` is the manager of positions)

#### Move positions through PositionManager contract
* LP owner can move positions (as long as from and to indexes are managed by `PositionManager`) by calling `PositionManager.moveLiquidity` (`Pool.moveQuoteToken` function accepts owner address as parameter). If `PositionManager` is not manager at indexes then tx is reverted.

#### Untrack positions from PositionManager contract
* If owner wants to stop tracking positions `PositionManager.untrackPositions` function is called, which removes tracked indexes and revokes `PositionManager` as a LP manager (by calling `Pool.revokeLPsManager` function).

#### Transfer positions through PositionManager contract
* In order to receive an NFT with tracked positions / get LPs transfered, an receiver should first approve `PositionManager` as transferor (by calling `Pool.approveLpsTransferor` function) - this is done in order to make sure receiver deposits time are not changed by malicious actors (by transferring small amounts of LPs). When owner transfers NFT to a different owner, `_afterTokenTransfer` transfers LPs from old owner to new owner by calling `Pool.transferLPs(from_, to_, trackedIndexes)` frunction. No additional operation / allowance is required (tx reverts if manager is set and sender is not `PositionManager`). LP amounts at tracked indexes are transferred in full.
Deposit time is inherited by new owner only if there's no liquidity / no deposit time set (that's it new owner doesn't have any deposit / LPs already). Extra check is done so LPs are not transferred if the from or to address is the `RewardsManager` contract (that is when staking or unstaking position NFT for rewards).
Managers approved by owner at transferred indexes are automatically revoked by `Pool.transferLPs` function (therefore after NFT transfer the owners will have full again rights on transferred indexes).

## Interactions diagram
![Alt text](./svg/positionManager.svg)

