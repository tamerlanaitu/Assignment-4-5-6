\set AUTOCOMMIT on
\set ON_ERROR_STOP on
\set ON_ERROR_ROLLBACK off
\pset pager off
SET search_path TO public, pg_catalog;

DO $preconditions$
DECLARE
    collisions TEXT;
BEGIN
    SELECT string_agg(label, ', ')
    INTO collisions
    FROM unnest(ARRAY[
        'v_order_totals', 'v_uk_customers', 'mv_category_sales', 'orders_big',
        'idx_orders_big_customer', 'idx_orders_big_country_date',
        'idx_orders_big_heavy', 'idx_orders_big_city_lower'
    ]) AS reserved(label)
    WHERE to_regclass(format('public.%I', label)) IS NOT NULL;
    IF collisions IS NOT NULL THEN
        RAISE EXCEPTION 'Use an unused lab copy; occupied names: %', collisions;
    END IF;
    IF EXISTS (SELECT 1 FROM orders WHERE order_id = 11078)
       OR EXISTS (SELECT 1 FROM customers WHERE customer_id IN ('AITU1', 'AITU2'))
       OR EXISTS (SELECT 1 FROM products WHERE product_id = 999)
       OR EXISTS (SELECT 1 FROM order_details WHERE (order_id, product_id) = (10248, 1))
    THEN
        RAISE EXCEPTION 'An identifier reserved for this exercise is already in use';
    END IF;
    IF (SELECT COUNT(*) FROM products WHERE product_id IN (1, 11, 42)) <> 3
       OR NOT EXISTS (SELECT 1 FROM customers WHERE customer_id = 'AROUT' AND country = 'UK')
       OR NOT EXISTS (SELECT 1 FROM customers WHERE customer_id = 'ALFKI')
       OR NOT EXISTS (SELECT 1 FROM orders WHERE order_id = 10248)
       OR NOT EXISTS (SELECT 1 FROM employees WHERE employee_id = 1)
       OR NOT EXISTS (SELECT 1 FROM shippers WHERE shipper_id = 1)
    THEN
        RAISE EXCEPTION 'The exercise needs the standard Northwind reference rows';
    END IF;
    IF EXISTS (SELECT 1 FROM products WHERE units_in_stock < 0)
       OR NOT EXISTS (SELECT 1 FROM products WHERE product_id = 1 AND units_in_stock >= 10)
       OR NOT EXISTS (SELECT 1 FROM products WHERE product_id = 11 AND units_in_stock >= 5)
       OR NOT EXISTS (SELECT 1 FROM products WHERE product_id = 42 AND units_in_stock BETWEEN 1 AND 100)
    THEN
        RAISE EXCEPTION 'Stock preconditions for Tasks 12 and 13 do not hold';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM categories AS category
        JOIN products AS product ON product.category_id = category.category_id
        WHERE product.product_id = 1 AND category.category_name = 'Beverages'
    ) THEN
        RAISE EXCEPTION 'The refresh example assumes product 1 is a beverage';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.products'::REGCLASS AND conname = 'chk_units_in_stock'
    ) THEN
        RAISE EXCEPTION 'The exercise CHECK constraint must not exist beforehand';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE contype = 'f' AND conrelid = 'public.order_details'::REGCLASS
          AND confrelid = 'public.products'::REGCLASS AND NOT condeferrable
    ) THEN
        RAISE EXCEPTION 'The invalid item must encounter an immediate product FK';
    END IF;
END
$preconditions$;

CREATE TEMP TABLE a6_two_original_stock ON COMMIT PRESERVE ROWS AS
SELECT product_id, units_in_stock FROM products WHERE product_id IN (11, 42);
CREATE TEMP TABLE a6_two_original_contact ON COMMIT PRESERVE ROWS AS
SELECT customer_id, phone FROM customers WHERE customer_id = 'AROUT';

-- Task 1

