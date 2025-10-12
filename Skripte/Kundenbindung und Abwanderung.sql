----------------- KUNDENBINDUNG UND CHURN -------------------------------------------------------------------------------------


---- RETENTION NACH KOHORTE ÜBER DIE VERGANGENEN QUARTALE: WIEVIEL % SIND NOCH AKTIV? --------------------------------

-- Zahl aktiver Kunden gruppiert nach Kohorte und vergangenem Quartal
WITH cohort_activity AS(
	SELECT customer_cohort, 
		   cohort_period_quarter,
     	   COUNT(DISTINCT customer_unique_id) AS retained_customers_count
	FROM customers_all_orders
	GROUP BY customer_cohort, cohort_period_quarter
),
-- Größe der Kohorte zur Berechnung des Anteils
cohort_size AS (
    SELECT customer_cohort,
           COUNT(DISTINCT customer_unique_id) AS initial_cohort_size
    FROM  customers_all_orders
    WHERE cohort_period_quarter = 0
    GROUP BY customer_cohort
)
-- absolut wiedergekommene Kunden und Anteil der Anfangsgröße der Kohorte retained
SELECT ca.customer_cohort,
	   ca.cohort_period_quarter,
		CAST(retained_customers_count AS NUMERIC) / initial_cohort_size AS retained_percentage
	FROM cohort_activity ca
	JOIN cohort_size cs ON ca.customer_cohort = cs.customer_cohort;


---- WIEVIEL % PRO KOHORTE SIND ÜBERHAUPT ZURÜCKGEKOMMEN? (EGAL WIE OFT) ---------------------------------------

-- Größe der Kohorte zur Berechnung des Anteils
WITH cohort_size AS (
    SELECT customer_cohort,
           COUNT(DISTINCT customer_unique_id) AS initial_cohort_size
    FROM customers_all_orders
    WHERE order_purchase_timestamp = first_order_date
    GROUP BY customer_cohort
),
-- Anzahl an aktiver Kunden in Quartalen nach dem ersten Bestellquartal
retained_anytime AS (
    SELECT customer_cohort,
           COUNT(DISTINCT customer_unique_id) AS retained_anytime_count
    FROM customers_all_orders
    WHERE order_quarter <> customer_cohort
    GROUP BY customer_cohort
)
-- Berechnung des Anteils rückgekehrter Kunden
SELECT retained_anytime.customer_cohort,
       initial_cohort_size,
       retained_anytime_count,
       CAST(retained_anytime_count AS NUMERIC) / initial_cohort_size AS retained_anytime_percentage
FROM cohort_size 
LEFT JOIN retained_anytime
       ON cohort_size.customer_cohort = retained_anytime.customer_cohort
ORDER BY customer_cohort;


---- KLASSIFIZIERUNG VON KUNDEN ALS AKTIV, AT RISK ODER CHURNED --------------------------------------------------

-- Nummerierung der abgegebenen Bestellung absteigend (letzte Bestellung = 1)
WITH customer_order_count AS(
	SELECT customer_unique_id,
		   order_purchase_timestamp,
		   first_order_date,
		   Row_Number() OVER(PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp DESC) AS order_count
	FROM customers_all_orders
),
-- Auswahl der letzten Bestellung
customer_last_order AS(	
	SELECT 	customer_unique_id, 
			first_order_date,
			order_purchase_timestamp AS last_order_date
	FROM customer_order_count
	WHERE order_count = 1
),
-- Klassifizierung der Kunden in Gruppen je nachdem wie lange die letzte Bestellung zurückliegt
customer_current_states AS(
	SELECT *,
		  CASE WHEN last_order_date >= (SELECT MAX(order_purchase_timestamp) FROM olist_orders_dataset) - INTERVAL '3 months' THEN 'active'
	  		   WHEN last_order_date >= (SELECT MAX(order_purchase_timestamp) FROM olist_orders_dataset) - INTERVAL '6 months' THEN 'at risk'
	  		   ELSE 'churned'
		  END AS customer_status
	FROM customer_last_order
)
-- Analyse wieviel % jede aktuell Gruppe ausmacht 
SELECT customer_status,
	   COUNT(customer_status) AS customer_count,
	   CAST(COUNT(customer_status) AS NUMERIC) / (SELECT COUNT(customer_unique_id) FROM olist_customers_dataset ocd) AS customer_percentage
FROM customer_current_states
GROUP BY customer_status;


---- WIEVIELE TAGE VERGEHEN IM SCHNITT BIS ZUR ZWEITEN BESTELLUNG? ----------------------------------------------------

