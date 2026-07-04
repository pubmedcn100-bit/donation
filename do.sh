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

if sys.version_info[0] < 3:
    reload(sys)
    sys.setdefaultencoding('utf-8')

plt.rcParams['font.family'] = 'IPAGothic'
plt.rcParams['axes.unicode_minus'] = False

employment_income = 5250573  # 給与所得控除後の金額(総所得金額)

social_security_deduction = 1030379
ideco = 240000
basic_income_tax_deduction = 580000
basic_resident_tax_deduction = 430000

stock_profit = 21432284
carryforward_loss = 2329386

taxable_stock_profit = max(0, stock_profit - carryforward_loss)

total_income_for_donation = employment_income + taxable_stock_profit

STOCK_INCOME_TAX_RATE = 0.15315
STOCK_RESIDENT_TAX_RATE = 0.05

donation_upper = int(total_income_for_donation * 0.40)
donation_range = range(100000, donation_upper + 50000, 50000)

def calc_income_tax(taxable_income):
    taxable_income = max(0, taxable_income)
    taxable_income = int(taxable_income // 1000 * 1000)
    brackets = [(1950000,0.05),(3300000,0.10),(6950000,0.20),(9000000,0.23),(18000000,0.33),(40000000,0.40),(float('inf'),0.45)]
    tax=0; prev=0
    for limit,rate in brackets:
        if taxable_income<=prev: break
        tax += (min(taxable_income,limit)-prev)*rate
        prev=limit
    return tax

def add_reconstruction_tax(tax): return tax*1.021

def marginal_income_tax_rate(x):
    x=max(0,int(x//1000*1000))
    if x<=1950000:return 0.05
    if x<=3300000:return 0.10
    if x<=6950000:return 0.20
    if x<=9000000:return 0.23
    if x<=18000000:return 0.33
    if x<=40000000:return 0.40
    return 0.45

general_income=max(0,employment_income-social_security_deduction-ideco-basic_income_tax_deduction)
resident_income=max(0,employment_income-social_security_deduction-ideco-basic_resident_tax_deduction)

base_general_income_tax=add_reconstruction_tax(calc_income_tax(general_income))
base_stock_income_tax=taxable_stock_profit*STOCK_INCOME_TAX_RATE

resident_tax_general=resident_income*0.10
resident_tax_stock=taxable_stock_profit*STOCK_RESIDENT_TAX_RATE
adjustment_credit=2500

resident_income_wari=resident_tax_general+resident_tax_stock-adjustment_credit
income_tax_rate=marginal_income_tax_rate(general_income)

results=[]
for d in donation_range:
    ded=max(0,d-2000)
    gen=max(0,general_income-ded)
    used=min(ded,general_income)
    rem=max(0,ded-used)
    stock=max(0,taxable_stock_profit-rem)

    inc_after=add_reconstruction_tax(calc_income_tax(gen))
    stock_after=stock*STOCK_INCOME_TAX_RATE

    ded_inc=(base_general_income_tax+base_stock_income_tax)-(inc_after+stock_after)
    res_after=max(0,resident_income-ded)
    ded_res=resident_tax_general-res_after*0.10

    total=ded_inc+ded_res
    credit=0

    rate=total/d if d else 0

    results.append({"寄付金額":d,"所得控除_還元額":total,"税額控除_還元額":credit,"最大還元額":total,"有利な方式":"所得控除","最大還元率":rate})


df=pd.DataFrame(results)

plt.figure(figsize=(14,7))

sns.lineplot(data=df,x='寄付金額',y='最大還元額',label='還元額')

xmax=donation_upper
ymax=df[['最大還元額']].max().max()*1.1

plt.xlim(0,xmax)
plt.ylim(0,ymax)

# ふるさと納税は完全分離（参考線のみ）
plt.axvline(x=donation_upper, color='purple', linestyle='--', label='ふるさと納税上限(目安)')

plt.title('寄付シミュレーション（寄付控除効果）')
plt.xlabel('寄付金額')
plt.ylabel('還元額')
plt.grid(True)
plt.legend()

plt.savefig('output.png',dpi=300,bbox_inches='tight')
HEREDOC