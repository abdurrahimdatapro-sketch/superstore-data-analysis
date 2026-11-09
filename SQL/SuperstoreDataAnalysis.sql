SELECT * FROM dbo.Customer
SELECT * FROM dbo.Products
SELECT * FROM dbo.Shipping
SELECT * FROM dbo.Sales
SELECT * FROM dbo.TargetSales


--Q1. List the top 10 customers by total sales amount. Show CustomerID, full name, and total sales.


SELECT TOP 10
       c.ID                                     AS CustomerID,
       CONCAT_WS(' ', c.FirstName, c.LastName)  AS Full_Name,
       CAST(SUM(s.Price * (1 - s.Discount)) AS DECIMAL(14,2)) AS Total_Sales
FROM dbo.Customer c
JOIN dbo.Sales s ON s.CustomerID = c.ID
GROUP BY c.ID, c.FirstName, c.LastName
ORDER BY Total_Sales DESC;


--Q2. Show total sales per month for the year 2023, ordered by month.


SELECT MONTH(OrderDate)                                        AS Month_Number,
       DATENAME(MONTH, OrderDate)                              AS Month_Name,
       CAST(SUM(Price * (1 - Discount)) AS DECIMAL(14,2))      AS Total_Sales
FROM dbo.Sales
WHERE OrderDate >= '2023-01-01'
  AND OrderDate <  '2024-01-01'
GROUP BY MONTH(OrderDate), DATENAME(MONTH, OrderDate)
ORDER BY Month_Number;



--Q3. Find out the products that have never been sold


SELECT p.ProductID,
       p.Category,
       p.SubCategory,
       p.ProductName,
       p.Price
FROM dbo.Products p
LEFT JOIN dbo.Sales s ON s.ProductID = p.ProductID
WHERE s.ProductID IS NULL
ORDER BY p.ProductID;


--Q4. Find how many new customers were acquired in 2022


SELECT COUNT(*) AS New_Customers_2022
FROM (
    SELECT CustomerID,
           MIN(OrderDate) AS First_Order_Date
    FROM dbo.Sales
    GROUP BY CustomerID
    HAVING MIN(OrderDate) >= '2022-01-01'
       AND MIN(OrderDate) <  '2023-01-01'
) AS first_orders;



--Q5. Calculate the profit margin (Profit / Sales) percentage for each category.



SELECT p.Category,
       CAST(SUM(s.Price * (1 - s.Discount)) AS DECIMAL(14,2))  AS Total_Sales,
       CAST(SUM(s.Profit) AS DECIMAL(14,2))                    AS Total_Profit,
       CAST(100.0 * SUM(s.Profit)
            / NULLIF(SUM(s.Price * (1 - s.Discount)), 0) AS DECIMAL(6,2)) AS Profit_Margin_Pct
FROM dbo.Sales s
JOIN dbo.Products p ON p.ProductID = s.ProductID
GROUP BY p.Category
ORDER BY Profit_Margin_Pct DESC;


--Q6. For each category, show date-wise sales and a running total of sales over time.


WITH daily AS (
    SELECT p.Category,
           s.OrderDate,
           SUM(s.Price * (1 - s.Discount)) AS Daily_Sales
    FROM dbo.Sales s
    JOIN dbo.Products p ON p.ProductID = s.ProductID
    GROUP BY p.Category, s.OrderDate
)
SELECT Category,
       OrderDate,
       CAST(Daily_Sales AS DECIMAL(14,2)) AS Daily_Sales,
       CAST(SUM(Daily_Sales) OVER (PARTITION BY Category
                                   ORDER BY OrderDate
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
            AS DECIMAL(14,2)) AS Running_Total
FROM daily
ORDER BY Category, OrderDate;



--Q7. Get the most recent order (by OrderDate) for every customer.


WITH customer_orders AS (
    SELECT CustomerID,
           OrderID,
           OrderDate,
           SUM(Price * (1 - Discount)) AS Order_Sales,
           COUNT(*)                    AS Order_Lines
    FROM dbo.Sales
    GROUP BY CustomerID, OrderID, OrderDate
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY CustomerID
                              ORDER BY OrderDate DESC, OrderID DESC) AS rn
    FROM customer_orders
)
SELECT c.ID                                    AS CustomerID,
       CONCAT_WS(' ', c.FirstName, c.LastName) AS Full_Name,
       r.OrderID,
       r.OrderDate,
       CAST(r.Order_Sales AS DECIMAL(14,2))    AS Order_Sales,
       r.Order_Lines
