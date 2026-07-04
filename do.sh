#!/bin/bash

SCRIPT_DIR=$(cd $(dirname $(readlink -f $0 || echo $0));pwd -P)
cd "$SCRIPT_DIR"

python3 <<HEREDOC
# -*- coding: utf-8 -*-
from __future__ import print_function  # Python2互換対応

import sys
import io
import matplotlib
matplotlib.use('Agg')

import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

# Python2の場合のstdout再設定（Python3では不要）
if sys.version_info[0] < 3:
    reload(sys)
    sys.setdefaultencoding('utf-8')

# =========================
# 日本語フォント設定
# =========================
plt.rcParams['font.family'] = 'IPAGothic'
plt.rcParams['axes.unicode_minus'] = False  # マイナス符号の文字化け防止

# =========================
# 初期値
# =========================
employment_income = 5250573  # 給与所得控除後の金額(総所得金額)

# 控除
social_security_deduction = 1030379  # 社会保険料控除
ideco = 240000  # iDeCo
basic_income_tax_deduction = 580000  # 所得税の基礎控除
basic_resident_tax_deduction = 430000  # 住民税の基礎控除

# 株の利益（申告分離課税）
stock_profit = 21432284

# 去年度からの損失繰越
carryforward_loss = 2329386

taxable_stock_profit = max(0, stock_profit - carryforward_loss)

# 総所得金額等
total_income_for_donation = employment_income + taxable_stock_profit

# 株の税率
STOCK_INCOME_TAX_RATE = 0.15315
STOCK_RESIDENT_TAX_RATE = 0.05

# 寄付金の金額範囲（10万～上限、5万刻み）
donation_upper = int(total_income_for_donation * 0.40)
donation_range = range(100000, donation_upper + 50000, 50000)

# ============================================
# 所得税計算
# ============================================

def calc_income_tax(taxable_income):
    taxable_income = max(0, taxable_income)
    taxable_income = int(taxable_income // 1000 * 1000)

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
        tax += (min(taxable_income, limit) - prev) * rate
        prev = limit

    return tax


def add_reconstruction_tax(tax):
    return tax * 1.021


def marginal_income_tax_rate(taxable_income):
    taxable_income = max(0, taxable_income)
    taxable_income = int(taxable_income // 1000 * 1000)

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
    else:
        return 0.45

# =========================================================
# 総合課税所得
# =========================================================

general_income = max(0,
    employment_income
    - social_security_deduction
    - ideco
    - basic_income_tax_deduction
)

resident_income = max(0,
    employment_income
    - social_security_deduction
    - ideco
    - basic_resident_tax_deduction
)

# =========================================================
# 基準税額
# =========================================================

base_general_income_tax = add_reconstruction_tax(calc_income_tax(general_income))
base_stock_income_tax = taxable_stock_profit * STOCK_INCOME_TAX_RATE

resident_tax_general = resident_income * 0.10
resident_tax_stock = taxable_stock_profit * STOCK_RESIDENT_TAX_RATE
adjustment_credit = 2500

resident_income_wari = (
    resident_tax_general
    + resident_tax_stock
    - adjustment_credit
)

income_tax_rate = marginal_income_tax_rate(general_income)

# =========================================================
# ふるさと納税上限（精度改善：実効税率補正）
# =========================================================

income_tax_rate_effective = income_tax_rate * 1.021

denom = max(0.1, 0.90 - income_tax_rate_effective)

furusato_limit = (
    resident_income_wari * 0.20
    / denom
    + 2000
)

# 税額控除の上限（所得税額の25%）
income_tax_base = base_general_income_tax + base_stock_income_tax
max_credit = income_tax_base * 0.25

donation_limit = max_credit / 0.40 + 2000
credit_limit_reduction = max_credit + (donation_limit - 2000) * 0.10

# シミュレーション範囲内に制限（描画用）
plot_donation_limit = min(
    donation_limit,
    donation_upper
)

# =========================================================
# 結果
# =========================================================

results = []

for donation in donation_range:

    deductible = max(0, donation - 2000)

    general_after = max(0,
        general_income - deductible
    )

    used_for_general = min(deductible, general_income)
    remaining_for_stock = max(0, deductible - used_for_general)

    stock_after = max(0, taxable_stock_profit - remaining_for_stock)

    income_tax_general_after = add_reconstruction_tax(
        calc_income_tax(general_after)
    )

    stock_tax_after = stock_after * STOCK_INCOME_TAX_RATE

    deduction_income_tax_reduction = (
        (base_general_income_tax + base_stock_income_tax)
        - (income_tax_general_after + stock_tax_after)
    )

    resident_after = max(0,
        resident_income - deductible
    )

    resident_tax_general_after = resident_after * 0.10

    deduction_resident_reduction = (
        resident_tax_general - resident_tax_general_after
    )

    total_reduction_deduction = (
        deduction_income_tax_reduction
        + deduction_resident_reduction
    )

    reduction_rate_deduction = (
        total_reduction_deduction / donation
    ) * 100

    tentative_credit = deductible * 0.40
    actual_credit = min(tentative_credit, max_credit)

    credit_resident_reduction = deductible * 0.10

    total_reduction_credit = (
        actual_credit + credit_resident_reduction
    )

    reduction_rate_credit = (
        total_reduction_credit / donation
    ) * 100

    if total_reduction_credit > total_reduction_deduction:
        best_method = "税額控除"
        best_reduction = total_reduction_credit
        best_rate = reduction_rate_credit
    else:
        best_method = "所得控除"
        best_reduction = total_reduction_deduction
        best_rate = reduction_rate_deduction

    results.append({
        "寄付金額": donation,
        "所得控除_還元額": total_reduction_deduction,
        "税額控除_還元額": total_reduction_credit,
        "有利な方式": best_method,
        "最大還元額": best_reduction,
        "最大還元率": best_rate
    })

import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

df = pd.DataFrame(results)

plt.figure(figsize=(14, 7))

sns.lineplot(
    data=df,
    x='寄付金額',
    y='最大還元額',
    label='有利な方',
    linewidth=5,
    color='green'
)

sns.lineplot(
    data=df,
    x='寄付金額',
    y='税額控除_還元額',
    label='税額控除方式',
    marker='o',
    markersize=3,
    color='red'
)

sns.lineplot(
    data=df,
    x='寄付金額',
    y='所得控除_還元額',
    label='所得控除方式',
    marker='o',
    markersize=3,
    color='blue'
)

plt.axvline(plot_donation_limit, color='black', linestyle='--', alpha=0.7)
plt.axvline(furusato_limit, color='purple', linestyle=':', linewidth=2)

plt.scatter(plot_donation_limit, credit_limit_reduction, color='black', zorder=10)

plt.title('名古屋大学寄付 控除シミュレーション')
plt.xlabel('寄付金額 [円]')
plt.ylabel('還元額 [円]')
plt.grid(True)
plt.legend()

plt.savefig('output.png', dpi=300, bbox_inches='tight')
HEREDOC
