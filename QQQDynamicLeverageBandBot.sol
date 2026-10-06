// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title QQQDynamicLeverageBandBot
 * @notice Minimal prototype that mirrors the spreadsheet logic in
 *         QQQ_Dynamic_Leverage_Band_Model_v1.xlsx (Model sheet, columns T:AG).
 *
 * Workbook mapping:
 *   T  = Shares_prev
 *   U  = Pos_pre
 *   V  = Cash_pre
 *   W  = Equity_pre
 *   X  = Leverage_pre
 *   Y  = Rebalance_Action
 *   Z  = Target_Pos
 *   AA = Trade_Value
 *   AB = Trade_Shares
 *   AC = Shares_new
 *   AD = Cash_new
 *   AE = Pos_new
 *   AF = Equity_new
 *   AG = Leverage_new
 *
 * Economic assumptions copied from the workbook:
 *   - direct leveraged long QQQ position
 *   - target leverage = 3.0
 *   - rebalance band = [3.0, 3.3]
 *   - no transaction costs
 *   - no slippage
 *   - no borrow interest
 *   - same-price observation and execution
 *   - fractional shares allowed
 *
 * Technical note:
 *   Solidity has no floating-point numbers, so this contract uses 18-decimal
 *   fixed-point arithmetic ("WAD"). The rebalance rule is therefore implemented
 *   approximately up to fixed-point rounding. The correctness criterion is:
 *   after rebalance, the portfolio is back inside the band and the next action is HOLD.
 */
