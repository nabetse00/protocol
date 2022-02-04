// SPDX-License-Identifier: BlueOak-1.0.0
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "contracts/libraries/Fixed.sol";
import "contracts/p0/interfaces/IAsset.sol";
import "contracts/p0/interfaces/IFurnace.sol";
import "contracts/p0/interfaces/IRToken.sol";

/**
 * @title FurnaceP0
 * @notice A helper to melt RTokens slowly and permisionlessly.
 */
contract FurnaceP0 is Ownable, IFurnace {
    using SafeERC20 for IRToken;
    using FixLib for Fix;

    IRToken public immutable rToken;
    uint256 public override batchDuration;

    struct Batch {
        uint256 amount; // {qTok}
        uint256 start; // {timestamp}
        uint256 melted; // {qTok}
    }

    Batch[] public batches;

    /// @param batchDuration_ {sec} The number of seconds to spread the melt over
    constructor(IRToken rToken_, uint256 batchDuration_) {
        require(address(rToken_) != address(0), "rToken is zero address");
        rToken = rToken_;
        batchDuration = batchDuration_;
    }

    /// Causes the Furnace to re-examine its holdings and create new batches.
    function notifyOfDeposit(IERC20 erc20) external override {
        require(address(erc20) == address(rToken), "RToken only");

        // Compute the `amount` of tokens the furnace owns that are not already in batches
        uint256 balance = erc20.balanceOf(address(this));
        uint256 batchTotal;
        for (uint256 i = 0; i < batches.length; i++) {
            Batch storage batch = batches[i];
            batchTotal += batch.amount - batch.melted;
        }
        uint256 amount = balance - batchTotal;

        if (amount > 0) {
            batches.push(Batch(amount, block.timestamp, 0));
            emit DistributionCreated(amount, batchDuration, _msgSender());
        }
    }

    /// Performs any melting that has vested since last call. Idempotent
    function melt() public override {
        // Compute the current total to melt across the batches,
        // and pull that total out of the batches that are here.

        uint256 toMelt = 0;
        for (uint256 i = 0; i < batches.length; i++) {
            Batch storage batch = batches[i];
            if (batch.melted < batch.amount) {
                // Pull the vested amount out of batch and register it melted.
                uint256 amt = vestedAmount(batch, block.timestamp);
                toMelt += amt - batch.melted;
                batch.melted = amt;
            }
        }

        if (toMelt > 0) {
            rToken.melt(toMelt);
            emit Burnt(toMelt);
        }
    }

    function setBatchDuration(uint256 batchDuration_) external override onlyOwner {
        emit BatchDurationSet(batchDuration, batchDuration_);
        batchDuration = batchDuration_;
    }

    // @return The cumulative amount of tokens from batch that have vested at `timestamp`
    function vestedAmount(Batch storage batch, uint256 timestamp) private view returns (uint256) {
        // Clamp results to the vesting period
        if (timestamp <= batch.start) return 0;
        else if (batch.start + batchDuration <= timestamp) return batch.amount;

        // (timestamp - batch.start){s} / batch.duration{s} * batch.amount{RTok}
        return toFix(timestamp - batch.start).divu(batchDuration).mulu(batch.amount).floor();
    }
}
