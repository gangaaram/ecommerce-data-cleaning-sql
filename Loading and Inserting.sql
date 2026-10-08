CREATE DATABASE ecommerce_cleaning;
USE ecommerce_cleaning;

-- Creating Table as text to avoid data import wizard errors
CREATE TABLE online_retail_II_raw (
    Invoice TEXT,
    StockCode TEXT,
    Description TEXT,
    Quantity TEXT,
    InvoiceDate TEXT,
    Price TEXT,
    `Customer ID` TEXT,
    Country TEXT
);
-- Load data intro table from csv to avoid data import wizard errors
LOAD DATA LOCAL INFILE '/path/online_retail_II_raw.csv'
INTO TABLE online_retail_II_raw
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;
SHOW WARNINGS LIMIT 20;

-- Creating staging table with proper data types 
CREATE TABLE online_retail_staging (
  invoice_no   VARCHAR(20),
  stock_code   VARCHAR(20),
  description  VARCHAR(255),
  quantity     INT,
  invoice_date DATETIME,
  price        DECIMAL(10,2),
  customer_id  INT NULL,
  country      VARCHAR(100)
);

-- Loading into staging table to proper data types
INSERT INTO online_retail_staging
SELECT
  Invoice,
  StockCode,
  NULLIF(Description, ''),
  CAST(Quantity AS SIGNED),
  STR_TO_DATE(InvoiceDate, '%Y-%m-%d %H:%i:%s'),
  CAST(Price AS DECIMAL(10,2)),
  CAST(NULLIF(NULLIF(`Customer ID`, ''), 'NaN') AS DECIMAL(10,0)),
  Country
FROM online_retail_II_raw;