contract QQQDynamicLeverageBandBot {
    uint256 public constant WAD = 1e18;

    // Policy parameters copied from the workbook.
    uint256 public constant TARGET_LEVERAGE_WAD = 3e18;        // 3.0
    uint256 public constant LOWER_BAND_WAD = 3e18;             // 3.0
    uint256 public constant UPPER_BAND_WAD = 33e17;            // 3.3

    // Workbook initial state:
    // Initial_Capital = 1,000,000
    // Initial QQQ price from Model!B2 = 94.66504669189453
    uint256 public constant INITIAL_CAPITAL_WAD = 1_000_000e18;
    uint256 public constant INITIAL_QQQ_PRICE_WAD = 94_665_046_691_894_530_000;

    // State variables (WAD-scaled unless signed cash).
    uint256 public priceWad;    // current QQQ price
    uint256 public sharesWad;   // current QQQ shares, 18-decimal fixed-point
    int256  public cashWad;     // current cash balance; can be negative

    enum Action {
        HOLD,
        BUY,
        SELL
    }

    event Rebalanced(
        Action action,
        uint256 oldLeverageWad,
        uint256 newLeverageWad,
        uint256 targetPositionValueWad,
        uint256 newPositionValueWad,
        uint256 newSharesWad,
        int256 newCashWad
    );

    constructor() {
        resetToWorkbookInitialState();
    }

    // ----------------------------
    // Basic fixed-point arithmetic
    // ----------------------------

    function wadMul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y) / WAD;
    }

    function wadDiv(uint256 x, uint256 y) internal pure returns (uint256) {
        require(y != 0, "division by zero");
        return (x * WAD) / y;
    }

    // Ceiling version of wadDiv so that post-rebalance leverage ends up
    // inside the band rather than slightly below the lower threshold.
    function wadDivUp(uint256 x, uint256 y) internal pure returns (uint256) {
        require(y != 0, "division by zero");
        return ((x * WAD) + y - 1) / y;
    }

    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a - b : b - a;
    }

    // ----------------------------
    // Initialization / price input
    // ----------------------------

    function resetToWorkbookInitialState() public {
        priceWad = INITIAL_QQQ_PRICE_WAD;

        // Spreadsheet idea: Shares_prev = 3 * Initial_Capital / QQQ
        // We round up by one fixed-point share tick so that the initial state
        // lies in-band in integer arithmetic.
        sharesWad = wadDivUp(3 * INITIAL_CAPITAL_WAD, priceWad);

        uint256 initialPositionValue = positionValueWadAt(sharesWad, priceWad);

        // Choose cash so that equity is exactly Initial_Capital.
        cashWad = int256(INITIAL_CAPITAL_WAD) - int256(initialPositionValue);

        // Runtime sanity checks.
        assert(equityWad() == int256(INITIAL_CAPITAL_WAD));
        assert(previewAction() == Action.HOLD);
    }

    function setPriceWad(uint256 newPriceWad) public {
        require(newPriceWad > 0, "price must be positive");
        priceWad = newPriceWad;
    }

    // Helper for easier manual testing in Remix:
    // price6 means a QQQ price scaled by 1e6 (for example 94.996147 -> 94996147).
    function setPrice6(uint256 newPrice6) public {
        require(newPrice6 > 0, "price must be positive");
        priceWad = newPrice6 * 1e12;
    }

    // ----------------------------
    // Views: state derived exactly like the workbook
    // ----------------------------

    function positionValueWadAt(uint256 someSharesWad, uint256 somePriceWad) internal pure returns (uint256) {
        return wadMul(someSharesWad, somePriceWad);
    }

    function positionValueWad() public view returns (uint256) {
        return positionValueWadAt(sharesWad, priceWad);
    }

    function equityWad() public view returns (int256) {
        return cashWad + int256(positionValueWad());
    }

    function leverageWad() public view returns (uint256) {
        int256 eq = equityWad();
        require(eq > 0, "equity must be positive");
        return wadDiv(positionValueWad(), uint256(eq));
    }

    function previewAction() public view returns (Action) {
        uint256 lev = leverageWad();

        if (lev < LOWER_BAND_WAD) {
            return Action.BUY;
        }
        if (lev > UPPER_BAND_WAD) {
            return Action.SELL;
        }
        return Action.HOLD;
    }

    function targetPositionValueWad() public view returns (uint256) {
        int256 eq = equityWad();
        require(eq > 0, "equity must be positive");
        return wadMul(TARGET_LEVERAGE_WAD, uint256(eq));
    }

    function currentState()
        external
        view
        returns (
            uint256 currentPriceWad,
            uint256 currentSharesWad,
            int256 currentCashWad,
            uint256 currentPositionValueWad,
            int256 currentEquityWad,
            uint256 currentLeverageWad,
            Action nextAction
        )
    {
        currentPriceWad = priceWad;
        currentSharesWad = sharesWad;
        currentCashWad = cashWad;
        currentPositionValueWad = positionValueWad();
        currentEquityWad = equityWad();
        currentLeverageWad = leverageWad();
        nextAction = previewAction();
    }

    // ----------------------------
    // Core rebalance transition
    // ----------------------------

    function rebalance() public {
        Action action = previewAction();
        require(action != Action.HOLD, "already inside band");

        uint256 oldShares = sharesWad;
        uint256 oldPositionValue = positionValueWad();
        int256 oldCash = cashWad;
        int256 oldEquity = equityWad();
        require(oldEquity > 0, "equity must be positive");

        uint256 oldLeverage = leverageWad();

        // Spreadsheet idea: Target_Pos = 3 * Equity_pre
        uint256 targetPositionValue = wadMul(TARGET_LEVERAGE_WAD, uint256(oldEquity));

        // Translate target position value into shares.
        // We round up so the resulting leverage is not pushed slightly below 3.0
        // by fixed-point truncation.
        uint256 targetShares = wadDivUp(targetPositionValue, priceWad);

        // Update shares first.
        sharesWad = targetShares;

        // Use executed notional (newPosition - oldPosition) when updating cash.
        // This preserves total equity exactly in integer arithmetic.
        uint256 newPositionValue = positionValueWad();
        int256 executedTradeValue = int256(newPositionValue) - int256(oldPositionValue);
        cashWad = oldCash - executedTradeValue;

        uint256 newLeverage = leverageWad();
        int256 newEquity = equityWad();

        // ----------------------------
        // Assertions = correctness hooks
        // ----------------------------

        // P1. Equity preservation.
        assert(newEquity == oldEquity);

        // P2. The state update actually moved shares to the target share level.
        assert(sharesWad == targetShares);

        // P3. Trade direction matches workbook action.
        if (action == Action.BUY) {
            assert(targetShares >= oldShares);
            assert(newPositionValue >= oldPositionValue);
        } else {
            assert(targetShares <= oldShares);
            assert(newPositionValue <= oldPositionValue);
        }

        // P4. New position is very close to the intended target position.
        // In WAD arithmetic the mismatch is tiny; using <= priceWad is a safe bound.
        assert(absDiff(newPositionValue, targetPositionValue) <= priceWad);

        // P5. After rebalance, we are back inside the no-trade band.
        assert(newLeverage >= LOWER_BAND_WAD);
        assert(newLeverage <= UPPER_BAND_WAD);
        assert(previewAction() == Action.HOLD);

        emit Rebalanced(
            action,
            oldLeverage,
            newLeverage,
            targetPositionValue,
            newPositionValue,
            sharesWad,
            cashWad
        );
    }

    // Single-step helper: update the price, then rebalance only if needed.
    function stepWithPriceWad(uint256 newPriceWad) external {
        setPriceWad(newPriceWad);
        if (previewAction() != Action.HOLD) {
            rebalance();
        }
    }

    // Same as above, but with price given in 1e6 units for easier manual testing.
    function stepWithPrice6(uint256 newPrice6) external {
        setPrice6(newPrice6);
        if (previewAction() != Action.HOLD) {
            rebalance();
        }
    }
}
