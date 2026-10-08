-- Data Quality Checks - Goal is to have a clean table for product level analysis.


-- WHITE SPACES
SELECT COUNT(*) FROM online_retail_staging WHERE invoice_no !=TRIM(invoice_no) OR stock_code != TRIM(stock_code) OR description != TRIM(description) OR country != TRIM(country); -- 213680 rows
-- Final Code:
SELECT TRIM(invoice_no) AS invoice_no, TRIM(stock_code) AS stock_code, TRIM(description) AS description,
	   quantity, invoice_date, price, customer_id, 
       TRIM(country) AS country FROM online_retail_staging;
-- Metrics: 
SELECT SUM(IF(invoice_no!=TRIM(invoice_no),1,0))/COUNT(*) AS white_space_invoice_no,
	   SUM(IF(stock_code!=TRIM(stock_code),1,0))/COUNT(*) AS white_space_stock_code,
       SUM(IF(description!=TRIM(description),1,0))/COUNT(*) AS white_space_description,
       SUM(IF(country!=TRIM(country),1,0))/COUNT(*) AS white_space_country
FROM online_retail_staging;
-- Conclusion: We trim all varchar columns to ensure there are no trailing spaces. 


-- COMPLETENESS -- check for the missing fields and row counts
SELECT COUNT(*) FROM online_retail_staging; -- 1,067,371 rows
SELECT SUM(invoice_no IS NULL ) AS invoice_no__null,
	   SUM(stock_code IS NULL) AS stock_code_null,
       SUM(description IS NULL) AS description_null, -- 361 rows
       SUM(quantity IS NULL) AS quantity_null,
       SUM(invoice_date IS NULL) AS invoice_date_null,
       SUM(price IS NULL) AS price_null,
       SUM(customer_id IS NULL) AS customer_null, -- 243007 rows
       SUM(country IS NULL) AS country
FROM online_retail_staging; -- customer_id cant be updated but description can be updated through similar stock_codes

SELECT stock_code FROM online_retail_staging GROUP BY stock_code 
HAVING COUNT(description) > 0 AND COUNT(*) - COUNT(description) >0; -- Finds stock_codes that have at least 1 null description and 1 non-null description

SELECT * FROM online_retail_staging WHERE stock_code = "35015"; -- We find that description can have other values, so we need to find the highest count of description to get the accurate name for update
-- Final COMPLETENESS code
WITH description_counts AS (
	SELECT stock_code, description, COUNT(*) as description_count FROM online_retail_staging 
    WHERE description IS NOT NULL 
    GROUP BY stock_code,description
), -- Finding counts of descriptions 
ranked_descriptions AS (
SELECT stock_code, description, description_count,
ROW_NUMBER() OVER(PARTITION BY stock_code ORDER BY description_count DESC) AS ranking FROM description_counts
) -- Ranking counts of descriptions
SELECT o.invoice_no, o.stock_code,
COALESCE(o.description, r.description) AS description,
o.quantity, o.invoice_date, o.price, o.customer_id, o.country FROM online_retail_staging o
LEFT JOIN ranked_descriptions r 
ON o.stock_code=r.stock_code and r.ranking=1; -- COALESCE allows for null value descriptions to take the value of ranked_description with ranking=1 (most common description)
-- METRICS
SELECT SUM(invoice_no IS NULL)/COUNT(*) AS invoice_no_null_ratio, 
	   SUM(stock_code IS NULL)/COUNT(*) AS stock_code_null_ratio,
       SUM(description IS NULL)/COUNT(*) AS description_null_percentage,
       SUM(quantity IS NULL)/COUNT(*) AS quantity_null_percentage,
       SUM(invoice_date IS NULL)/COUNT(*) AS invoice_date_null_percentage,
       SUM(price IS NULL)/COUNT(*) AS price_null_percentage,
       SUM(customer_id IS NULL)/COUNT(*) AS customer_id_null_percentage,
       SUM(country IS NULL)/COUNT(*) AS country_null_percentage
       FROM online_retail_staging; 
-- CONCLUSION: Remaining null rows do not have to be removed as they still serve function for transaction level analysis.


-- VALIDITY-- we check each column to see if it is valid and remove invalid rows
-- invoice_no is supposed to be 6 digit, cancellations start with C and are 7 digits (we keep cancellations) 
SELECT COUNT(invoice_no) FROM online_retail_staging WHERE LENGTH(invoice_no)<6; -- 0 rows
SELECT COUNT(invoice_no) FROM online_retail_staging WHERE LENGTH(invoice_no)>6; -- 19500 rows

SELECT * FROM online_retail_staging 
WHERE LENGTH(invoice_no)>6 AND invoice_no NOT LIKE "C%"; -- 6 rows are starting with A which represent bad debt adjustments which arent real transactions

-- Check if invoice_no is unique
SELECT invoice_no FROM online_retail_staging 
WHERE LENGTH(invoice_no)=6 OR (LENGTH(invoice_no)>6 AND invoice_no LIKE "C%") 
GROUP BY invoice_no 
HAVING COUNT(*)>1; -- There are multiple entries with same invoice_no as each product has one row. Refer to example below.