WITH uk_contacts (contact_type, organization, person, city) AS (
    SELECT 'Customer', company_name, contact_name, city
    FROM customers
    WHERE country = 'UK'
    UNION ALL
    SELECT 'Supplier', company_name, contact_name, city
    FROM suppliers
    WHERE country = 'UK'
    UNION ALL
    SELECT 'Employee', 'Northwind Traders', first_name || ' ' || last_name, city
    FROM employees
    WHERE country = 'UK'
)
SELECT contact_type, organization, person, city
FROM uk_contacts
ORDER BY contact_type, city, person;

-- Task 2

SELECT country FROM suppliers
INTERSECT
SELECT country FROM customers
ORDER BY country;

SELECT country FROM customers
EXCEPT
SELECT country FROM suppliers
ORDER BY country;

SELECT city FROM suppliers
UNION
SELECT city FROM customers;

SELECT city FROM suppliers
UNION ALL
SELECT city FROM customers;

WITH distinct_places AS (
    SELECT city FROM suppliers UNION SELECT city FROM customers
), source_places AS (
    SELECT city FROM suppliers UNION ALL SELECT city FROM customers
)
SELECT '2c UNION' AS query, COUNT(*) AS result_rows FROM distinct_places
UNION ALL
SELECT '2d UNION ALL', COUNT(*) FROM source_places;

-- Task 3
SELECT client.customer_id, client.company_name, client.country, client.phone
FROM (
    SELECT customer_id
    FROM orders
    WHERE EXTRACT(YEAR FROM order_date) = 1997
    EXCEPT
    SELECT customer_id
    FROM orders
    WHERE EXTRACT(YEAR FROM order_date) = 1998
) AS lapsed
JOIN customers AS client ON client.customer_id = lapsed.customer_id
ORDER BY client.company_name;

-- Task 4
WITH dated_orders AS (
    SELECT EXTRACT(YEAR FROM order_date) AS yr,
           EXTRACT(QUARTER FROM order_date) AS qtr, freight
    FROM orders
)
SELECT yr AS order_year, qtr AS order_quarter, COUNT(*) AS orders_cnt,
       ROUND(SUM(freight)::NUMERIC, 2) AS total_freight
FROM dated_orders
GROUP BY ROLLUP (yr, qtr)
ORDER BY GROUPING(yr), yr NULLS LAST, GROUPING(qtr), qtr NULLS LAST;

WITH report AS (
    SELECT EXTRACT(YEAR FROM order_date), EXTRACT(QUARTER FROM order_date)
    FROM orders
    GROUP BY ROLLUP (EXTRACT(YEAR FROM order_date), EXTRACT(QUARTER FROM order_date))
)
SELECT COUNT(*) AS rollup_rows FROM report;

-- Task 5
WITH sale_lines AS (
    SELECT category.category_name, EXTRACT(YEAR FROM purchase.order_date) AS yr,
           item.unit_price::NUMERIC * item.quantity * (1 - item.discount::NUMERIC) AS line_revenue
    FROM orders AS purchase
    JOIN order_details AS item USING (order_id)
    JOIN products AS product USING (product_id)
    JOIN categories AS category USING (category_id)
), cube_report AS (
    SELECT category_name, yr, GROUPING(category_name) AS all_categories,
           GROUPING(yr) AS all_years, SUM(line_revenue) AS amount
    FROM sale_lines
    GROUP BY CUBE (category_name, yr)
)
SELECT CASE all_categories WHEN 1 THEN 'All categories' ELSE category_name END AS category,
       CASE all_years WHEN 1 THEN 'All years' ELSE yr::TEXT END AS order_year,
       ROUND(amount, 2) AS revenue
FROM cube_report
ORDER BY all_categories, category_name NULLS LAST, all_years, yr NULLS LAST;

-- Task 6
WITH catalog AS (
    SELECT category.category_name, vendor.country AS supplier_country, product.unit_price
    FROM products AS product
    LEFT JOIN categories AS category USING (category_id)
    LEFT JOIN suppliers AS vendor USING (supplier_id)
)
SELECT category_name, supplier_country, COUNT(*) AS products_cnt,
       ROUND(AVG(unit_price)::NUMERIC, 2) AS avg_price