FROM ranked r
JOIN dbo.Customer c ON c.ID = r.CustomerID
WHERE r.rn = 1
ORDER BY c.ID;


--Q8. Classify customers based on their total sale. Show CustomerID, name, total sales: 
--Platinum – TotalSales ≥ 15,000
--Gold – 10,000 to < 15,000
--Silver – 5,000 to < 10,000
--Bronze – < 5,000


WITH customer_sales AS (
    SELECT c.ID                                    AS CustomerID,
           CONCAT_WS(' ', c.FirstName, c.LastName) AS Full_Name,
           SUM(s.Price * (1 - s.Discount))         AS Total_Sales
    FROM dbo.Customer c
    JOIN dbo.Sales s ON s.CustomerID = c.ID
    GROUP BY c.ID, c.FirstName, c.LastName
)
SELECT CustomerID,
       Full_Name,
       CAST(Total_Sales AS DECIMAL(14,2)) AS Total_Sales,
       CASE
           WHEN Total_Sales >= 15000 THEN 'Platinum'
           WHEN Total_Sales >= 10000 THEN 'Gold'
           WHEN Total_Sales >= 5000  THEN 'Silver'
           ELSE 'Bronze'
       END AS Customer_Tier
FROM customer_sales
ORDER BY Total_Sales DESC;



--Q9. For each category, find the product with the highest total sales. If ties exist, show all tied products.


WITH product_sales AS (
    SELECT p.Category,
           p.ProductID,
           p.ProductName,
           SUM(s.Price * (1 - s.Discount)) AS Total_Sales
    FROM dbo.Products p
    JOIN dbo.Sales s ON s.ProductID = p.ProductID
    GROUP BY p.Category, p.ProductID, p.ProductName
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY Category ORDER BY Total_Sales DESC) AS rnk
    FROM product_sales
)
SELECT Category,
       ProductID,
       ProductName,
       CAST(Total_Sales AS DECIMAL(14,2)) AS Total_Sales
FROM ranked
WHERE rnk = 1
ORDER BY Total_Sales DESC;



--Q10. Actual vs Target sales by category & year


WITH targets AS (
    -- TargetSales has one column per year, so turn the years into rows
    SELECT t.Category,
           v.Sales_Year,
           v.Target_Sales
    FROM dbo.TargetSales t
    CROSS APPLY (VALUES (2020, t.[2020_Sales]),
                        (2021, t.[2021_Sales]),
                        (2022, t.[2022_Sales]),
                        (2023, t.[2023_Sales])) AS v(Sales_Year, Target_Sales)
),
actuals AS (
    SELECT p.Category,
           YEAR(s.OrderDate)               AS Sales_Year,
           SUM(s.Price * (1 - s.Discount)) AS Actual_Sales
    FROM dbo.Sales s
    JOIN dbo.Products p ON p.ProductID = s.ProductID
    GROUP BY p.Category, YEAR(s.OrderDate)
)
SELECT t.Category,
       t.Sales_Year,
       CAST(COALESCE(a.Actual_Sales, 0) AS DECIMAL(14,2))                      AS Actual_Sales,
       t.Target_Sales,
       CAST(COALESCE(a.Actual_Sales, 0) - t.Target_Sales AS DECIMAL(14,2))     AS Variance,
       CAST(100.0 * COALESCE(a.Actual_Sales, 0) / NULLIF(t.Target_Sales, 0) AS DECIMAL(6,1)) AS Pct_of_Target,
       CASE WHEN COALESCE(a.Actual_Sales, 0) >= t.Target_Sales
            THEN 'Target met' ELSE 'Below target' END                          AS Status
FROM targets t
LEFT JOIN actuals a
       ON a.Category = t.Category
      AND a.Sales_Year = t.Sales_Year
ORDER BY t.Category, t.Sales_Year;

