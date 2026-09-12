-- =========================
-- DIMENSION: CUSTOMER
-- =========================
CREATE TABLE DimCustomer (
    -- permitir análisis por clientes
    customer_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    customer_id NVARCHAR(30) NOT NULL UNIQUE,
    customer_name NVARCHAR(100) NOT NULL,
    segment NVARCHAR(20) NOT NULL CHECK (segment IN ('Consumer', 'Corporate', 'Home Office'))
);

-- =========================
-- DIMENSION: PRODUCT
-- =========================
CREATE TABLE DimProduct (
    -- permitir análisis por productos
    product_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    product_id NVARCHAR(50) NOT NULL,
    category NVARCHAR(40) NOT NULL 
        CHECK (category IN ('Office Supplies', 'Furniture', 'Technology')),
    subcategory NVARCHAR(40) NOT NULL CHECK (subcategory IN ('Supplies', 'Storage', 'Phones', 'Fasteners', 'Copiers', 'Chairs', 
                                             'Bookcases', 'Machines', 'Art', 'Envelopes', 'Binders', 
                                             'Labels', 'Furnishings', 'Accessories', 'Appliances', 
                                             'Paper', 'Tables')),
    product_name NVARCHAR(255) NOT NULL
);

-- =========================
-- DIMENSION: GEOGRAPHY
-- =========================
CREATE TABLE DimGeography (
    -- Permitir análisis por ubicación geográfica
    geography_key INT IDENTITY(1,1) PRIMARY KEY,
    region NVARCHAR(15) NOT NULL 
        CHECK (region IN ('West', 'East', 'South', 'Central')),
    country NVARCHAR(50) NOT NULL,
    state NVARCHAR(50) NOT NULL,
    city NVARCHAR(50) NOT NULL,
    postal_code NVARCHAR(10) NOT NULL
);

-- =========================
-- DIMENSION: DATE
-- =========================
CREATE TABLE DimDate (
    -- permitir análisis por tiempo (año, mes, día, trimestre, etc)
    date_key BIGINT PRIMARY KEY, -- YYYYMMDD
    date DATE NOT NULL,
    ship_date DATE NOT NULL,
    year INT NOT NULL,
    month INT NOT NULL,
    month_name NVARCHAR(10) NOT NULL,
    day INT NOT NULL,
    quarter INT NOT NULL,
    weekday NVARCHAR(10) NOT NULL
);

-- Definir función de partición por fecha
CREATE PARTITION FUNCTION pf_FactOrders_Date (BIGINT)
AS RANGE RIGHT FOR VALUES (
    20140101,
    20150101,
    20160101,
    20170101
);

-- Crear esquema de partición por fecha a partir de la función de partición
CREATE PARTITION SCHEME ps_FactOrders_Date
AS PARTITION pf_FactOrders_Date
ALL TO ([PRIMARY]);

-- =========================
-- FACT TABLE: ORDERS
-- =========================
CREATE TABLE FactOrders (
    order_key BIGINT IDENTITY(1,1) NOT NULL, 
    order_id NVARCHAR(255) NOT NULL, 

    order_date DATE NOT NULL 
        CHECK(order_date <= GETDATE()) 
        DEFAULT GETDATE(),

    ship_date DATE DEFAULT NULL,
    ship_mode NVARCHAR(30) DEFAULT NULL 
              CHECK(ship_mode IS NULL OR ship_mode IN ('Second Class', 'Standard Class', 
                                                       'First Class', 'Same Day')),

    customer_key BIGINT NOT NULL,
    product_key BIGINT NOT NULL,
    geography_key INT NOT NULL,
    date_key BIGINT NOT NULL,

    sales DECIMAL(12,2) NOT NULL 
        CHECK(sales > 0),

    quantity INT NOT NULL 
        CHECK(quantity > 0),

    discount DECIMAL(4,2) NOT NULL 
        CHECK(discount BETWEEN 0 AND 1) 
        DEFAULT 0,

    profit DECIMAL(12,2) NOT NULL,

    CONSTRAINT FK_orders_customer 
        FOREIGN KEY (customer_key) 
        REFERENCES DimCustomer(customer_key),

    CONSTRAINT FK_orders_product 
        FOREIGN KEY (product_key) 
        REFERENCES DimProduct(product_key),

    CONSTRAINT FK_orders_geography 
        FOREIGN KEY (geography_key) 
        REFERENCES DimGeography(geography_key),

    CONSTRAINT FK_orders_date 
        FOREIGN KEY (date_key) 
        REFERENCES DimDate(date_key),

    CONSTRAINT CK_ship_date CHECK(ship_date IS NULL OR ship_date >= order_date)

)
ON ps_FactOrders_Date(date_key);

