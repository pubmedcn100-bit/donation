#!/bin/bash

SCRIPT_DIR=$(cd $(dirname $(readlink -f $0 || echo $0));pwd -P)
cd "$SCRIPT_DIR"

python3 <<HEREDOC
# -*- coding: utf-8 -*-
from __future__ import print_function

import sys
import io
import matplotlib
matplotlib.use('Agg')

import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

plt.rcParams['font.family'] = 'IPAGothic'
plt.rcParams['axes.unicode_minus'] = False

# =========================
# inputs
# =========================
employment_income = 5250573
social_security_deduction = 1030379
ideco = 240000
basic_income_tax_deduction = 580000
basic_resident_tax_deduction = 430000

stock_profit = 21432284
carryforward_loss = 2329386

taxable_stock_profit = max(0, stock_profit - carryforward_loss)

# =========================
# income
# =========================
general_income = max(0,
    employment_income - social_security_deduction - ideco - basic_income_tax_deduction
)

resident_income = max(0,
    employment_income - social_security_deduction - ideco - basic_resident_tax_deduction
)

# =========================
# tax functions
# =========================
def calc_income_tax(x):
    x = max(0, int(x // 1000 * 1000))
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
        if x <= prev:
            break
        tax += (min(x, limit) - prev) * rate
        prev = limit
    return tax

def add_reconstruction_tax(t):
    return t * 1.021

def marginal_income_tax_rate(x):
    x = max(0, int(x // 1000 * 1000))
    if x <= 1950000: return 0.05
    if x <= 3300000: return 0.10
    if x <= 6950000: return 0.20
    if x <= 9000000: return 0.23
    if x <= 18000000: return 0.33
    if x <= 40000000: return 0.40
    return 0.45

# =========================
# base tax
# =========================
base_income_tax = add_reconstruction_tax(calc_income_tax(general_income))
base_stock_tax = taxable_stock_profit * 0.15315

resident_tax_general = resident_income * 0.10
resident_tax_stock = taxable_stock_profit * 0.05
adjustment_credit = 2500

resident_income_wari = (
    resident_tax_general + resident_tax_stock - adjustment_credit
)

income_tax_rate = marginal_income_tax_rate(general_income)

# =========================
# correct furusato limit
# =========================
denom = max(0.1, 0.90 - income_tax_rate * 1.021)
available = resident_income_wari * 0.20

furusato_limit = available / denom + 2000
furusato_limit = max(0, furusato_limit)

# =========================
# donation range
# =========================
# safety cap for plotting stability
plot_cap = min(furusato_limit, general_income * 0.5)

donation_upper = int(plot_cap)
donation_range = range(0, donation_upper + 1, 25000)

results = []

for donation in donation_range:
    deductible = max(0, donation - 2000)

    general_after = max(0, general_income - deductible)

    used_general = min(deductible, general_income)
    remaining = max(0, deductible - used_general)

    stock_after = max(0, taxable_stock_profit - remaining)

    income_tax_after = add_reconstruction_tax(calc_income_tax(general_after))
    stock_tax_after = stock_after * 0.15315

    deduction_income = (base_income_tax + base_stock_tax) - (income_tax_after + stock_tax_after)

    resident_after = max(0, resident_income - deductible)
    deduction_resident = resident_tax_general - resident_after * 0.10

    total = deduction_income + deduction_resident

    results.append({
        "寄付金額": donation,
        "還元額": total
    })



df = pd.DataFrame(results)

plt.figure(figsize=(14,7))
sns.lineplot(data=df, x="寄付金額", y="還元額", linewidth=2)

plt.axvline(furusato_limit, linestyle="--", color="red", label="理論上限")

plt.title("ふるさと納税シミュレーション（修正版）")
plt.xlabel("寄付金額")
plt.ylabel("還元額")
plt.grid(True)
plt.legend()

plt.savefig("output.png", dpi=300, bbox_inches="tight")

print("furusato_limit:", furusato_limit)
HEREDOC
