-- Assignment 5. Window Functions

-- Task 1
SELECT
    c.category_name,
    p.product_name,
    p.unit_price,
    ROW_NUMBER() OVER (
        PARTITION BY p.category_id
        ORDER BY p.unit_price DESC, p.product_name
    ) AS price_position
FROM products AS p
JOIN categories AS c
    ON c.category_id = p.category_id
ORDER BY c.category_name, price_position;

-- Task 2
-- The result contains more than 15 rows because products with the same price
-- receive the same DENSE_RANK, so one dense rank can contain several products.
-- price_rank jumps from 11 to 13 because two products share rank 11;
-- RANK leaves a gap after tied rows, while DENSE_RANK does not.
SELECT
    product_name,
    unit_price,
    price_rank,
    price_dense_rank
FROM (
    SELECT
        product_name,
        unit_price,
        RANK() OVER (ORDER BY unit_price DESC) AS price_rank,
        DENSE_RANK() OVER (ORDER BY unit_price DESC) AS price_dense_rank
    FROM products
) AS ranked_products
WHERE price_dense_rank <= 15
ORDER BY price_rank, product_name;

-- Task 3
SELECT
    category_name,
    product_name,
    units_sold,
    position
FROM (
    SELECT
        c.category_name,
        p.product_name,
        SUM(od.quantity) AS units_sold,
        ROW_NUMBER() OVER (
            PARTITION BY c.category_id
            ORDER BY SUM(od.quantity) DESC, p.product_name
        ) AS position
    FROM products AS p
    JOIN categories AS c
        ON c.category_id = p.category_id
    JOIN order_details AS od
        ON od.product_id = p.product_id
    GROUP BY
        c.category_id,
        c.category_name,
        p.product_id,
        p.product_name
) AS product_sales
WHERE position <= 3
ORDER BY category_name, position;

-- Task 4
SELECT
    p.product_name,
    c.category_name,
    p.unit_price,
    COUNT(*) OVER (
        PARTITION BY p.category_id
    ) AS products_in_category,
    ROUND((
        AVG(p.unit_price) OVER (
            PARTITION BY p.category_id
        )
    )::numeric, 2) AS category_avg,
    ROUND((
        p.unit_price - AVG(p.unit_price) OVER (
            PARTITION BY p.category_id
        )
    )::numeric, 2) AS diff_from_avg
FROM products AS p
JOIN categories AS c
    ON c.category_id = p.category_id
ORDER BY c.category_name, diff_from_avg DESC;

-- Task 5
SELECT
    TO_CHAR(DATE_TRUNC('month', o.order_date), 'YYYY-MM') AS month,
    ROUND(SUM(
        od.unit_price * od.quantity * (1 - od.discount)
    )::numeric, 2) AS revenue,
    ROUND((
        SUM(SUM(
            od.unit_price * od.quantity * (1 - od.discount)
        )) OVER (
            ORDER BY DATE_TRUNC('month', o.order_date)
        )
    )::numeric, 2) AS running_total
FROM orders AS o
JOIN order_details AS od
    ON od.order_id = o.order_id
WHERE EXTRACT(YEAR FROM o.order_date) = 1997
GROUP BY DATE_TRUNC('month', o.order_date)
ORDER BY month;

-- Task 6
SELECT
    e.first_name || ' ' || e.last_name AS employee,
    ROUND(SUM(
        od.unit_price * od.quantity * (1 - od.discount)
    )::numeric, 2) AS revenue_1997,
    ROUND((
        100 * SUM(
            od.unit_price * od.quantity * (1 - od.discount)
        ) / SUM(SUM(
            od.unit_price * od.quantity * (1 - od.discount)
        )) OVER ()
    )::numeric, 1) AS share_pct,
    RANK() OVER (
        ORDER BY SUM(
            od.unit_price * od.quantity * (1 - od.discount)
        ) DESC
    ) AS revenue_rank
FROM employees AS e
JOIN orders AS o
    ON o.employee_id = e.employee_id
JOIN order_details AS od
    ON od.order_id = o.order_id
WHERE EXTRACT(YEAR FROM o.order_date) = 1997
GROUP BY e.employee_id, e.first_name, e.last_name
ORDER BY revenue_rank;

-- Task 7
SELECT
    TO_CHAR(DATE_TRUNC('month', order_date), 'YYYY-MM') AS month,
    COUNT(*) AS orders_cnt,
    LAG(COUNT(*)) OVER (
        ORDER BY DATE_TRUNC('month', order_date)
    ) AS prev_orders,
    COUNT(*) - LAG(COUNT(*)) OVER (
        ORDER BY DATE_TRUNC('month', order_date)
    ) AS change
FROM orders
WHERE EXTRACT(YEAR FROM order_date) = 1997
GROUP BY DATE_TRUNC('month', order_date)
ORDER BY month;

-- Task 8
SELECT
    c.company_name,
    o.order_id,
    o.order_date,
    ROW_NUMBER() OVER (
        PARTITION BY c.customer_id
        ORDER BY o.order_date, o.order_id
    ) AS order_number,
    o.order_date - LAG(o.order_date) OVER (
        PARTITION BY c.customer_id
        ORDER BY o.order_date, o.order_id
    ) AS days_since_prev
FROM customers AS c
JOIN orders AS o
    ON o.customer_id = c.customer_id
WHERE c.country = 'Mexico'
ORDER BY c.company_name, order_number;

-- Task 9
-- For the first month, moving_avg_3m equals that month's revenue because
-- there are no preceding rows. For the second month, it is the average of
-- the first two months. The frame uses all available rows up to three months.
SELECT
    TO_CHAR(month_start, 'YYYY-MM') AS month,
    ROUND(revenue::numeric, 2) AS revenue,
    ROUND((
        AVG(revenue) OVER (
            ORDER BY month_start
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        )
    )::numeric, 2) AS moving_avg_3m
FROM (
    SELECT
        DATE_TRUNC('month', o.order_date) AS month_start,
        SUM(
            od.unit_price * od.quantity * (1 - od.discount)
        ) AS revenue
    FROM orders AS o
    JOIN order_details AS od
        ON od.order_id = o.order_id
    GROUP BY DATE_TRUNC('month', o.order_date)
) AS monthly_revenue
ORDER BY month_start;

-- Task 10
SELECT
    company_name,
    country,
    revenue,
    revenue_quartile,
    best_in_country,
    pct_of_country
FROM (
    SELECT
        c.company_name,
        c.country,
        ROUND(SUM(
            od.unit_price * od.quantity * (1 - od.discount)
        )::numeric, 2) AS revenue,
        NTILE(4) OVER (
            ORDER BY SUM(
                od.unit_price * od.quantity * (1 - od.discount)
            ) DESC, c.company_name
        ) AS revenue_quartile,
        FIRST_VALUE(c.company_name) OVER (
            PARTITION BY c.country
            ORDER BY SUM(
                od.unit_price * od.quantity * (1 - od.discount)
            ) DESC, c.company_name
        ) AS best_in_country,
        ROUND((
            100 * SUM(
                od.unit_price * od.quantity * (1 - od.discount)
            ) / SUM(SUM(
                od.unit_price * od.quantity * (1 - od.discount)
            )) OVER (
                PARTITION BY c.country
            )
        )::numeric, 1) AS pct_of_country
    FROM customers AS c
    JOIN orders AS o
        ON o.customer_id = c.customer_id
    JOIN order_details AS od
        ON od.order_id = o.order_id
    GROUP BY c.customer_id, c.company_name, c.country
) AS customer_revenue
WHERE revenue_quartile = 1
ORDER BY revenue DESC;
