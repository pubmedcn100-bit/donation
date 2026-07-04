#!/bin/bash

SCRIPT_DIR=$(cd $(dirname $(readlink -f $0 || echo $0)); pwd -P)
cd "$SCRIPT_DIR"

python3 <<'HEREDOC'
# -*- coding: utf-8 -*-
from __future__ import print_function

import sys
import math
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import seaborn as sns
import matplotlib.ticker as mticker

# =========================================================
# Font / style
# =========================================================
plt.rcParams['font.family'] = 'IPAGothic'
plt.rcParams['axes.unicode_minus'] = False

# =========================================================
# Input parameters
# =========================================================
EMPLOYMENT_INCOME = 5250573
SOCIAL_SECURITY_DEDUCTION = 1030379
I_DECO = 240000
BASIC_INCOME_TAX_DEDUCTION = 580000
BASIC_RESIDENT_TAX_DEDUCTION = 430000

STOCK_PROFIT = 21432284
CARRYFORWARD_LOSS = 2329386

STOCK_INCOME_TAX_RATE = 0.15315
STOCK_RESIDENT_TAX_RATE = 0.05

# =========================================================
# Tax functions
# =========================================================

def calc_income_tax(taxable_income: float) -> float:
    taxable_income = max(0, int(taxable_income // 1000 * 1000))

    brackets = [
        (1950000, 0.05),
        (3300000, 0.10),
        (6950000, 0.20),
        (9000000, 0.23),
        (18000000, 0.33),
        (40000000, 0.40),
        (float('inf'), 0.45)
    ]

    tax = 0
    prev = 0

    for limit, rate in brackets:
        if taxable_income <= prev:
            break
        taxable_part = min(taxable_income, limit) - prev
        tax += taxable_part * rate
        prev = limit

    return tax


def add_reconstruction_tax(tax: float) -> float:
    return tax * 1.021

# =========================================================
# Income base
# =========================================================

def compute_income():
    general = max(0, EMPLOYMENT_INCOME - SOCIAL_SECURITY_DEDUCTION - I_DECO - BASIC_INCOME_TAX_DEDUCTION)
    resident = max(0, EMPLOYMENT_INCOME - SOCIAL_SECURITY_DEDUCTION - I_DECO - BASIC_RESIDENT_TAX_DEDUCTION)

    stock_income = max(0, STOCK_PROFIT - CARRYFORWARD_LOSS)

    return general, resident, stock_income

# =========================================================
# Simulation
# =========================================================

def simulate():
    general_income, resident_income, stock_income = compute_income()

    base_income_tax = add_reconstruction_tax(calc_income_tax(general_income))
    base_stock_tax = stock_income * STOCK_INCOME_TAX_RATE
    base_resident_tax = resident_income * 0.10

    max_credit = (base_income_tax + base_stock_tax) * 0.25

    donation_upper = int((general_income + stock_income) * 0.40)
    donation_range = range(100000, donation_upper + 50000, 50000)

    results = []

    for donation in donation_range:
        deductible = max(0, donation - 2000)

        used_general = min(deductible, general_income)
        remaining_stock = max(0, deductible - used_general)

        general_after = max(0, general_income - deductible)
        stock_after = max(0, stock_income - remaining_stock)

        tax_after = add_reconstruction_tax(calc_income_tax(general_after))
        stock_tax_after = stock_after * STOCK_INCOME_TAX_RATE

        deduction_income = (base_income_tax + base_stock_tax) - (tax_after + stock_tax_after)
        resident_after = max(0, resident_income - deductible)
        deduction_resident = base_resident_tax - resident_after * 0.10

        total_deduction = deduction_income + deduction_resident

        tentative_credit = deductible * 0.40
        actual_credit = min(tentative_credit, max_credit)

        credit_resident = deductible * 0.10
        total_credit = actual_credit + credit_resident

        best_method = "税額控除" if total_credit > total_deduction else "所得控除"
        best = max(total_deduction, total_credit)

        results.append({
            "寄付金額": donation,
            "所得控除": total_deduction,
            "税額控除": total_credit,
            "最大還元": best,
            "方式": best_method
        })

    return pd.DataFrame(results), donation_upper, max_credit

# =========================================================
# Plot
# =========================================================

def plot(df, donation_upper, max_credit):
    plt.figure(figsize=(14, 7))

    df = df.sort_values("寄付金額").reset_index(drop=True)

    ax = plt.gca()

    fmt = mticker.StrMethodFormatter('{x:,.0f}')
    ax.xaxis.set_major_formatter(fmt)
    ax.yaxis.set_major_formatter(fmt)

    # --- split lines by regime ---
    df_ded = df[df["方式"] == "所得控除"]
    df_tax = df[df["方式"] == "税額控除"]

    plt.plot(df_ded["寄付金額"], df_ded["最大還元"],
             color="blue", label="所得控除最適領域", linewidth=2)

    plt.plot(df_tax["寄付金額"], df_tax["最大還元"],
             color="green", label="税額控除最適領域", linewidth=2)

    # --- optimal marker ---
    best_idx = df["最大還元"].idxmax()
    best_row = df.loc[best_idx]

    plt.scatter(best_row["寄付金額"], best_row["最大還元"],
                color="gold", marker="*", s=250, zorder=5,
                label="★最適寄付額")

    plt.text(best_row["寄付金額"], best_row["最大還元"],
             "★最適", va="bottom", ha="left")

    ymax = df["最大還元"].max()

    # floor display values
    du = math.floor(donation_upper)
    mc = math.floor(max_credit)

    ax.set_xlim(0, donation_upper * 1.02)
    ax.set_ylim(0, max(ymax, max_credit) * 1.05)

    # upper bound (donation)
    plt.axvline(du, linestyle='--', color='black', label='ふるさと納税上限額')
    plt.text(du, ymax * 0.95,
             f"上限:{du:,}円",
             rotation=90, va='top', ha='right')

    # 25% cap
    plt.axhline(mc, linestyle='--', color='red', label='25%税額控除上限額')
    plt.text(df["寄付金額"].min(), mc,
             f"上限:{mc:,}円",
             va="bottom", ha="left")

    # kink
    kink_donation = math.floor(max_credit / 0.40 + 2000)
    plt.axvline(kink_donation, linestyle=':', color='gray', label='税額控除飽和点')

    plt.title('寄付金シミュレーション（optimal + regime split）')
    plt.xlabel('寄付金額')
    plt.ylabel('還元額')

    plt.grid(True)
    plt.legend()
    plt.savefig('output.png', dpi=300, bbox_inches='tight')

# main

df, upper, cap = simulate()
plot(df, upper, cap)
HEREDOC