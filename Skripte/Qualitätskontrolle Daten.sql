----------------- QUALITÄTSKONTROLLE UND DATENMODELLIERUNG ------------------------------------------


---- ÜBERSICHT UND QUALITÄTSKONTROLLE OLIST_CUSTOMERS_DATASET -------------------------------------

-- keine Dopplungen in customer_id, zeigt einzelne Transaktionen
SELECT customer_id
FROM olist_customers_dataset ocd 
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- Customer_id als primary Key
ALTER TABLE olist_customers_dataset 
ADD CONSTRAINT pk_customer_id 
PRIMARY KEY(customer_id);

-- Dopplungen in customer_unique_id -> zeigt wiederholte Käufe von gleichen Kunden
SELECT customer_unique_id
FROM olist_customers_dataset ocd 
GROUP BY customer_unique_id
HAVING COUNT(*)>1;

-- customer_zip_code_prefix, 14994 einzigartige Zipcodes
SELECT COUNT(DISTINCT customer_zip_code_prefix)
FROM olist_customers_dataset ocd;

-- Korrektur der Zipcodes, indem vorangestellte 0 wieder hinzugefügt wird (auf 5 Stellen)
ALTER TABLE olist_customers_dataset
ALTER COLUMN customer_zip_code_prefix TYPE VARCHAR(5)
USING LPAD(customer_zip_code_prefix::text, 5, '0');

-- 4119 einzigartige Einträge. Customer_city unauffällig, allerdings alles klein geschrieben
SELECT COUNT(DISTINCT customer_city)
FROM olist_customers_dataset ocd;

-- 27 Bundesstaaten, sind korrekt
SELECT customer_state, COUNT(*)
FROM olist_customers_dataset ocd 
GROUP BY customer_state
ORDER BY customer_state;


---- ÜBERSICHT UND QUALITÄTSKONTROLLE OLIST_GEOLOCATION_DATASET -------------------------------------

-- Pro Zipcode gibt es mehrere Dopplungen mit leicht anderen Koordinaten. So wären Verbindungen zwischen Tabellen nicht möglich.
SELECT COUNT(*)
FROM (SELECT geolocation_zip_code_prefix 
	  FROM olist_geolocation_dataset ogd 
	  GROUP BY geolocation_zip_code_prefix 
	  HAVING COUNT(*) > 1);

-- Zipcode ist auch mit Stadt und State nicht einzigartig (also nicht mehrere Städte pro Zipcode)
SELECT CONCAT(geolocation_zip_code_prefix, geolocation_city, geolocation_state) AS concat_key
FROM olist_geolocation_dataset
GROUP BY CONCAT(geolocation_zip_code_prefix, geolocation_city, geolocation_state)
HAVING COUNT(*) > 1;

-- Nur behalten des ersten Zipcode Eintrags
WITH duplicates AS (
    SELECT ctid,
           ROW_NUMBER() OVER(PARTITION BY geolocation_zip_code_prefix 
           					 ORDER BY geolocation_zip_code_prefix) AS rn
    FROM olist_geolocation_dataset
)
DELETE FROM olist_geolocation_dataset
WHERE ctid IN(
			  SELECT ctid 
			  FROM duplicates 
			  WHERE rn > 1
);

-- Primary Key kann jetzt gesetzt werden (Zipcode)
ALTER TABLE olist_geolocation_dataset
ADD CONSTRAINT pk_zip_code
PRIMARY KEY (geolocation_zip_code_prefix);

-- auch hier wird das Problem der entfernten Nullen im Zipcode korrigiert
ALTER TABLE olist_geolocation_dataset
ALTER COLUMN geolocation_zip_code_prefix TYPE VARCHAR(5)
USING LPAD(geolocation_zip_code_prefix::text, 5, '0');

--Koordinaten unauffällig, keine Zahlen außerhalb des korrekten Bereichs für Koordinaten
SELECT *
FROM olist_geolocation_dataset ogd
WHERE geolocation_lng > 180 OR geolocation_lng < -180 OR 
	  geolocation_lat > 180 OR geolocation_lat < -180;

-- Kontrolle Städte: es gibt Dopplungen bei Buchstaben, die Akzente enthalten
SELECT geolocation_city, geolocation_zip_code_prefix
FROM olist_geolocation_dataset ogd
GROUP BY geolocation_city, geolocation_zip_code_prefix 
ORDER BY geolocation_city ASC;

