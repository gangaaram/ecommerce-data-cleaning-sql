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
-- fill null descriptions with most common description for sepcific stock_code
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
