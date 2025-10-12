----------------- ÜBERSICHT ÜBER KUNDENENTWICKLUNG - ANALYSEN ÜBER DIE ZEIT -----------------------------

-- Keine Kunden im November 2016. Grund ist eine neue Version der Plattform, weshalb Einträge pausiert wurden. Darum am Anfang vermutlich auch noch Monate mit 1 Kunden. 
-- Für diese Analyse daher Beginn ab 2017
SELECT *
FROM olist_orders_dataset ood 
WHERE ood.order_purchase_timestamp BETWEEN '2016-11-01' AND '2016-11-30';


---- ANALYSE VON MONATLICHEN KENNZAHLEN ÜBER DIE ZEIT ------------------------------------------------

-- Alle monatlichen Kennzahlen in einem View gespeichert
CREATE VIEW monthly_metrics AS
SELECT TO_CHAR(DATE_TRUNC('month', order_purchase_timestamp), 'YYYY-MM') AS order_month,
	   -- Anzahl einzigartiger Kunden
	   COUNT(DISTINCT(ocd.customer_unique_id)) AS num_of_unique_customers,
	   -- Umsatz
	   SUM(ooid.price + ooid.freight_value) AS revenue,
	   -- Anzahl Bestellungen
	   COUNT(DISTINCT(ood.order_id)) AS num_of_orders,
	   -- Durchschnittlicher Bestellwert
	   ROUND(CAST(SUM(ooid.price + ooid.freight_value) / COUNT(DISTINCT(ood.order_id))AS NUMERIC), 2) AS AOV,
	   -- Durchschnittlicher Umsatz pro Kunde
	   ROUND(CAST(SUM(ooid.price + ooid.freight_value) / COUNT(DISTINCT(ocd.customer_unique_id)) AS  NUMERIC),2) AS ARPC
FROM olist_order_items_dataset ooid 
LEFT JOIN olist_orders_dataset ood ON ooid.order_id = ood.order_id
LEFT JOIN olist_customers_dataset ocd ON ood.customer_id = ocd.customer_id
WHERE ood.order_status = 'delivered' AND order_purchase_timestamp >= '2017-01-01'
GROUP BY order_month;


---- ANALYSE BESTELLFREQUENZ PRO MONAT ------------------------------------------------------------

-- Gruppierung der Bestellungen nach Kunden und Bestellmonat
WITH monthly_customer_orders AS (
    SELECT
        ocd.customer_unique_id,
        TO_CHAR(DATE_TRUNC('month', ood.order_purchase_timestamp), 'YYYY-MM') AS order_month,
        COUNT(ood.order_id) AS purchase_count
    FROM olist_orders_dataset ood
    JOIN olist_customers_dataset ocd ON ood.customer_id = ocd.customer_id
    WHERE ood.order_status = 'delivered' AND order_purchase_timestamp >= '2017-01-01'
    GROUP BY customer_unique_id, order_month
)
-- Berechnung des Durchschnitts der Bestellanzahl pro Monat
SELECT order_month, AVG(purchase_count)
FROM monthly_customer_orders
GROUP BY order_month
ORDER BY order_month; 


---- ANALYSE NEUKUNDEN VS. BESTANDSKUNDEN ------------------------------------------------------------

---- Wieviele neue Kunden werden pro Monat gewonnen? Wieviel % der Kunden pro Monat sind Neukunden?

-- Numerierung der einzelnen Bestellungen pro Kunde
WITH customer_purchase_time AS(
	SELECT order_id, ocd.customer_unique_id, ood.order_purchase_timestamp, row_number() OVER(PARTITION BY ocd.customer_unique_id ORDER BY order_purchase_timestamp ASC) AS purchase_time
	FROM olist_orders_dataset ood
	JOIN olist_customers_dataset ocd ON ood.customer_id = ocd.customer_id
	WHERE ood.order_status = 'delivered' AND order_purchase_timestamp >= '2017-01-01'
),
-- Markierung der ersten Bestellung als 'new', bei allen weiteren Bestellungen ist er Bestandskunde
customer_type AS(	
	SELECT *,
		CASE WHEN purchase_time = 1 THEN 'new'
		ELSE 'existing'
		END AS customer_type
	FROM customer_purchase_time
)
-- Pro Monat: wieviele Kunden sind Neukunden, wie ist der Anteil an Neukunden von allen Kunden
SELECT TO_CHAR(DATE_TRUNC('month', order_purchase_timestamp), 'YYYY-MM') AS order_month,
	   COUNT(CASE WHEN customer_type = 'new' THEN 1 ELSE NULL END)  AS count_of_new_customers,
	   COUNT(DISTINCT(order_id)) AS order_count,
	   COUNT(DISTINCT(customer_unique_id)) AS total_customer_count,
	   ROUND(CAST(COUNT(DISTINCT(CASE WHEN purchase_time = 1 THEN customer_unique_id ELSE NULL END)) AS NUMERIC) 
	    / COUNT(DISTINCT(customer_unique_id)), 4) AS percentage_new_customers
FROM customer_type
GROUP BY order_month
ORDER BY order_month;


---- Wieviel Geld bringen Neukunden vs. Bestandskunden pro Monat?

-- Numerierung der einzelnen Bestellungen pro Kunde
WITH customer_purchase_time_value AS(
	SELECT ocd.customer_unique_id, 
		   order_purchase_timestamp, 
		   row_number() OVER(PARTITION BY ocd.customer_unique_id ORDER BY order_purchase_timestamp ASC) AS purchase_time,
	 	   ooid.price, ooid.freight_value 
	FROM olist_order_items_dataset ooid 
	LEFT JOIN olist_orders_dataset ood ON ooid.order_id = ood.order_id
	LEFT JOIN olist_customers_dataset ocd ON ood.customer_id = ocd.customer_id
	WHERE ood.order_status = 'delivered' AND order_purchase_timestamp >= '2017-01-01'
),
-- Markierung der ersten Bestellung als 'new', bei allen weiteren Bestellungen ist er Bestandskunde
customer_purchase_type_value AS(
	SELECT *,
		CASE WHEN purchase_time = 1 THEN 'new'
		ELSE 'existing'
		END AS customer_type
	FROM customer_purchase_time_value
)
-- Berechung des Umsatzes nach Kundentyp pro Monat
SELECT TO_CHAR(DATE_TRUNC('month', order_purchase_timestamp), 'YYYY-MM') AS order_month,
	   customer_type,
	   SUM(price + freight_value) AS revenue
FROM customer_purchase_type_value
GROUP BY order_month, customer_type
ORDER BY order_month;