SELECT * FROM online_retail_staging WHERE invoice_no="489434"; 

SELECT invoice_date FROM online_retail_staging GROUP BY invoice_date HAVING COUNT(DISTINCT(invoice_no))>1; -- Now we compare invoice_no to invoice_date to see if each date has one invoice_no.

SELECT * FROM online_retail_staging WHERE invoice_date="2009-12-01 10:49:00"; -- We find that customers can have multiple invoice_no at the same invoice_date, hence dedeuplication shouldn't be performed.

-- Final Code: 
SELECT * FROM online_retail_staging 
		WHERE LENGTH(invoice_no)=6 OR
	    (LENGTH(invoice_no)>6 AND invoice_no LIKE "C%");
-- METRICS 
SELECT COUNT(*) AS non_cancellations_invoice_no_greater_than_7_digits FROM online_retail_staging WHERE LENGTH(invoice_no)>6 AND invoice_no NOT LIKE "C%";
-- CONCLUSION: We remove invoice_no that have length >6 and do not start with "C".

-- stock_code is 5 digits long and is assigned to each distinct product
SELECT COUNT(stock_code) FROM online_retail_staging WHERE LENGTH(stock_code)<5;-- 5600 rows
SELECT DISTINCT(stock_code) FROM online_retail_staging WHERE LENGTH(stock_code)<5; -- We remove the stock_codes here as they do not represent real transaction data (e.g. POST, GIFT, MANUAL)
SELECT COUNT(stock_code) FROM online_retail_staging WHERE LENGTH(stock_code)>5;-- 129 386 rows
SELECT DISTINCT(stock_code) FROM online_retail_staging WHERE LENGTH(stock_code)>5 AND stock_code NOT REGEXP '^[0-9]{5}[A-Z]{1,2}$';--  we find that stock_codes with these format: 12345A, 12345AB, "DCGS%", "SP%" are valid
SELECT DISTINCT(stock_code) FROM online_retail_staging WHERE LENGTH(stock_code)>5 AND stock_code NOT REGEXP '^[0-9]{5}[A-Z]{1,2}$' AND (stock_code NOT LIKE "DCGS%" AND stock_code NOT LIKE "SP%"); -- We remove BANK CHARGES, TEST, GIFT, ADJUST, AMAZONFEE

-- Now we check to see if each stock_code has its unique product, products with null descriptions are unique.
SELECT description FROM online_retail_staging WHERE 
(LENGTH(stock_code)=5 OR (LENGTH(stock_code)>5 
AND stock_code REGEXP '^[0-9]{5}[A-Z]{1,2}$' 
OR stock_code LIKE 'DCGS%' OR stock_code LIKE 'SP%'))
AND description IS NOT NULL 
GROUP BY description 
HAVING COUNT(DISTINCT stock_code)>1;  -- Refer to example below.

SELECT * FROM online_retail_staging WHERE description='BLUE FLOCK GLASS CANDLEHOLDER' ORDER BY invoice_date DESC;
-- Although there are multiple stock codes, there could be variations such as packaging and size so we keep stocks with same descriptions.

-- Final Code: 
SELECT * FROM online_retail_staging 
		 WHERE LENGTH(stock_code)=5 
		 OR (LENGTH(stock_code)>5 AND stock_code REGEXP '^[0-9]{5}[A-Z]{1,2}$' 
         OR stock_code LIKE 'DCGS%' OR stock_code LIKE 'SP%');
-- Metrics 
SELECT SUM(IF(LENGTH(stock_code)<5,1,0))/COUNT(*) AS less_than_5_digits_stock_code,
	   SUM(IF(LENGTH(stock_code)>5 AND stock_code NOT REGEXP '^[0-9]{5}[A-Z]{1,2}$' AND (stock_code NOT LIKE "DCGS%" AND stock_code NOT LIKE "SP%")
       ,1,0))/COUNT(*) AS more_than_5_digits_stock_code
	   FROM online_retail_staging;
-- CONCLUSION: We remove stock_codes with length <5, >5 that don't follow the regex and LIKE patterns as they are things such as BANK CHARGES and TESTS. We keep stock_codes that have the same description.
-- Final Code w/ invoice_no filtering:
SELECT * FROM online_retail_staging 
		 WHERE (LENGTH(invoice_no)=6 OR
	     (LENGTH(invoice_no)>6 AND invoice_no LIKE "C%"))
		 AND (LENGTH(stock_code)=5 
		 OR (LENGTH(stock_code)>5 AND stock_code REGEXP '^[0-9]{5}[A-Z]{1,2}$' 
         OR stock_code LIKE 'DCGS%' OR stock_code LIKE 'SP%'));

