SELECT COUNT(*) FROM online_retail_clean;

-- Metrics Checks

-- White space
SELECT SUM(IF(invoice_no!=TRIM(invoice_no),1,0))/COUNT(*) AS white_space_invoice_no,
	   SUM(IF(stock_code!=TRIM(stock_code),1,0))/COUNT(*) AS white_space_stock_code,
       SUM(IF(description!=TRIM(description),1,0))/COUNT(*) AS white_space_description,
       SUM(IF(country!=TRIM(country),1,0))/COUNT(*) AS white_space_country
FROM online_retail_clean;
-- Expected: 0 for all fields

-- Completeness
SELECT SUM(invoice_no IS NULL)/COUNT(*) AS invoice_no_null_ratio, 
	   SUM(stock_code IS NULL)/COUNT(*) AS stock_code_null_ratio,
       SUM(description IS NULL)/COUNT(*) AS description_null_percentage,
       SUM(quantity IS NULL)/COUNT(*) AS quantity_null_percentage,
       SUM(invoice_date IS NULL)/COUNT(*) AS invoice_date_null_percentage,
       SUM(price IS NULL)/COUNT(*) AS price_null_percentage,
       SUM(customer_id IS NULL)/COUNT(*) AS customer_id_null_percentage,
       SUM(country IS NULL)/COUNT(*) AS country_null_percentage
       FROM online_retail_clean; 
       
-- Validity
SELECT COUNT(*) AS non_cancellations_invoice_no_greater_than_7_digits FROM online_retail_clean WHERE LENGTH(invoice_no)>6 AND invoice_no NOT LIKE "C%";
-- Expected: 0 

SELECT SUM(IF(LENGTH(stock_code)<5,1,0))/COUNT(*) AS less_than_5_digits_stock_code,
	   SUM(IF(LENGTH(stock_code)>5 AND stock_code NOT REGEXP '^[0-9]{5}[A-Z]{1,2}$' AND (stock_code NOT LIKE "DCGS%" AND stock_code NOT LIKE "SP%")
       ,1,0))/COUNT(*) AS more_than_5_digits_stock_code
	   FROM online_retail_clean;
-- Expected: 0 for both fields
       
SELECT SUM(IF(price<=0, 1, 0))/COUNT(*) AS neg_and_zero_price,
	   SUM(IF(quantity<=0 AND invoice_no NOT LIKE "C%", 1, 0))/COUNT(*) neg_and_zero_non_cancellations_quantity
       FROM online_retail_clean;
-- Expected: 0 for both fields
       
-- Duplicates
 SELECT SUM(cnt - 1)/(SELECT COUNT(*) FROM online_retail_clean) AS extra_rows_ratio
FROM (
  SELECT COUNT(*) AS cnt
  FROM online_retail_clean
  GROUP BY invoice_no, stock_code, description, quantity, invoice_date, price, customer_id, country
  HAVING COUNT(*) > 1
) temp;  
-- Expected: NULL 