FROM catalog
GROUP BY GROUPING SETS ((category_name), (supplier_country), ())
ORDER BY GROUPING(category_name), category_name NULLS LAST,
         GROUPING(supplier_country), supplier_country NULLS LAST;

-- Task 7

CREATE VIEW v_order_totals (order_id, customer_id, employee_id, order_date, order_total) AS
SELECT purchase.order_id, purchase.customer_id, purchase.employee_id, purchase.order_date,
       ROUND(COALESCE(total.amount, 0), 2)
FROM orders AS purchase
CROSS JOIN LATERAL (
    SELECT SUM(item.unit_price::NUMERIC * item.quantity * (1 - item.discount::NUMERIC)) AS amount
    FROM order_details AS item
    WHERE item.order_id = purchase.order_id
) AS total;

WITH customer_revenue AS (
    SELECT customer_id, COUNT(*) AS orders_1997, SUM(order_total) AS revenue_1997
    FROM v_order_totals
    WHERE EXTRACT(YEAR FROM order_date) = 1997
    GROUP BY customer_id
)
SELECT customer.company_name, summary.orders_1997, summary.revenue_1997
FROM customer_revenue AS summary
JOIN customers AS customer USING (customer_id)
ORDER BY summary.revenue_1997 DESC, customer.customer_id
FETCH FIRST 5 ROWS ONLY;

-- Task 8

CREATE VIEW v_uk_customers (customer_id, company_name, contact_name, city, country, phone) AS
SELECT customer_id, company_name, contact_name, city, country, phone
FROM customers
WHERE country = 'UK'
WITH CASCADED CHECK OPTION;

UPDATE v_uk_customers
SET phone = '(171) 555-0000'
WHERE customer_id = 'AROUT'
RETURNING customer_id, phone;
SELECT customer_id, phone FROM customers WHERE customer_id = 'AROUT';

INSERT INTO v_uk_customers (customer_id, company_name, city, country)
VALUES ('AITU1', 'AITU Test Ltd', 'London', 'UK');
\set ON_ERROR_STOP off

INSERT INTO v_uk_customers (customer_id, company_name, city, country)
VALUES ('AITU2', 'AITU Paris', 'Paris', 'France');
\set ON_ERROR_STOP on

\set ON_ERROR_STOP off

UPDATE v_uk_customers
SET country = 'Kazakhstan'
WHERE customer_id = 'AITU1';
\set ON_ERROR_STOP on
SELECT customer_id, country FROM v_uk_customers WHERE customer_id = 'AITU1';
SELECT COUNT(*) AS rejected_customer_rows FROM customers WHERE customer_id = 'AITU2';

-- Task 9

CREATE MATERIALIZED VIEW mv_category_sales AS
WITH facts AS (
    SELECT category.category_name, item.order_id, item.quantity,
           item.unit_price::NUMERIC * item.quantity * (1 - item.discount::NUMERIC) AS value
    FROM order_details AS item
    JOIN products AS product USING (product_id)
    JOIN categories AS category USING (category_id)
)
SELECT category_name, COUNT(DISTINCT order_id) AS orders_cnt,
       SUM(quantity) AS units_sold, ROUND(SUM(value), 2) AS revenue
FROM facts
GROUP BY category_name;
SELECT category_name, orders_cnt, units_sold, revenue
FROM mv_category_sales
ORDER BY revenue DESC, category_name;

BEGIN;
INSERT INTO order_details (order_id, product_id, unit_price, quantity, discount)
VALUES (10248, 1, 18, 100, 0);
SELECT units_sold AS beverage_units_before_refresh
FROM mv_category_sales WHERE category_name = 'Beverages';
REFRESH MATERIALIZED VIEW mv_category_sales;
SELECT units_sold AS beverage_units_after_refresh
FROM mv_category_sales WHERE category_name = 'Beverages';
ROLLBACK;
SELECT units_sold AS beverage_units_after_rollback
FROM mv_category_sales WHERE category_name = 'Beverages';