-- quantity and price 
SELECT COUNT(*) FROM online_retail_staging WHERE price <=0; -- 6225 rows
SELECT COUNT(*) FROM online_retail_staging WHERE quantity <=0; -- 22950 rows
SELECT * FROM online_retail_staging WHERE quantity <=0 AND invoice_no LIKE "C%"; -- We know that quantity is negative due to cancellations and we want to keep those 
-- Final Code 
SELECT * FROM online_retail_staging WHERE price >0 AND (quantity>0 OR (quantity <=0 AND invoice_no LIKE "C%"));
-- Metrics
SELECT SUM(IF(price<=0, 1, 0))/COUNT(*) AS neg_and_zero_price,
	   SUM(IF(quantity<=0 AND invoice_no NOT LIKE "C%", 1, 0))/COUNT(*) neg_and_zero_non_cancellations_quantity
       FROM online_retail_staging;
-- Conclusion: Remove rows that have price and quantity <=0 (only non-cancellations) as they are errors and descriptions such as "Damage" are not relevant to transaction level analysis
-- Final Code w/ invoice_no and stock_code filtering
SELECT * FROM online_retail_staging 
		 WHERE (price >0 AND (quantity>0 OR (quantity <=0 AND invoice_no LIKE "C%"))) AND 
		 ((LENGTH(invoice_no)=6 OR
	     (LENGTH(invoice_no)>6 AND invoice_no LIKE "C%"))
		 AND (LENGTH(stock_code)=5 
		 OR (LENGTH(stock_code)>5 AND (stock_code REGEXP '^[0-9]{5}[A-Z]{1,2}$' 
         OR stock_code LIKE 'DCGS%' OR stock_code LIKE 'SP%'))));

-- invoice_date
SELECT MIN(invoice_date) AS earliest_date, MAX(invoice_date) AS latest_date FROM online_retail_staging; -- must be between 2009-2011
SELECT invoice_no FROM online_retail_staging GROUP BY invoice_no HAVING COUNT(DISTINCT(invoice_date))>1; -- checking how many dates to each invoice_no, refer to example below.
SELECT * FROM online_retail_staging WHERE invoice_no='529368'; 
SELECT invoice_no, MIN(invoice_date) AS earliest_date, MAX(invoice_date) AS latest_date,
		TIMESTAMPDIFF(minute, MIN(invoice_date), MAX(invoice_date)) AS difference_time FROM online_retail_staging
		GROUP BY invoice_no HAVING COUNT(DISTINCT(invoice_date))>1 ORDER BY difference_time DESC;
-- Although there are multiple invoice_date to one invoice_no, they are only a minute apart so data is valid
-- Conclusion, invoice_date has consistent data. Datetime format is checked when loading data into table.

 -- customer_id - needs to be 5 digits
 SELECT SUM(IF(LENGTH(customer_id)=5,1,0))/COUNT(*) FROM online_retail_staging WHERE LENGTH(customer_id)=5; -- equals to 1 so all rows have the correct customer_id
 SELECT * FROM online_retail_staging WHERE customer_id IS NULL AND invoice_no NOT LIKE "C%" AND quantity>0 AND price >0; -- all valid transactions and therefore are kept despite missing customer_id
 
 -- country
SELECT COUNT(*) AS rows_with_spaces FROM online_retail_staging WHERE country != TRIM(country); -- 0 rows
SELECT DISTINCT(country) FROM online_retail_staging; -- no repeats through incorrect spelling

-- Final VALIDITY code
SELECT * FROM online_retail_staging 
		 WHERE (price >0 AND (quantity>0 OR (quantity <=0 AND invoice_no LIKE "C%"))) AND 
		 ((LENGTH(invoice_no)=6 OR
	     (LENGTH(invoice_no)>6 AND invoice_no LIKE "C%"))
		 AND (LENGTH(stock_code)=5 
		 OR (LENGTH(stock_code)>5 AND (stock_code REGEXP '^[0-9]{5}[A-Z]{1,2}$' 
         OR stock_code LIKE 'DCGS%' OR stock_code LIKE 'SP%'))));
         
         
-- DEDUPLICATION -- to find duplicates that are invalid
SELECT *, COUNT(*) as duplicate_count 
FROM online_retail_staging 
GROUP BY invoice_no, stock_code, 
		 description, quantity, 
         invoice_date, price, 
         customer_id, country 
         HAVING COUNT(*)>1 ORDER BY duplicate_count DESC;
-- Under the assumption that the customer would have indicated X for quantity instead of making a purchase X number of times, we remove duplicates.
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
-- Final DEDUPLICATION Code
SELECT DISTINCT invoice_no, stock_code, description, quantity, invoice_date, price, customer_id, country FROM online_retail_staging;
-- Metrics 
 SELECT SUM(cnt - 1)/(SELECT COUNT(*) FROM online_retail_staging) AS extra_rows_ratio
FROM (
  SELECT COUNT(*) AS cnt
  FROM online_retail_staging
  GROUP BY invoice_no, stock_code, description, quantity, invoice_date, price, customer_id, country
  HAVING COUNT(*) > 1
) temp;  
-- Conclusion: We remove rows that are exact duplicates for each column.