-- Entfernen der Akzente bei Kollision
CREATE EXTENSION IF NOT EXISTS unaccent;

UPDATE olist_geolocation_dataset c
SET geolocation_city = unaccent(geolocation_city)
WHERE EXISTS(
			SELECT 1
    		FROM olist_geolocation_dataset c2
   		 	WHERE unaccent(c2.geolocation_city) = unaccent(c.geolocation_city)
      	 	AND c2.geolocation_city <> unaccent(c2.geolocation_city)
      );

-- Bundesstaaten sind korrekt
SELECT geolocation_state
FROM olist_geolocation_dataset
GROUP BY geolocation_state;

-- 155 Zipcodes sind nicht im Geolocation Dataset aber im Customer Dataset
SELECT customer_zip_code_prefix
FROM olist_customers_dataset ocd 
LEFT JOIN olist_geolocation_dataset ON customer_zip_code_prefix = geolocation_zip_code_prefix
WHERE geolocation_zip_code_prefix IS NULL
GROUP BY 1;

-- Mit AI Informationen über die Geolocation nachgeschaut, um sie in der Tabelle hinzuzufügen
INSERT INTO olist_geolocation_dataset
    (geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state)
VALUES
    ('71591', -15.6888, -47.8824, 'brasilia', 'DF'),
    ('83843', -25.7592, -49.3364, 'fazenda rio grande', 'PR'),
    ('73310', -15.8601, -47.7951, 'paranoa', 'DF'),
    ('87323', -24.0863, -52.4172, 'jaracatia', 'PR'),
    ('35104', -19.4939, -42.5029, 'governador valadares', 'MG'),
    ('70701', -15.7606, -47.8814, 'brasilia', 'DF'),
    ('73391', -15.7606, -47.8814, 'brasilia', 'DF'),
    ('72427', -16.0353, -48.0673, 'gama', 'DF'),
    ('72280', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('72596', -16.0610, -48.0163, 'gama', 'DF'),
    ('72023', -15.7981, -48.0645, 'taguatinga', 'DF'),
    ('70316', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('72863', -16.0441, -48.0833, 'cidade ocidental', 'GO'),
    ('36248', -21.4116, -43.6841, 'barbacena', 'MG'),
    ('72457', -16.0353, -48.0673, 'gama', 'DF'),
    ('73401', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('72536', -16.0353, -48.0673, 'gama', 'DF'),
    ('62625', -4.0182, -39.0651, 'pacatuba', 'CE'),
    ('28575', -21.6033, -42.3486, 'sao fidelis', 'RJ'),
    ('28160', -21.6033, -42.3486, 'campos dos goytacazes', 'RJ'),
    ('85118', -25.5645, -51.5794, 'guarapuava', 'PR'),
    ('72535', -16.0353, -48.0673, 'gama', 'DF'),
    ('25919', -22.7554, -42.8203, 'guapimirim', 'RJ'),
    ('58286', -6.7460, -35.2608, 'joao pessoa', 'PB'),
    ('71953', -15.8205, -48.0435, 'aguas claras', 'DF'),
    ('65830', -6.8282, -44.5910, 'balsas', 'MA'),
    ('71208', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('70716', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('48504', -12.1950, -38.3300, 'alagoinhas', 'BA'),
    ('42843', -12.6370, -38.3150, 'camacari', 'BA'),
    ('71539', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('72440', -16.0353, -48.0673, 'gama', 'DF'),
    ('55863', -7.5950, -35.2950, 'caruaru', 'PE'),
    ('43870', -12.7712, -38.3117, 'candeias', 'BA'),
    ('71676', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('62898', -4.8436, -37.8974, 'horizonte', 'CE'),
    ('28617', -22.2858, -42.5312, 'nova friburgo', 'RJ'),
    ('70686', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('57254', -9.9980, -36.0070, 'arapiraca', 'AL'),
    ('95572', -29.3508, -50.1158, 'capao da canoa', 'RS'),
    ('72268', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('72760', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('86135', -23.3103, -51.1611, 'londrina', 'PR'),
    ('38627', -17.5878, -46.8837, 'unai', 'MG'),
    ('64047', -5.0934, -42.8030, 'teresina', 'PI'),
    ('72017', -15.7981, -48.0645, 'taguatinga', 'DF'),
    ('77404', -10.3522, -48.3392, 'porto nacional', 'TO'),
    ('25840', -22.1481, -43.2045, 'tres rios', 'RJ'),
    ('49870', -10.5960, -37.3750, 'propria', 'SE'),
    ('72821', -16.0029, -47.9620, 'luziania', 'GO'),
    ('68511', -5.4623, -49.1235, 'parauapebas', 'PA'),
    ('71995', -15.8205, -48.0435, 'aguas claras', 'DF'),
    ('84623', -25.7592, -49.3364, 'fazenda rio grande', 'PR'),
    ('76968', -11.9070, -61.4280, 'cacoal', 'RO'),
    ('71590', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('73082', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('44135', -12.4278, -38.5028, 'santo antonio de jesus', 'BA'),
    ('71993', -15.8205, -48.0435, 'aguas claras', 'DF'),
    ('72341', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('29718', -19.4622, -40.0886, 'colatina', 'ES'),
    ('64095', -5.0934, -42.8030, 'teresina', 'PI'),
    ('39103', -18.5700, -43.3400, 'diamantina', 'MG'),
    ('41347', -12.9730, -38.5016, 'salvador', 'BA'),
    ('13307', -23.2842, -47.2882, 'itu', 'SP'),
    ('36596', -20.6601, -42.9248, 'ponte nova', 'MG'),
    ('73369', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('42716', -12.8752, -38.3117, 'lauro de freitas', 'BA'),
    ('70702', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('73272', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('59547', -5.6791, -35.3957, 'natal', 'RN'),
    ('28388', -21.6033, -42.3486, 'campos dos goytacazes', 'RJ'),
    ('71971', -15.8205, -48.0435, 'aguas claras', 'DF'),
    ('58734', -7.0270, -37.2850, 'patos', 'PB'),
    ('41098', -12.9730, -38.5016, 'salvador', 'BA'),
    ('72338', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('29949', -18.7895, -39.8660, 'sao mateus', 'ES'),
    ('71261', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('59299', -5.7330, -35.2000, 'parnamirim', 'RN'),
    ('72549', -16.0353, -48.0673, 'gama', 'DF'),
    ('76897', -10.4210, -62.8900, 'jaru', 'RO'),
    ('95853', -29.8188, -50.9840, 'montenegro', 'RS'),
    ('35408', -20.4497, -43.6841, 'ouropreto', 'MG'),
    ('29196', -19.9820, -40.0601, 'aracruz', 'ES'),
    ('87511', -23.7710, -53.3080, 'umuarama', 'PR'),
    ('73090', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('06930', -23.5350, -46.8770, 'cotia', 'SP'),
    ('73093', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('36956', -20.6601, -42.9248, 'ponte nova', 'MG'),
    ('56327', -9.4000, -40.5000, 'petrolina', 'PE'),
    ('71996', -15.8205, -48.0435, 'aguas claras', 'DF'),
    ('72237', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('72455', -16.0353, -48.0673, 'gama', 'DF'),
    ('94370', -29.9145, -51.0504, 'porto alegre', 'RS'),
    ('08342', -23.5900, -46.4600, 'sao paulo', 'SP'),
    ('67105', -1.3850, -48.4520, 'anani-deua', 'PA'),
    ('08980', -23.5900, -46.4600, 'sao paulo', 'SP'),
    ('73088', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('75257', -16.7118, -48.8893, 'senador canedo', 'GO'),
    ('71905', -15.8205, -48.0435, 'aguas claras', 'DF'),
    ('73081', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('11547', -23.9317, -46.4387, 'cubatao', 'SP'),
    ('86996', -23.4682, -51.4925, 'arapongas', 'PR'),
    ('37005', -21.5794, -45.5401, 'varginha', 'MG'),
    ('12332', -23.3275, -45.9602, 'jacarei', 'SP'),
    ('71975', -15.8205, -48.0435, 'aguas claras', 'DF'),
    ('71698', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('72583', -16.0610, -48.0163, 'gama', 'DF'),
    ('85894', -25.0425, -53.4839, 'foz do igua-u', 'PR'),
    ('56485', -8.5435, -40.2315, 'petrolina', 'PE'),
    ('28530', -21.6033, -42.3486, 'campos dos goytacazes', 'RJ'),
    ('70324', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('72238', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('72904', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('68629', -3.7656, -47.3323, 'paragominas', 'PA'),
    ('71884', -15.8601, -47.7951, 'paranoa', 'DF'),
    ('85958', -24.4750, -53.8640, 'palotina', 'PR'),
    ('72465', -16.0353, -48.0673, 'gama', 'DF'),
    ('19740', -22.5833, -51.6833, 'regente feijo', 'SP'),
    ('72243', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('78554', -11.8845, -55.5140, 'sinop', 'MT'),
    ('28655', -22.2858, -42.5312, 'nova friburgo', 'RJ'),
    ('83210', -25.5513, -48.5292, 'paranagua', 'PR'),
    ('07729', -23.3556, -46.7324, 'caieiras', 'SP'),
    ('71593', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('38710', -18.5700, -43.3400, 'patos de minas', 'MG'),
    ('02140', -23.5900, -46.4600, 'sao paulo', 'SP'),
    ('71976', -15.8205, -48.0435, 'aguas claras', 'DF'),
    ('72300', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('55027', -8.2700, -35.9700, 'caruaru', 'PE'),
    ('73402', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('72242', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('71574', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('72002', -15.7981, -48.0645, 'taguatinga', 'DF'),
    ('75784', -18.1500, -47.8800, 'caldas novas', 'GO'),
    ('65137', -2.5925, -44.2467, 'sao luis', 'MA'),
    ('70333', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('28120', -21.6033, -42.3486, 'campos dos goytacazes', 'RJ'),
    ('17390', -22.4277, -46.9429, 'amparo', 'SP'),
    ('71919', -15.8205, -48.0435, 'aguas claras', 'DF'),
    ('72587', -16.0610, -48.0163, 'gama', 'DF'),
    ('72867', -16.0441, -48.0833, 'cidade ocidental', 'GO'),
    ('07430', -23.3556, -46.7324, 'aruga', 'SP'),
    ('73091', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('72595', -16.0610, -48.0163, 'gama', 'DF'),
    ('93602', -29.7420, -51.0450, 'esteio', 'RS'),
    ('72005', -15.7981, -48.0645, 'taguatinga', 'DF'),
    ('07784', -23.3556, -46.7324, 'franco da rocha', 'SP'),
    ('64605', -5.0934, -42.8030, 'teresina', 'PI'),
    ('71810', -15.8450, -47.9810, 'samambaia', 'DF'),
    ('12770', -22.6186, -45.0970, 'cruzeiro', 'SP'),
    ('27980', -22.4831, -41.7423, 'macaé', 'RJ'),
    ('35242', -19.4939, -42.5029, 'governador valadares', 'MG'),
    ('73255', -15.7725, -47.7885, 'brasilia', 'DF'),
    ('36857', -20.6601, -42.9248, 'ponte nova', 'MG'),
    ('61906', -3.7656, -47.3323, 'maracanau', 'CE')
	('07412', -23.40, -46.32, 'Arujá', 'SP'),
	('71551', -15.75, -47.90, 'Brasília', 'DF');

-- Verbindung mit Customer Dataset etablieren
ALTER TABLE olist_customers_dataset
ADD CONSTRAINT fk_customer_zip FOREIGN KEY(customer_zip_code_prefix)
REFERENCES olist_geolocation_dataset(geolocation_zip_code_prefix);


---- ÜBERSICHT UND QUALITÄTSKONTROLLE OLIST_ORDER_ITEMS_DATASET -------------------------------------

-- 9803 Duplikate in Order_ID vorhanden
SELECT COUNT(*)
FROM (SELECT order_id
	  FROM olist_order_items_dataset ooid 
	  GROUP BY order_id
	  HAVING COUNT(*) > 1);

-- Wenn man es mit Order_item zusammen nimmt, ist es einzigartig
SELECT CONCAT(order_id, order_item_id) AS concat_key
FROM olist_order_items_dataset ooid 
GROUP BY CONCAT(order_id, order_item_id)
HAVING COUNT(*) > 1;

-- gemeinsam als Primary Key befiniert
ALTER TABLE olist_order_items_dataset
ADD CONSTRAINT pk_order_items PRIMARY KEY(order_id, order_item_id);

-- Minimale und maximale Anzahl an gekauften Produkten ist plausibel
SELECT MAX(order_item_id), MIN(order_item_id)
FROM olist_order_items_dataset ooid;

-- Datum des Versands nicht als Datum formatiert. Die Formatierung ist aber einheitlich
SELECT shipping_limit_date
FROM olist_order_items_dataset ooid
WHERE shipping_limit_date !~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$';

-- korrekte Formatierung des Datums
ALTER TABLE olist_order_items_dataset
ALTER COLUMN shipping_limit_date TYPE DATE
USING NULLIF(shipping_limit_date, '')::DATE;

-- Preisspanne ist sinnvoll
SELECT MAX(price), MIN(price)
FROM olist_order_items_dataset;

-- Freight-Value von 0 heißt kostenloser Versand, ist möglich
SELECT MAX(freight_value), MIN(freight_value)
FROM olist_order_items_dataset;

-- alle Product_ids kommen im products Table vor, können verbunden werden
SELECT product_id
FROM olist_order_items_dataset ooid 
WHERE product_id NOT IN (SELECT product_id FROM olist_products_dataset);


---- ÜBERSICHT UND QUALITÄTSKONTROLLE OLIST_ORDERS_DATASET --------------------------------------------

-- order_id ist einzigartig
SELECT order_id
FROM olist_orders_dataset
GROUP BY order_id
HAVING COUNT(*)>1;

-- Order_id als Primary Key setzen
ALTER TABLE olist_orders_dataset
ADD CONSTRAINT pk_orders PRIMARY KEY(order_id);

-- Keine Dopplungen im order_status
SELECT order_status
FROM olist_orders_dataset ood
GROUP BY order_status;

-- order_purchase_timestamp nicht als Timestamp, aber alle gleich formatiert
SELECT order_purchase_timestamp
FROM olist_orders_dataset ood
WHERE order_purchase_timestamp !~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$';

-- korrekte Formatierung
ALTER TABLE olist_orders_dataset
ALTER COLUMN order_purchase_timestamp TYPE TIMESTAMP WITHOUT TIME ZONE
USING NULLIF(order_purchase_timestamp, '')::TIMESTAMP WITHOUT TIME ZONE;

-- order_approved_at hat 160 falsch formatierte Werte
SELECT COUNT(*)
FROM olist_orders_dataset ood
WHERE order_approved_at !~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$';

-- das sind 160 leere Werte
SELECT COUNT(*)
FROM olist_orders_dataset ood 
WHERE order_approved_at = '';

-- Umwandlung zu Timestamp
ALTER TABLE olist_orders_dataset
ALTER COLUMN order_approved_at TYPE TIMESTAMP WITHOUT TIME ZONE
USING NULLIF(order_approved_at, '')::TIMESTAMP WITHOUT TIME ZONE;

-- order_delivered_carrier_date nicht als Timestamp
SELECT COUNT(*)
FROM olist_orders_dataset ood
WHERE order_delivered_carrier_date !~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$';

-- 1783 leere Werte
SELECT COUNT(*)
FROM olist_orders_dataset ood
WHERE order_delivered_carrier_date = '';

-- Umwandlung zu Timestamp
ALTER TABLE olist_orders_dataset
ALTER COLUMN order_delivered_carrier_date TYPE TIMESTAMP WITHOUT TIME ZONE
USING NULLIF(order_delivered_carrier_date, '')::TIMESTAMP WITHOUT TIME ZONE;

-- order_delivered_customer_date nicht als Timestamp
SELECT ood.order_delivered_customer_date 
FROM olist_orders_dataset ood
WHERE ood.order_delivered_customer_date !~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$';

-- 2965 leere Werte
SELECT COUNT(*)
FROM olist_orders_dataset ood
WHERE order_delivered_customer_date = '';

-- Umwandlung zu Timestamp
ALTER TABLE olist_orders_dataset
ALTER COLUMN order_delivered_customer_date TYPE TIMESTAMP WITHOUT TIME ZONE
USING NULLIF(order_delivered_customer_date, '')::TIMESTAMP WITHOUT TIME ZONE;

-- order_estimated_delivery_date nicht als Datum formatiert
SELECT ood.order_estimated_delivery_date
FROM olist_orders_dataset ood
WHERE ood.order_estimated_delivery_date !~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$';

-- Umwandlung zu Datum
ALTER TABLE olist_orders_dataset
ALTER COLUMN order_estimated_delivery_date TYPE DATE
USING NULLIF(order_estimated_delivery_date, '')::DATE;

-- kein Missmatch zu olist_order_items
SELECT order_id
FROM olist_order_items_dataset ooid 
WHERE order_id NOT IN (SELECT order_id FROM olist_orders_dataset);

-- Verbindung zu olist_order_items
ALTER TABLE olist_order_items_dataset 
ADD CONSTRAINT fk_order_id FOREIGN KEY(order_id)
REFERENCES olist_orders_dataset(order_id);

-- kein Missmatch zu olist_customers
SELECT customer_id
FROM olist_orders_dataset
WHERE customer_id NOT IN (SELECT customer_id FROM olist_customers_dataset);

-- Verbindung zu olist_customers
ALTER TABLE olist_orders_dataset
ADD CONSTRAINT fk_order_customer FOREIGN KEY(customer_id)
REFERENCES olist_customers_dataset(customer_id);


---- ÜBERSICHT UND QUALITÄTSKONTROLLE OLIST_PRODUCTS_DATASET -------------------------------------

-- Product ID ist einzigartig
SELECT product_id
FROM olist_products_dataset opd 
GROUP BY product_id
HAVING COUNT(*)>1;

-- Product_ID als Primary Key
ALTER TABLE olist_products_dataset
ADD CONSTRAINT pk_product PRIMARY KEY (product_id);

-- Bei Product Category Name gibt es eine leere Kategorie
SELECT product_category_name
FROM olist_products_dataset
GROUP BY product_category_name
ORDER BY product_category_name;

-- 610 Produkte haben keine Kategorie oder Beschreibung, aber Dimensions und Gewichtsangaben. Daher nicht entfernt.
SELECT *
FROM olist_products_dataset opd 
WHERE product_category_name = '';

-- zu NULL gesetzt
UPDATE olist_products_dataset opd 
SET product_category_name = NULL
WHERE product_category_name = '';

-- Länge des Produktnames von 5 bis 76, realistisch
SELECT MAX(product_name_lenght), MIN(product_name_lenght)
FROM olist_products_dataset;

-- Länge der Beschreibung von 4 bis 3992
SELECT MAX(product_description_lenght), MIN(product_description_lenght)
FROM olist_products_dataset;

-- 1 bis 20 Fotos bei den Produkten
SELECT MAX(product_photos_qty), MIN(product_photos_qty)
FROM olist_products_dataset;

-- keine weiteren fehlenden Werte in den Daten außer den 610, wo auch die Kategorie fehlt
SELECT COUNT(*)
FROM olist_products_dataset opd 
WHERE opd.product_photos_qty IS NULL;

-- unauffällige Länge der Produkte
SELECT MAX(product_length_cm), MIN(product_length_cm)
FROM olist_products_dataset;

-- 2 fehlende Werte, fehlt bei allen Maßeinheiten
SELECT *
FROM olist_products_dataset opd 
WHERE opd.product_length_cm IS NULL;

-- Gewicht geht bei null Gramm los, digital?
SELECT MAX(product_weight_g), MIN(product_weight_g)
FROM olist_products_dataset;

-- Kategorie ist Bett- und Badsachen, eventuell falsche Angabe. Außerdem haben sie physische Größe.
SELECT *
FROM olist_products_dataset opd 
WHERE opd.product_weight_g = 0;

-- 105 bis 2 cm Höhe der Produkte
SELECT MAX(product_height_cm), MIN(product_height_cm)
FROM olist_products_dataset;

-- 118 bis 6 cm Breite der Produkte
SELECT MAX(product_width_cm), MIN(product_width_cm)
FROM olist_products_dataset;

-- pc_gamer und portateis_cozinha_e_preparadores_de_alimentos sind nicht im Parent Table, wurden also nicht übersetzt
SELECT product_category_name
FROM olist_products_dataset opd
WHERE product_category_name NOT IN (SELECT product_category_name FROM product_category_name_translation)
GROUP BY product_category_name;

-- Foreign Key zu products_dataset und order_items_dataset
ALTER TABLE olist_order_items_dataset 
ADD CONSTRAINT fk_product_id FOREIGN KEY(product_id)
REFERENCES olist_products_dataset(product_id)



------ QUALITÄTSKONTROLLE UND DATENMODELLIERUNG FÜR WEITERE TABELLEN, DIESE LIEGEN ABER NICHT IM PROJEKTFOKUS

---- ÜBERSICHT UND QUALITÄTSKONTROLLE OLIST_ORDER_PAYMENTS_DATASET -------------------------------------

-- 2961 Duplikate in Order_ID vorhanden
SELECT COUNT(*)
FROM (SELECT order_id
	  FROM olist_order_payments_dataset ooid 
      GROUP BY order_id
	  HAVING COUNT(*) > 1);

-- Mit Payment Sequential sind die Zahlungen einzigartig
SELECT CONCAT(order_id, payment_sequential) AS concat_key
FROM olist_order_payments_dataset ooid
GROUP BY CONCAT(order_id, payment_sequential)
HAVING COUNT(*) > 1;

-- gemeinsam als Primary Key setzen
ALTER TABLE olist_order_payments_dataset
ADD CONSTRAINT pk_order_payment PRIMARY KEY(order_id, payment_sequential);

-- Zahlungsarten sinnvoll gruppiert
SELECT payment_type, COUNT(*)
FROM olist_order_payments_dataset
GROUP BY payment_type;

-- wie viele Zahlungseinheiten haben die Kunden gewählt: 0? -> könnte extra-Aktion sein, daher nicht entfernt.
SELECT MIN(payment_installments), MAX(payment_installments)
FROM olist_order_payments_dataset ooid;

-- Minimale Zahlung von 0
SELECT MIN(payment_value), MAX(payment_value)
FROM olist_order_payments_dataset ooid;

-- Zahlung jeweils per Voucher (oder undefined), sinnvoll
SELECT *
FROM olist_order_payments_dataset ooid
WHERE payment_value = 0;

-- kein Missmatch zu olist_orders_dataset
SELECT order_id
FROM olist_order_payments_dataset oopd 
WHERE order_id NOT IN (SELECT order_id FROM olist_orders_dataset);

-- Verbindung zu olist_orders_dataset
ALTER TABLE olist_order_payments_dataset
ADD CONSTRAINT fk_order_id_pay FOREIGN KEY (order_id)
REFERENCES olist_orders_dataset(order_id);


---- ÜBERSICHT UND QUALITÄTSKONTROLLE OLIST_ORDER_REVIEWS_DATASET -------------------------------------

-- das csv hat fehlende Anführungszeichen um Kommentare, daher als txt mit neuer Kodierung importiert
SELECT COUNT(*)
FROM olist_order_reviews_dataset oord;

-- Review ID ist nicht einzigartig 
SELECT COUNT(*)
FROM (SELECT review_id
	  FROM olist_order_reviews_dataset 
	  GROUP BY review_id
	  HAVING COUNT(*) > 1);

-- keine fehlende order_id
SELECT *
FROM olist_order_reviews_dataset oord 
WHERE order_id IS NULL;

-- gemeinsam mit order_id ist es einzigartig. Zu jeder Review kann es verschiedene Bestellungen geben
SELECT CONCAT(review_id, order_id) AS concat_key
FROM olist_order_reviews_dataset 
GROUP BY CONCAT(review_id, order_id)
HAVING COUNT(*) > 1;

-- gemeinsam als Primary Key setzen
ALTER TABLE olist_order_reviews_dataset 
ADD CONSTRAINT pk_order_review PRIMARY KEY (review_id, order_id);

-- Score von 1 bis 5
SELECT MIN(review_score), MAX(review_score)
FROM olist_order_reviews_dataset;

-- Datum des Reviews ist nicht als Datum formatiert. Die Formatierung ist aber einheitlich
SELECT review_creation_date
FROM olist_order_reviews_dataset
WHERE review_creation_date !~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$';

-- korrekte Formatierung des Datums
ALTER TABLE olist_order_reviews_dataset
ALTER COLUMN review_creation_date TYPE DATE
USING NULLIF(review_creation_date, '')::DATE;

-- Datum des review_answer_timestamp nicht als Datum formatiert. Die Formatierung ist aber einheitlich
SELECT review_answer_timestamp
FROM olist_order_reviews_dataset
WHERE review_answer_timestamp !~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$';

-- korrekte Formatierung des Antwortdatums
ALTER TABLE olist_order_reviews_dataset
ALTER COLUMN review_answer_timestamp TYPE TIMESTAMP WITHOUT TIME ZONE
USING NULLIF(review_answer_timestamp, '')::TIMESTAMP WITHOUT TIME ZONE;

-- kein Missmatch zu olist_orders_dataset
SELECT order_id
FROM olist_order_reviews_dataset oord 
WHERE order_id NOT IN (SELECT order_id FROM olist_orders_dataset);

-- Verbindung zu olist_orders_dataset
ALTER TABLE olist_order_reviews_dataset
ADD CONSTRAINT fk_order_review FOREIGN KEY (order_id)
REFERENCES  olist_orders_dataset(order_id);


---- ÜBERSICHT UND QUALITÄTSKONTROLLE OLIST_SELLERS_DATASET -------------------------------------

-- Seller ID ist einzigartig
SELECT COUNT(*)
FROM olist_sellers_dataset
GROUP BY seller_id
HAVING COUNT(*) > 1

-- Seller ID als Primary Key
ALTER TABLE olist_sellers_dataset
ADD CONSTRAINT pk_sellers PRIMARY KEY (seller_id);

-- Zipcode Prefix sollte 5 Stellen haben, auch hier korrigiert
SELECT MIN(seller_zip_code_prefix), MAX(seller_zip_code_prefix)
FROM olist_sellers_dataset osd;

ALTER TABLE olist_sellers_dataset
ALTER COLUMN seller_zip_code_prefix TYPE VARCHAR(5)
USING LPAD(seller_zip_code_prefix::text, 5, '0');

-- Eintrag 04482255 als Stadt? Keine Akzente in den Stadtnamen, also ist es einheitlich im Datensatz jetzt
SELECT seller_city
FROM olist_sellers_dataset
GROUP BY seller_city
ORDER BY seller_city;

-- Stadtname ist ein Zipcode von Sao Paulo, aber das passt nicht zu Stadt und Zip.
SELECT *
FROM olist_sellers_dataset osd
WHERE seller_city = '04482255';

-- nicht alle States vorhanden, was möglich ist
SELECT seller_state
FROM olist_sellers_dataset osd 
GROUP BY seller_state;

-- kein Missmatch in Seller IDs
SELECT seller_id
FROM olist_order_items_dataset ooid 
WHERE seller_id NOT IN (SELECT seller_id FROM olist_sellers_dataset);

-- Foreign Key Verbindung order_items
ALTER TABLE olist_order_items_dataset
ADD CONSTRAINT fk_seller_id FOREIGN KEY (seller_id)
REFERENCES olist_sellers_dataset(seller_id);

-- 7 Zipcodes sind nicht im geolocation table
SELECT seller_zip_code_prefix
FROM olist_sellers_dataset
LEFT JOIN olist_geolocation_dataset ON seller_zip_code_prefix = geolocation_zip_code_prefix
WHERE geolocation_zip_code_prefix IS NULL
GROUP BY 1;

-- Update des geolocation tables mit den fehlenden Zipcodes
INSERT INTO olist_geolocation_dataset
    (geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state)
VALUES
    ('02285', -23.4735, -46.5701, 'sao paulo', 'SP'),
    ('37708', -21.7850, -46.5800, 'pocos de caldas', 'MG'),
    ('72580', -15.9392, -47.7851, 'brasilia', 'DF'),
    ('82040', -25.4190, -49.3360, 'curitiba', 'PR'),
    ('91901', -30.0818, -51.2290, 'porto alegre', 'RS');

-- jetzt ist die Verbindung mit dem geolocation_dataset möglich
ALTER TABLE olist_sellers_dataset
ADD CONSTRAINT fk_seller_zip FOREIGN KEY (seller_zip_code_prefix)
REFERENCES olist_geolocation_dataset (geolocation_zip_code_prefix);


---- ÜBERSICHT UND QUALITÄTSKONTROLLE PRODUCT_CATEGORY_NAME_TRANSLATION -------------------------------------

-- kann man überblicken, unauffällig
SELECT *
FROM product_category_name_translation pcnt
ORDER BY product_category_name_english;

-- Primary Key
ALTER TABLE product_category_name_translation
ADD CONSTRAINT pk_category_name PRIMARY KEY (product_category_name);

-- fehlende Kategorien hinzufügen, die im product_dataset noch vorhanden sind
INSERT INTO product_category_name_translation(product_category_name, product_category_name_english)
VALUES ('pc_gamer', 'pc_gamer'),
	   ('portateis_cozinha_e_preparadores_de_alimentos', 'small_kitchen_and_food_preparation_appliances');

-- keine fehlenden Kategorien mehr
SELECT opd.product_category_name 
FROM olist_products_dataset opd
WHERE product_category_name NOT IN (SELECT product_category_name FROM product_category_name_translation pcnt)
GROUP BY product_category_name;

-- Foreign Key Verbindung mit products_dataset
ALTER TABLE olist_products_dataset
ADD CONSTRAINT fk_product_category FOREIGN KEY (product_category_name)
REFERENCES product_category_name_translation(product_category_name);