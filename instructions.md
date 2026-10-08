# Data

The raw data is not included in this repo (about 45 MB as Excel, over 90 MB as CSV).

## 1. Download

Download **Online Retail II** from the UCI Machine Learning Repository:
https://archive.ics.uci.edu/dataset/502/online+retail+ii

Unzip it and place `online_retail_II.xlsx` in working path. The workbook has two sheets (`Year 2009-2010` and `Year 2010-2011`), 1,067,371 rows combined.

## 2. Convert to CSV with Python (Pandas)

Refer to [`Excel to CSV Online_Retail_II.ipynb`](./Excel%20to%20Online_Retail_II.ipynb). Replace path with your working path.


## 3. Continue in SQL

Run the scripts in `Queries` in order ([`Loading and Inserting.sql`](./Queries/Loading%20and%20Inserting.sql), then [`Final Clean Table Query.sql`](./Queries/Final%20Clean%20Table%20Query.sql)). Replace path with your working path.
