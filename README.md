# Cleaning 1M+ Rows of UK E-Commerce Transactions with MySQL
A SQL data-cleaning project on the **Online Retail II** dataset (1,067,371 transactions from a UK-based online gift retailer, 2009-2011). The goal is a clean, analysis-ready table for **transaction-level analysis**, built with a single reproducible MySQL script.

## Highlights
- Cleaned **1,067,371 rows** across 8 columns.
- Applied data quality checks for completeness, validity, duplicates and whitespaces.
- Replaced null product descriptions using the most common description per stock_code.
- Removed **34, 335 exact duplicate rows**
- Documented every cleaning decision and its justifications (see below)
  
## SQL Techniques Used
- Common Table Expressions (CTEs)
- Window functions (`ROW_NUMBER() OVER (PARTITION BY ...)`)
- Regular expressions (`REGEXP`) for pattern validation
- `COALESCE`, `NULLIF`, `If`, `TRIM`
- `GROUP BY` / `HAVING` for duplicate and consistency checks
- `SELECT DISTINCT` for deduplication
- `JOIN` for `COALESCE` fallback values
- Type conversion with `CAST` and `STR_TO_DATE` (raw text table to typed table)

## Dataset
- **Source:** [Online Retail II (UCI Machine Learning Repository)](https://archive.ics.uci.edu/dataset/502/online+retail+ii)
- **Size:** 1,067,371 rows
- **Period:** 2009 to 2011

| Column | Description |
|---|---|
| `invoice_no` | 6-digit invoice number. Starts with `C` for cancellations |
| `stock_code` | 5-digit product code, optionally followed by letters |
| `description` | Product name |
| `quantity` | Units per line (negative for cancellations) |
| `invoice_date` | Date and time of the invoice |
| `price` | Unit price in GBP |
| `customer_id` | 5-digit customer ID (missing for guest checkouts) |
| `country` | Customer's country |

> The raw CSV is not included in this repo. See [`instructions.md`](./instructions.md) for download instructions.

Data quality findings before cleaning: 
| Issue | Count | % of rows |
|---|---|---|
| Whitespace `description` | 213,679 | 20.02% |
| Missing `description` | 4,382 | 0.41% |
| Missing `customer_id` | 243,007 | 22.7% |
| Invalid `invoice_no` | 8752 | 0.82% |
| Price <= 0 | 6,225 | 0.58% |
| Quantity <= 0 | 22,950 | 2.15% |
| Stock codes shorter than 5 characters | 5,600 | 0.52% |
| Exact Duplicate Rows | 34,335 | 3.21% |

## Methodology

The cleaning follows four data quality dimensions. The full exploration, with comments, is in [`Main Online Retail Cleaning 2.sql`](./Queries/Main%20Cleaning%20Online%20Retail%202.sql). A total of 3 tables are used for this cleaning. The raw excel file which contains 2 sheets is combined and converted into a CSV through Python. Refer to code in [`Excel to CSV Online_Retail_II.ipnyb`](./Excel%20to%20CSV%20Online_Retail_II.ipnyb). First the data is loaded into `online_retail_II_raw` to store the raw data. The data is then inserted into `online_retail_staging` and when cleaning is done, the final table is called `online_retail_clean`.

### 1. Whitespace

Leading and trailing spaces were stripped from all VARCHAR columns with `TRIM()`. This was done first, because later steps (length checks, grouping by description, `DISTINCT`) would otherwise treat `'ABC'` and `'ABC '` as different values.

```sql
SELECT TRIM(invoice_no) AS invoice_no, TRIM(stock_code) AS stock_code, TRIM(description) AS description,
	   quantity, invoice_date, price, customer_id, 
       TRIM(country) AS country FROM online_retail_staging;
```

### 2. Completeness

- **`description` (4,382 NULLs):** these can be recovered. For each `stock_code`, the most frequent non-null description was found and used to fill the gaps. A stock code can have several descriptions over time, so the most common one is used rather than an arbitrary one. Ties are broken alphabetically so the result is repeatable.
- **`customer_id` (243,007 NULLs):** cannot be recovered. These rows were **kept**: they are valid transactions (guest checkouts), and removing them would discard about 23% of the data.

```sql
WITH description_counts AS (
  SELECT stock_code, description, COUNT(*) AS description_count
  FROM trimmed
  WHERE description IS NOT NULL
  GROUP BY stock_code, description
),
ranked_descriptions AS (
  SELECT stock_code, description,
         ROW_NUMBER() OVER (PARTITION BY stock_code
                            ORDER BY description_count DESC, description) AS ranking
  FROM description_counts
)
-- LEFT JOIN on ranking = 1, then COALESCE(original, most_common)
```

### 3. Validity

| Column | Rule | Decision |
|---|---|---|
| `invoice_no` | 6 digits, or `C` + 6 digits for cancellations | Kept cancellations. Removed 6 rows starting with `A` (bad-debt adjustments, not real transactions) |
| `stock_code` | 5 digits, optionally followed by 1-2 letters (e.g. `85123A`)and `DCGS%` and `SP%` product codes | Removed non-product codes such as `POST`, `BANK CHARGES`, `TEST`, `GIFT`, `ADJUST`, `AMAZONFEE` |
| `price` | Must be > 0 | Removed zero and negative prices (e.g. stock adjustments such as "damaged") |
| `quantity` | Must be > 0, except for cancellations | Negative quantities on `C` invoices are expected and kept |
| `invoice_date` | Within 2009-2011 | Valid. Some invoices span multiple timestamps, but only about a minute apart |
| `customer_id` | 5 digits | All non-null values valid |
| `country` | No spelling variants | Valid |

Different stock codes sharing the same description (for example packaging or size variants) were **kept**, since they can represent distinct products.

```sql
SELECT * FROM online_retail_staging 
		 WHERE (price >0 AND (quantity>0 OR (quantity <=0 AND invoice_no LIKE "C%"))) AND 
		 ((LENGTH(invoice_no)=6 OR
	     (LENGTH(invoice_no)>6 AND invoice_no LIKE "C%"))
		 AND (LENGTH(stock_code)=5 
		 OR (LENGTH(stock_code)>5 AND (stock_code REGEXP '^[0-9]{5}[A-Z]{1,2}$' 
         OR stock_code LIKE 'DCGS%' OR stock_code LIKE 'SP%'))));
```

### 4. Deduplication

Rows identical in **all eight columns** were treated as duplicates and reduced to one copy. Assumption: a customer buying several units would normally appear as one line with a higher quantity, not as repeated identical lines, so repeated lines are likely double entries. 

```sql
WITH dist AS (SELECT DISTINCT invoice_no, stock_code, description, quantity, invoice_date, price, customer_id, country FROM online_retail_staging)
SELECT COUNT(*) FROM dist; -- 1033036 rows
SELECT COUNT(*) FROM online_retail_staging; -- 1067371 rows, the difference is 34335 rows
SELECT SUM(cnt - 1) AS extra_rows -- -1 as we want to keep 1 row but the rest are redundant
FROM (
  SELECT COUNT(*) AS cnt
  FROM online_retail_staging
  GROUP BY invoice_no, stock_code, description, quantity, invoice_date, price, customer_id, country
  HAVING COUNT(*) > 1
) temp; -- Number of duplicate rows to be removed are 34335
Check: `COUNT(*)` before minus `COUNT(DISTINCT row)` after equals the surplus-copies count (`SUM(cnt - 1)`), confirming only the extra copies were removed.
```
Code above checks number of rows to be removed before removing. Code below is final deduplication code.

```sql
SELECT DISTINCT invoice_no, stock_code, description, quantity, invoice_date, price, customer_id, country FROM online_retail_staging;
```
 ## Final cleaning pipeline
```sql
DROP TABLE IF EXISTS online_retail_clean;

CREATE TABLE online_retail_clean AS
WITH trimmed AS(
-- remove whitespace
SELECT TRIM(invoice_no) AS invoice_no, TRIM(stock_code) AS stock_code, TRIM(description) AS description,
	   quantity, invoice_date, price, customer_id, 
       TRIM(country) AS country
       FROM online_retail_staging
),
description_counts AS (
	SELECT stock_code, description, COUNT(*) as description_count 
    FROM trimmed
    WHERE description IS NOT NULL 
    GROUP BY stock_code,description
),
ranked_descriptions AS (
	SELECT stock_code, description,
	ROW_NUMBER() OVER(PARTITION BY stock_code ORDER BY description_count DESC, description) AS ranking 
	FROM description_counts
),
filled AS (
-- fill null descriptions with most common description for specific stock_code
	SELECT t.invoice_no, t.stock_code,
	COALESCE(t.description, r.description) AS description,
	t.quantity, t.invoice_date, t.price, t.customer_id, t.country 
    FROM trimmed t
	LEFT JOIN ranked_descriptions r 
	ON t.stock_code=r.stock_code and r.ranking=1
)
-- validity and deduplication code
SELECT DISTINCT invoice_no, stock_code, description, quantity,
				invoice_date, price, customer_id, country
		 FROM filled
		 WHERE (price >0 AND (quantity>0 OR (quantity <=0 AND invoice_no LIKE "C%"))) AND 
		 ((LENGTH(invoice_no)=6 OR
	     (LENGTH(invoice_no)>6 AND invoice_no LIKE "C%"))
		 AND (LENGTH(stock_code)=5 
		 OR (LENGTH(stock_code)>5 AND (stock_code REGEXP '^[0-9]{5}[A-Z]{1,2}$' 
         OR stock_code LIKE 'DCGS%' OR stock_code LIKE 'SP%'))));
```

## Metrics
For each data quality measure, there are metrics to be checked against for future reference. Refer to [`Query/Clean Table Check.sql`](./Queries/Clean%20Table%20Check.sql). These metrics allow users to check if data quality has improved over time.

## Challenges

- **Import problems:** the first import loaded only about 31k of 1M+ rows. Fixed by loading everything into an all-text table first, then converting types in SQL, where failures are visible instead of silently skipped.
- **Deciding what a "duplicate" is:** same invoice and timestamp do not mean duplicate. Only rows identical across all columns were treated as such.
- **Order of operations:** trimming and description filling had to happen before `DISTINCT`, otherwise rows differing only by a trailing space or a NULL description would survive as unique.
