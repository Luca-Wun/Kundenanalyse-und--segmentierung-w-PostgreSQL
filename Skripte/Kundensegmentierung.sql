----------------- KUNDENSEGMENTIERUNG NACH RFM ----------------------------------------------------------------


---- ANALYSE DER RECENCY: WANN WAR DIE LETZTE BESTELLUNG? -------------------------------------

-- Nummerierung der Bestellungen pro Kunde absteigend (letzte Bestellung = 1)
CREATE OR REPLACE VIEW customer_recency AS
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
-- Wieviele Tage sind seit der letzten Bestellung vergangen?
-- jeder Kunde ist seit mindestens 52 Tagen inaktiv, da die letzten 26 Bestellungen gecancelet wurden
customers_last_active AS(	
	SELECT customer_unique_id,
		   first_order_date,
		   last_order_date,
		   CAST(
	         EXTRACT(EPOCH FROM ((SELECT MAX(order_purchase_timestamp) FROM olist_orders_dataset)  - last_order_date)) / 86400 
	   	    AS INTEGER) AS days_inactive
	FROM customer_last_order
),
-- Berechnung der Quartile der Anzahl vergangener Tage, um Kunden in Gruppen zu segmentieren
recency_quartiles AS (
	SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY days_inactive) AS q1_threshold,
           PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY days_inactive) AS q3_threshold,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_inactive) AS q2_threshold
    FROM customers_last_active
)
-- Segmentierung der Kunden anhand der Quartile mit Wert und Textbeschreibung
SELECT customer_unique_id,
	   last_order_date, 
	   days_inactive,
	   CASE	WHEN days_inactive > q3_threshold THEN 'lowest R'
	   		WHEN days_inactive <= q3_threshold AND days_inactive > q2_threshold THEN 'low R'
	   		WHEN days_inactive < q1_threshold THEN 'highest R'
	   		ELSE 'high R'
	   END AS Recency_Text,
	   CASE	WHEN days_inactive > q3_threshold THEN 1
	   		WHEN days_inactive <= q3_threshold AND days_inactive > q2_threshold THEN 2
	   		WHEN days_inactive < q1_threshold THEN 4
	   		ELSE 3
	   END AS Recency_Value
FROM customers_last_active
CROSS JOIN recency_quartiles;


---- ANALYSE DER FREQUENCY: WIE HÄUFIG BESTELLEN DIE KUNDEN -------------------------------------

-- Zählen der Bestellfrequenz nach der Kunden
CREATE VIEW customer_RF AS 
WITH customer_purchase_count AS(
	SELECT ocd.customer_unique_id,
		   COUNT(ood.order_id) AS purchase_frequency
	FROM olist_customers_dataset ocd
	JOIN olist_orders_dataset ood ON ocd.customer_id = ood.customer_id
	WHERE order_status = 'delivered'
	GROUP BY ocd.customer_unique_id
)
-- Einteilung in Quartile funktioniert hier nicht gut, da die Verteilung zu konzentriert ist
-- Daher Segmentierung nach konkreter Kaufanzahl
SELECT cpc.customer_unique_id,
	   days_inactive,
	   recency_text,
	   recency_value,
	   purchase_frequency,
	   CASE WHEN purchase_frequency > 3 THEN 'highest F'
	  		WHEN purchase_frequency = 3 THEN 'high F'
	  		WHEN purchase_frequency = 2 THEN 'low F'
	  		WHEN purchase_frequency = 1 THEN 'lowest F'
	  	END AS frequency_text,
	  	CASE WHEN purchase_frequency > 3 THEN 4
	  		WHEN purchase_frequency = 3 THEN 3
	  		WHEN purchase_frequency = 2 THEN 2
	  		WHEN purchase_frequency = 1 THEN 1
	  	END AS frequency_value
FROM customer_purchase_count cpc
JOIN customer_recency cr ON cr.customer_unique_id = cpc.customer_unique_id;


---- Wieviele Kunden kaufen wie häufig? Wie ist der Anteil?