CREATE TABLE orders_big AS
SELECT g.n * 100000 + o.order_id AS order_id,
    o.customer_id, o.employee_id,
    o.order_date + (g.n % 365) AS order_date,
    o.ship_country, o.ship_city, o.freight
FROM orders o
CROSS JOIN generate_series(1, 1000) AS g(n);
ANALYZE orders_big;

-- Task 10

EXPLAIN ANALYZE
SELECT * FROM orders_big WHERE customer_id = 'ALFKI';

CREATE INDEX idx_orders_big_customer ON orders_big USING BTREE (customer_id);
EXPLAIN ANALYZE
SELECT * FROM orders_big WHERE customer_id = 'ALFKI';

EXPLAIN ANALYZE
SELECT * FROM orders_big WHERE customer_id >= 'B';
SELECT COUNT(*) AS table_rows,
       COUNT(CASE WHEN customer_id >= 'B' THEN 1 END) AS qualifying_rows,
       ROUND(COUNT(CASE WHEN customer_id >= 'B' THEN 1 END)::NUMERIC
             / NULLIF(COUNT(*), 0), 6) AS matching_fraction,
       ROUND(100 * COUNT(CASE WHEN customer_id >= 'B' THEN 1 END)::NUMERIC
             / NULLIF(COUNT(*), 0), 2) AS matching_percent
FROM orders_big;

-- Task 11

EXPLAIN ANALYZE
SELECT * FROM orders_big
WHERE ship_country = 'Germany'
  AND order_date BETWEEN DATE '1997-01-01' AND DATE '1997-01-31';
CREATE INDEX idx_orders_big_country_date ON orders_big USING BTREE (ship_country, order_date);
EXPLAIN ANALYZE
SELECT * FROM orders_big
WHERE ship_country = 'Germany'
  AND order_date BETWEEN DATE '1997-01-01' AND DATE '1997-01-31';
EXPLAIN ANALYZE
SELECT * FROM orders_big
WHERE order_date BETWEEN DATE '1997-01-01' AND DATE '1997-01-31';

EXPLAIN ANALYZE SELECT * FROM orders_big WHERE freight > 500;
CREATE INDEX idx_orders_big_heavy ON orders_big USING BTREE (freight) WHERE freight > 500;
EXPLAIN ANALYZE SELECT * FROM orders_big WHERE freight > 500;

EXPLAIN ANALYZE SELECT * FROM orders_big WHERE LOWER(ship_city) = 'london';
CREATE INDEX idx_orders_big_city_lower ON orders_big USING BTREE (LOWER(ship_city));
ANALYZE orders_big;
EXPLAIN ANALYZE SELECT * FROM orders_big WHERE LOWER(ship_city) = 'london';

SELECT listed.indexname, pg_size_pretty(pg_relation_size(index_relation.oid)) AS index_size
FROM pg_indexes AS listed
JOIN pg_namespace AS namespace ON namespace.nspname = listed.schemaname
JOIN pg_class AS index_relation
  ON index_relation.relnamespace = namespace.oid AND index_relation.relname = listed.indexname
WHERE listed.schemaname = 'public' AND listed.tablename = 'orders_big'
ORDER BY pg_relation_size(index_relation.oid) DESC, listed.indexname;
SELECT pg_size_pretty(pg_relation_size('public.orders_big'::REGCLASS)) AS heap_size,
       pg_size_pretty(pg_total_relation_size('public.orders_big'::REGCLASS)) AS complete_size;

-- Task 12
SELECT product_id, units_in_stock AS starting_stock
FROM products WHERE product_id IN (11, 42) ORDER BY product_id;

BEGIN;
INSERT INTO orders (order_id, customer_id, employee_id, order_date, required_date,
                    ship_via, freight, ship_country)
