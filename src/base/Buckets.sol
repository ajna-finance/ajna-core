// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { BitMaps } from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

import { IBuckets } from "../interfaces/IBuckets.sol";

import "../libraries/Maths.sol";

abstract contract Buckets is IBuckets {

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @notice Mapping of buckets for a given pool
     *  @dev price [WAD] -> bucket
     */
    mapping(uint256 => Buckets.Bucket) internal _buckets;
    mapping(uint256 => uint256)        internal _lpOutstanding;
    mapping(uint256 => uint256)        internal _collateral;

    BitMaps.BitMap internal _bitmap;

    uint256 public override hpb;
    uint256 public override lup;
    uint256 public override pdAccumulator;

    /**********************************/
    /*** Internal Utility Functions ***/
    /**********************************/

    /**
     *  @notice Called by a lender to add quote tokens to a bucket
     *  @param  params_   Add quote token params.
     *  @return lpTokens_ The amount of lpTokens received by the lender for the added quote tokens.
     */
    function addQuoteTokenToBucket(AddQuoteTokenParams memory params_) internal returns (uint256 lpTokens_) {
        // initialize bucket if required and get new HPB
        uint256 newHpb = !BitMaps.get(_bitmap, params_.price) ? initializeBucket(hpb, params_.price) : hpb;

        Bucket storage bucket = _buckets[params_.price];
        if (bucket.debt != 0) {
            // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
            bucket.debt += Maths.radToWadTruncate(
                bucket.debt * (Maths.rdiv(params_.inflator, bucket.inflatorSnapshot) - Maths.ONE_RAY)
            );
        }
        bucket.inflatorSnapshot = params_.inflator;

        lpTokens_ = Maths.rdiv(Maths.wadToRay(params_.amount), getExchangeRate(params_.price, bucket.onDeposit + bucket.debt));

        // bucket accounting
        _lpOutstanding[params_.price]  += lpTokens_;
        bucket.onDeposit                += params_.amount;
        pdAccumulator                   += Maths.wmul(params_.amount, params_.price);

        // debt reallocation
        bool reallocate = params_.totalDebt != 0 && params_.price > lup;
        uint256 newLup = reallocate ? reallocateUp(bucket, params_.amount, params_.inflator) : lup;

        // HPB and LUP management
        if (lup != newLup) lup = newLup;
        if (hpb != newHpb) hpb = newHpb;
    }

    /**
     *  @notice Called by a borrower to borrow from a given bucket
     *  @param  params_ Borrow params.
     */
    function borrowFromBucket(BorrowParams memory params_) internal {
        // if first loan then borrow at HPB price, otherwise at LUP
        uint256 price = lup == 0 ? hpb : lup;
        uint256 curPrice = price;

        uint256 pdRemove;
        while (true) {
            require(curPrice >= params_.limit, "B:B:PRICE_LT_LIMIT");

            Bucket storage curLup = _buckets[curPrice];
            uint256 curDebt = curLup.debt;
            if (curDebt != 0) {
                // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
                curDebt += Maths.radToWadTruncate(
                    curDebt * (Maths.rdiv(params_.inflator, curLup.inflatorSnapshot) - Maths.ONE_RAY)
                );
            }
            curLup.inflatorSnapshot = params_.inflator;

            if (params_.amount > curLup.onDeposit) {
                // take all on deposit from this bucket
                curLup.debt      = curDebt + curLup.onDeposit;
                params_.amount  -= curLup.onDeposit;
                pdRemove         += Maths.wmul(curLup.onDeposit, curPrice);
                curLup.onDeposit -= curLup.onDeposit;
            } else {
                // take all remaining amount for loan from this bucket and exit
                curLup.onDeposit -= params_.amount;
                pdRemove         += Maths.wmul(params_.amount, curPrice);
                curLup.debt      = curDebt + params_.amount + params_.fee;
                break;
            }

            curPrice = curLup.down; // move to next bucket
        }

        // HPB and LUP management
        lup = (price > curPrice || price == 0) ? curPrice : price;
        pdAccumulator -= pdRemove;
    }

    /**
     *  @notice Called by a lender to claim accumulated collateral
     *  @param  params_       Claim collateral params
     *  @return lpRedemption_ The amount of LP tokens that will be redeemed
     */
    function claimCollateralFromBucket(ClaimCollateralParams memory params_) internal returns (uint256 lpRedemption_) {
        require(params_.amount <= _collateral[params_.price], "B:CC:AMT_GT_COLLAT");

        Bucket storage bucket = _buckets[params_.price];
        lpRedemption_ = Maths.wrdivr(Maths.wmul(params_.amount, params_.price), getExchangeRate(params_.price, bucket.onDeposit + bucket.debt));

        require(lpRedemption_ <= params_.lpBalance, "B:CC:INSUF_LP_BAL");

        // bucket accounting
        _collateral[params_.price]    -= params_.amount;
        _lpOutstanding[params_.price] -= lpRedemption_;

        // bucket management
        bool isEmpty = bucket.onDeposit == 0 && bucket.debt == 0;
        bool noClaim = _lpOutstanding[params_.price] == 0 && _collateral[params_.price] == 0;
        if (isEmpty && noClaim) deactivateBucket(params_.price, bucket.up, bucket.down); // cleanup if bucket no longer used
    }

    /**
     *  @notice Liquidate a given position's collateral
     *  @param  params_             Liquidate params
     *  @return requiredCollateral_ The amount of collateral to be liquidated
     */
    function liquidateAtBucket(LiquidateParams memory params_) internal returns (uint256 requiredCollateral_) {
        uint256 curPrice = hpb;

        while (true) {
            Bucket storage bucket = _buckets[curPrice];
            uint256 curDebt = bucket.debt;
            if (curDebt != 0) {
                // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
                curDebt += Maths.radToWadTruncate(
                    curDebt * (Maths.rdiv(params_.inflator, bucket.inflatorSnapshot) - Maths.ONE_RAY)
                );
            }
            bucket.inflatorSnapshot = params_.inflator;

            uint256 bucketDebtToPurchase     = Maths.min(params_.debt, curDebt);
            uint256 debtByPrice              = Maths.wdiv(params_.debt, curPrice);
            uint256 bucketRequiredCollateral = Maths.min(
                Maths.min(debtByPrice, params_.collateral),
                debtByPrice
            );

            params_.debt        -= bucketDebtToPurchase;
            params_.collateral  -= bucketRequiredCollateral;
            requiredCollateral_ += bucketRequiredCollateral;

            // bucket accounting
            curDebt               -= bucketDebtToPurchase;
            _collateral[curPrice] += bucketRequiredCollateral;

            // forgive the debt when borrower has no remaining collateral but still has debt
            if (params_.debt != 0 && params_.collateral == 0) {
                bucket.debt = 0;
                break;
            }

            bucket.debt = curDebt;

            if (params_.debt == 0) break; // stop if all debt reconciliated

            curPrice = bucket.down;
        }

        // HPB and LUP management
        uint256 newHpb = getHpb();
        if (hpb != newHpb) hpb = newHpb;
    }

    /**
     *  @notice Called by a lender to remove quote tokens from a bucket
     *  @param  params_       Move quote token params
     *  @return lpRedemption_ The amount of lpTokens moved from bucket
     *  @return lpAward_      The amount of lpTokens moved to bucket
     */
    function moveQuoteTokenFromBucket(MoveQuoteTokenParams memory params_) internal returns (uint256 lpRedemption_, uint256 lpAward_) {
        uint256 newHpb = !BitMaps.get(_bitmap, params_.toPrice) ? initializeBucket(hpb, params_.toPrice) : hpb;
        uint256 newLup = lup;

        Bucket storage fromBucket = _buckets[params_.fromPrice];
        if (fromBucket.debt != 0) {
            // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
            fromBucket.debt += Maths.radToWadTruncate(
                fromBucket.debt * (Maths.rdiv(params_.inflator, fromBucket.inflatorSnapshot) - Maths.ONE_RAY)
            );
        }
        fromBucket.inflatorSnapshot = params_.inflator;

        uint256 exchangeRate = getExchangeRate(params_.fromPrice, fromBucket.onDeposit + fromBucket.debt);
        lpRedemption_ = Maths.rdiv(Maths.wadToRay(params_.amount), exchangeRate);

        require(lpRedemption_ <= params_.lpBalance, "B:MQT:AMT_GT_CLAIM");

        Bucket storage toBucket = _buckets[params_.toPrice];
        if (toBucket.debt != 0) {
            // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
            toBucket.debt += Maths.radToWadTruncate(
                toBucket.debt * (Maths.rdiv(params_.inflator, toBucket.inflatorSnapshot) - Maths.ONE_RAY)
            );
        }
        toBucket.inflatorSnapshot = params_.inflator;

        lpAward_ = Maths.rdiv(Maths.wadToRay(params_.amount), getExchangeRate(params_.toPrice, toBucket.onDeposit + toBucket.debt));

        // move LP tokens
        _lpOutstanding[params_.fromPrice] -= lpRedemption_;
        _lpOutstanding[params_.toPrice]   += lpAward_;

        bool moveUp = params_.fromPrice < params_.toPrice;
        bool atLup  = newLup != 0 && params_.fromPrice == newLup;

        if (atLup) {
            uint256 debtToMove    = (params_.amount > fromBucket.onDeposit) ? params_.amount - fromBucket.onDeposit : 0;
            uint256 depositToMove = params_.amount - debtToMove;

            // move debt
            if (moveUp) {
                fromBucket.debt -= debtToMove;
                toBucket.debt   += debtToMove;
            }

            // move deposit
            uint256 toOnDeposit  = moveUp ? depositToMove : params_.amount;
            fromBucket.onDeposit -= depositToMove;
            toBucket.onDeposit   += toOnDeposit;

            newLup = moveUp ? reallocateUp(toBucket, depositToMove, params_.inflator) : reallocateDown(fromBucket, debtToMove, params_.inflator);
            pdAccumulator = pdAccumulator + Maths.wmul(toOnDeposit, params_.toPrice) - Maths.wmul(depositToMove, params_.fromPrice);
        } else {
            bool aboveLup = newLup !=0 && newLup < Maths.min(params_.fromPrice, params_.toPrice);
            if (aboveLup) {
                // move debt
                fromBucket.debt -= params_.amount;
                toBucket.debt   += params_.amount;
            } else {
                // move deposit
                uint256 fromOnDeposit = moveUp ? params_.amount : Maths.min(params_.amount, fromBucket.onDeposit);
                fromBucket.onDeposit -= fromOnDeposit;
                toBucket.onDeposit   += params_.amount;

                if (newLup != 0 && params_.toPrice > Maths.max(params_.fromPrice, newLup)) newLup = reallocateUp(toBucket,  params_.amount, params_.inflator);
                else if (newLup != 0 && params_.fromPrice >= Maths.max(params_.toPrice, newLup)) newLup = reallocateDown(fromBucket, params_.amount, params_.inflator);
                pdAccumulator = pdAccumulator + Maths.wmul(params_.amount, params_.toPrice) - Maths.wmul(fromOnDeposit, params_.fromPrice);
            }
        }

        bool isEmpty = fromBucket.onDeposit == 0 && fromBucket.debt == 0;
        bool noClaim = _lpOutstanding[params_.fromPrice] == 0 && _collateral[params_.fromPrice] == 0;

        // HPB and LUP management
        if (newLup != lup) lup = newLup;
        newHpb = (isEmpty && params_.fromPrice == newHpb) ? getHpb() : newHpb;
        if (newHpb != hpb) hpb = newHpb;

        // bucket management
        if (isEmpty && noClaim) deactivateBucket(params_.fromPrice, fromBucket.up, fromBucket.down); // cleanup if bucket no longer used
    }

    /**
     *  @notice Puchase a given amount of quote tokens for given collateral tokens
     *  @param  params_ Purchase bid params
     */
    function purchaseBidFromBucket(PurchaseBidParams memory params_) internal {
        Bucket storage bucket = _buckets[params_.price];
        if (bucket.debt != 0) {
            // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
            bucket.debt += Maths.radToWadTruncate(
                bucket.debt * (Maths.rdiv(params_.inflator, bucket.inflatorSnapshot) - Maths.ONE_RAY)
            );
        }
        bucket.inflatorSnapshot = params_.inflator;

        uint256 available = bucket.onDeposit + bucket.debt;

        require(params_.amount <= available, "B:PB:INSUF_BUCKET_LIQ");

        // Exchange collateral for quote token on deposit
        uint256 purchaseFromDeposit = Maths.min(params_.amount, bucket.onDeposit);

        params_.amount      -= purchaseFromDeposit;
        // bucket accounting
        bucket.onDeposit     -= purchaseFromDeposit;
        _collateral[params_.price] += params_.collateral;

        // debt reallocation
        uint256 newLup = reallocateDown(bucket, params_.amount, params_.inflator);
        uint256 newHpb = (bucket.onDeposit == 0 && bucket.debt == 0) ? getHpb() : hpb;

        // HPB and LUP management
        if (lup != newLup) lup = newLup;
        if (hpb != newHpb) hpb = newHpb;

        pdAccumulator -= Maths.wmul(purchaseFromDeposit, params_.price);
    }

    /**
     *  @notice Called by a lender to remove quote tokens from a bucket
     *  @param  params_   Remove quote token params
     *  @return amount_   The actual amount being removed
     *  @return lpTokens_ The amount of lpTokens removed equivalent to the quote tokens removed
     */
    function removeQuoteTokenFromBucket(RemoveQuoteTokenParams memory params_) internal returns (uint256 amount_, uint256 lpTokens_) {
        Bucket storage bucket = _buckets[params_.price];
        if (bucket.debt != 0) {
            // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
            bucket.debt += Maths.radToWadTruncate(
                bucket.debt * (Maths.rdiv(params_.inflator, bucket.inflatorSnapshot) - Maths.ONE_RAY)
            );
        }
        bucket.inflatorSnapshot = params_.inflator;

        uint256 exchangeRate = getExchangeRate(params_.price, bucket.onDeposit + bucket.debt); // RAY
        uint256 claimable    = Maths.rmul(params_.lpBalance, exchangeRate);                    // RAY

        amount_   = Maths.min(Maths.wadToRay(params_.maxAmount), claimable); // RAY
        lpTokens_ = Maths.rdiv(amount_, exchangeRate);                // RAY
        amount_   = Maths.rayToWad(amount_);

        // bucket accounting
        uint256 removeFromDeposit = Maths.min(amount_, bucket.onDeposit); // Remove from deposit first
        bucket.onDeposit        -= removeFromDeposit;
        _lpOutstanding[params_.price] -= lpTokens_;

        // debt reallocation
        uint256 newLup = reallocateDown(bucket, amount_ - removeFromDeposit, params_.inflator);
        pdAccumulator  -= Maths.wmul(removeFromDeposit, params_.price);

        bool isEmpty = bucket.onDeposit == 0 && bucket.debt == 0;
        bool noClaim = _lpOutstanding[params_.price] == 0 && _collateral[params_.price] == 0;

        // HPB and LUP management
        uint256 newHpb = (isEmpty && params_.price == hpb) ? getHpb() : hpb;
        if (params_.price >= lup && newLup < lup) lup = newLup; // move lup down only if removal happened at or above lup
        if (newHpb != hpb) hpb = newHpb;

        // bucket management
        if (isEmpty && noClaim) deactivateBucket(params_.price, bucket.up, bucket.down); // cleanup if bucket no longer used
    }

    /**
     *  @notice Called by a borrower to repay quote tokens as part of reducing their position
     *  @param  params_ Repay params
     */
    function repayBucket(RepayParams memory params_) internal {

        uint256 curPrice = lup;
        uint256 pdAdd;

        while (true) {
            Bucket storage curLup = _buckets[curPrice];
            uint256 curDebt = curLup.debt;
            if (curDebt != 0) {
                // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
                curDebt += Maths.radToWadTruncate(
                    curDebt * (Maths.rdiv(params_.inflator, curLup.inflatorSnapshot) - Maths.ONE_RAY)
                );
                curLup.inflatorSnapshot = params_.inflator;

                if (params_.amount > curDebt) {
                    // pay entire debt on this bucket
                    params_.amount         -= curDebt;
                    curLup.onDeposit += curDebt;
                    pdAdd            += Maths.wmul(curDebt, curPrice);
                    curLup.debt      = 0;
                } else {
                    // pay as much debt as possible and exit
                    curLup.onDeposit += params_.amount;
                    pdAdd            += Maths.wmul(params_.amount, curPrice);
                    curLup.debt      = curDebt - params_.amount;
                    params_.amount         = 0;
                    break;
                }
            }

            if (curPrice == curLup.up) break; // nowhere to go

            curPrice = curLup.up; // move to upper bucket
        }

        // HPB and LUP management
        if (params_.reconcile) lup = 0;                         // reset LUP if no debt in pool
        else if (lup != curPrice) lup = curPrice; // update LUP to current price

        pdAccumulator += pdAdd;
    }

    /*********************************/
    /*** Private Utility Functions ***/
    /*********************************/

    /**
     *  @notice Removes state for an unused bucket and update surrounding price pointers
     *  @param  price_ The price bucket to deactivate.
     *  @param  up_    The upper price of bucket to deactivate.
     *  @param  down_  The lower price of bucket to deactivate.
     */
    function deactivateBucket(uint256 price_, uint256 up_, uint256 down_) private {
        BitMaps.setTo(_bitmap, price_, false);
        bool isHighestBucket = price_ == up_;
        bool isLowestBucket = down_ == 0;
        if (isHighestBucket && !isLowestBucket) {                     // if highest bucket
            _buckets[down_].up = _buckets[down_].price; // make lower bucket the highest bucket
        } else if (!isHighestBucket && !isLowestBucket) {             // if middle bucket
            _buckets[up_].down = down_;                 // update down pointer of upper bucket
            _buckets[down_].up = up_;                   // update up pointer of lower bucket
        } else if (!isHighestBucket && isLowestBucket) {              // if lowest bucket
            _buckets[up_].down = 0;                            // make upper bucket the lowest bucket
        }
        delete _buckets[price_];
        delete _lpOutstanding[price_];
        delete _collateral[price_];
    }

    /**
     *  @notice Set state for a new bucket and update surrounding price pointers
     *  @param  hpb_   The current highest price bucket of the pool, WAD
     *  @param  price_ The price of the bucket to retrieve information from, WAD
     *  @return The new HPB given the newly initialized bucket
     */
    function initializeBucket(uint256 hpb_, uint256 price_) private returns (uint256) {
        Bucket storage bucket = _buckets[price_];

        bucket.price            = price_;
        bucket.inflatorSnapshot = Maths.ONE_RAY;

        if (price_ > hpb_) {
            bucket.down = hpb_;
            hpb_ = price_;
        }

        uint256 cur  = hpb_;
        uint256 down = _buckets[hpb_].down;
        uint256 up   = _buckets[hpb_].up;

        // update price pointers
        while (true) {
            if (price_ > down) {
                _buckets[cur].down = price_;
                bucket.up          = cur;
                bucket.down        = down;
                _buckets[down].up  = price_;
                break;
            }
            cur  = down;
            down = _buckets[cur].down;
            up   = _buckets[cur].up;
        }
        BitMaps.setTo(_bitmap, price_, true);
        return hpb_;
    }

    /**
     *  @notice Moves assets in a bucket to a bucket's down pointers
     *  @dev    Occurs when quote tokens are being removed
     *  @dev    Should continue until all of the desired quote tokens have been removed
     *  @param  bucket_   The given bucket whose assets are being reallocated
     *  @param  amount_   The amount of quote tokens requiring reallocation, WAD
     *  @param  inflator_ The current pool inflator rate, RAY
     *  @return lup_      The price to which assets were reallocated
     */
    function reallocateDown(
        Bucket storage bucket_, uint256 amount_, uint256 inflator_
    ) private returns (uint256 lup_) {
        lup_ = bucket_.price;
        // debt reallocation
        if (amount_ > bucket_.onDeposit) {
            uint256 pdRemove;
            uint256 reallocation = amount_ - bucket_.onDeposit;
            if (bucket_.down != 0) {
                uint256 toPrice = bucket_.down;

                while (true) {
                    Bucket storage toBucket = _buckets[toPrice];
                    uint256 toDebt    = toBucket.debt;
                    uint256 toDeposit = toBucket.onDeposit;

                    if (toDebt != 0) {
                        // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
                        toDebt += Maths.radToWadTruncate(
                            toDebt * (Maths.rdiv(inflator_, toBucket.inflatorSnapshot) - Maths.ONE_RAY)
                        );
                    }
                    toBucket.inflatorSnapshot = inflator_;

                    if (reallocation < toDeposit) {
                        // reallocate all and exit
                        bucket_.debt       -= reallocation;
                        toBucket.debt      = toDebt + reallocation;
                        toBucket.onDeposit -= reallocation;
                        pdRemove           += Maths.wmul(reallocation, toPrice);
                        lup_ = toPrice;
                        break;
                    } else {
                        if (toDeposit != 0) {
                            reallocation       -= toDeposit;
                            bucket_.debt       -= toDeposit;
                            toDebt             += toDeposit;
                            pdRemove           += Maths.wmul(toDeposit, toPrice);
                            toBucket.onDeposit -= toDeposit;
                        }
                        toBucket.debt = toDebt;
                    }

                    if (toBucket.down == 0) {
                        // last bucket, nowhere to go, guard against reallocation failures
                        require(reallocation == 0, "B:RD:NO_REALLOC_LOCATION");
                        lup_ = toPrice;
                        break;
                    }

                    toPrice = toBucket.down;
                }
            } else {
                require(reallocation == 0, "B:RD:NO_REALLOC_LOCATION");
            }

            pdAccumulator -= pdRemove;
        }
    }

    /**
     *  @notice Moves assets in a bucket to a bucket's up pointers
     *  @dev    Should continue until all desired quote tokens are added
     *  @dev    Occcurs when quote tokens are being added
     *  @param  bucket_   The given bucket whose assets are being reallocated
     *  @param  amount_   The amount of quote tokens requiring reallocation, WAD
     *  @param  inflator_ The current pool inflator rate, RAY
     *  @return lup_      The price to which assets were reallocated
     */
    function reallocateUp(
        Bucket storage bucket_, uint256 amount_, uint256 inflator_
    ) private returns (uint256 lup_) {

        uint256 curPrice = lup;
        uint256 pdAdd;
        uint256 pdRemove;

        while (true) {
            if (curPrice == bucket_.price) break; // reached deposit bucket; nowhere to go

            Bucket storage curLup = _buckets[curPrice];
            uint256 curLupDebt = curLup.debt;
            if (curLupDebt != 0) {
                // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
                curLupDebt += Maths.radToWadTruncate(
                    curLupDebt * (Maths.rdiv(inflator_, curLup.inflatorSnapshot) - Maths.ONE_RAY)
                );
            }
            curLup.inflatorSnapshot = inflator_;

            if (amount_ > curLupDebt) {
                bucket_.debt      += curLupDebt;
                bucket_.onDeposit -= curLupDebt;
                pdRemove          += Maths.wmul(curLupDebt, bucket_.price);
                curLup.debt       = 0;
                curLup.onDeposit  += curLupDebt;
                pdAdd             += Maths.wmul(curLupDebt, curPrice);
                amount_           -= curLupDebt;

                if (curPrice == curLup.up) break; // reached top-of-book; nowhere to go

            } else {
                bucket_.debt      += amount_;
                bucket_.onDeposit -= amount_;
                pdRemove          += Maths.wmul(amount_, bucket_.price);
                curLup.debt       = curLupDebt - amount_;
                curLup.onDeposit  += amount_;
                pdAdd             += Maths.wmul(amount_, curPrice);
                break;
            }

            curPrice = curLup.up;
        }

        lup_ = curPrice;
        pdAccumulator = pdAccumulator + pdAdd - pdRemove;
    }

    /*****************************/
    /*** Public View Functions ***/
    /*****************************/

    function bucketAt(uint256 price_)
        public
        view
        override
        returns (
            uint256 bucketPrice_,
            uint256 up_,
            uint256 down_,
            uint256 onDeposit_,
            uint256 debt_,
            uint256 bucketInflator_,
            uint256 lpOutstanding_,
            uint256 bucketCollateral_
        )
    {
        Bucket memory bucket = _buckets[price_];

        bucketPrice_      = bucket.price;
        up_               = bucket.up;
        down_             = bucket.down;
        onDeposit_        = bucket.onDeposit;
        debt_             = bucket.debt;
        bucketInflator_   = bucket.inflatorSnapshot;
        lpOutstanding_    = _lpOutstanding[price_];
        bucketCollateral_ = _collateral[price_];
    }

    function estimatePrice(uint256 amount_, uint256 hpb_) public view override returns (uint256 price_) {
        Bucket memory curLup = _buckets[hpb_];

        while (true) {
            if (amount_ > curLup.onDeposit) {
                amount_ -= curLup.onDeposit;
            } else if (amount_ <= curLup.onDeposit) {
                price_ = curLup.price;
                break;
            }

            if (curLup.down == 0) {
                break;
            } else {
                curLup = _buckets[curLup.down];
            }
        }
    }

    function getHpb() public view override returns (uint256 newHpb_) {
        newHpb_ = hpb;
        while (true) {
            (, , uint256 down, uint256 onDeposit, uint256 debt, , , ) = bucketAt(newHpb_);
            if (onDeposit != 0 || debt != 0) {
                break;
            } else if (down == 0) {
                newHpb_ = 0;
                break;
            }
            newHpb_ = down;
        }
    }

    function getHup() public view override returns (uint256 hup_) {
        hup_ = lup;
        while (true) {
            (uint256 price, , uint256 down, uint256 onDeposit, , , , ) = bucketAt(hup_);

            if (price == down || onDeposit != 0) break;

            // check that there are available quote tokens on deposit in down bucket
            (, , , uint256 downAmount, , , , ) = bucketAt(down);

            if (downAmount == 0) break;

            hup_ = down;
        }
    }

    function isBucketInitialized(uint256 price_) public view override returns (bool) {
        return BitMaps.get(_bitmap, price_);
    }

    /*******************************/
    /*** Internal View Functions ***/
    /*******************************/

    /**
     *  @notice Calculate the current exchange rate for Quote tokens / LP Tokens
     *  @dev    Performs calculations in RAY terms and rounds up to determine size to minimize precision loss
     *  @return RAY The current rate at which quote tokens can be exchanged for LP tokens
     */
    function getExchangeRate(uint256 price_, uint256 amount_) internal view returns (uint256) {
        uint256 size = amount_ + Maths.wmul(_collateral[price_], price_);
        uint256 lpOutstanding = _lpOutstanding[price_];
        return (size != 0 && lpOutstanding != 0) ? Maths.wrdivr(size, lpOutstanding) : Maths.ONE_RAY;
    }

}