-- Zählen der Bestellfrequenz nach der Kunden
WITH purchase_per_customer AS(
	SELECT customer_unique_id, 
		   COUNT(*) AS purchase_count
	FROM olist_customers_dataset ocd
	JOIN olist_orders_dataset ood ON ood.customer_id = ocd.customer_id
	WHERE order_status = 'delivered'
	GROUP BY ocd.customer_unique_id
),
-- absolute Kundenanzahl
total_customers AS(
	SELECT COUNT(customer_unique_id) AS total_count
	FROM purchase_per_customer 
)
-- Anzahl Kunden pro Bestellfrequenz und Anteil an Gesamtkunden
SELECT purchase_count, 
	   COUNT(*) AS number_of_purchase_count,
	   CAST(COUNT(*) AS NUMERIC)/ total_count  AS percent_of_purchase_count
FROM purchase_per_customer
CROSS JOIN total_customers
GROUP BY purchase_count, total_count
ORDER BY purchase_count;


---- ANALYSE DES MONETARY VALUE: WIEVIEL UMSATZ GENERIEREN DIE KUNDEN -----------------------------

-- Berechnung des LTV pro Kunden
CREATE VIEW customer_RFM AS
WITH customer_ltv AS(
	SELECT customer_unique_id,
		   SUM(price_all) AS customer_LTV
	FROM customers_all_orders
	GROUP BY customer_unique_id
),
-- Berechnung der Quartile des LTV, um Kunden in Gruppen zu segmentieren
monetary_quartiles AS(
	SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY customer_LTV) AS q1_threshold,
    	   PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY customer_LTV) AS q3_threshold,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY customer_LTV) AS q2_threshold
	FROM customer_ltv
),
-- Segmentierung der Kunden nach ihrem LTV, als Wert und als Text
customer_RFM AS(
	SELECT cl.customer_unique_id,
		   days_inactive,
		   recency_text,
		   recency_value,
		   purchase_frequency,
		   frequency_text,
		   frequency_value,
		   customer_LTV,
		   CASE	WHEN customer_LTV > q3_threshold THEN 'highest M'
		   		WHEN customer_LTV <= q3_threshold AND customer_LTV > q2_threshold THEN 'high M'
		   		WHEN customer_LTV < q1_threshold THEN 'lowest M'
		   		ELSE 'low M'
		   END AS Monetary_Text,
		   CASE	WHEN customer_LTV > q3_threshold THEN 4
		   		WHEN customer_LTV <= q3_threshold AND customer_LTV > q2_threshold THEN 3
		   		WHEN customer_LTV < q1_threshold THEN 1
		   		ELSE 2
		   END AS monetary_value
	FROM customer_ltv cl
	JOIN customer_rf crf ON cl.customer_unique_id = crf.customer_unique_id 
	CROSS JOIN monetary_quartiles
)
-- Generierung eines Gesamtscores aus allen drei Werten
SELECT *,
	  	ROUND((CAST(recency_value AS NUMERIC) + 
        CAST(frequency_value AS NUMERIC) + 
        CAST(monetary_value AS NUMERIC)) / 3.0, 2) AS overall_score
FROM customer_RFM;

-- Analyse der Anteile am Umsatz nach Segmenten im Monetary Value
SELECT monetary_text,
	   SUM(customer_ltv),
	   AVG(customer_ltv),
	   COUNT(*) AS num_of_customers
FROM customer_rfm cr 
GROUP BY cr.monetary_text;

-- Der höchste Score macht 60% des Umsatzes aus. Gibt es bei diesen Kunden nochmal eine starke Konzentration auf "Whales"?
SELECT customer_unique_id,
	   customer_ltv,
	   100*(SUM(customer_ltv) OVER (ORDER BY customer_ltv DESC) / SUM(customer_ltv) OVER()) AS percentage_cumulative
FROM customer_rfm
ORDER BY customer_ltv DESC;


---- ANALYSE DES GESAMTSCORES -----------------------------------------------------------------

SELECT overall_score,
	   COUNT(overall_score),
	   CAST(COUNT(overall_score) AS NUMERIC) / (SELECT COUNT(*) FROM customer_rfm) AS percentage
