-- Task 1
SELECT
    first_name || ' ' || UPPER(last_name) AS full_name,
    title,
    LOWER(LEFT(first_name, 1) || last_name) AS login,
    LENGTH(first_name) + LENGTH(last_name) AS name_length,
    EXTRACT(YEAR FROM hire_date) AS hire_year
FROM employees
ORDER BY hire_date;

-- Task 2
SELECT
    order_id,
    TO_CHAR(order_date, 'DD.MM.YYYY') AS order_day,
    required_date,
    shipped_date,
    shipped_date - required_date AS days_late
FROM orders
WHERE shipped_date > required_date
ORDER BY days_late DESC, order_id;

-- Task 3
SELECT
    c.category_name,
    COUNT(*) AS products_cnt,
    ROUND(AVG(p.unit_price)::numeric, 2) AS avg_price,
    MIN(p.unit_price) AS min_price,
    MAX(p.unit_price) AS max_price,
    SUM(p.units_in_stock) AS total_stock
FROM products AS p
JOIN categories AS c
    ON c.category_id = p.category_id
GROUP BY c.category_id, c.category_name
HAVING AVG(p.unit_price) > 25
ORDER BY avg_price DESC;

-- Task 4
SELECT
    c.country,
    COUNT(DISTINCT c.customer_id) AS customers_cnt,
    COUNT(o.order_id) AS orders_cnt,
    ROUND(SUM(o.freight)::numeric, 2) AS total_freight
FROM customers AS c
JOIN orders AS o
    ON o.customer_id = c.customer_id
GROUP BY c.country
HAVING COUNT(o.order_id) >= 30
ORDER BY orders_cnt DESC;

-- Task 5
SELECT
    product_name,
    unit_price,
    ROUND((SELECT AVG(unit_price) FROM products)::numeric, 2) AS avg_price
FROM products
WHERE unit_price > (SELECT AVG(unit_price) FROM products)
ORDER BY unit_price DESC;

-- Task 6
SELECT
    customer_id,
    company_name,
    country
FROM customers
WHERE customer_id IN (
    SELECT customer_id
    FROM orders
    WHERE order_id IN (
        SELECT order_id
        FROM order_details
        WHERE product_id = (
            SELECT product_id
            FROM products
            WHERE product_name = 'Chai'
        )
    )
)
ORDER BY company_name;

-- Task 7
SELECT
    c.customer_id,
    c.company_name,
    c.city,
    c.country
FROM customers AS c
WHERE NOT EXISTS (
    SELECT 1
    FROM orders AS o
    WHERE o.customer_id = c.customer_id
      AND EXTRACT(YEAR FROM o.order_date) = 1998
)
ORDER BY c.country, c.company_name;

-- Task 8
SELECT
    p.product_name,
    c.category_name,
    p.unit_price,
    ROUND((
        SELECT AVG(p2.unit_price)
        FROM products AS p2
        WHERE p2.category_id = p.category_id
    )::numeric, 2) AS category_avg
FROM products AS p
JOIN categories AS c
    ON c.category_id = p.category_id
WHERE p.unit_price > (
    SELECT AVG(p2.unit_price)
    FROM products AS p2
    WHERE p2.category_id = p.category_id
)
ORDER BY c.category_name, p.unit_price DESC;

-- Task 9
SELECT
    c.company_name,
    COUNT(ot.order_id) AS orders_cnt,
    ROUND(AVG(ot.order_total)::numeric, 2) AS avg_order_value,
    ROUND(MAX(ot.order_total)::numeric, 2) AS max_order_value
FROM customers AS c
JOIN orders AS o
    ON o.customer_id = c.customer_id
JOIN (
    SELECT
        order_id,
        SUM(unit_price * quantity * (1 - discount)) AS order_total
    FROM order_details
    GROUP BY order_id
) AS ot
    ON ot.order_id = o.order_id
GROUP BY c.customer_id, c.company_name
HAVING COUNT(ot.order_id) >= 15
ORDER BY avg_order_value DESC;

-- Task 10
SELECT
    e.first_name || ' ' || e.last_name AS employee,
    COUNT(o.order_id) AS orders_1997
FROM employees AS e
JOIN orders AS o
    ON o.employee_id = e.employee_id
WHERE EXTRACT(YEAR FROM o.order_date) = 1997
GROUP BY e.employee_id, e.first_name, e.last_name
HAVING COUNT(o.order_id) > (
    SELECT AVG(employee_orders)
    FROM (
        SELECT COUNT(*) AS employee_orders
        FROM orders
        WHERE EXTRACT(YEAR FROM order_date) = 1997
        GROUP BY employee_id
    ) AS employee_counts
)
ORDER BY orders_1997 DESC;