-- Crear índice columnstore en FactOrders para optimizar agregaciones de datos
CREATE CLUSTERED COLUMNSTORE INDEX CCI_FactOrders
ON FactOrders;

--Çrear índices adicionales para optimizar JOINs entre la tabla de hechos y sus dimensiones
CREATE NONCLUSTERED INDEX idx_FactOrders_customer
ON FactOrders(customer_key);

CREATE NONCLUSTERED INDEX idx_FactOrders_product
ON FactOrders(product_key);

CREATE NONCLUSTERED INDEX idx_FactOrders_geography
ON FactOrders(geography_key);

CREATE NONCLUSTERED INDEX idx_FactOrders_date
ON FactOrders(date_key);

-- Crear índices en las tablas de dimensiones
CREATE NONCLUSTERED INDEX idx_DimCustomer_customer_id
ON DimCustomer(customer_id);

CREATE NONCLUSTERED INDEX idx_DimProduct_product_id
ON DimProduct(product_id);

CREATE NONCLUSTERED INDEX idx_DimGeography_geo
ON DimGeography(country, state, city);

CREATE NONCLUSTERED INDEX idx_DimDate_year_month
ON DimDate(year, month);

-- Poblar la tabla DimCustomer con los datos de clientes
INSERT INTO DimCustomer (customer_id, customer_name, segment)
SELECT
      DISTINCT CustomerID,
      CustomerName,
      Segment
FROM Stg_Superstore;

-- Poblar tabla DimGeography con datos de ubicaciones geográficas
INSERT INTO DimGeography (region, country, state, city, postal_code)
SELECT 
      DISTINCT Region,
      Country,
      State,
      City,
      PostalCode
FROM Stg_Superstore

-- Poblar tabla DimProduct con datos de productos 
INSERT INTO DimProduct (product_id, category, subcategory, product_name)
SELECT
     DISTINCT ProductID,
     Category,
     SubCategory,
     ProductName
FROM Stg_Superstore;

-- Poblar tabla DimDate con datos de fechas de pedidos
INSERT INTO DimDate (date_key, year, month, month_name, day, quarter, weekday)
SELECT 
      DISTINCT CONVERT(BIGINT, FORMAT(OrderDate, 'yyyyMMdd')),
      YEAR(OrderDate),
      MONTH(OrderDate),
      DATENAME(MONTH, OrderDate),
      DAY(OrderDate),
      DATEPART(QUARTER, OrderDate),
      DATENAME(WEEKDAY, OrderDate)
FROM Stg_Superstore;

-- Poblar la tabla FactOrders con registros de pedidos de clientes
INSERT INTO FactOrders (order_id, order_date, ship_date, ship_mode,
                        customer_key, product_key, geography_key, date_key,
                        sales, quantity, discount, profit)
SELECT 
      sup.OrderID,
      sup.OrderDate,
      sup.ShipDate,
      sup.ShipMode,
      c.customer_key,
      p.product_key,
      g.geography_key,
      d.date_key,
      sup.Sales,
      sup.Quantity,
      sup.Discount,
      sup.Profit
FROM Stg_Superstore sup
JOIN DimCustomer c ON c.customer_id = sup.CustomerID
JOIN DimProduct p ON p.product_id = sup.ProductID
JOIN DimGeography g ON g.postal_code = sup.PostalCode AND g.city = sup.City
JOIN DimDate d ON d.year = YEAR(sup.OrderDate) AND 
                  d.month = MONTH(sup.OrderDate) AND 
                  d.day = DAY(sup.OrderDate);


