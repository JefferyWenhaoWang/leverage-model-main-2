# Leverage Model Automation (QQQ)

This project is based on a dynamic leverage model built in Excel.
The goal is to maintain a target leverage level automatically as the price changes.

---

## 1. Project Idea

In the Excel model, we track:

* price of QQQ
* number of shares
* cash
* equity
* leverage

The target leverage is **3.0**, and we allow it to fluctuate within a band:

* lower bound: 3.0
* upper bound: 3.3

If leverage goes outside this band, we rebalance.

* If leverage < 3.0 → BUY
* If leverage > 3.3 → SELL
* Otherwise → HOLD

---

## 2. What I Implemented

This project extends the Excel model into three parts:

### (1) Research Memo

A short comparison between:

* off-chain trading bots (Python / APIs)
* on-chain bots (Solidity smart contracts)

This explains different ways to automate trading strategies.

---

### (2) Formal Specification

I translated the Excel logic into a more precise form:

* define equity, exposure, leverage
* define when rebalance should happen
* define how many shares to adjust

The goal is to clearly describe **what the strategy is supposed to do**.

---

### (3) Solidity Prototype

A simple smart contract that simulates the strategy.

Main functions:

* `previewAction()` → returns 0 (HOLD), 1 (BUY), 2 (SELL)
* `setPrice6(...)` → update price (scaled by 1e6)
* `rebalance()` → adjust position to target leverage
* `currentState()` → shows current state variables

---

## 3. How It Works (Simple Example)

Initial state:

* leverage is within [3.0, 3.3] → HOLD

Then:

1. price changes → leverage changes
2. if leverage drops below 3 → previewAction = BUY
3. call `rebalance()`
4. leverage returns to the target range → HOLD again

This matches the behavior in the Excel model.

---

## 4. Notes

* No transaction cost
* No slippage
* No interest on borrowing
* Same price used for observation and execution
* Fractional shares allowed

These assumptions are the same as in the Excel model.

---

## 5. Purpose

The main goal is not just to run the model, but to:

* clearly define the strategy
* implement it in code
* check that the implementation matches the intended behavior
