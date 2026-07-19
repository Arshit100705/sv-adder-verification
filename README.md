# 🔧 Object-Oriented SystemVerilog Verification Environment for Arithmetic Units

A layered, class-based **SystemVerilog** testbench built around a configurable 9-bit arithmetic core — using **Object-Oriented Programming (OOP)**, **Constrained-Random Verification (CRV)**, and **Functional Coverage** to automatically and exhaustively verify the design, the way real ASIC/DV teams do it.

---

## 📌 Overview

Most student projects stop at "the RTL compiles and gives the right answer." This project goes a step further — it builds a **complete, self-checking verification environment** around the design, proving correctness automatically across thousands of randomized scenarios instead of relying on manual inspection.

**Design Under Test (DUT):** A 9-bit configurable arithmetic core supporting 4 operations (ADD / SUB / MAX / MIN), with a synchronous active-low reset and a clock-enable input that models variable transmission frequencies.

**Verification Environment:** An 8-class, layered OOP testbench (`transaction`, `generator`, `driver`, `monitor`, `scoreboard`, `functional_coverage`, `environment`, `test`) connected via an SV interface, mailboxes, and virtual interfaces — with a self-checking scoreboard and cross-coverage analysis.

---

## ✨ Key Features

- 🏗️ **Layered OOP Architecture** — 8 independent classes, each with a single responsibility (generator, driver, monitor, scoreboard, coverage, environment, test)
- 🔌 **SV Interface Bus Wrapper** — fully decouples the testbench from the DUT's exact pinout via `modport`-controlled access (`DRIVER` / `MONITOR`)
- 🎲 **Constrained-Random Verification (CRV)** — `rand` fields + weighted `constraint`/`dist` blocks driving **10,000 automatically generated stimulus transactions**
- ✅ **Self-Checking Scoreboard** — maintains its own cycle-accurate golden reference model and automatically compares it against DUT output every clock cycle — zero manual waveform inspection
- 📊 **Functional Coverage with Cross-Coverage** — measures and proves that every mode × transmission-frequency combination was actually exercised
- 🧪 **16 Directed Test Cases + CRV loop** — covering reset behavior, boundary values, invalid input handling, back-to-back transactions, mid-operation resets, mode coverage, and combined corner cases
- 🐛 **Real bug found & fixed during development** — an unbounded mailbox was letting the generator race 10,000 cycles ahead of the driver, silently skipping verification of the entire random loop (see [Key Learnings](#-key-learnings) below)


**Flow:** Generator creates transactions (random or directed) → Driver drives them onto the DUT via the interface → Monitor passively observes every cycle → Scoreboard compares actual vs. its own predicted output → Functional Coverage records which mode/frequency combinations were hit.

---

## 📁 File Structure

```
├── adder.sv        # DUT: 9-bit configurable arithmetic core (Design Source)
└── tb_adder.sv      # Complete testbench: interface + all 8 classes + top module (Simulation Source)
```

Everything is contained in just two files for easy setup — no packages or includes to manage.

---

## ⚙️ DUT Specification

| Signal | Direction | Width | Description |
|---|---|---|---|
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Active-low synchronous reset |
| `clk_en` | input | 1 | Clock enable — `0` holds the last output (models throttled transmission frequency) |
| `data_in0`, `data_in1` | input | 9 | Operands (0–511) |
| `in_valid` | input | 1 | Input valid qualifier |
| `mode` | input | 2 | `00`=ADD, `01`=SUB (saturates at 0), `10`=MAX, `11`=MIN |
| `data_out` | output | 10 | Result (registered, 1-cycle latency) |
| `out_valid` | output | 1 | Output valid, follows `in_valid` with 1-cycle latency |

---

## 🧪 Test Plan

| TC | Description |
|---|---|
| TC-001 | Reset verification |
| TC-002–006 | Directed ADD: zero, basic, max+max, max+zero, zero+max |
| TC-007 | Invalid input handling |
| TC-009 | 25 back-to-back valid transactions |
| TC-010 | Reset during active operation |
| TC-011 | 10,000 constrained-random transactions (all modes × frequencies) |
| TC-012 | Boundary value analysis |
| TC-014 | Directed SUB/MAX/MIN mode coverage |
| TC-015 | Throttled transmission frequency (`clk_en=0`) |
| TC-016 | Simultaneous max-value result + unexpected reset (combined corner case) |

---

## ▶️ How to Run (Vivado)

1. Add `adder.sv` as a **Design Source**
2. Add `tb_adder.sv` as a **Simulation Source**
3. Set `tb_top` as the **simulation top**
4. Set `xsim.simulate.runtime` to `all` (Settings → Simulation) so it runs to completion
5. Run **Behavioral Simulation**
6. Check the **Tcl Console** for results (not the waveform viewer)

*(Works with any standard SystemVerilog simulator supporting classes, constraints, and covergroups — e.g. VCS, Questa, Xcelium, or Vivado XSim.)*

---

## 📊 Results

```
==================== SCOREBOARD SUMMARY ====================
 Checks: 10053   Passed: 10053   Failed: 0
 >>> ALL CHECKS PASSED <<<
==============================================================

=================== FUNCTIONAL COVERAGE ====================
 mode coverage            : 100.00 %
 frequency coverage       : 100.00 %
 in_valid coverage        : 100.00 %
 mode x frequency (cross) : 100.00 %
 overall covergroup       : 100.00 %
==============================================================
```

- **10,053 automatically self-checked cycle-level comparisons**, zero failures
- **100% functional coverage**, including full mode × frequency cross-coverage
- 14 directed test scenarios + a 10,000-transaction CRV loop

---

## 💡 Key Learnings

- **Bounded mailboxes matter for flow control.** An unbounded mailbox let the generator dump all 10,000 transactions instantly, finishing before the driver could actually process and check most of them — silently reducing real coverage to near-zero for the random loop. Switching to a bounded mailbox (`new(2)`) forced the generator to naturally pace itself to the driver's clock-rate consumption.
- **Class declaration order matters in a single-file testbench** — a class must be declared before any other class references its type.
- **1-cycle registered latency requires a check-then-update pattern in the scoreboard** — the reference model must predict *before* comparing, or every comparison will be off by one cycle.
- **Functional coverage and scoreboard checking are two different questions** — passing checks proves correctness of what was tested; coverage proves *how much* was actually tested.

---

## 🛠️ Tech Stack

`SystemVerilog` · `Object-Oriented Programming (OOP)` · `Constrained-Random Verification (CRV)` · `Functional Coverage` · `Xilinx Vivado (XSim)`

-