VALUES (11078, 'ALFKI', 1, DATE '1998-05-07', DATE '1998-06-04', 1, 25.00, 'Germany');
INSERT INTO order_details (order_id, product_id, unit_price, quantity, discount)
VALUES (11078, 11, 21.00, 5, 0);
UPDATE products SET units_in_stock = units_in_stock - 5 WHERE product_id = 11;
\set ON_ERROR_STOP off

INSERT INTO order_details (order_id, product_id, unit_price, quantity, discount)
VALUES (11078, 999, 10.00, 1, 0);

UPDATE products SET units_in_stock = units_in_stock - 1 WHERE product_id = 42;
COMMIT;
\set ON_ERROR_STOP on
SELECT COUNT(*) AS orders_left_after_failure FROM orders WHERE order_id = 11078;
SELECT product_id, units_in_stock FROM products WHERE product_id = 11;
DO $atomicity_check$
BEGIN
    IF EXISTS (SELECT 1 FROM orders WHERE order_id = 11078)
       OR EXISTS (
           SELECT 1 FROM a6_two_original_stock AS original
           JOIN products AS current_row USING (product_id)
           WHERE current_row.units_in_stock IS DISTINCT FROM original.units_in_stock
       ) THEN
        RAISE EXCEPTION 'Atomicity observation differs from expectation; inspect before continuing';
    END IF;
END
$atomicity_check$;

BEGIN;
INSERT INTO orders (order_id, customer_id, employee_id, order_date, required_date,
                    ship_via, freight, ship_country)
VALUES (11078, 'ALFKI', 1, DATE '1998-05-07', DATE '1998-06-04', 1, 25.00, 'Germany');
INSERT INTO order_details (order_id, product_id, unit_price, quantity, discount)
VALUES (11078, 11, 21.00, 5, 0);
UPDATE products SET units_in_stock = units_in_stock - 5 WHERE product_id = 11;
SAVEPOINT before_second_item;
\set ON_ERROR_STOP off

INSERT INTO order_details (order_id, product_id, unit_price, quantity, discount)
VALUES (11078, 999, 10.00, 1, 0);
ROLLBACK TO SAVEPOINT before_second_item;
\set ON_ERROR_STOP on
INSERT INTO order_details (order_id, product_id, unit_price, quantity, discount)
VALUES (11078, 42, 14.00, 1, 0);
UPDATE products SET units_in_stock = units_in_stock - 1 WHERE product_id = 42;
COMMIT;
SELECT order_id, product_id, unit_price, quantity, discount
FROM order_details WHERE order_id = 11078 ORDER BY product_id;
SELECT current_row.product_id, original.units_in_stock AS initial_stock,
       current_row.units_in_stock AS committed_stock
FROM products AS current_row
JOIN a6_two_original_stock AS original USING (product_id)
ORDER BY current_row.product_id;

-- Task 13
ALTER TABLE products
ADD CONSTRAINT chk_units_in_stock CHECK (units_in_stock >= 0);
BEGIN;
\set ON_ERROR_STOP off

UPDATE products SET units_in_stock = units_in_stock - 100 WHERE product_id = 42;
ROLLBACK;
\set ON_ERROR_STOP on
SELECT product_id, units_in_stock FROM products WHERE product_id = 42;

BEGIN;
DELETE FROM order_details WHERE order_id = 11078;
DELETE FROM orders WHERE order_id = 11078;
UPDATE products AS product
SET units_in_stock = original.units_in_stock
FROM a6_two_original_stock AS original
WHERE product.product_id = original.product_id;
UPDATE customers AS customer
SET phone = original.phone
FROM a6_two_original_contact AS original
WHERE customer.customer_id = original.customer_id;
DELETE FROM customers WHERE customer_id = 'AITU1';
ALTER TABLE products DROP CONSTRAINT chk_units_in_stock;
DROP MATERIALIZED VIEW mv_category_sales;
DROP VIEW v_order_totals, v_uk_customers;
DROP TABLE orders_big;
COMMIT;
DROP TABLE a6_two_original_stock, a6_two_original_contact;