-- Berechnung vergangener Tage
WITH days_since AS(
	SELECT *,
		CAST(
            EXTRACT(EPOCH FROM (order_purchase_timestamp - MIN(order_purchase_timestamp) OVER (PARTITION BY customer_unique_id))) / 86400 
        AS INTEGER) AS days_since_first_order,
        ROW_NUMBER() OVER(PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp) AS order_rank
	FROM customers_all_orders
)
-- Minimun, Mittelwert und Maximum, nur Beachtung der zweiten Bestellung, Bestellungen am gleichen Tag ausgenommen
SELECT MIN(days_since_first_order), AVG(days_since_first_order), MAX(days_since_first_order)
FROM days_since 
WHERE order_rank = 2 AND days_since_first_order > 0;



----------------- KOHORTENANALYSE ------------------------------------------------------------------------


---- VORBEREITEND: VIEW MIT ALLEN KÄUFEN PRO KUNDE UND KOHORTENINFORMATIONEN (auch im weiteren genutzt) --
CREATE OR REPLACE VIEW customers_all_orders AS
SELECT ood.customer_id,
	   ocd.customer_unique_id,
	   ood.order_purchase_timestamp,
	   ooid.price + ooid.freight_value AS price_all,
	   -- Quartal der aktuellen Bestellung
	   TO_CHAR(DATE_TRUNC('quarter', ood.order_purchase_timestamp), 'YYYY-Q') AS order_quarter,
	   -- Quartal der ersten Bestellung: Kundenkohorte
	   TO_CHAR(DATE_TRUNC('quarter', 
	   					  	MIN(ood.order_purchase_timestamp) OVER (PARTITION BY ocd.customer_unique_id)
	   		), 'YYYY-Q'
	   	) AS customer_cohort,
	   -- Datum der ersten Bestellung	
	   MIN(ood.order_purchase_timestamp) OVER(PARTITION BY ocd.customer_unique_id) AS first_order_date,
	   -- wieviele Quartale sind seit der ersten Bestellung vergangen?
	   CAST(
           ((EXTRACT(YEAR FROM ood.order_purchase_timestamp) * 4 + EXTRACT(QUARTER FROM ood.order_purchase_timestamp)) -
               (EXTRACT(YEAR FROM MIN(ood.order_purchase_timestamp) OVER (PARTITION BY ocd.customer_unique_id)) * 4 + 
                EXTRACT(QUARTER FROM MIN(ood.order_purchase_timestamp) OVER (PARTITION BY ocd.customer_unique_id)))
           ) AS INTEGER) AS cohort_period_quarter
FROM olist_orders_dataset ood
JOIN olist_customers_dataset ocd  ON ood.customer_id = ocd.customer_id 
JOIN olist_order_items_dataset ooid ON ood.order_id = ooid.order_id
WHERE ood.order_status = 'delivered' AND ood.order_purchase_timestamp >= '2017-01-01'
ORDER BY ocd.customer_unique_id, order_quarter;


--- WIEVIEL UMSATZ ERWIRTSCHAFTET JEDE KOHORTE ÜBER DIE ZEIT? ----------------------------------------
SELECT customer_cohort, 
       cohort_period_quarter,
       SUM(price_all) AS revenue
FROM customers_all_orders
GROUP BY customer_cohort, cohort_period_quarter
ORDER BY customer_cohort, cohort_period_quarter;


---- WIEVIEL UMSATZ WIRD IN DEN QUARTALEN NACH DER ERSTEN BESTELLUNG ERWIRTSCHAFTET? -------------------
WITH sum_all AS(
SELECT sum(price_all) AS total_revenue
FROM customers_all_orders
)
SELECT cohort_period_quarter,
       SUM(price_all) AS revenue,
       SUM(price_all) / total_revenue AS percentage
FROM customers_all_orders
CROSS JOIN sum_all
GROUP BY cohort_period_quarter, total_revenue
ORDER BY cohort_period_quarter;


---- UMSATZ, KUNDENANZAHL UND CUSTOMER REVENUE PRO KOHORTE, ANGEPASST AUF ZEIT IM MARKT --------
SELECT customer_cohort, 
	   SUM(price_all) AS total_revenue,
	   COUNT(DISTINCT(customer_unique_id)) AS total_customers,
	   SUM(price_all)/ COUNT(DISTINCT(customer_unique_id)) AS customer_revenue
FROM customers_all_orders
WHERE cohort_period_quarter = 0
GROUP BY customer_cohort
ORDER BY customer_cohort;