FROM customer_rfm
GROUP BY overall_score
ORDER BY overall_score DESC;



------ WEITERE ANALYSE DER KUNDENSEGMENTE -----------------------------------------------------


---- UNTERSCHEIDEN SICH KUNDENSEGMENTE IN GEKAUFTEN PRODUKTKATEGORIEN? ------------------

-- Bestellhäufigkeit und Umsatz nach Kategorie bei allen Kunden
SELECT product_category_name,
	   COUNT(product_category_name) AS count,
	   SUM(price + freight_value) AS revenue
FROM olist_order_items_dataset ooid
JOIN olist_products_dataset opd ON ooid.product_id = opd.product_id
GROUP BY product_category_name
ORDER BY count DESC;

-- Erstellen einer Faktentabelle um den Join nicht jedesmal zu wiederholen
CREATE TABLE customer_product_facts AS
SELECT ocd.customer_id, 
	   ocd.customer_unique_id, 
	   ood.order_id, 
	   ooid.price, 
	   ooid.freight_value, 
	   opd.product_category_name
FROM olist_order_items_dataset ooid
JOIN olist_products_dataset opd ON ooid.product_id = opd.product_id
JOIN olist_orders_dataset ood ON ooid.order_id = ood.order_id 
JOIN olist_customers_dataset ocd ON ocd.customer_id = ood.customer_id;

-- Bestellhäufigkeit und Umsatz nach Kategorie bei den profitabelsten Kunden
SELECT product_category_name,
	   COUNT(product_category_name) AS count,
	   SUM(price + freight_value) AS revenue
FROM customer_product_facts cpf
JOIN customer_rfm cr  ON cr.customer_unique_id = cpf.customer_unique_id
WHERE cr.monetary_text = 'highest M'
GROUP BY product_category_name
ORDER BY count DESC;

-- Bestellhäufigkeit und Umsatz nach Kategorie bei den häufigsten Kunden
SELECT product_category_name,
	   COUNT(product_category_name) AS count,
	   SUM(price + freight_value) AS revenue
FROM customer_product_facts cpf
JOIN customer_rfm cr  ON cr.customer_unique_id = cpf.customer_unique_id
WHERE cr.frequency_text = 'highest F'
GROUP BY product_category_name
ORDER BY count DESC;


---- UNTERSCHEIDEN SICH KUNDENSEGMENTE IN REGIONALER HERKUNFT -----------------------------

-- Aus welchen Staaten kommen die Kunden insgesamt (nach Location des ersten Einkaufs)?

-- Numerierung der Bestellungen
WITH customers_row_num AS(
	SELECT customer_unique_id, customer_state,
	row_number() OVER (PARTITION BY customer_unique_id) AS purchase_count
	FROM olist_customers_dataset
)
-- Anzahl der Herkunft nach der ersten Bestellung
SELECT customer_state, COUNT(*)
FROM customers_row_num
WHERE purchase_count = 1
GROUP BY customer_state
ORDER BY COUNT(*) DESC;

-- Aus welchen Staaten kommen die profitabelsten Kunden?
SELECT ogd.geolocation_state,
	   COUNT(geolocation_state)
FROM olist_customers_dataset ocd 
JOIN olist_geolocation_dataset ogd ON ocd.customer_zip_code_prefix = ogd.geolocation_zip_code_prefix
JOIN customer_rfm cr ON cr.customer_unique_id = ocd.customer_unique_id
WHERE cr.monetary_text = 'highest M'
GROUP BY geolocation_state 
ORDER BY count DESC;

-- Aus welchen Staaten kommen die häufisten Kunden?
SELECT ogd.geolocation_state,
	   COUNT(geolocation_state)
FROM olist_customers_dataset ocd 
JOIN olist_geolocation_dataset ogd ON ocd.customer_zip_code_prefix = ogd.geolocation_zip_code_prefix
JOIN customer_rfm cr ON cr.customer_unique_id = ocd.customer_unique_id
WHERE cr.frequency_text = 'highest F'
GROUP BY geolocation_state 
ORDER BY count DESC;