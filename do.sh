#!/bin/bash

SCRIPT_DIR=$(cd $(dirname $(readlink -f $0 || echo $0)); pwd -P)
cd "$SCRIPT_DIR"

python <<'HEREDOC'
# -*- coding: utf-8 -*-
from __future__ import print_function

import sys
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import seaborn as sns

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


def marginal_rate(taxable_income: float) -> float:
    taxable_income = max(0, int(taxable_income // 1000 * 1000))

    if taxable_income <= 1950000:
        return 0.05
    elif taxable_income <= 3300000:
        return 0.10
    elif taxable_income <= 6950000:
        return 0.20
    elif taxable_income <= 9000000:
        return 0.23
    elif taxable_income <= 18000000:
        return 0.33
    elif taxable_income <= 40000000:
        return 0.40
    return 0.45

# =========================================================
# Income base
# =========================================================

def compute_income():
    general = max(0, EMPLOYMENT_INCOME - SOCIAL_SECURITY_DEDUCTION - I_DECO - BASIC_INCOME_TAX_DEDUCTION)
    resident = max(0, EMPLOYMENT_INCOME - SOCIAL_SECURITY_DEDUCTION - I_DECO - BASIC_RESIDENT_TAX_DEDUCTION)

    stock_taxable = max(0, STOCK_PROFIT - CARRYFORWARD_LOSS)

    return general, resident, stock_taxable

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

    return pd.DataFrame(results), donation_upper

# =========================================================
# Plot
# =========================================================

def plot(df, donation_upper):
    plt.figure(figsize=(14, 7))
    sns.lineplot(data=df, x='寄付金額', y='最大還元', label='最適', linewidth=3)
    plt.axvline(donation_upper, linestyle='--', color='black', label='上限')
    plt.title('寄付金シミュレーション（Refactored v2）')
    plt.xlabel('寄付金額')
    plt.ylabel('還元額')
    plt.grid(True)
    plt.legend()
    plt.savefig('output.png', dpi=300, bbox_inches='tight')

# =========================================================
# main
# =========================================================

df, upper = simulate()
plot(df, upper)
HEREDOC