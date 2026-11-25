/* ======================================================================
   AGRICULTURAL MANAGEMENT SYSTEM  -  MySQL 8.0 / MySQL Workbench
   Source of truth: the attached ER diagram (44 tables).
   Sections:  1) Database  2) Tables (parents first)  3) Circular FKs
              (structure only: no data, no views, no test queries)
   Run the whole file (lightning icon) in Workbench.
   ====================================================================== */

/* ---------- 1. DATABASE ---------- */
DROP DATABASE IF EXISTS agri_management_database;
CREATE DATABASE agri_management_database CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE agri_management_database;
SET SQL_SAFE_UPDATES = 1;
SET FOREIGN_KEY_CHECKS = 1;

/* ----------------------------------------------------------------------
   2. TABLES.  Every ID is CHAR(36) (diagram says "char"; 36 also fits UUIDs).
   Notes:
   * [ORIGINAL]    = exactly as in the diagram.
   * [RECOMMENDED] = improvement added by me (marked in comments).
   * MySQL forbids a CHECK on a column that has a foreign-key action, so
     CHECKs are only placed on non-FK columns.
   ---------------------------------------------------------------------- */

/* ===== Group A: independent master tables ===== */
CREATE TABLE administrative_regions (
  region_id     CHAR(36)     NOT NULL,
  state_name    VARCHAR(100) NOT NULL,
  district_name VARCHAR(100) NOT NULL,
  mandal_name   VARCHAR(100) NOT NULL,
  village_name  VARCHAR(100) NOT NULL,
  pincode       VARCHAR(10)  NOT NULL,
  PRIMARY KEY (region_id),
  KEY idx_reg_district (district_name),
  KEY idx_reg_village (village_name)
) ENGINE=InnoDB;

CREATE OR REPLACE VIEW administrative_divisions AS SELECT * FROM administrative_regions;

CREATE TABLE buyers (
  buyer_id            CHAR(36)     NOT NULL,
  buyer_name          VARCHAR(150) NOT NULL,
  buyer_type          VARCHAR(30)  NOT NULL DEFAULT 'Retailer',
  phone               VARCHAR(15)  NOT NULL,
  email               VARCHAR(120) NULL,
  address             VARCHAR(255) NULL,
  registration_number VARCHAR(50)  NOT NULL,
  buyer_password_hash VARCHAR(255) NULL,
  PRIMARY KEY (buyer_id),
  UNIQUE KEY uq_buyers_registration (registration_number),
  CONSTRAINT chk_buyers_type CHECK (buyer_type IN ('Wholesaler','Retailer','Processor','Exporter','Other'))
) ENGINE=InnoDB;

CREATE TABLE crop_categories (
  category_id   CHAR(36)     NOT NULL,
  category_name VARCHAR(100) NOT NULL,
  description   TEXT         NULL,
  PRIMARY KEY (category_id),
  UNIQUE KEY uq_crop_categories_name (category_name)
) ENGINE=InnoDB;

CREATE TABLE product_categories (
  category_id   CHAR(36)     NOT NULL,
  category_name VARCHAR(100) NOT NULL,
  description   TEXT         NULL,
  PRIMARY KEY (category_id),
  UNIQUE KEY uq_product_categories_name (category_name)
) ENGINE=InnoDB;

CREATE TABLE agro_companies (
  company_id          CHAR(36)     NOT NULL,
  company_name        VARCHAR(150) NOT NULL,
  registration_number VARCHAR(50)  NOT NULL,
  phone               VARCHAR(15)  NULL,
  email               VARCHAR(120) NULL,
  GST_number          VARCHAR(20)  NULL,
  address             VARCHAR(255) NULL,
  established_date    DATE         NULL,
  PRIMARY KEY (company_id),
  UNIQUE KEY uq_agro_companies_registration (registration_number)
) ENGINE=InnoDB;

CREATE TABLE cultivation_seasons (
  season_id   CHAR(36)    NOT NULL,
  season_name VARCHAR(60) NOT NULL,
  start_date  DATE        NOT NULL,
  end_date    DATE        NOT NULL,
  description TEXT        NULL,
  PRIMARY KEY (season_id),
  CONSTRAINT chk_season_dates CHECK (end_date >= start_date)
) ENGINE=InnoDB;

CREATE TABLE warehouses (
  warehouse_id   CHAR(36)      NOT NULL,
  warehouse_name VARCHAR(150)  NOT NULL,
  location       VARCHAR(150)  NOT NULL,
  district       VARCHAR(80)   NOT NULL,
  capacity       DECIMAL(12,2) NOT NULL,
  contact_number VARCHAR(15)   NULL,
  PRIMARY KEY (warehouse_id),
  KEY idx_warehouses_district (district),
  CONSTRAINT chk_warehouses_capacity CHECK (capacity > 0)
) ENGINE=InnoDB;

CREATE TABLE rbk_centres (
  rbk_id   CHAR(36)     NOT NULL,
  rbk_name VARCHAR(150) NOT NULL,
  location VARCHAR(150) NOT NULL,
  district VARCHAR(80)  NOT NULL,
  contact  VARCHAR(15)  NULL,
  status   VARCHAR(20)  NOT NULL DEFAULT 'Active',
  PRIMARY KEY (rbk_id),
  KEY idx_rbk_centres_district (district),
  CONSTRAINT chk_rbk_status CHECK (status IN ('Active','Inactive'))
) ENGINE=InnoDB;

/* ===== Group B: farmer side =====
   farmers <-> biometric_authentication reference each other (circular).
   Solution: create farmers WITHOUT the FK to biometric, create biometric,
   then ADD the FK afterwards (section 3). Same for rbk_employees/emp_password. */
CREATE TABLE farmers (
  farmer_id         CHAR(36)     NOT NULL,
  farmer_name       VARCHAR(120) NOT NULL,
  dob               DATE         NULL,
  gender            VARCHAR(10)  NULL,
  phone             VARCHAR(15)  NOT NULL,
  email             VARCHAR(120) NULL,
  password_hash     VARCHAR(255) NOT NULL,
  authentication_id CHAR(36)     NULL,           -- FK added in section 3
  registration_date DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (farmer_id),
  UNIQUE KEY uq_farmers_phone (phone),
  UNIQUE KEY uq_farmers_email (email),
  UNIQUE KEY uq_farmers_auth (authentication_id),   -- [RECOMMENDED] makes the link 1:1
  CONSTRAINT chk_farmers_gender CHECK (gender IS NULL OR gender IN ('Male','Female','Other'))
) ENGINE=InnoDB;

CREATE TABLE biometric_authentication (
  authentication_id CHAR(36)    NOT NULL,
  farmer_id         CHAR(36)    NOT NULL,
  aadhaar_number    VARCHAR(20) NOT NULL,        -- store masked/hashed value only (privacy)
  biometric_type    VARCHAR(30) NOT NULL,
  status            VARCHAR(20) NOT NULL DEFAULT 'Pending',
  authenticated_at  TIMESTAMP   NULL,
  PRIMARY KEY (authentication_id),
  UNIQUE KEY uq_bio_farmer (farmer_id),             -- [RECOMMENDED] one record per farmer
  CONSTRAINT fk_bio_farmer FOREIGN KEY (farmer_id) REFERENCES farmers (farmer_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_bio_status CHECK (status IN ('Pending','Verified','Failed','Revoked'))
) ENGINE=InnoDB;

CREATE TABLE farmer_addresses (
  address_id   CHAR(36)     NOT NULL,
  farmer_id    CHAR(36)     NOT NULL,
  house_number VARCHAR(30)  NULL,
  village      VARCHAR(100) NOT NULL,
  mandal       VARCHAR(100) NOT NULL,
  district     VARCHAR(100) NOT NULL,
  state        VARCHAR(60)  NOT NULL DEFAULT 'Andhra Pradesh',
  pincode      CHAR(6)      NOT NULL,
  address_type VARCHAR(20)  NOT NULL DEFAULT 'Permanent',
  PRIMARY KEY (address_id),
  KEY idx_addr_district (district),
  CONSTRAINT fk_addr_farmer FOREIGN KEY (farmer_id) REFERENCES farmers (farmer_id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT chk_addr_type CHECK (address_type IN ('Permanent','Current','Farm','Other'))
) ENGINE=InnoDB;

CREATE TABLE farmer_land_records (
  land_id           CHAR(36)      NOT NULL,
  farmer_id         CHAR(36)      NOT NULL,
  survey_number     VARCHAR(40)   NOT NULL,
  passbook_number   VARCHAR(40)   NOT NULL,
  land_area         DECIMAL(10,2) NOT NULL,       -- acres
  ownership_type    VARCHAR(20)   NOT NULL DEFAULT 'Owned',
  village           VARCHAR(100)  NOT NULL,
  registration_date DATE          NULL,
  verified_by       VARCHAR(100)  NULL,
  verified_at       TIMESTAMP     NULL,
  PRIMARY KEY (land_id),
  UNIQUE KEY uq_land_survey (survey_number, village),   -- [RECOMMENDED]
  CONSTRAINT fk_land_farmer FOREIGN KEY (farmer_id) REFERENCES farmers (farmer_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_land_area CHECK (land_area > 0),
  CONSTRAINT chk_land_owner CHECK (ownership_type IN ('Owned','Leased','Joint'))
) ENGINE=InnoDB;

CREATE TABLE farmer_credit_accounts (
  credit_account_id  CHAR(36)      NOT NULL,
  farmer_id          CHAR(36)      NOT NULL,
  institution_name   VARCHAR(150)  NOT NULL,
  kcc_card_number    VARCHAR(30)   NOT NULL,
  total_credit_limit DECIMAL(12,2) NOT NULL,
  available_balance  DECIMAL(12,2) NOT NULL,
  repayment_due_date DATE          NULL,
  account_status     VARCHAR(20)   NOT NULL DEFAULT 'Active',
  PRIMARY KEY (credit_account_id),
  UNIQUE KEY uq_credit_kcc (kcc_card_number),
  CONSTRAINT fk_credit_farmer FOREIGN KEY (farmer_id) REFERENCES farmers (farmer_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_credit_limit CHECK (total_credit_limit >= 0 AND available_balance >= 0
                                     AND available_balance <= total_credit_limit),
  CONSTRAINT chk_credit_status CHECK (account_status IN ('Active','Closed','Suspended'))
) ENGINE=InnoDB;

/* ===== Group C: crops, land use ===== */
CREATE TABLE crops (
  crop_id     CHAR(36)     NOT NULL,
  category_id CHAR(36)     NOT NULL,
  crop_name   VARCHAR(100) NOT NULL,
  description TEXT         NULL,
  PRIMARY KEY (crop_id),
  UNIQUE KEY uq_crops_name (crop_name),             -- [RECOMMENDED]
  CONSTRAINT fk_crops_category FOREIGN KEY (category_id) REFERENCES crop_categories (category_id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE crop_varieties (
  variety_id    CHAR(36)     NOT NULL,
  crop_id       CHAR(36)     NOT NULL,
  variety_name  VARCHAR(100) NOT NULL,
  duration_days INT          NULL,
  description   TEXT         NULL,
  PRIMARY KEY (variety_id),
  UNIQUE KEY uq_variety (crop_id, variety_name),    -- [RECOMMENDED]
  CONSTRAINT fk_variety_crop FOREIGN KEY (crop_id) REFERENCES crops (crop_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_variety_days CHECK (duration_days IS NULL OR duration_days > 0)
) ENGINE=InnoDB;

CREATE TABLE seasonal_cultivator_rights (
  tenure_id              CHAR(36)    NOT NULL,
  land_id                CHAR(36)    NOT NULL,
  tenant_farmer_id       CHAR(36)    NOT NULL,
  owner_farmer_id        CHAR(36)    NOT NULL,
  agreement_type         VARCHAR(40) NOT NULL,
  non_encumbrance_clause BOOLEAN     NOT NULL DEFAULT FALSE,
  lease_expiry_date      DATE        NULL,
  approval_status        VARCHAR(20) NOT NULL DEFAULT 'Pending',
  PRIMARY KEY (tenure_id),
  CONSTRAINT fk_scr_land   FOREIGN KEY (land_id) REFERENCES farmer_land_records (land_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_scr_tenant FOREIGN KEY (tenant_farmer_id) REFERENCES farmers (farmer_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_scr_owner  FOREIGN KEY (owner_farmer_id) REFERENCES farmers (farmer_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_scr_status CHECK (approval_status IN ('Pending','Approved','Rejected','Expired'))
) ENGINE=InnoDB;

CREATE TABLE farm_fields (
  field_id        CHAR(36)      NOT NULL,
  land_id         CHAR(36)      NOT NULL,
  field_name      VARCHAR(100)  NOT NULL,
  field_area      DECIMAL(10,2) NOT NULL,
  soil_type       VARCHAR(60)   NULL,
  irrigation_type VARCHAR(60)   NULL,
  PRIMARY KEY (field_id),
  UNIQUE KEY uq_field_name (land_id, field_name),   -- [RECOMMENDED]
  CONSTRAINT fk_field_land FOREIGN KEY (land_id) REFERENCES farmer_land_records (land_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_field_area CHECK (field_area > 0)
) ENGINE=InnoDB;

CREATE TABLE soil_health_records (
  test_id         CHAR(36)      NOT NULL,
  field_id        CHAR(36)      NOT NULL,
  ph_level        DECIMAL(4,2)  NULL,
  organic_carbon  DECIMAL(5,2)  NULL,
  nitrogen_kg_ha  DECIMAL(8,2)  NULL,
  phosphorus_kg_ha DECIMAL(8,2) NULL,
  potassium_kg_ha DECIMAL(8,2)  NULL,
  test_date       DATE          NOT NULL,
  PRIMARY KEY (test_id),
  KEY idx_soil_field_date (field_id, test_date),
  CONSTRAINT fk_soil_field FOREIGN KEY (field_id) REFERENCES farm_fields (field_id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT chk_soil_ph CHECK (ph_level IS NULL OR ph_level BETWEEN 0 AND 14)
) ENGINE=InnoDB;

/* ===== Group D: RBK staff (circular with emp_password) ===== */
CREATE TABLE rbk_employees (
  employee_id       CHAR(36)     NOT NULL,
  rbk_id            CHAR(36)     NOT NULL,
  employee_name     VARCHAR(120) NOT NULL,
  designation       VARCHAR(80)  NOT NULL,
  gender            VARCHAR(10)  NULL,
  phone             VARCHAR(15)  NOT NULL,
  email             VARCHAR(120) NULL,
  emp_password_id   CHAR(36)     NULL,           -- FK added in section 3
  joining_date      DATE         NULL,
  employment_status VARCHAR(20)  NOT NULL DEFAULT 'Active',
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (employee_id),
  UNIQUE KEY uq_emp_phone (phone),
  UNIQUE KEY uq_emp_email (email),
  UNIQUE KEY uq_emp_pwd (emp_password_id),          -- [RECOMMENDED] 1:1
  CONSTRAINT fk_emp_rbk FOREIGN KEY (rbk_id) REFERENCES rbk_centres (rbk_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_emp_gender CHECK (gender IS NULL OR gender IN ('Male','Female','Other')),
  CONSTRAINT chk_emp_status CHECK (employment_status IN ('Active','Inactive','Resigned','Retired'))
) ENGINE=InnoDB;

CREATE TABLE emp_password (
  emp_password_id       CHAR(36)     NOT NULL,
  employee_id           CHAR(36)     NOT NULL,
  password_hash         VARCHAR(255) NOT NULL,
  confirm_password_hash VARCHAR(255) NULL,       -- kept from diagram; redundant, see documentation
  PRIMARY KEY (emp_password_id),
  UNIQUE KEY uq_emppwd_employee (employee_id),      -- [RECOMMENDED]
  CONSTRAINT fk_emppwd_employee FOREIGN KEY (employee_id) REFERENCES rbk_employees (employee_id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

/* ===== Group E: agri-inputs catalogue ===== */
CREATE TABLE agricultural_products (
  product_id   CHAR(36)      NOT NULL,
  company_id   CHAR(36)      NOT NULL,
  category_id  CHAR(36)      NOT NULL,
  product_name VARCHAR(150)  NOT NULL,
  description  TEXT          NULL,
  price        DECIMAL(10,2) NOT NULL,
  unit         VARCHAR(20)   NOT NULL,
  product_code VARCHAR(40)   NOT NULL,
  product_type VARCHAR(40)   NULL,
  status       VARCHAR(20)   NOT NULL DEFAULT 'Active',
  PRIMARY KEY (product_id),
  UNIQUE KEY uq_product_code (product_code),
  CONSTRAINT fk_prod_company  FOREIGN KEY (company_id)  REFERENCES agro_companies (company_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_prod_category FOREIGN KEY (category_id) REFERENCES product_categories (category_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_prod_price  CHECK (price >= 0),
  CONSTRAINT chk_prod_status CHECK (status IN ('Active','Inactive','Discontinued'))
) ENGINE=InnoDB;

CREATE TABLE product_batches (
  product_batch_id   CHAR(36)      NOT NULL,
  product_id         CHAR(36)      NOT NULL,
  batch_number       VARCHAR(50)   NOT NULL,
  manufacturing_date DATE          NULL,
  expiry_date        DATE          NULL,
  batch_status       VARCHAR(20)   NOT NULL DEFAULT 'Active',
  received_quantity  DECIMAL(12,2) NOT NULL DEFAULT 0,
  available_quantity DECIMAL(12,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (product_batch_id),
  UNIQUE KEY uq_product_batch_no (batch_number),
  CONSTRAINT fk_pbatch_product FOREIGN KEY (product_id) REFERENCES agricultural_products (product_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_pbatch_qty CHECK (received_quantity >= 0 AND available_quantity >= 0
                                   AND available_quantity <= received_quantity),
  CONSTRAINT chk_pbatch_dates CHECK (expiry_date IS NULL OR manufacturing_date IS NULL
                                     OR expiry_date > manufacturing_date),
  CONSTRAINT chk_pbatch_status CHECK (batch_status IN ('Active','Expired','Recalled','Exhausted'))
) ENGINE=InnoDB;

CREATE TABLE pre_booking_orders (
  preorder_id     CHAR(36)    NOT NULL,
  farmer_id       CHAR(36)    NOT NULL,
  rbk_id          CHAR(36)    NOT NULL,
  preorder_number VARCHAR(40) NOT NULL,
  target_season   VARCHAR(40) NULL,
  target_year     SMALLINT    NULL,
  order_status    VARCHAR(20) NOT NULL DEFAULT 'Pending',
  created_at      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (preorder_id),
  UNIQUE KEY uq_preorder_number (preorder_number),
  CONSTRAINT fk_preorder_farmer FOREIGN KEY (farmer_id) REFERENCES farmers (farmer_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_preorder_rbk FOREIGN KEY (rbk_id) REFERENCES rbk_centres (rbk_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_preorder_status CHECK (order_status IN ('Pending','Confirmed','Fulfilled','Cancelled'))
) ENGINE=InnoDB;

CREATE TABLE pre_booking_items (
  item_id            CHAR(36)      NOT NULL,
  preorder_id        CHAR(36)      NOT NULL,
  product_id         CHAR(36)      NOT NULL,
  requested_quantity DECIMAL(12,2) NOT NULL,
  PRIMARY KEY (item_id),
  UNIQUE KEY uq_prebook_item (preorder_id, product_id),   -- [RECOMMENDED]
  CONSTRAINT fk_pbi_preorder FOREIGN KEY (preorder_id) REFERENCES pre_booking_orders (preorder_id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_pbi_product FOREIGN KEY (product_id) REFERENCES agricultural_products (product_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_pbi_qty CHECK (requested_quantity > 0)
) ENGINE=InnoDB;

/* ===== Group F: cultivation cycle ===== */
CREATE TABLE cultivations (
  cultivation_id         CHAR(36)    NOT NULL,
  farmer_id              CHAR(36)    NOT NULL,
  field_id               CHAR(36)    NOT NULL,
  variety_id             CHAR(36)    NOT NULL,
  season_id              CHAR(36)    NOT NULL,
  sowing_date            DATE        NOT NULL,
  expected_harvest_date  DATE        NULL,
  cultivation_status     VARCHAR(20) NOT NULL DEFAULT 'Sown',
  PRIMARY KEY (cultivation_id),
  KEY idx_cult_status (cultivation_status),
  CONSTRAINT fk_cult_farmer  FOREIGN KEY (farmer_id)  REFERENCES farmers (farmer_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_cult_field   FOREIGN KEY (field_id)   REFERENCES farm_fields (field_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_cult_variety FOREIGN KEY (variety_id) REFERENCES crop_varieties (variety_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_cult_season  FOREIGN KEY (season_id)  REFERENCES cultivation_seasons (season_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_cult_dates CHECK (expected_harvest_date IS NULL OR expected_harvest_date >= sowing_date),
  CONSTRAINT chk_cult_status CHECK (cultivation_status IN ('Sown','Growing','Harvested','Failed','Abandoned'))
) ENGINE=InnoDB;

CREATE TABLE cultivation_activities (
  activity_id    CHAR(36)      NOT NULL,
  cultivation_id CHAR(36)      NOT NULL,
  activity_type  VARCHAR(60)   NOT NULL,
  activity_date  DATE          NOT NULL,
  description    TEXT          NULL,
  expense        DECIMAL(12,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (activity_id),
  CONSTRAINT fk_act_cult FOREIGN KEY (cultivation_id) REFERENCES cultivations (cultivation_id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT chk_act_expense CHECK (expense >= 0)
) ENGINE=InnoDB;

CREATE TABLE input_applications (
  application_id     CHAR(36)      NOT NULL,
  cultivation_id     CHAR(36)      NOT NULL,
  product_id         CHAR(36)      NOT NULL,
  product_batch_id   CHAR(36)      NOT NULL,
  quantity_used      DECIMAL(12,2) NOT NULL,
  application_date   DATE          NOT NULL,
  application_method VARCHAR(60)   NULL,
  remarks            TEXT          NULL,
  PRIMARY KEY (application_id),
  CONSTRAINT fk_ia_cult    FOREIGN KEY (cultivation_id)   REFERENCES cultivations (cultivation_id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_ia_product FOREIGN KEY (product_id)       REFERENCES agricultural_products (product_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_ia_batch   FOREIGN KEY (product_batch_id) REFERENCES product_batches (product_batch_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_ia_qty CHECK (quantity_used > 0)
) ENGINE=InnoDB;

CREATE TABLE harvest_records (
  harvest_id     CHAR(36)      NOT NULL,
  cultivation_id CHAR(36)      NOT NULL,
  harvest_date   DATE          NOT NULL,
  total_quantity DECIMAL(12,2) NOT NULL,
  unit           VARCHAR(10)   NOT NULL DEFAULT 'kg',
  remarks        TEXT          NULL,
  PRIMARY KEY (harvest_id),
  CONSTRAINT fk_harvest_cult FOREIGN KEY (cultivation_id) REFERENCES cultivations (cultivation_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_harvest_qty CHECK (total_quantity > 0)
) ENGINE=InnoDB;

CREATE TABLE crop_batches (
  crop_batch_id CHAR(36)      NOT NULL,
  harvest_id    CHAR(36)      NOT NULL,
  batch_code    VARCHAR(50)   NOT NULL,
  qr_code       VARCHAR(100)  NOT NULL,
  quantity      DECIMAL(12,2) NOT NULL,
  quality_status VARCHAR(30)  NULL,
  unit          VARCHAR(10)   NOT NULL DEFAULT 'kg',
  packing_date  DATE          NULL,
  batch_status  VARCHAR(20)   NOT NULL DEFAULT 'In Stock',
  created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (crop_batch_id),
  UNIQUE KEY uq_crop_batch_code (batch_code),
  UNIQUE KEY uq_crop_batch_qr (qr_code),
  CONSTRAINT fk_cbatch_harvest FOREIGN KEY (harvest_id) REFERENCES harvest_records (harvest_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_cbatch_qty CHECK (quantity > 0)
) ENGINE=InnoDB;

/* ===== Group G: warehouse and sales ===== */
CREATE TABLE warehouse_inventory (
  inventory_id  CHAR(36)      NOT NULL,
  warehouse_id  CHAR(36)      NOT NULL,
  crop_batch_id CHAR(36)      NOT NULL,
  quantity      DECIMAL(12,2) NOT NULL DEFAULT 0,
  storage_date  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_updated  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (inventory_id),
  UNIQUE KEY uq_wi_wh_batch (warehouse_id, crop_batch_id),   -- [RECOMMENDED]
  CONSTRAINT fk_wi_wh    FOREIGN KEY (warehouse_id)  REFERENCES warehouses (warehouse_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_wi_batch FOREIGN KEY (crop_batch_id) REFERENCES crop_batches (crop_batch_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_wi_qty CHECK (quantity >= 0)
) ENGINE=InnoDB;

CREATE TABLE stock_movements (
  movement_id   CHAR(36)      NOT NULL,
  warehouse_id  CHAR(36)      NOT NULL,
  crop_batch_id CHAR(36)      NOT NULL,
  movement_type VARCHAR(20)   NOT NULL,
  quantity      DECIMAL(12,2) NOT NULL,
  movement_date DATE          NOT NULL,
  reference_id  CHAR(36)      NULL,      -- no FK in diagram: points to a sales order, etc.
  PRIMARY KEY (movement_id),
  KEY idx_sm_ref (reference_id),
  CONSTRAINT fk_sm_wh    FOREIGN KEY (warehouse_id)  REFERENCES warehouses (warehouse_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_sm_batch FOREIGN KEY (crop_batch_id) REFERENCES crop_batches (crop_batch_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_sm_type CHECK (movement_type IN ('IN','OUT','TRANSFER','ADJUSTMENT')),
  CONSTRAINT chk_sm_qty CHECK (quantity > 0)
) ENGINE=InnoDB;

CREATE TABLE sales_orders (
  sales_order_id   CHAR(36)      NOT NULL,
  farmer_id        CHAR(36)      NOT NULL,
  buyer_id         CHAR(36)      NOT NULL,
  delivery_address VARCHAR(255)  NULL,
  order_date       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  total_amount     DECIMAL(14,2) NOT NULL DEFAULT 0,
  payment_status   VARCHAR(20)   NOT NULL DEFAULT 'Pending',
  sales_channel    VARCHAR(30)   NULL,
  order_status     VARCHAR(20)   NOT NULL DEFAULT 'Placed',
  PRIMARY KEY (sales_order_id),
  KEY idx_so_date (order_date),
  CONSTRAINT fk_so_farmer FOREIGN KEY (farmer_id) REFERENCES farmers (farmer_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_so_buyer  FOREIGN KEY (buyer_id)  REFERENCES buyers (buyer_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_so_total CHECK (total_amount >= 0),
  CONSTRAINT chk_so_pay   CHECK (payment_status IN ('Pending','Partial','Paid','Refunded')),
  CONSTRAINT chk_so_stat  CHECK (order_status IN ('Placed','Processing','Shipped','Delivered','Cancelled'))
) ENGINE=InnoDB;

CREATE TABLE sales_order_items (
  sales_item_id  CHAR(36)      NOT NULL,
  sales_order_id CHAR(36)      NOT NULL,
  crop_batch_id  CHAR(36)      NOT NULL,
  quantity       DECIMAL(12,2) NOT NULL,
  unit_price     DECIMAL(10,2) NOT NULL,
  subtotal       DECIMAL(14,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,  -- [RECOMMENDED] derived value
  PRIMARY KEY (sales_item_id),
  UNIQUE KEY uq_soi (sales_order_id, crop_batch_id),        -- [RECOMMENDED]
  CONSTRAINT fk_soi_order FOREIGN KEY (sales_order_id) REFERENCES sales_orders (sales_order_id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_soi_batch FOREIGN KEY (crop_batch_id)  REFERENCES crop_batches (crop_batch_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_soi_vals CHECK (quantity > 0 AND unit_price >= 0)
) ENGINE=InnoDB;

CREATE TABLE sales_payments (
  payment_id            CHAR(36)      NOT NULL,
  sales_order_id        CHAR(36)      NOT NULL,
  amount                DECIMAL(14,2) NOT NULL,
  payment_method        VARCHAR(30)   NOT NULL,
  payment_date          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  payment_status        VARCHAR(20)   NOT NULL DEFAULT 'Pending',
  transaction_reference VARCHAR(60)   NULL,
  PRIMARY KEY (payment_id),
  KEY idx_sp_ref (transaction_reference),
  CONSTRAINT fk_sp_order FOREIGN KEY (sales_order_id) REFERENCES sales_orders (sales_order_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_sp_amount CHECK (amount > 0),
  CONSTRAINT chk_sp_status CHECK (payment_status IN ('Pending','Completed','Failed','Refunded'))
) ENGINE=InnoDB;

CREATE TABLE crop_quality_tests (
  quality_test_id     CHAR(36)     NOT NULL,
  crop_batch_id       CHAR(36)     NOT NULL,
  moisture_percentage DECIMAL(5,2) NULL,
  quality_grade       VARCHAR(20)  NULL,
  test_date           DATE         NOT NULL,
  test_result         VARCHAR(30)  NULL,
  remarks             TEXT         NULL,
  PRIMARY KEY (quality_test_id),
  CONSTRAINT fk_qt_batch FOREIGN KEY (crop_batch_id) REFERENCES crop_batches (crop_batch_id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT chk_qt_moist CHECK (moisture_percentage IS NULL OR moisture_percentage BETWEEN 0 AND 100)
) ENGINE=InnoDB;

CREATE TABLE shipments (
  shipment_id          CHAR(36)     NOT NULL,
  crop_batch_id        CHAR(36)     NOT NULL,
  source_location      VARCHAR(150) NOT NULL,
  destination_location VARCHAR(150) NOT NULL,
  vehicle_number       VARCHAR(20)  NULL,
  driver_name          VARCHAR(100) NULL,
  dispatch_date        DATETIME     NULL,
  delivery_date        DATETIME     NULL,
  shipment_status      VARCHAR(20)  NOT NULL DEFAULT 'Scheduled',
  PRIMARY KEY (shipment_id),
  KEY idx_ship_status (shipment_status),
  CONSTRAINT fk_ship_batch FOREIGN KEY (crop_batch_id) REFERENCES crop_batches (crop_batch_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_ship_dates CHECK (delivery_date IS NULL OR dispatch_date IS NULL OR delivery_date >= dispatch_date),
  CONSTRAINT chk_ship_status CHECK (shipment_status IN ('Scheduled','In Transit','Delivered','Cancelled','Delayed'))
) ENGINE=InnoDB;

CREATE TABLE shipment_items (
  shipment_item_id CHAR(36)      NOT NULL,
  shipment_id      CHAR(36)      NOT NULL,
  crop_batch_id    CHAR(36)      NOT NULL,
  sales_item_id    CHAR(36)      NOT NULL,
  quantity         DECIMAL(12,2) NOT NULL,   -- diagram text reads "varchar"; DECIMAL chosen (unclear in image)
  PRIMARY KEY (shipment_item_id),
  CONSTRAINT fk_shi_ship  FOREIGN KEY (shipment_id)   REFERENCES shipments (shipment_id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_shi_batch FOREIGN KEY (crop_batch_id) REFERENCES crop_batches (crop_batch_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_shi_sitem FOREIGN KEY (sales_item_id) REFERENCES sales_order_items (sales_item_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_shi_qty CHECK (quantity > 0)
) ENGINE=InnoDB;

CREATE TABLE traceability_events (
  event_id      CHAR(36)     NOT NULL,
  crop_batch_id CHAR(36)     NOT NULL,
  event_type    VARCHAR(40)  NOT NULL,
  location      VARCHAR(150) NULL,
  event_date    DATETIME     NOT NULL,
  description   TEXT         NULL,
  recorded_by   VARCHAR(100) NULL,
  PRIMARY KEY (event_id),
  KEY idx_trace_batch_date (crop_batch_id, event_date),
  CONSTRAINT fk_trace_batch FOREIGN KEY (crop_batch_id) REFERENCES crop_batches (crop_batch_id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

/* ===== Group H: RBK supply chain and input sales ===== */
CREATE TABLE rbk_supply_orders (
  supply_id               CHAR(36)      NOT NULL,
  rbk_id                  CHAR(36)      NOT NULL,
  company_id              CHAR(36)      NOT NULL,
  supply_date             DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expected_delivery_date  DATE          NULL,
  received_date           DATE          NULL,
  status                  VARCHAR(20)   NOT NULL DEFAULT 'Ordered',
  total_amount            DECIMAL(14,2) NOT NULL DEFAULT 0,
  created_by_employee_id  CHAR(36)      NULL,
  PRIMARY KEY (supply_id),
  CONSTRAINT fk_sup_rbk     FOREIGN KEY (rbk_id)     REFERENCES rbk_centres (rbk_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_sup_company FOREIGN KEY (company_id) REFERENCES agro_companies (company_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_sup_emp     FOREIGN KEY (created_by_employee_id) REFERENCES rbk_employees (employee_id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_sup_status CHECK (status IN ('Ordered','Partially Received','Received','Cancelled')),
  CONSTRAINT chk_sup_total  CHECK (total_amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE rbk_supply_items (
  item_id           CHAR(36)      NOT NULL,
  supply_id         CHAR(36)      NOT NULL,
  product_batch_id  CHAR(36)      NOT NULL,
  ordered_quantity  DECIMAL(12,2) NOT NULL,
  received_quantity DECIMAL(12,2) NOT NULL DEFAULT 0,
  rejected_quantity DECIMAL(12,2) NOT NULL DEFAULT 0,
  unit_price        DECIMAL(10,2) NOT NULL,
  PRIMARY KEY (item_id),
  UNIQUE KEY uq_rsi (supply_id, product_batch_id),          -- [RECOMMENDED]
  CONSTRAINT fk_rsi_supply FOREIGN KEY (supply_id)        REFERENCES rbk_supply_orders (supply_id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_rsi_batch  FOREIGN KEY (product_batch_id) REFERENCES product_batches (product_batch_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_rsi_qty CHECK (ordered_quantity > 0 AND received_quantity >= 0
                                AND rejected_quantity >= 0 AND unit_price >= 0)
) ENGINE=InnoDB;

CREATE TABLE rbk_inventory (
  inventory_id     CHAR(36)      NOT NULL,
  rbk_id           CHAR(36)      NOT NULL,
  product_batch_id CHAR(36)      NOT NULL,
  quantity         DECIMAL(12,2) NOT NULL DEFAULT 0,
  last_updated     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (inventory_id),
  UNIQUE KEY uq_rbk_inv (rbk_id, product_batch_id),         -- [RECOMMENDED]
  CONSTRAINT fk_rinv_rbk   FOREIGN KEY (rbk_id)           REFERENCES rbk_centres (rbk_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_rinv_batch FOREIGN KEY (product_batch_id) REFERENCES product_batches (product_batch_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_rinv_qty CHECK (quantity >= 0)
) ENGINE=InnoDB;

CREATE TABLE input_purchases (
  purchase_id            CHAR(36)      NOT NULL,
  farmer_id              CHAR(36)      NOT NULL,
  rbk_id                 CHAR(36)      NOT NULL,
  purchase_date          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  total_amount           DECIMAL(14,2) NOT NULL DEFAULT 0,
  purchase_status        VARCHAR(20)   NOT NULL DEFAULT 'Pending',
  created_by_employee_id CHAR(36)      NULL,
  PRIMARY KEY (purchase_id),
  KEY idx_ip_date (purchase_date),
  CONSTRAINT fk_ip_farmer FOREIGN KEY (farmer_id) REFERENCES farmers (farmer_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_ip_rbk    FOREIGN KEY (rbk_id)    REFERENCES rbk_centres (rbk_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_ip_emp    FOREIGN KEY (created_by_employee_id) REFERENCES rbk_employees (employee_id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_ip_total  CHECK (total_amount >= 0),
  CONSTRAINT chk_ip_status CHECK (purchase_status IN ('Pending','Partial','Paid','Cancelled'))
) ENGINE=InnoDB;

CREATE TABLE input_purchase_items (
  item_id          CHAR(36)      NOT NULL,
  purchase_id      CHAR(36)      NOT NULL,
  product_batch_id CHAR(36)      NOT NULL,
  quantity         DECIMAL(12,2) NOT NULL,
  unit_price       DECIMAL(10,2) NOT NULL,
  subtotal         DECIMAL(14,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,  -- [RECOMMENDED]
  PRIMARY KEY (item_id),
  UNIQUE KEY uq_ipi (purchase_id, product_batch_id),        -- [RECOMMENDED]
  CONSTRAINT fk_ipi_purchase FOREIGN KEY (purchase_id)      REFERENCES input_purchases (purchase_id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_ipi_batch    FOREIGN KEY (product_batch_id) REFERENCES product_batches (product_batch_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_ipi_vals CHECK (quantity > 0 AND unit_price >= 0)
) ENGINE=InnoDB;

CREATE TABLE input_payments (
  payment_id            CHAR(36)      NOT NULL,
  purchase_id           CHAR(36)      NOT NULL,
  amount                DECIMAL(14,2) NOT NULL,
  payment_method        VARCHAR(30)   NOT NULL,
  payment_date          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  payment_status        VARCHAR(20)   NOT NULL DEFAULT 'Pending',
  transaction_reference VARCHAR(60)   NULL,
  PRIMARY KEY (payment_id),
  CONSTRAINT fk_ipay_purchase FOREIGN KEY (purchase_id) REFERENCES input_purchases (purchase_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_ipay_amount CHECK (amount > 0),
  CONSTRAINT chk_ipay_status CHECK (payment_status IN ('Pending','Completed','Failed','Refunded'))
) ENGINE=InnoDB;

CREATE TABLE rbk_stock_movements (
  movement_id   CHAR(36)      NOT NULL,
  inventory_id  CHAR(36)      NOT NULL,
  employee_id   CHAR(36)      NOT NULL,
  movement_type VARCHAR(20)   NOT NULL,
  quantity      DECIMAL(12,2) NOT NULL,
  movement_date DATE          NOT NULL,
  reference_id  CHAR(36)      NULL,      -- no FK in diagram (supply or purchase id)
  PRIMARY KEY (movement_id),
  KEY idx_rsm_ref (reference_id),
  CONSTRAINT fk_rsm_inv FOREIGN KEY (inventory_id) REFERENCES rbk_inventory (inventory_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_rsm_emp FOREIGN KEY (employee_id)  REFERENCES rbk_employees (employee_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_rsm_type CHECK (movement_type IN ('IN','OUT','ADJUSTMENT','RETURN')),
  CONSTRAINT chk_rsm_qty CHECK (quantity > 0)
) ENGINE=InnoDB;

CREATE TABLE system_users (
  user_id       CHAR(36)     NOT NULL,
  username      VARCHAR(50)  NOT NULL,
  email         VARCHAR(120) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  full_name     VARCHAR(120) NOT NULL,
  role          VARCHAR(30)  NOT NULL DEFAULT 'Admin',
  status        VARCHAR(20)  NOT NULL DEFAULT 'Active',
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  UNIQUE KEY uq_system_users_username (username),
  UNIQUE KEY uq_system_users_email (email)
) ENGINE=InnoDB;

/* ---------- 3. CIRCULAR FOREIGN KEYS (added after both tables exist) ---------- */
ALTER TABLE farmers
  ADD CONSTRAINT fk_farmers_auth FOREIGN KEY (authentication_id)
  REFERENCES biometric_authentication (authentication_id)
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE rbk_employees
  ADD CONSTRAINT fk_emp_password FOREIGN KEY (emp_password_id)
  REFERENCES emp_password (emp_password_id)
  ON DELETE SET NULL ON UPDATE CASCADE;

-- End of script


/* ======================================================================
   4. COMPREHENSIVE SEED DATA (PURE MYSQL COMMANDS)
   ====================================================================== */

SET FOREIGN_KEY_CHECKS = 0;

-- Data for table `administrative_regions` (15 records)
REPLACE INTO `administrative_regions` (`region_id`, `state_name`, `district_name`, `mandal_name`, `village_name`, `pincode`) VALUES ('REG-01', 'Andhra Pradesh', 'Guntur', 'Tenali', 'Angalakuduru', '522202');
REPLACE INTO `administrative_regions` (`region_id`, `state_name`, `district_name`, `mandal_name`, `village_name`, `pincode`) VALUES ('REG-02', 'Andhra Pradesh', 'Guntur', 'Mangalagiri', 'Navuluru', '522503');
REPLACE INTO `administrative_regions` (`region_id`, `state_name`, `district_name`, `mandal_name`, `village_name`, `pincode`) VALUES ('REG-03', 'Andhra Pradesh', 'Guntur', 'Amaravati', 'Dharanikota', '522020');
REPLACE INTO `administrative_regions` (`region_id`, `state_name`, `district_name`, `mandal_name`, `village_name`, `pincode`) VALUES ('REG-04', 'Andhra Pradesh', 'Krishna', 'Vijayawada Rural', 'Enikepadu', '521108');
REPLACE INTO `administrative_regions` (`region_id`, `state_name`, `district_name`, `mandal_name`, `village_name`, `pincode`) VALUES ('REG-05', 'Andhra Pradesh', 'Prakasam', 'Ongole', 'Karavadi', '523182');
REPLACE INTO `administrative_regions` (`region_id`, `state_name`, `district_name`, `mandal_name`, `village_name`, `pincode`) VALUES ('REG-06', 'Andhra Pradesh', 'Bapatla', 'Bapatla Urban', 'Karlapalem', '522101');
REPLACE INTO `administrative_regions` (`region_id`, `state_name`, `district_name`, `mandal_name`, `village_name`, `pincode`) VALUES ('REG-07', 'Andhra Pradesh', 'Krishna', 'Gudivada', 'Billapadu', '521301');
REPLACE INTO `administrative_regions` (`region_id`, `state_name`, `district_name`, `mandal_name`, `village_name`, `pincode`) VALUES ('REG-08', 'Andhra Pradesh', 'Palnadu', 'Narasaraopet', 'Petlurivaripalem', '522601');
REPLACE INTO `administrative_regions` (`region_id`, `state_name`, `district_name`, `mandal_name`, `village_name`, `pincode`) VALUES ('REG-09', 'Andhra Pradesh', 'East Godavari', 'Rajahmundry', 'Kadiyam', '533126');
REPLACE INTO `administrative_regions` (`region_id`, `state_name`, `district_name`, `mandal_name`, `village_name`, `pincode`) VALUES ('REG-10', 'Andhra Pradesh', 'West Godavari', 'Eluru', 'Sanivarapupeta', '534005');
REPLACE INTO `administrative_regions` (`region_id`, `state_name`, `district_name`, `mandal_name`, `village_name`, `pincode`) VALUES ('REG-11', 'Andhra Pradesh', 'Kurnool', 'Nandyal', 'Panyam', '518112');
REPLACE INTO `administrative_regions` (`region_id`, `state_name`, `district_name`, `mandal_name`, `village_name`, `pincode`) VALUES ('REG-12', 'Andhra Pradesh', 'SPSR Nellore', 'Kavali', 'Musunuru', '524201');
REPLACE INTO `administrative_regions` (`region_id`, `state_name`, `district_name`, `mandal_name`, `village_name`, `pincode`) VALUES ('REG-13', 'Andhra Pradesh', 'Chittoor', 'Madanapalle', 'Valasapalle', '517325');
REPLACE INTO `administrative_regions` (`region_id`, `state_name`, `district_name`, `mandal_name`, `village_name`, `pincode`) VALUES ('REG-14', 'Andhra Pradesh', 'Anantapur', 'Tadipatri', 'Yerraguntapalli', '515411');
REPLACE INTO `administrative_regions` (`region_id`, `state_name`, `district_name`, `mandal_name`, `village_name`, `pincode`) VALUES ('REG-15', 'Andhra Pradesh', 'Visakhapatnam', 'Anakapalle', 'Kasimkota', '531031');

-- Data for table `agricultural_products` (20 records)
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-01', 'COMP-01', 'PCAT-02', 'Gromor Urea 46% N (45kg)', 'High nitrogen granulated fertilizer for vigorous vegetative growth', 266.5, 'Bag (45kg)', 'FERT-UREA-45', 'Nitrogenous', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-02', 'COMP-01', 'PCAT-02', 'Gromor DAP 18-46-0 (50kg)', 'Essential phosphatic fertilizer for root establishment and tillering', 1350, 'Bag (50kg)', 'FERT-DAP-50', 'Complex', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-03', 'COMP-02', 'PCAT-01', 'Certified BPT-5204 Paddy Seeds (25kg)', 'Tested 98% germination certified paddy foundation seeds', 1125, 'Bag (25kg)', 'SEED-BPT5204-25', 'Certified Seed', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-04', 'COMP-03', 'PCAT-04', 'Confidor 200 SL Imidacloprid (250ml)', 'Systemic insecticide for sucking pests in chilli and cotton', 420, 'Bottle (250ml)', 'PEST-CONF-250', 'Insecticide', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-05', 'COMP-04', 'PCAT-05', 'UPL Saaf Fungicide Carbendazim+Mancozeb (500g)', 'Broad spectrum protective and curative fungicide', 380, 'Pack (500g)', 'FUNG-SAAF-500', 'Fungicide', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-06', 'COMP-01', 'PCAT-02', 'Muriate of Potash MOP 60% K2O (50kg)', 'Potassic fertilizer improving grain weight, disease tolerance, and shine', 1700, 'Bag (50kg)', 'FERT-MOP-50', 'Potassic', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-07', 'COMP-01', 'PCAT-02', 'Gromor 20-20-0-13 Ammonium Phosphate Sulphate (50kg)', 'NPKS complex fertilizer with 13% essential sulphur for pulses & oilseeds', 1250, 'Bag (50kg)', 'FERT-2020-50', 'Complex', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-08', 'COMP-09', 'PCAT-01', 'NSC Certified MTU-1010 Paddy Seeds (25kg)', 'Certified seed with high vigor, disease tested by seed certification agency', 950, 'Bag (25kg)', 'SEED-MTU1010-25', 'Certified Seed', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-09', 'COMP-07', 'PCAT-01', 'Kaveri Jaadoo Bt-Cotton Seeds (450g)', 'BG-II hybrid bollworm resistant high fiber yield hybrid seeds', 864, 'Pkt (450g)', 'SEED-COTTON-450', 'Hybrid Seed', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-10', 'COMP-02', 'PCAT-04', 'Ampligo Chlorantraniliprole+Lambda (100ml)', 'Advanced dual-action insecticide for fall armyworm and pod borers', 780, 'Bottle (100ml)', 'PEST-AMPLI-100', 'Insecticide', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-11', 'COMP-03', 'PCAT-05', 'Nativo Tebuconazole+Trifloxystrobin (100g)', 'Premium systemic fungicide for sheath blight and blast control in paddy', 850, 'Pack (100g)', 'FUNG-NATI-100', 'Fungicide', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-12', 'COMP-04', 'PCAT-06', 'UPL Iris Herbicide Sodium Acifluorfen+Clodinafop (400ml)', 'Broad spectrum post-emergence herbicide for soybean and pulses', 620, 'Bottle (400ml)', 'HERB-IRIS-400', 'Herbicide', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-13', 'COMP-10', 'PCAT-03', 'IFFCO Nano Urea Liquid (500ml)', 'Nanotechnology liquid nitrogen fertilizer for direct foliar spray efficiency', 225, 'Bottle (500ml)', 'NANO-UREA-500', 'Bio-Fertilizer', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-14', 'COMP-10', 'PCAT-03', 'IFFCO Nano DAP Liquid (500ml)', 'Nano-scale bio-available phosphorus source reducing conventional fertilizer by 50%', 600, 'Bottle (500ml)', 'NANO-DAP-500', 'Bio-Fertilizer', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-15', 'COMP-05', 'PCAT-03', 'Godrej VIPUL Plant Growth Regulator Triacontanol (500ml)', 'Photosynthetic booster and flowering stimulant', 320, 'Bottle (500ml)', 'PGR-VIPUL-500', 'Bio-Stimulant', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-16', 'COMP-06', 'PCAT-07', 'Nagarjuna Zinc Sulphate Monohydrate 33% (5kg)', 'Essential micronutrient preventing Khaira disease in paddy delta soils', 450, 'Pack (5kg)', 'MICRO-ZN33-5', 'Micronutrient', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-17', 'COMP-08', 'PCAT-04', 'Tata Rallis Tafgor Dimethoate 30% EC (500ml)', 'Proven systemic insecticide for thrips, aphids and jassids', 310, 'Bottle (500ml)', 'PEST-TAF-500', 'Insecticide', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-18', 'COMP-07', 'PCAT-01', 'Kaveri KMH-258 Hybrid Maize Seeds (4kg)', 'High cob weight orange flint grain high yielding hybrid', 980, 'Pack (4kg)', 'SEED-MAIZE-4', 'Hybrid Seed', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-19', 'COMP-09', 'PCAT-01', 'NSC Certified LBG-752 Black Gram Seeds (10kg)', 'Certified seed lot suitable for zero-tillage rice fallow sowing', 1200, 'Bag (10kg)', 'SEED-BG752-10', 'Certified Seed', 'Active');
REPLACE INTO `agricultural_products` (`product_id`, `company_id`, `category_id`, `product_name`, `description`, `price`, `unit`, `product_code`, `product_type`, `status`) VALUES ('PROD-20', 'COMP-03', 'PCAT-07', 'Bayer Ambition Amino Acid Micronutrient Tonic (1L)', 'Bio-activator with fulvic and amino acids for heat/drought stress recovery', 1150, 'Bottle (1L)', 'TONIC-AMBI-1L', 'Micronutrient', 'Active');

-- Data for table `agro_companies` (10 records)
REPLACE INTO `agro_companies` (`company_id`, `company_name`, `registration_number`, `phone`, `email`, `GST_number`, `address`, `established_date`) VALUES ('COMP-01', 'Coromandel International Ltd', 'REG-COR-AP-001', '0863223344', 'contact@coromandel.biz', '37AAACC1234A1Z9', 'Coromandel House, Guntur', '1961-04-10');
REPLACE INTO `agro_companies` (`company_id`, `company_name`, `registration_number`, `phone`, `email`, `GST_number`, `address`, `established_date`) VALUES ('COMP-02', 'Syngenta India Ltd', 'REG-SYN-IN-002', '0863234455', 'customercare@syngenta.com', '37AAACS5678B1Z7', 'Highway Road, Vijayawada', '2000-01-15');
REPLACE INTO `agro_companies` (`company_id`, `company_name`, `registration_number`, `phone`, `email`, `GST_number`, `address`, `established_date`) VALUES ('COMP-03', 'Bayer CropScience Ltd', 'REG-BAY-IN-003', '0863245566', 'india@bayer.com', '37AAACB9012C1Z5', 'APIIC Industrial Area, Tenali', '1995-08-20');
REPLACE INTO `agro_companies` (`company_id`, `company_name`, `registration_number`, `phone`, `email`, `GST_number`, `address`, `established_date`) VALUES ('COMP-04', 'UPL India Ltd', 'REG-UPL-IN-004', '0863256677', 'connect@upl-ltd.com', '37AAACU3456D1Z3', 'Ring Road, Guntur', '1980-05-29');
REPLACE INTO `agro_companies` (`company_id`, `company_name`, `registration_number`, `phone`, `email`, `GST_number`, `address`, `established_date`) VALUES ('COMP-05', 'Godrej Agrovet Ltd', 'REG-GOD-AP-005', '0863267788', 'agri@godrejagrovet.com', '37AAACG7890E1Z1', 'Industrial Estate, Tenali', '1991-11-24');
REPLACE INTO `agro_companies` (`company_id`, `company_name`, `registration_number`, `phone`, `email`, `GST_number`, `address`, `established_date`) VALUES ('COMP-06', 'Nagarjuna Fertilizers and Chemicals Ltd', 'REG-NFCL-006', '0863278899', 'sales@nagarjuna.com', '37AAACN4455F1Z2', 'Nagarjuna Hills, Vijayawada', '1985-03-12');
REPLACE INTO `agro_companies` (`company_id`, `company_name`, `registration_number`, `phone`, `email`, `GST_number`, `address`, `established_date`) VALUES ('COMP-07', 'Kaveri Seed Company Ltd', 'REG-KAV-007', '0863289900', 'info@kaveriseeds.in', '37AAACK1122G1Z4', 'Seed Park, Guntur', '1986-09-05');
REPLACE INTO `agro_companies` (`company_id`, `company_name`, `registration_number`, `phone`, `email`, `GST_number`, `address`, `established_date`) VALUES ('COMP-08', 'Rallis India Ltd (Tata Enterprise)', 'REG-RAL-008', '0863290011', 'agro@rallis.com', '37AAACR3344H1Z6', 'Benz Circle, Vijayawada', '1948-08-23');
REPLACE INTO `agro_companies` (`company_id`, `company_name`, `registration_number`, `phone`, `email`, `GST_number`, `address`, `established_date`) VALUES ('COMP-09', 'National Seeds Corporation Ltd', 'REG-NSC-009', '0863211122', 'support@indiaseeds.gov.in', '37AAACN9988I1Z8', 'Central Godown, Guntur', '1963-03-01');
REPLACE INTO `agro_companies` (`company_id`, `company_name`, `registration_number`, `phone`, `email`, `GST_number`, `address`, `established_date`) VALUES ('COMP-10', 'IFFCO AP Marketing Federation', 'REG-IFF-010', '0863222233', 'coop@iffco.in', '37AAAII7766J1Z0', 'Fertilizer Bhavan, Vijayawada', '1967-11-03');

-- Data for table `biometric_authentication` (15 records)
REPLACE INTO `biometric_authentication` (`authentication_id`, `farmer_id`, `aadhaar_number`, `biometric_type`, `status`, `authenticated_at`) VALUES ('BIO-7CCFAE', 'FAR-A6F321', 'XXXX-XXXX-1111', 'Fingerprint', 'Verified', '2026-11-22 13:22:38');
REPLACE INTO `biometric_authentication` (`authentication_id`, `farmer_id`, `aadhaar_number`, `biometric_type`, `status`, `authenticated_at`) VALUES ('BIO-428625', 'FAR-2EBF3A', 'XXXX-XXXX-8c1f', 'Fingerprint', 'Verified', '2026-11-22 13:23:29');
REPLACE INTO `biometric_authentication` (`authentication_id`, `farmer_id`, `aadhaar_number`, `biometric_type`, `status`, `authenticated_at`) VALUES ('BIO-2B344E', 'FAR-548814', 'XXXX-XXXX-3b78', 'Fingerprint', 'Verified', '2026-11-24 16:37:38');
REPLACE INTO `biometric_authentication` (`authentication_id`, `farmer_id`, `aadhaar_number`, `biometric_type`, `status`, `authenticated_at`) VALUES ('BIO-0A93C5', 'FAR-C70ACA', 'XXXX-XXXX-1531', 'Fingerprint', 'Verified', '2026-11-24 16:42:43');
REPLACE INTO `biometric_authentication` (`authentication_id`, `farmer_id`, `aadhaar_number`, `biometric_type`, `status`, `authenticated_at`) VALUES ('BIO-342CBA', 'FAR-5CF802', 'XXXX-XXXX-79fd', 'Fingerprint', 'Verified', '2026-11-24 16:52:27');
REPLACE INTO `biometric_authentication` (`authentication_id`, `farmer_id`, `aadhaar_number`, `biometric_type`, `status`, `authenticated_at`) VALUES ('BIO-001', 'FAR-001', 'XXXX-XXXX-9812', 'Fingerprint & Iris', 'Verified', '2026-01-10 10:30:00');
REPLACE INTO `biometric_authentication` (`authentication_id`, `farmer_id`, `aadhaar_number`, `biometric_type`, `status`, `authenticated_at`) VALUES ('BIO-002', 'FAR-002', 'XXXX-XXXX-4521', 'Fingerprint', 'Verified', '2026-01-12 11:15:00');
REPLACE INTO `biometric_authentication` (`authentication_id`, `farmer_id`, `aadhaar_number`, `biometric_type`, `status`, `authenticated_at`) VALUES ('BIO-003', 'FAR-003', 'XXXX-XXXX-7834', 'Iris Scan', 'Verified', '2026-01-15 14:00:00');
REPLACE INTO `biometric_authentication` (`authentication_id`, `farmer_id`, `aadhaar_number`, `biometric_type`, `status`, `authenticated_at`) VALUES ('BIO-004', 'FAR-004', 'XXXX-XXXX-3319', 'Fingerprint', 'Verified', '2026-01-18 09:45:00');
REPLACE INTO `biometric_authentication` (`authentication_id`, `farmer_id`, `aadhaar_number`, `biometric_type`, `status`, `authenticated_at`) VALUES ('BIO-005', 'FAR-005', 'XXXX-XXXX-6628', 'Fingerprint', 'Verified', '2026-01-20 16:20:00');
REPLACE INTO `biometric_authentication` (`authentication_id`, `farmer_id`, `aadhaar_number`, `biometric_type`, `status`, `authenticated_at`) VALUES ('BIO-006', 'FAR-006', 'XXXX-XXXX-1123', 'Fingerprint', 'Verified', '2026-02-05 10:00:00');
REPLACE INTO `biometric_authentication` (`authentication_id`, `farmer_id`, `aadhaar_number`, `biometric_type`, `status`, `authenticated_at`) VALUES ('BIO-007', 'FAR-007', 'XXXX-XXXX-2234', 'Fingerprint & Iris', 'Verified', '2026-02-12 11:30:00');
REPLACE INTO `biometric_authentication` (`authentication_id`, `farmer_id`, `aadhaar_number`, `biometric_type`, `status`, `authenticated_at`) VALUES ('BIO-008', 'FAR-008', 'XXXX-XXXX-3345', 'Fingerprint', 'Verified', '2026-02-18 14:15:00');
REPLACE INTO `biometric_authentication` (`authentication_id`, `farmer_id`, `aadhaar_number`, `biometric_type`, `status`, `authenticated_at`) VALUES ('BIO-009', 'FAR-009', 'XXXX-XXXX-4456', 'Iris Scan', 'Verified', '2026-02-25 09:30:00');
REPLACE INTO `biometric_authentication` (`authentication_id`, `farmer_id`, `aadhaar_number`, `biometric_type`, `status`, `authenticated_at`) VALUES ('BIO-010', 'FAR-010', 'XXXX-XXXX-5567', 'Fingerprint', 'Verified', '2026-03-02 15:45:00');

-- Data for table `buyers` (10 records)
REPLACE INTO `buyers` (`buyer_id`, `buyer_name`, `buyer_type`, `phone`, `email`, `address`, `registration_number`, `buyer_password_hash`) VALUES ('BUY-001', 'ITC Agri Business Division', 'Wholesaler', '9848111222', 'procure@itcagri.com', 'ITC Agri Tower, Guntur AP', 'GSTIN37AAACI1234F1Z1', '5b00747be16208921be89629dbfe741c4ad5453e0c48061f945e668f3ad4b69f');
REPLACE INTO `buyers` (`buyer_id`, `buyer_name`, `buyer_type`, `phone`, `email`, `address`, `registration_number`, `buyer_password_hash`) VALUES ('BUY-002', 'BigBasket Fresh Sourcing', 'Retailer', '9848222333', 'sourcing@bigbasket.com', 'DC-4, Autonagar, Vijayawada', 'GSTIN37AABCB9876E1Z5', '5b00747be16208921be89629dbfe741c4ad5453e0c48061f945e668f3ad4b69f');
REPLACE INTO `buyers` (`buyer_id`, `buyer_name`, `buyer_type`, `phone`, `email`, `address`, `registration_number`, `buyer_password_hash`) VALUES ('BUY-003', 'Godrej Agrovet Ltd', 'Processor', '9848333444', 'support@godrejagrovet.com', 'Industrial Estate, Tenali', 'GSTIN37AACCG5544D1Z8', '5b00747be16208921be89629dbfe741c4ad5453e0c48061f945e668f3ad4b69f');
REPLACE INTO `buyers` (`buyer_id`, `buyer_name`, `buyer_type`, `phone`, `email`, `address`, `registration_number`, `buyer_password_hash`) VALUES ('BUY-004', 'Southern Agro Exports Ltd', 'Exporter', '9848444555', 'exports@southernagro.in', 'Port Road, Krishnapatnam', 'GSTIN37AAACS6677A1Z3', '5b00747be16208921be89629dbfe741c4ad5453e0c48061f945e668f3ad4b69f');
REPLACE INTO `buyers` (`buyer_id`, `buyer_name`, `buyer_type`, `phone`, `email`, `address`, `registration_number`, `buyer_password_hash`) VALUES ('BUY-005', 'Reliance Retail Agro Procurement', 'Retailer', '9848555666', 'agro.south@ril.com', 'Reliance Logistics Hub, Gannavaram', 'GSTIN37AAACR7788B1Z5', '5b00747be16208921be89629dbfe741c4ad5453e0c48061f945e668f3ad4b69f');
REPLACE INTO `buyers` (`buyer_id`, `buyer_name`, `buyer_type`, `phone`, `email`, `address`, `registration_number`, `buyer_password_hash`) VALUES ('BUY-006', 'Olam Agri India Pvt Ltd', 'Exporter', '9848666777', 'procure.ap@olamagri.com', 'Port Area, Kakinada', 'GSTIN37AAACO8899C1Z7', '5b00747be16208921be89629dbfe741c4ad5453e0c48061f945e668f3ad4b69f');
REPLACE INTO `buyers` (`buyer_id`, `buyer_name`, `buyer_type`, `phone`, `email`, `address`, `registration_number`, `buyer_password_hash`) VALUES ('BUY-007', 'Heritage Foods Agri Division', 'Processor', '9848777888', 'agri@heritagefoods.in', 'Dinnedevarapadu, Guntur', 'GSTIN37AAACH9900D1Z9', '5b00747be16208921be89629dbfe741c4ad5453e0c48061f945e668f3ad4b69f');
REPLACE INTO `buyers` (`buyer_id`, `buyer_name`, `buyer_type`, `phone`, `email`, `address`, `registration_number`, `buyer_password_hash`) VALUES ('BUY-008', 'Adani Wilmar Commodity Desk', 'Wholesaler', '9848888999', 'commodities@adaniwilmar.in', 'Marthand complex, Guntur', 'GSTIN37AAACA1122E1Z1', '5b00747be16208921be89629dbfe741c4ad5453e0c48061f945e668f3ad4b69f');
REPLACE INTO `buyers` (`buyer_id`, `buyer_name`, `buyer_type`, `phone`, `email`, `address`, `registration_number`, `buyer_password_hash`) VALUES ('BUY-009', 'Tata Chemicals Rallis Produce Sourcing', 'Wholesaler', '9848999000', 'sourcing@tatachemicals.com', 'Autonagar, Guntur', 'GSTIN37AAACT3344F1Z3', '5b00747be16208921be89629dbfe741c4ad5453e0c48061f945e668f3ad4b69f');
REPLACE INTO `buyers` (`buyer_id`, `buyer_name`, `buyer_type`, `phone`, `email`, `address`, `registration_number`, `buyer_password_hash`) VALUES ('BUY-010', 'Patanjali Agro Andhra Division', 'Processor', '9848000111', 'ap.sourcing@patanjaliayurved.org', 'Industrial Hub, Vijayawada', 'GSTIN37AAACP5566G1Z5', '5b00747be16208921be89629dbfe741c4ad5453e0c48061f945e668f3ad4b69f');

-- Data for table `crop_batches` (10 records)
REPLACE INTO `crop_batches` (`crop_batch_id`, `harvest_id`, `batch_code`, `qr_code`, `quantity`, `quality_status`, `unit`, `packing_date`, `batch_status`, `created_at`) VALUES ('CBAT-C3CFAB', 'HARV-BE9828', 'CB-2026-73E718', 'QR-AGRI-CB-2026-73E718-AP', 4800, 'Grade A', 'kg', '2026-11-15', 'In Stock', '2026-11-22 13:22:38');
REPLACE INTO `crop_batches` (`crop_batch_id`, `harvest_id`, `batch_code`, `qr_code`, `quantity`, `quality_status`, `unit`, `packing_date`, `batch_status`, `created_at`) VALUES ('CBAT-09ABC2', 'HARV-5F4A5B', 'CB-2026-B63B05', 'QR-AGRI-CB-2026-B63B05-AP', 4800, 'Grade A', 'kg', '2026-11-15', 'In Stock', '2026-11-22 13:23:14');
REPLACE INTO `crop_batches` (`crop_batch_id`, `harvest_id`, `batch_code`, `qr_code`, `quantity`, `quality_status`, `unit`, `packing_date`, `batch_status`, `created_at`) VALUES ('CBAT-7F5C49', 'HARV-7348C5', 'CB-2026-626EAF', 'QR-AGRI-CB-2026-626EAF-AP', 4800, 'Grade A', 'kg', '2026-11-15', 'In Stock', '2026-11-22 13:23:29');
REPLACE INTO `crop_batches` (`crop_batch_id`, `harvest_id`, `batch_code`, `qr_code`, `quantity`, `quality_status`, `unit`, `packing_date`, `batch_status`, `created_at`) VALUES ('CBAT-A51896', 'HARV-509BF3', 'CB-2026-BCCC63', 'QR-AGRI-CB-2026-BCCC63-AP', 4500, 'Grade', 'kg', '2026-11-21', 'In Stock', '2026-11-23 03:45:54');
REPLACE INTO `crop_batches` (`crop_batch_id`, `harvest_id`, `batch_code`, `qr_code`, `quantity`, `quality_status`, `unit`, `packing_date`, `batch_status`, `created_at`) VALUES ('CBAT-F82472', 'HARV-2AA99D', 'CB-2026-6BAE0D', 'QR-AGRI-CB-2026-6BAE0D-AP', 4800, 'Grade A', 'kg', '2026-11-15', 'In Stock', '2026-11-24 16:37:38');
REPLACE INTO `crop_batches` (`crop_batch_id`, `harvest_id`, `batch_code`, `qr_code`, `quantity`, `quality_status`, `unit`, `packing_date`, `batch_status`, `created_at`) VALUES ('CBAT-FFF4ED', 'HARV-05C723', 'CB-2026-4F66A7', 'QR-AGRI-CB-2026-4F66A7-AP', 4800, 'Grade A', 'kg', '2026-11-15', 'In Stock', '2026-11-24 16:42:43');
REPLACE INTO `crop_batches` (`crop_batch_id`, `harvest_id`, `batch_code`, `qr_code`, `quantity`, `quality_status`, `unit`, `packing_date`, `batch_status`, `created_at`) VALUES ('CBAT-B4F5B5', 'HARV-078ABE', 'CB-2026-150B94', 'QR-AGRI-CB-2026-150B94-AP', 4800, 'Grade A', 'kg', '2026-11-15', 'In Stock', '2026-11-24 16:52:27');
REPLACE INTO `crop_batches` (`crop_batch_id`, `harvest_id`, `batch_code`, `qr_code`, `quantity`, `quality_status`, `unit`, `packing_date`, `batch_status`, `created_at`) VALUES ('CBAT-001', 'HARV-001', 'CB-2026-MTU-001', 'QR-AGRI-MTU1010-GNT-01', 5800, 'Grade A', 'kg', '2026-10-16', 'In Stock', '2026-11-24 17:37:29');
REPLACE INTO `crop_batches` (`crop_batch_id`, `harvest_id`, `batch_code`, `qr_code`, `quantity`, `quality_status`, `unit`, `packing_date`, `batch_status`, `created_at`) VALUES ('CBAT-002', 'HARV-002', 'CB-2026-BPT-002', 'QR-AGRI-BPT5204-GNT-02', 4500, 'Grade A+', 'kg', '2026-10-29', 'In Stock', '2026-11-24 17:37:29');
REPLACE INTO `crop_batches` (`crop_batch_id`, `harvest_id`, `batch_code`, `qr_code`, `quantity`, `quality_status`, `unit`, `packing_date`, `batch_status`, `created_at`) VALUES ('CBAT-003', 'HARV-003', 'CB-2026-MAIZ-003', 'QR-AGRI-MAIZ3396-KRS-03', 8500, 'Grade A', 'kg', '2026-10-26', 'In Stock', '2026-11-24 17:37:29');

-- Data for table `crop_categories` (8 records)
REPLACE INTO `crop_categories` (`category_id`, `category_name`, `description`) VALUES ('CCAT-01', 'Cereals & Grains', 'Staple food crops including Paddy, Maize, Wheat, Millets');
REPLACE INTO `crop_categories` (`category_id`, `category_name`, `description`) VALUES ('CCAT-02', 'Pulses & Legumes', 'Protein rich crops like Black Gram, Red Gram, Green Gram, Bengal Gram');
REPLACE INTO `crop_categories` (`category_id`, `category_name`, `description`) VALUES ('CCAT-03', 'Commercial & Cash Crops', 'High value crops including Cotton, Tobacco, Sugarcane, Jute');
REPLACE INTO `crop_categories` (`category_id`, `category_name`, `description`) VALUES ('CCAT-04', 'Spices & Condiments', 'Chilli, Turmeric, Coriander, Ginger, Garlic, Cumin');
REPLACE INTO `crop_categories` (`category_id`, `category_name`, `description`) VALUES ('CCAT-05', 'Oilseeds', 'Groundnut, Sunflower, Mustard, Sesame, Soybean');
REPLACE INTO `crop_categories` (`category_id`, `category_name`, `description`) VALUES ('CCAT-06', 'Horticulture Fruits', 'Mango, Banana, Guava, Sweet Orange, Papaya');
REPLACE INTO `crop_categories` (`category_id`, `category_name`, `description`) VALUES ('CCAT-07', 'Vegetables & Greens', 'Tomato, Brinjal, Bhendi, Onion, Gourds, Leafy vegetables');
REPLACE INTO `crop_categories` (`category_id`, `category_name`, `description`) VALUES ('CCAT-08', 'Plantation Crops', 'Coconut, Oil Palm, Cashewnut, Cocoa');

-- Data for table `crop_quality_tests` (10 records)
REPLACE INTO `crop_quality_tests` (`quality_test_id`, `crop_batch_id`, `moisture_percentage`, `quality_grade`, `test_date`, `test_result`, `remarks`) VALUES ('TEST-3866D2', 'CBAT-C3CFAB', 12.8, 'Grade A', '2026-11-15', 'Passed', 'Certified standard moisture & quality parameters');
REPLACE INTO `crop_quality_tests` (`quality_test_id`, `crop_batch_id`, `moisture_percentage`, `quality_grade`, `test_date`, `test_result`, `remarks`) VALUES ('TEST-CCAB19', 'CBAT-09ABC2', 12.8, 'Grade A', '2026-11-15', 'Passed', 'Certified standard moisture & quality parameters');
REPLACE INTO `crop_quality_tests` (`quality_test_id`, `crop_batch_id`, `moisture_percentage`, `quality_grade`, `test_date`, `test_result`, `remarks`) VALUES ('TEST-DBBF2E', 'CBAT-7F5C49', 12.8, 'Grade A', '2026-11-15', 'Passed', 'Certified standard moisture & quality parameters');
REPLACE INTO `crop_quality_tests` (`quality_test_id`, `crop_batch_id`, `moisture_percentage`, `quality_grade`, `test_date`, `test_result`, `remarks`) VALUES ('TEST-886C59', 'CBAT-A51896', 12.8, 'Grade', '2026-11-21', 'Passed', 'Certified standard moisture & quality parameters');
REPLACE INTO `crop_quality_tests` (`quality_test_id`, `crop_batch_id`, `moisture_percentage`, `quality_grade`, `test_date`, `test_result`, `remarks`) VALUES ('TEST-9EA87B', 'CBAT-F82472', 12.8, 'Grade A', '2026-11-15', 'Passed', 'Certified standard moisture & quality parameters');
REPLACE INTO `crop_quality_tests` (`quality_test_id`, `crop_batch_id`, `moisture_percentage`, `quality_grade`, `test_date`, `test_result`, `remarks`) VALUES ('TEST-4B5FF5', 'CBAT-FFF4ED', 12.8, 'Grade A', '2026-11-15', 'Passed', 'Certified standard moisture & quality parameters');
REPLACE INTO `crop_quality_tests` (`quality_test_id`, `crop_batch_id`, `moisture_percentage`, `quality_grade`, `test_date`, `test_result`, `remarks`) VALUES ('TEST-080594', 'CBAT-B4F5B5', 12.8, 'Grade A', '2026-11-15', 'Passed', 'Certified standard moisture & quality parameters');
REPLACE INTO `crop_quality_tests` (`quality_test_id`, `crop_batch_id`, `moisture_percentage`, `quality_grade`, `test_date`, `test_result`, `remarks`) VALUES ('TEST-001', 'CBAT-001', 13.2, 'Grade A', '2026-10-17', 'Passed', 'Moisture optimal for storage, foreign matter 0.4%, MSP Grade approved');
REPLACE INTO `crop_quality_tests` (`quality_test_id`, `crop_batch_id`, `moisture_percentage`, `quality_grade`, `test_date`, `test_result`, `remarks`) VALUES ('TEST-002', 'CBAT-002', 12.5, 'Grade A+', '2026-10-30', 'Passed', 'Superior aromatic quality, head rice recovery 68%, Export Eligible');
REPLACE INTO `crop_quality_tests` (`quality_test_id`, `crop_batch_id`, `moisture_percentage`, `quality_grade`, `test_date`, `test_result`, `remarks`) VALUES ('TEST-003', 'CBAT-003', 13.8, 'Grade A', '2026-10-27', 'Passed', 'Uniform moisture, zero aflatoxin, approved for starch processing');

-- Data for table `crop_varieties` (8 records)
REPLACE INTO `crop_varieties` (`variety_id`, `crop_id`, `variety_name`, `duration_days`, `description`) VALUES ('VAR-01', 'CROP-01', 'BPT-5204 (Samba Masuri)', 145, 'Fine grain premium rice variety with excellent cooking quality.');
REPLACE INTO `crop_varieties` (`variety_id`, `crop_id`, `variety_name`, `duration_days`, `description`) VALUES ('VAR-02', 'CROP-01', 'MTU-1010 (Cottondora Sannalu)', 120, 'Short duration high yielding blast-resistant paddy.');
REPLACE INTO `crop_varieties` (`variety_id`, `crop_id`, `variety_name`, `duration_days`, `description`) VALUES ('VAR-03', 'CROP-04', 'Bt-Cotton (Mallika)', 160, 'Bollworm resistant hybrid with high ginning percentage.');
REPLACE INTO `crop_varieties` (`variety_id`, `crop_id`, `variety_name`, `duration_days`, `description`) VALUES ('VAR-04', 'CROP-05', 'Teja Guntur S17 Chilli', 150, 'Deep red high capsaicin pungency export variety.');
REPLACE INTO `crop_varieties` (`variety_id`, `crop_id`, `variety_name`, `duration_days`, `description`) VALUES ('VAR-05', 'CROP-03', 'LBG-752 (Black Gram)', 75, 'High yielding bold black seeded pulse.');
REPLACE INTO `crop_varieties` (`variety_id`, `crop_id`, `variety_name`, `duration_days`, `description`) VALUES ('VAR-06', 'CROP-02', 'Pioneer P3396 Maize', 110, 'High yielding hybrid maize with uniform cob filling.');
REPLACE INTO `crop_varieties` (`variety_id`, `crop_id`, `variety_name`, `duration_days`, `description`) VALUES ('VAR-07', 'CROP-06', 'JG-11 Bengal Gram', 95, 'Wilt tolerant bold seeded chana variety.');
REPLACE INTO `crop_varieties` (`variety_id`, `crop_id`, `variety_name`, `duration_days`, `description`) VALUES ('VAR-08', 'CROP-07', 'Kadiri-6 Groundnut', 105, 'Drought tolerant Spanish bunch high oil groundnut.');

-- Data for table `crops` (8 records)
REPLACE INTO `crops` (`crop_id`, `category_id`, `crop_name`, `description`) VALUES ('CROP-01', 'CCAT-01', 'Paddy (Rice)', 'Major food crop of coastal Andhra Pradesh delta.');
REPLACE INTO `crops` (`crop_id`, `category_id`, `crop_name`, `description`) VALUES ('CROP-02', 'CCAT-01', 'Maize (Corn)', 'High yielding feed and grain crop.');
REPLACE INTO `crops` (`crop_id`, `category_id`, `crop_name`, `description`) VALUES ('CROP-03', 'CCAT-02', 'Black Gram (Urad)', 'Pulse crop suitable for relay cropping in rice fallows.');
REPLACE INTO `crops` (`crop_id`, `category_id`, `crop_name`, `description`) VALUES ('CROP-04', 'CCAT-03', 'Cotton', 'Major cash crop known for superior fiber quality.');
REPLACE INTO `crops` (`crop_id`, `category_id`, `crop_name`, `description`) VALUES ('CROP-05', 'CCAT-04', 'Guntur Red Chilli', 'World renowned pungent spice crop.');
REPLACE INTO `crops` (`crop_id`, `category_id`, `crop_name`, `description`) VALUES ('CROP-06', 'CCAT-02', 'Bengal Gram (Chana)', 'Major winter pulse cultivated in black soils.');
REPLACE INTO `crops` (`crop_id`, `category_id`, `crop_name`, `description`) VALUES ('CROP-07', 'CCAT-05', 'Groundnut', 'Important oilseed crop with high oil and protein value.');
REPLACE INTO `crops` (`crop_id`, `category_id`, `crop_name`, `description`) VALUES ('CROP-08', 'CCAT-04', 'Turmeric (Haldi)', 'Curcumin-rich spice crop of Duggirala and Guntur belt.');

-- Data for table `cultivation_activities` (20 records)
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-98B6AE', 'CULT-20F276', 'Seed Sowing & Field Establishment', '2026-06-15', 'Transplanting / Drilling of certified foundation seeds', 4000);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-EFE91E', 'CULT-20F276', 'Foliar Spray of Micronutrients', '2026-08-10', 'Zinc and Boron spray', 1200);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-45EA1C', 'CULT-6B9B48', 'Seed Sowing & Field Establishment', '2026-06-15', 'Transplanting / Drilling of certified foundation seeds', 4000);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-6E947B', 'CULT-6B9B48', 'Foliar Spray of Micronutrients', '2026-08-10', 'Zinc and Boron spray', 1200);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-8D745B', 'CULT-161705', 'Seed Sowing & Field Establishment', '2026-06-15', 'Transplanting / Drilling of certified foundation seeds', 4000);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-3B3C59', 'CULT-161705', 'Foliar Spray of Micronutrients', '2026-08-10', 'Zinc and Boron spray', 1200);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-3B3572', 'CULT-C15E53', 'Seed Sowing & Field Establishment', '2026-06-15', 'Transplanting / Drilling of certified foundation seeds', 4000);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-C53791', 'CULT-C15E53', 'Foliar Spray of Micronutrients', '2026-08-10', 'Zinc and Boron spray', 1200);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-17EF9D', 'CULT-2C90B2', 'Seed Sowing & Field Establishment', '2026-06-15', 'Transplanting / Drilling of certified foundation seeds', 4000);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-496EE2', 'CULT-2C90B2', 'Foliar Spray of Micronutrients', '2026-08-10', 'Zinc and Boron spray', 1200);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-401813', 'CULT-DE09B1', 'Seed Sowing & Field Establishment', '2026-06-15', 'Transplanting / Drilling of certified foundation seeds', 4000);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-17CAA9', 'CULT-DE09B1', 'Foliar Spray of Micronutrients', '2026-08-10', 'Zinc and Boron spray', 1200);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-001', 'CULT-001', 'Deep Summer Ploughing & Puddling', '2026-06-08', 'Field prepared with rotavator and leveled with tractor', 3500);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-002', 'CULT-001', 'Transplantation of 25-day Seedlings', '2026-06-15', 'Line transplanting with recommended 20x15 cm spacing', 4800);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-003', 'CULT-001', 'First Top Dressing & Weeding', '2026-07-10', 'Manual weeding and basal fertilizer incorporation', 2200);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-004', 'CULT-001', 'Foliar Spraying for Blast Prevention', '2026-08-14', 'Sprayed Saaf fungicide as per RBK advisory', 1150);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-005', 'CULT-002', 'Raised Bed Preparation & Drip Laying', '2026-06-25', 'Chilli nursery transplantation on plastic mulch beds', 5200);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-006', 'CULT-002', 'Sucking Pest Chemical Management', '2026-07-28', 'Applied Confidor at recommended dosage of 0.5ml/L', 980);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-007', 'CULT-004', 'Mechanical Combine Harvesting', '2026-10-15', 'Paddy harvested, threshed and bagged in field', 6500);
REPLACE INTO `cultivation_activities` (`activity_id`, `cultivation_id`, `activity_type`, `activity_date`, `description`, `expense`) VALUES ('ACT-008', 'CULT-005', 'Maize Mechanical Shelling & Bagging', '2026-10-25', 'Harvested 8500 kg grain, moisture test completed', 5800);

-- Data for table `cultivation_seasons` (6 records)
REPLACE INTO `cultivation_seasons` (`season_id`, `season_name`, `start_date`, `end_date`, `description`) VALUES ('SEAS-2026-ZD', 'Zaid 2026', '2026-03-01', '2026-06-15', 'Summer short-duration vegetables and fodder crops');
REPLACE INTO `cultivation_seasons` (`season_id`, `season_name`, `start_date`, `end_date`, `description`) VALUES ('SEAS-2025-KH', 'Kharif 2025', '2025-06-01', '2025-11-30', 'Monsoon season sowing Paddy, Cotton, Pulses');
REPLACE INTO `cultivation_seasons` (`season_id`, `season_name`, `start_date`, `end_date`, `description`) VALUES ('SEAS-2025-RB', 'Rabi 2025-26', '2025-10-15', '2026-03-31', 'Winter cultivation for Bengal Gram, Maize, Chilli');
REPLACE INTO `cultivation_seasons` (`season_id`, `season_name`, `start_date`, `end_date`, `description`) VALUES ('SEAS-2026-KH', 'Kharif 2026', '2026-06-01', '2026-11-30', 'Active monsoon cultivation season');
REPLACE INTO `cultivation_seasons` (`season_id`, `season_name`, `start_date`, `end_date`, `description`) VALUES ('SEAS-2026-RB', 'Rabi 2026-27', '2026-10-15', '2027-03-31', 'Upcoming winter crop cycle');
REPLACE INTO `cultivation_seasons` (`season_id`, `season_name`, `start_date`, `end_date`, `description`) VALUES ('SEAS-2027-ZD', 'Zaid 2027', '2027-03-01', '2027-06-15', 'Summer short-duration pulse and fodder cycle');

-- Data for table `cultivations` (12 records)
REPLACE INTO `cultivations` (`cultivation_id`, `farmer_id`, `field_id`, `variety_id`, `season_id`, `sowing_date`, `expected_harvest_date`, `cultivation_status`) VALUES ('CULT-20F276', 'FAR-001', 'FLD-001', 'VAR-05', 'SEAS-2026-RB', '2026-06-15', '2026-11-15', 'Harvested');
REPLACE INTO `cultivations` (`cultivation_id`, `farmer_id`, `field_id`, `variety_id`, `season_id`, `sowing_date`, `expected_harvest_date`, `cultivation_status`) VALUES ('CULT-6B9B48', 'FAR-001', 'FLD-001', 'VAR-05', 'SEAS-2026-RB', '2026-06-15', '2026-11-15', 'Harvested');
REPLACE INTO `cultivations` (`cultivation_id`, `farmer_id`, `field_id`, `variety_id`, `season_id`, `sowing_date`, `expected_harvest_date`, `cultivation_status`) VALUES ('CULT-161705', 'FAR-001', 'FLD-001', 'VAR-05', 'SEAS-2026-RB', '2026-06-15', '2026-11-15', 'Harvested');
REPLACE INTO `cultivations` (`cultivation_id`, `farmer_id`, `field_id`, `variety_id`, `season_id`, `sowing_date`, `expected_harvest_date`, `cultivation_status`) VALUES ('CULT-C15E53', 'FAR-001', 'FLD-001', 'VAR-05', 'SEAS-2026-RB', '2026-06-15', '2026-11-15', 'Harvested');
REPLACE INTO `cultivations` (`cultivation_id`, `farmer_id`, `field_id`, `variety_id`, `season_id`, `sowing_date`, `expected_harvest_date`, `cultivation_status`) VALUES ('CULT-2C90B2', 'FAR-001', 'FLD-001', 'VAR-05', 'SEAS-2026-RB', '2026-06-15', '2026-11-15', 'Harvested');
REPLACE INTO `cultivations` (`cultivation_id`, `farmer_id`, `field_id`, `variety_id`, `season_id`, `sowing_date`, `expected_harvest_date`, `cultivation_status`) VALUES ('CULT-DE09B1', 'FAR-001', 'FLD-001', 'VAR-05', 'SEAS-2026-RB', '2026-06-15', '2026-11-15', 'Harvested');
REPLACE INTO `cultivations` (`cultivation_id`, `farmer_id`, `field_id`, `variety_id`, `season_id`, `sowing_date`, `expected_harvest_date`, `cultivation_status`) VALUES ('CULT-001', 'FAR-001', 'FLD-001', 'VAR-01', 'SEAS-2026-KH', '2026-06-15', '2026-11-10', 'Growing');
REPLACE INTO `cultivations` (`cultivation_id`, `farmer_id`, `field_id`, `variety_id`, `season_id`, `sowing_date`, `expected_harvest_date`, `cultivation_status`) VALUES ('CULT-002', 'FAR-001', 'FLD-002', 'VAR-04', 'SEAS-2026-KH', '2026-07-01', '2026-12-05', 'Growing');
REPLACE INTO `cultivations` (`cultivation_id`, `farmer_id`, `field_id`, `variety_id`, `season_id`, `sowing_date`, `expected_harvest_date`, `cultivation_status`) VALUES ('CULT-003', 'FAR-002', 'FLD-004', 'VAR-03', 'SEAS-2026-KH', '2026-06-25', '2026-12-15', 'Growing');
REPLACE INTO `cultivations` (`cultivation_id`, `farmer_id`, `field_id`, `variety_id`, `season_id`, `sowing_date`, `expected_harvest_date`, `cultivation_status`) VALUES ('CULT-004', 'FAR-003', 'FLD-006', 'VAR-02', 'SEAS-2026-KH', '2026-06-10', '2026-10-15', 'Harvested');
REPLACE INTO `cultivations` (`cultivation_id`, `farmer_id`, `field_id`, `variety_id`, `season_id`, `sowing_date`, `expected_harvest_date`, `cultivation_status`) VALUES ('CULT-005', 'FAR-004', 'FLD-007', 'VAR-06', 'SEAS-2026-KH', '2026-06-18', '2026-10-25', 'Harvested');
REPLACE INTO `cultivations` (`cultivation_id`, `farmer_id`, `field_id`, `variety_id`, `season_id`, `sowing_date`, `expected_harvest_date`, `cultivation_status`) VALUES ('CULT-006', 'FAR-006', 'FLD-008', 'VAR-01', 'SEAS-2026-KH', '2026-06-20', '2026-11-15', 'Growing');

-- Data for table `emp_password` (10 records)
REPLACE INTO `emp_password` (`emp_password_id`, `employee_id`, `password_hash`, `confirm_password_hash`) VALUES ('PWD-001', 'EMP-001', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd');
REPLACE INTO `emp_password` (`emp_password_id`, `employee_id`, `password_hash`, `confirm_password_hash`) VALUES ('PWD-002', 'EMP-002', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd');
REPLACE INTO `emp_password` (`emp_password_id`, `employee_id`, `password_hash`, `confirm_password_hash`) VALUES ('PWD-003', 'EMP-003', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd');
REPLACE INTO `emp_password` (`emp_password_id`, `employee_id`, `password_hash`, `confirm_password_hash`) VALUES ('PWD-004', 'EMP-004', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd');
REPLACE INTO `emp_password` (`emp_password_id`, `employee_id`, `password_hash`, `confirm_password_hash`) VALUES ('PWD-005', 'EMP-005', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd');
REPLACE INTO `emp_password` (`emp_password_id`, `employee_id`, `password_hash`, `confirm_password_hash`) VALUES ('PWD-006', 'EMP-006', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd');
REPLACE INTO `emp_password` (`emp_password_id`, `employee_id`, `password_hash`, `confirm_password_hash`) VALUES ('PWD-007', 'EMP-007', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd');
REPLACE INTO `emp_password` (`emp_password_id`, `employee_id`, `password_hash`, `confirm_password_hash`) VALUES ('PWD-008', 'EMP-008', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd');
REPLACE INTO `emp_password` (`emp_password_id`, `employee_id`, `password_hash`, `confirm_password_hash`) VALUES ('PWD-009', 'EMP-009', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd');
REPLACE INTO `emp_password` (`emp_password_id`, `employee_id`, `password_hash`, `confirm_password_hash`) VALUES ('PWD-010', 'EMP-010', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd');

-- Data for table `farm_fields` (13 records)
REPLACE INTO `farm_fields` (`field_id`, `land_id`, `field_name`, `field_area`, `soil_type`, `irrigation_type`) VALUES ('FLD-B17A19', 'LAND-00413B', 'Main Field (Sy. No. 999)', 5, 'Black Cotton', 'Canal / Borewell');
REPLACE INTO `farm_fields` (`field_id`, `land_id`, `field_name`, `field_area`, `soil_type`, `irrigation_type`) VALUES ('FLD-6CBACA', 'LAND-810435', 'Main Field (Sy. No. 8c1)', 5, 'Black Cotton', 'Canal / Borewell');
REPLACE INTO `farm_fields` (`field_id`, `land_id`, `field_name`, `field_area`, `soil_type`, `irrigation_type`) VALUES ('FLD-E19AA4', 'LAND-ADA15E', 'Main Field (Sy. No. 3b7)', 5, 'Black Cotton', 'Canal / Borewell');
REPLACE INTO `farm_fields` (`field_id`, `land_id`, `field_name`, `field_area`, `soil_type`, `irrigation_type`) VALUES ('FLD-C489F8', 'LAND-5FC5A3', 'Main Field (Sy. No. 153)', 5, 'Black Cotton', 'Canal / Borewell');
REPLACE INTO `farm_fields` (`field_id`, `land_id`, `field_name`, `field_area`, `soil_type`, `irrigation_type`) VALUES ('FLD-8CE9C7', 'LAND-8FE112', 'Main Field (Sy. No. 79f)', 5, 'Black Cotton', 'Canal / Borewell');
REPLACE INTO `farm_fields` (`field_id`, `land_id`, `field_name`, `field_area`, `soil_type`, `irrigation_type`) VALUES ('FLD-001', 'LAND-001', 'North Delta Canal Field', 2.5, 'Deep Black Alluvial', 'Krishna Canal Drip');
REPLACE INTO `farm_fields` (`field_id`, `land_id`, `field_name`, `field_area`, `soil_type`, `irrigation_type`) VALUES ('FLD-002', 'LAND-001', 'South Well Agro Plot', 2, 'Clayey Loam', 'Submersible Borewell');
REPLACE INTO `farm_fields` (`field_id`, `land_id`, `field_name`, `field_area`, `soil_type`, `irrigation_type`) VALUES ('FLD-003', 'LAND-002', 'East Feeder Plot', 2.2, 'Alluvial Delta Soil', 'Canal Water');
REPLACE INTO `farm_fields` (`field_id`, `land_id`, `field_name`, `field_area`, `soil_type`, `irrigation_type`) VALUES ('FLD-004', 'LAND-003', 'Hill Slope Red Plot', 3.2, 'Red Sandy Loam', 'Borewell Sprinkler');
REPLACE INTO `farm_fields` (`field_id`, `land_id`, `field_name`, `field_area`, `soil_type`, `irrigation_type`) VALUES ('FLD-005', 'LAND-003', 'River Bank Flat Field', 3, 'Rich Black Cotton', 'River Lift Irrigation');
REPLACE INTO `farm_fields` (`field_id`, `land_id`, `field_name`, `field_area`, `soil_type`, `irrigation_type`) VALUES ('FLD-006', 'LAND-004', 'Heritage Fertile Field', 3, 'Alluvial Silt Loam', 'Canal Water');
REPLACE INTO `farm_fields` (`field_id`, `land_id`, `field_name`, `field_area`, `soil_type`, `irrigation_type`) VALUES ('FLD-007', 'LAND-005', 'Enikepadu Black Soil Parcel', 5, 'Heavy Black Cotton', 'Drip & Canal');
REPLACE INTO `farm_fields` (`field_id`, `land_id`, `field_name`, `field_area`, `soil_type`, `irrigation_type`) VALUES ('FLD-008', 'LAND-007', 'Leased Out Delta Parcel', 3.5, 'Medium Black Alluvial', 'Canal Irrigation');

-- Data for table `farmer_addresses` (15 records)
REPLACE INTO `farmer_addresses` (`address_id`, `farmer_id`, `house_number`, `village`, `mandal`, `district`, `state`, `pincode`, `address_type`) VALUES ('ADDR-75E48E', 'FAR-A6F321', '', 'Angalakuduru', 'Tenali', 'Guntur', 'Andhra Pradesh', '522001', 'Permanent');
REPLACE INTO `farmer_addresses` (`address_id`, `farmer_id`, `house_number`, `village`, `mandal`, `district`, `state`, `pincode`, `address_type`) VALUES ('ADDR-E43BAE', 'FAR-2EBF3A', '', 'Angalakuduru', 'Tenali', 'Guntur', 'Andhra Pradesh', '522001', 'Permanent');
REPLACE INTO `farmer_addresses` (`address_id`, `farmer_id`, `house_number`, `village`, `mandal`, `district`, `state`, `pincode`, `address_type`) VALUES ('ADDR-AAE325', 'FAR-548814', '', 'Angalakuduru', 'Tenali', 'Guntur', 'Andhra Pradesh', '522001', 'Permanent');
REPLACE INTO `farmer_addresses` (`address_id`, `farmer_id`, `house_number`, `village`, `mandal`, `district`, `state`, `pincode`, `address_type`) VALUES ('ADDR-C06C45', 'FAR-C70ACA', '', 'Angalakuduru', 'Tenali', 'Guntur', 'Andhra Pradesh', '522001', 'Permanent');
REPLACE INTO `farmer_addresses` (`address_id`, `farmer_id`, `house_number`, `village`, `mandal`, `district`, `state`, `pincode`, `address_type`) VALUES ('ADDR-EC2297', 'FAR-5CF802', '', 'Angalakuduru', 'Tenali', 'Guntur', 'Andhra Pradesh', '522001', 'Permanent');
REPLACE INTO `farmer_addresses` (`address_id`, `farmer_id`, `house_number`, `village`, `mandal`, `district`, `state`, `pincode`, `address_type`) VALUES ('ADDR-001', 'FAR-001', '4-52/A', 'Angalakuduru', 'Tenali', 'Guntur', 'Andhra Pradesh', '522202', 'Permanent');
REPLACE INTO `farmer_addresses` (`address_id`, `farmer_id`, `house_number`, `village`, `mandal`, `district`, `state`, `pincode`, `address_type`) VALUES ('ADDR-002', 'FAR-002', '12-104', 'Navuluru', 'Mangalagiri', 'Guntur', 'Andhra Pradesh', '522503', 'Permanent');
REPLACE INTO `farmer_addresses` (`address_id`, `farmer_id`, `house_number`, `village`, `mandal`, `district`, `state`, `pincode`, `address_type`) VALUES ('ADDR-003', 'FAR-003', '2-19', 'Dharanikota', 'Amaravati', 'Guntur', 'Andhra Pradesh', '522020', 'Permanent');
REPLACE INTO `farmer_addresses` (`address_id`, `farmer_id`, `house_number`, `village`, `mandal`, `district`, `state`, `pincode`, `address_type`) VALUES ('ADDR-004', 'FAR-004', '7-88', 'Enikepadu', 'Vijayawada Rural', 'Krishna', 'Andhra Pradesh', '521108', 'Permanent');
REPLACE INTO `farmer_addresses` (`address_id`, `farmer_id`, `house_number`, `village`, `mandal`, `district`, `state`, `pincode`, `address_type`) VALUES ('ADDR-005', 'FAR-005', '3-45', 'Karavadi', 'Ongole', 'Prakasam', 'Andhra Pradesh', '523182', 'Permanent');
REPLACE INTO `farmer_addresses` (`address_id`, `farmer_id`, `house_number`, `village`, `mandal`, `district`, `state`, `pincode`, `address_type`) VALUES ('ADDR-006', 'FAR-006', '1-88/C', 'Karlapalem', 'Bapatla Urban', 'Bapatla', 'Andhra Pradesh', '522101', 'Permanent');
REPLACE INTO `farmer_addresses` (`address_id`, `farmer_id`, `house_number`, `village`, `mandal`, `district`, `state`, `pincode`, `address_type`) VALUES ('ADDR-007', 'FAR-007', '8-112', 'Billapadu', 'Gudivada', 'Krishna', 'Andhra Pradesh', '521301', 'Permanent');
REPLACE INTO `farmer_addresses` (`address_id`, `farmer_id`, `house_number`, `village`, `mandal`, `district`, `state`, `pincode`, `address_type`) VALUES ('ADDR-008', 'FAR-008', '5-34', 'Petlurivaripalem', 'Narasaraopet', 'Palnadu', 'Andhra Pradesh', '522601', 'Permanent');
REPLACE INTO `farmer_addresses` (`address_id`, `farmer_id`, `house_number`, `village`, `mandal`, `district`, `state`, `pincode`, `address_type`) VALUES ('ADDR-009', 'FAR-009', '11-20', 'Kadiyam', 'Rajahmundry', 'East Godavari', 'Andhra Pradesh', '533126', 'Permanent');
REPLACE INTO `farmer_addresses` (`address_id`, `farmer_id`, `house_number`, `village`, `mandal`, `district`, `state`, `pincode`, `address_type`) VALUES ('ADDR-010', 'FAR-010', '6-77', 'Sanivarapupeta', 'Eluru', 'West Godavari', 'Andhra Pradesh', '534005', 'Permanent');

-- Data for table `farmer_credit_accounts` (11 records)
REPLACE INTO `farmer_credit_accounts` (`credit_account_id`, `farmer_id`, `institution_name`, `kcc_card_number`, `total_credit_limit`, `available_balance`, `repayment_due_date`, `account_status`) VALUES ('CRED-417D69', 'FAR-A6F321', 'State Bank of India', 'KCC-AP-FD19E8', 250000, 250000, '2026-11-22', 'Active');
REPLACE INTO `farmer_credit_accounts` (`credit_account_id`, `farmer_id`, `institution_name`, `kcc_card_number`, `total_credit_limit`, `available_balance`, `repayment_due_date`, `account_status`) VALUES ('CRED-FF0FB1', 'FAR-2EBF3A', 'State Bank of India', 'KCC-AP-45CD94', 250000, 250000, '2026-11-22', 'Active');
REPLACE INTO `farmer_credit_accounts` (`credit_account_id`, `farmer_id`, `institution_name`, `kcc_card_number`, `total_credit_limit`, `available_balance`, `repayment_due_date`, `account_status`) VALUES ('CRED-76477E', 'FAR-548814', 'State Bank of India', 'KCC-AP-6B077C', 250000, 250000, '2026-11-24', 'Active');
REPLACE INTO `farmer_credit_accounts` (`credit_account_id`, `farmer_id`, `institution_name`, `kcc_card_number`, `total_credit_limit`, `available_balance`, `repayment_due_date`, `account_status`) VALUES ('CRED-4D04C1', 'FAR-C70ACA', 'State Bank of India', 'KCC-AP-B22FB6', 250000, 250000, '2026-11-24', 'Active');
REPLACE INTO `farmer_credit_accounts` (`credit_account_id`, `farmer_id`, `institution_name`, `kcc_card_number`, `total_credit_limit`, `available_balance`, `repayment_due_date`, `account_status`) VALUES ('CRED-02E1E5', 'FAR-5CF802', 'State Bank of India', 'KCC-AP-5636C5', 250000, 250000, '2026-11-24', 'Active');
REPLACE INTO `farmer_credit_accounts` (`credit_account_id`, `farmer_id`, `institution_name`, `kcc_card_number`, `total_credit_limit`, `available_balance`, `repayment_due_date`, `account_status`) VALUES ('CRED-001', 'FAR-001', 'State Bank of India - Tenali', 'KCC-SBIN-892147', 350000, 215000, '2027-03-31', 'Active');
REPLACE INTO `farmer_credit_accounts` (`credit_account_id`, `farmer_id`, `institution_name`, `kcc_card_number`, `total_credit_limit`, `available_balance`, `repayment_due_date`, `account_status`) VALUES ('CRED-002', 'FAR-002', 'Union Bank of India - Mangalagiri', 'KCC-UBIN-445892', 450000, 310000, '2027-03-31', 'Active');
REPLACE INTO `farmer_credit_accounts` (`credit_account_id`, `farmer_id`, `institution_name`, `kcc_card_number`, `total_credit_limit`, `available_balance`, `repayment_due_date`, `account_status`) VALUES ('CRED-003', 'FAR-003', 'Canara Bank - Amaravati', 'KCC-CNRB-119284', 200000, 140000, '2027-03-31', 'Active');
REPLACE INTO `farmer_credit_accounts` (`credit_account_id`, `farmer_id`, `institution_name`, `kcc_card_number`, `total_credit_limit`, `available_balance`, `repayment_due_date`, `account_status`) VALUES ('CRED-004', 'FAR-004', 'HDFC Bank - Vijayawada', 'KCC-HDFC-993821', 600000, 425000, '2027-03-31', 'Active');
REPLACE INTO `farmer_credit_accounts` (`credit_account_id`, `farmer_id`, `institution_name`, `kcc_card_number`, `total_credit_limit`, `available_balance`, `repayment_due_date`, `account_status`) VALUES ('CRED-005', 'FAR-005', 'Andhra Pragathi Grameena Bank', 'KCC-APGB-771122', 300000, 195000, '2027-03-31', 'Active');
REPLACE INTO `farmer_credit_accounts` (`credit_account_id`, `farmer_id`, `institution_name`, `kcc_card_number`, `total_credit_limit`, `available_balance`, `repayment_due_date`, `account_status`) VALUES ('CRED-006', 'FAR-006', 'SBI Agricultural Branch Bapatla', 'KCC-SBIN-102938', 150000, 95000, '2027-03-31', 'Active');

-- Data for table `farmer_land_records` (12 records)
REPLACE INTO `farmer_land_records` (`land_id`, `farmer_id`, `survey_number`, `passbook_number`, `land_area`, `ownership_type`, `village`, `registration_date`, `verified_by`, `verified_at`) VALUES ('LAND-00413B', 'FAR-A6F321', 'Sy. No. 999', 'PB-E7F8EF', 5, 'Owned', 'Angalakuduru', '2026-11-22', 'RBK Officer', '2026-11-22 13:22:38');
REPLACE INTO `farmer_land_records` (`land_id`, `farmer_id`, `survey_number`, `passbook_number`, `land_area`, `ownership_type`, `village`, `registration_date`, `verified_by`, `verified_at`) VALUES ('LAND-810435', 'FAR-2EBF3A', 'Sy. No. 8c1', 'PB-B0FA4D', 5, 'Owned', 'Angalakuduru', '2026-11-22', 'RBK Officer', '2026-11-22 13:23:29');
REPLACE INTO `farmer_land_records` (`land_id`, `farmer_id`, `survey_number`, `passbook_number`, `land_area`, `ownership_type`, `village`, `registration_date`, `verified_by`, `verified_at`) VALUES ('LAND-ADA15E', 'FAR-548814', 'Sy. No. 3b7', 'PB-C739C3', 5, 'Owned', 'Angalakuduru', '2026-11-24', 'RBK Officer', '2026-11-24 16:37:38');
REPLACE INTO `farmer_land_records` (`land_id`, `farmer_id`, `survey_number`, `passbook_number`, `land_area`, `ownership_type`, `village`, `registration_date`, `verified_by`, `verified_at`) VALUES ('LAND-5FC5A3', 'FAR-C70ACA', 'Sy. No. 153', 'PB-CAC1F2', 5, 'Owned', 'Angalakuduru', '2026-11-24', 'RBK Officer', '2026-11-24 16:42:43');
REPLACE INTO `farmer_land_records` (`land_id`, `farmer_id`, `survey_number`, `passbook_number`, `land_area`, `ownership_type`, `village`, `registration_date`, `verified_by`, `verified_at`) VALUES ('LAND-8FE112', 'FAR-5CF802', 'Sy. No. 79f', 'PB-19E08F', 5, 'Owned', 'Angalakuduru', '2026-11-24', 'RBK Officer', '2026-11-24 16:52:27');
REPLACE INTO `farmer_land_records` (`land_id`, `farmer_id`, `survey_number`, `passbook_number`, `land_area`, `ownership_type`, `village`, `registration_date`, `verified_by`, `verified_at`) VALUES ('LAND-001', 'FAR-001', 'Sy. No. 142/2A', 'AP-GNT-109283', 4.5, 'Owned', 'Angalakuduru', '2015-06-10', 'Tahsildar Tenali', '2021-03-15 11:00:00');
REPLACE INTO `farmer_land_records` (`land_id`, `farmer_id`, `survey_number`, `passbook_number`, `land_area`, `ownership_type`, `village`, `registration_date`, `verified_by`, `verified_at`) VALUES ('LAND-002', 'FAR-001', 'Sy. No. 143/1', 'AP-GNT-109284', 2.2, 'Owned', 'Angalakuduru', '2017-08-15', 'Tahsildar Tenali', '2021-03-15 11:30:00');
REPLACE INTO `farmer_land_records` (`land_id`, `farmer_id`, `survey_number`, `passbook_number`, `land_area`, `ownership_type`, `village`, `registration_date`, `verified_by`, `verified_at`) VALUES ('LAND-003', 'FAR-002', 'Sy. No. 89/1B', 'AP-GNT-208374', 6.2, 'Owned', 'Navuluru', '2018-02-20', 'Tahsildar Mangalagiri', '2021-04-10 10:00:00');
REPLACE INTO `farmer_land_records` (`land_id`, `farmer_id`, `survey_number`, `passbook_number`, `land_area`, `ownership_type`, `village`, `registration_date`, `verified_by`, `verified_at`) VALUES ('LAND-004', 'FAR-003', 'Sy. No. 305/4', 'AP-GNT-304912', 3, 'Owned', 'Dharanikota', '2016-09-12', 'Tahsildar Amaravati', '2021-05-22 15:30:00');
REPLACE INTO `farmer_land_records` (`land_id`, `farmer_id`, `survey_number`, `passbook_number`, `land_area`, `ownership_type`, `village`, `registration_date`, `verified_by`, `verified_at`) VALUES ('LAND-005', 'FAR-004', 'Sy. No. 55/3C', 'AP-KRS-401928', 8.5, 'Owned', 'Enikepadu', '2012-11-05', 'Tahsildar Vijayawada', '2021-06-18 14:15:00');
REPLACE INTO `farmer_land_records` (`land_id`, `farmer_id`, `survey_number`, `passbook_number`, `land_area`, `ownership_type`, `village`, `registration_date`, `verified_by`, `verified_at`) VALUES ('LAND-006', 'FAR-005', 'Sy. No. 120/4', 'AP-PRK-502819', 5, 'Owned', 'Karavadi', '2019-01-20', 'Tahsildar Ongole', '2021-07-05 16:00:00');
REPLACE INTO `farmer_land_records` (`land_id`, `farmer_id`, `survey_number`, `passbook_number`, `land_area`, `ownership_type`, `village`, `registration_date`, `verified_by`, `verified_at`) VALUES ('LAND-007', 'FAR-001', 'Sy. No. 150/B', 'AP-GNT-109999', 3.5, 'Leased Out', 'Angalakuduru', '2020-04-10', 'Tahsildar Tenali', '2021-03-15 12:00:00');

-- Data for table `farmers` (15 records)
REPLACE INTO `farmers` (`farmer_id`, `farmer_name`, `dob`, `gender`, `phone`, `email`, `password_hash`, `authentication_id`, `registration_date`) VALUES ('FAR-A6F321', 'Test K. Rao', '1980-01-01', 'Male', '9999988888', 'test.k.rao@gmail.com', '85afce2dc45c54f07e9e48f33e8c55f91c25c634ec5512516c874d5bcca4e651', 'BIO-7CCFAE', '2026-11-22 13:22:38');
REPLACE INTO `farmers` (`farmer_id`, `farmer_name`, `dob`, `gender`, `phone`, `email`, `password_hash`, `authentication_id`, `registration_date`) VALUES ('FAR-2EBF3A', 'Test K. Rao', '1980-01-01', 'Male', '998c1fe5', 'test.8c1fe5@agrichain.in', '85afce2dc45c54f07e9e48f33e8c55f91c25c634ec5512516c874d5bcca4e651', 'BIO-428625', '2026-11-22 13:23:29');
REPLACE INTO `farmers` (`farmer_id`, `farmer_name`, `dob`, `gender`, `phone`, `email`, `password_hash`, `authentication_id`, `registration_date`) VALUES ('FAR-548814', 'Test K. Rao', '1980-01-01', 'Male', '993b787d', 'test.3b787d@agrichain.in', '85afce2dc45c54f07e9e48f33e8c55f91c25c634ec5512516c874d5bcca4e651', 'BIO-2B344E', '2026-11-24 16:37:38');
REPLACE INTO `farmers` (`farmer_id`, `farmer_name`, `dob`, `gender`, `phone`, `email`, `password_hash`, `authentication_id`, `registration_date`) VALUES ('FAR-C70ACA', 'Test K. Rao', '1980-01-01', 'Male', '99153137', 'test.153137@agrichain.in', '85afce2dc45c54f07e9e48f33e8c55f91c25c634ec5512516c874d5bcca4e651', 'BIO-0A93C5', '2026-11-24 16:42:43');
REPLACE INTO `farmers` (`farmer_id`, `farmer_name`, `dob`, `gender`, `phone`, `email`, `password_hash`, `authentication_id`, `registration_date`) VALUES ('FAR-5CF802', 'Test K. Rao', '1980-01-01', 'Male', '9979fdbb', 'test.79fdbb@agrichain.in', '85afce2dc45c54f07e9e48f33e8c55f91c25c634ec5512516c874d5bcca4e651', 'BIO-342CBA', '2026-11-24 16:52:27');
REPLACE INTO `farmers` (`farmer_id`, `farmer_name`, `dob`, `gender`, `phone`, `email`, `password_hash`, `authentication_id`, `registration_date`) VALUES ('FAR-001', 'Ramesh Babu Naidu', '1978-04-12', 'Male', '9848011223', 'ramesh.naidu@gmail.com', '85afce2dc45c54f07e9e48f33e8c55f91c25c634ec5512516c874d5bcca4e651', 'BIO-001', '2026-11-24 17:37:28');
REPLACE INTO `farmers` (`farmer_id`, `farmer_name`, `dob`, `gender`, `phone`, `email`, `password_hash`, `authentication_id`, `registration_date`) VALUES ('FAR-002', 'Venkat Rao Chowdary', '1982-08-25', 'Male', '9848022334', 'venkat.rao@gmail.com', '85afce2dc45c54f07e9e48f33e8c55f91c25c634ec5512516c874d5bcca4e651', 'BIO-002', '2026-11-24 17:37:28');
REPLACE INTO `farmers` (`farmer_id`, `farmer_name`, `dob`, `gender`, `phone`, `email`, `password_hash`, `authentication_id`, `registration_date`) VALUES ('FAR-003', 'Lakshmi Devi Korrapati', '1985-11-14', 'Female', '9848033445', 'lakshmi.k@gmail.com', '85afce2dc45c54f07e9e48f33e8c55f91c25c634ec5512516c874d5bcca4e651', 'BIO-003', '2026-11-24 17:37:28');
REPLACE INTO `farmers` (`farmer_id`, `farmer_name`, `dob`, `gender`, `phone`, `email`, `password_hash`, `authentication_id`, `registration_date`) VALUES ('FAR-004', 'Siva Rama Krishna Reddy', '1975-02-18', 'Male', '9848044556', 'siva.reddy@gmail.com', '85afce2dc45c54f07e9e48f33e8c55f91c25c634ec5512516c874d5bcca4e651', 'BIO-004', '2026-11-24 17:37:28');
REPLACE INTO `farmers` (`farmer_id`, `farmer_name`, `dob`, `gender`, `phone`, `email`, `password_hash`, `authentication_id`, `registration_date`) VALUES ('FAR-005', 'Apparao Kollipara', '1980-07-30', 'Male', '9848055667', 'apparao.k@gmail.com', '85afce2dc45c54f07e9e48f33e8c55f91c25c634ec5512516c874d5bcca4e651', 'BIO-005', '2026-11-24 17:37:28');
REPLACE INTO `farmers` (`farmer_id`, `farmer_name`, `dob`, `gender`, `phone`, `email`, `password_hash`, `authentication_id`, `registration_date`) VALUES ('FAR-006', 'Ch. Subbaiah (Tenant Farmer)', '1984-03-15', 'Male', '9848066778', 'subbaiah.ch@gmail.com', '85afce2dc45c54f07e9e48f33e8c55f91c25c634ec5512516c874d5bcca4e651', 'BIO-006', '2026-11-24 17:37:28');
REPLACE INTO `farmers` (`farmer_id`, `farmer_name`, `dob`, `gender`, `phone`, `email`, `password_hash`, `authentication_id`, `registration_date`) VALUES ('FAR-007', 'G. Mallikarjuna Rao', '1972-10-08', 'Male', '9848077889', 'malli.g@gmail.com', '85afce2dc45c54f07e9e48f33e8c55f91c25c634ec5512516c874d5bcca4e651', 'BIO-007', '2026-11-24 17:37:28');
REPLACE INTO `farmers` (`farmer_id`, `farmer_name`, `dob`, `gender`, `phone`, `email`, `password_hash`, `authentication_id`, `registration_date`) VALUES ('FAR-008', 'K. Parvathi Amma', '1988-06-22', 'Female', '9848088990', 'parvathi.k@gmail.com', '85afce2dc45c54f07e9e48f33e8c55f91c25c634ec5512516c874d5bcca4e651', 'BIO-008', '2026-11-24 17:37:28');
REPLACE INTO `farmers` (`farmer_id`, `farmer_name`, `dob`, `gender`, `phone`, `email`, `password_hash`, `authentication_id`, `registration_date`) VALUES ('FAR-009', 'T. Narayana Murthy', '1969-12-01', 'Male', '9848099001', 'narayana.t@gmail.com', '85afce2dc45c54f07e9e48f33e8c55f91c25c634ec5512516c874d5bcca4e651', 'BIO-009', '2026-11-24 17:37:28');
REPLACE INTO `farmers` (`farmer_id`, `farmer_name`, `dob`, `gender`, `phone`, `email`, `password_hash`, `authentication_id`, `registration_date`) VALUES ('FAR-010', 'Y. Ramachandra Raju', '1986-09-19', 'Male', '9848000222', 'raju.y@gmail.com', '85afce2dc45c54f07e9e48f33e8c55f91c25c634ec5512516c874d5bcca4e651', 'BIO-010', '2026-11-24 17:37:28');

-- Data for table `harvest_records` (10 records)
REPLACE INTO `harvest_records` (`harvest_id`, `cultivation_id`, `harvest_date`, `total_quantity`, `unit`, `remarks`) VALUES ('HARV-BE9828', 'CULT-20F276', '2026-11-15', 4800, 'kg', 'Optimal grain size and luster');
REPLACE INTO `harvest_records` (`harvest_id`, `cultivation_id`, `harvest_date`, `total_quantity`, `unit`, `remarks`) VALUES ('HARV-5F4A5B', 'CULT-6B9B48', '2026-11-15', 4800, 'kg', 'Optimal grain size and luster');
REPLACE INTO `harvest_records` (`harvest_id`, `cultivation_id`, `harvest_date`, `total_quantity`, `unit`, `remarks`) VALUES ('HARV-7348C5', 'CULT-161705', '2026-11-15', 4800, 'kg', 'Optimal grain size and luster');
REPLACE INTO `harvest_records` (`harvest_id`, `cultivation_id`, `harvest_date`, `total_quantity`, `unit`, `remarks`) VALUES ('HARV-509BF3', 'CULT-002', '2026-11-21', 4500, 'kg', 'Standard harvest inspection passed');
REPLACE INTO `harvest_records` (`harvest_id`, `cultivation_id`, `harvest_date`, `total_quantity`, `unit`, `remarks`) VALUES ('HARV-2AA99D', 'CULT-C15E53', '2026-11-15', 4800, 'kg', 'Optimal grain size and luster');
REPLACE INTO `harvest_records` (`harvest_id`, `cultivation_id`, `harvest_date`, `total_quantity`, `unit`, `remarks`) VALUES ('HARV-05C723', 'CULT-2C90B2', '2026-11-15', 4800, 'kg', 'Optimal grain size and luster');
REPLACE INTO `harvest_records` (`harvest_id`, `cultivation_id`, `harvest_date`, `total_quantity`, `unit`, `remarks`) VALUES ('HARV-078ABE', 'CULT-DE09B1', '2026-11-15', 4800, 'kg', 'Optimal grain size and luster');
REPLACE INTO `harvest_records` (`harvest_id`, `cultivation_id`, `harvest_date`, `total_quantity`, `unit`, `remarks`) VALUES ('HARV-001', 'CULT-004', '2026-10-15', 5800, 'kg', 'Bumper yield MTU-1010 high grain density');
REPLACE INTO `harvest_records` (`harvest_id`, `cultivation_id`, `harvest_date`, `total_quantity`, `unit`, `remarks`) VALUES ('HARV-002', 'CULT-001', '2026-10-28', 4500, 'kg', 'Sample harvest BPT-5204 premium quality aromatic grain');
REPLACE INTO `harvest_records` (`harvest_id`, `cultivation_id`, `harvest_date`, `total_quantity`, `unit`, `remarks`) VALUES ('HARV-003', 'CULT-005', '2026-10-25', 8500, 'kg', 'Maize hybrid high cob grain recovery');

-- Data for table `input_applications` (9 records)
REPLACE INTO `input_applications` (`application_id`, `cultivation_id`, `product_id`, `product_batch_id`, `quantity_used`, `application_date`, `application_method`, `remarks`) VALUES ('APP-001', 'CULT-001', 'PROD-01', 'PBAT-01', 45, '2026-06-15', 'Basal Soil Incorporation', 'Basal Urea application before transplanting');
REPLACE INTO `input_applications` (`application_id`, `cultivation_id`, `product_id`, `product_batch_id`, `quantity_used`, `application_date`, `application_method`, `remarks`) VALUES ('APP-002', 'CULT-001', 'PROD-02', 'PBAT-02', 50, '2026-06-16', 'Basal Placement', 'Full dose DAP applied for vigorous root tillering');
REPLACE INTO `input_applications` (`application_id`, `cultivation_id`, `product_id`, `product_batch_id`, `quantity_used`, `application_date`, `application_method`, `remarks`) VALUES ('APP-003', 'CULT-001', 'PROD-16', 'PBAT-16', 5, '2026-07-05', 'Broadcasting', 'Zinc Sulphate applied to prevent Khaira deficiency');
REPLACE INTO `input_applications` (`application_id`, `cultivation_id`, `product_id`, `product_batch_id`, `quantity_used`, `application_date`, `application_method`, `remarks`) VALUES ('APP-004', 'CULT-001', 'PROD-05', 'PBAT-05', 0.5, '2026-08-14', 'Foliar Spray', 'Preventative spray for sheath blight with battery sprayer');
REPLACE INTO `input_applications` (`application_id`, `cultivation_id`, `product_id`, `product_batch_id`, `quantity_used`, `application_date`, `application_method`, `remarks`) VALUES ('APP-005', 'CULT-001', 'PROD-13', 'PBAT-13', 0.5, '2026-08-25', 'Foliar Spray', 'Nano Urea foliar top dressing at panicle initiation');
REPLACE INTO `input_applications` (`application_id`, `cultivation_id`, `product_id`, `product_batch_id`, `quantity_used`, `application_date`, `application_method`, `remarks`) VALUES ('APP-006', 'CULT-002', 'PROD-04', 'PBAT-04', 0.25, '2026-07-28', 'Knapsack Spraying', 'Confidor systemic spray for chilli thrips and whiteflies');
REPLACE INTO `input_applications` (`application_id`, `cultivation_id`, `product_id`, `product_batch_id`, `quantity_used`, `application_date`, `application_method`, `remarks`) VALUES ('APP-007', 'CULT-002', 'PROD-15', 'PBAT-15', 0.5, '2026-08-20', 'Foliar Spray', 'Vipul plant growth promoter for profuse flowering and pod set');
REPLACE INTO `input_applications` (`application_id`, `cultivation_id`, `product_id`, `product_batch_id`, `quantity_used`, `application_date`, `application_method`, `remarks`) VALUES ('APP-008', 'CULT-004', 'PROD-01', 'PBAT-01', 90, '2026-06-12', 'Split Top Dressing', 'Applied in two equal splits at active tillering');
REPLACE INTO `input_applications` (`application_id`, `cultivation_id`, `product_id`, `product_batch_id`, `quantity_used`, `application_date`, `application_method`, `remarks`) VALUES ('APP-009', 'CULT-004', 'PROD-11', 'PBAT-11', 0.1, '2026-08-10', 'Foliar Spray', 'Nativo spray for neck blast and sheath rot protection');

-- Data for table `input_payments` (12 records)
REPLACE INTO `input_payments` (`payment_id`, `purchase_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('IPAY-7263AE', 'PUR-9210DE', 2250, 'Cash at Counter', '2026-11-22 13:22:38', 'Completed', 'TXN-BEDE554A');
REPLACE INTO `input_payments` (`payment_id`, `purchase_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('IPAY-6D6F67', 'PUR-2D00AE', 2250, 'Cash at Counter', '2026-11-22 13:23:14', 'Completed', 'TXN-01BF4C2F');
REPLACE INTO `input_payments` (`payment_id`, `purchase_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('IPAY-CDF1CE', 'PUR-85A989', 2250, 'Cash at Counter', '2026-11-22 13:23:29', 'Completed', 'TXN-8ADBDCB0');
REPLACE INTO `input_payments` (`payment_id`, `purchase_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('IPAY-F54A72', 'PUR-AFFB8C', 533, 'Direct UPI / QR', '2026-11-23 13:35:30', 'Completed', 'TXN-046E73AF');
REPLACE INTO `input_payments` (`payment_id`, `purchase_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('IPAY-E6CB98', 'PUR-C81A60', 2250, 'Direct UPI / QR', '2026-11-23 13:35:56', 'Completed', 'TXN-F9A8EC6B');
REPLACE INTO `input_payments` (`payment_id`, `purchase_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('IPAY-E761FF', 'PUR-E5424A', 2250, 'Cash at Counter', '2026-11-24 16:37:38', 'Completed', 'TXN-C0D0EA17');
REPLACE INTO `input_payments` (`payment_id`, `purchase_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('IPAY-02FA9D', 'PUR-8CD75A', 2250, 'Cash at Counter', '2026-11-24 16:42:43', 'Completed', 'TXN-BFCEFE00');
REPLACE INTO `input_payments` (`payment_id`, `purchase_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('IPAY-3022ED', 'PUR-45FE84', 2250, 'Cash at Counter', '2026-11-24 16:52:27', 'Completed', 'TXN-781D43DA');
REPLACE INTO `input_payments` (`payment_id`, `purchase_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('IPAY-001', 'PUR-001', 3316, 'KCC Card Swipe (Biometric)', '2026-11-24 17:37:29', 'Completed', 'UPI-KCC-99882211');
REPLACE INTO `input_payments` (`payment_id`, `purchase_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('IPAY-002', 'PUR-002', 2700, 'Direct UPI / QR', '2026-11-24 17:37:29', 'Completed', 'UPI-GNT-55443322');
REPLACE INTO `input_payments` (`payment_id`, `purchase_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('IPAY-003', 'PUR-003', 1750, 'KCC Card Swipe', '2026-11-24 17:37:29', 'Completed', 'UPI-KCC-11223344');
REPLACE INTO `input_payments` (`payment_id`, `purchase_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('IPAY-004', 'FAR-PUR-004', 870, 'Cash Counter', '2026-11-24 17:37:29', 'Completed', 'CSH-RBK-GNT-8812');

-- Data for table `input_purchase_items` (14 records)
REPLACE INTO `input_purchase_items` (`item_id`, `purchase_id`, `product_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('PURI-96529A', 'PUR-9210DE', 'PBAT-03', 2, 1125, 2250);
REPLACE INTO `input_purchase_items` (`item_id`, `purchase_id`, `product_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('PURI-21D310', 'PUR-2D00AE', 'PBAT-03', 2, 1125, 2250);
REPLACE INTO `input_purchase_items` (`item_id`, `purchase_id`, `product_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('PURI-D0EDFB', 'PUR-85A989', 'PBAT-03', 2, 1125, 2250);
REPLACE INTO `input_purchase_items` (`item_id`, `purchase_id`, `product_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('PURI-6A4E1B', 'PUR-AFFB8C', 'PBAT-01', 2, 266.5, 533);
REPLACE INTO `input_purchase_items` (`item_id`, `purchase_id`, `product_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('PURI-73FCA7', 'PUR-C81A60', 'PBAT-03', 2, 1125, 2250);
REPLACE INTO `input_purchase_items` (`item_id`, `purchase_id`, `product_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('PURI-0D791B', 'PUR-E5424A', 'PBAT-03', 2, 1125, 2250);
REPLACE INTO `input_purchase_items` (`item_id`, `purchase_id`, `product_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('PURI-0305A4', 'PUR-8CD75A', 'PBAT-03', 2, 1125, 2250);
REPLACE INTO `input_purchase_items` (`item_id`, `purchase_id`, `product_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('PURI-9314F4', 'PUR-45FE84', 'PBAT-03', 2, 1125, 2250);
REPLACE INTO `input_purchase_items` (`item_id`, `purchase_id`, `product_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('PURI-001', 'PUR-001', 'PBAT-01', 4, 266.5, 1066);
REPLACE INTO `input_purchase_items` (`item_id`, `purchase_id`, `product_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('PURI-002', 'PUR-001', 'PBAT-03', 2, 1125, 2250);
REPLACE INTO `input_purchase_items` (`item_id`, `purchase_id`, `product_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('PURI-003', 'PUR-002', 'PBAT-02', 2, 1350, 2700);
REPLACE INTO `input_purchase_items` (`item_id`, `purchase_id`, `product_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('PURI-004', 'PUR-003', 'PBAT-06', 1, 1700, 1700);
REPLACE INTO `input_purchase_items` (`item_id`, `purchase_id`, `product_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('PURI-005', 'FAR-PUR-004', 'PBAT-04', 1, 420, 420);
REPLACE INTO `input_purchase_items` (`item_id`, `purchase_id`, `product_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('PURI-006', 'FAR-PUR-004', 'PBAT-16', 1, 450, 450);

-- Data for table `input_purchases` (12 records)
REPLACE INTO `input_purchases` (`purchase_id`, `farmer_id`, `rbk_id`, `purchase_date`, `total_amount`, `purchase_status`, `created_by_employee_id`) VALUES ('PUR-9210DE', 'FAR-001', 'RBK-GNT-03', '2026-11-22 13:22:38', 2250, 'Paid', NULL);
REPLACE INTO `input_purchases` (`purchase_id`, `farmer_id`, `rbk_id`, `purchase_date`, `total_amount`, `purchase_status`, `created_by_employee_id`) VALUES ('PUR-2D00AE', 'FAR-001', 'RBK-GNT-01', '2026-11-22 13:23:14', 2250, 'Paid', NULL);
REPLACE INTO `input_purchases` (`purchase_id`, `farmer_id`, `rbk_id`, `purchase_date`, `total_amount`, `purchase_status`, `created_by_employee_id`) VALUES ('PUR-85A989', 'FAR-001', 'RBK-GNT-01', '2026-11-22 13:23:29', 2250, 'Paid', NULL);
REPLACE INTO `input_purchases` (`purchase_id`, `farmer_id`, `rbk_id`, `purchase_date`, `total_amount`, `purchase_status`, `created_by_employee_id`) VALUES ('PUR-AFFB8C', 'FAR-001', 'RBK-GNT-03', '2026-11-23 13:35:30', 533, 'Paid', NULL);
REPLACE INTO `input_purchases` (`purchase_id`, `farmer_id`, `rbk_id`, `purchase_date`, `total_amount`, `purchase_status`, `created_by_employee_id`) VALUES ('PUR-C81A60', 'FAR-001', 'RBK-KRS-04', '2026-11-23 13:35:56', 2250, 'Paid', NULL);
REPLACE INTO `input_purchases` (`purchase_id`, `farmer_id`, `rbk_id`, `purchase_date`, `total_amount`, `purchase_status`, `created_by_employee_id`) VALUES ('PUR-E5424A', 'FAR-001', 'RBK-GNT-01', '2026-11-24 16:37:38', 2250, 'Paid', NULL);
REPLACE INTO `input_purchases` (`purchase_id`, `farmer_id`, `rbk_id`, `purchase_date`, `total_amount`, `purchase_status`, `created_by_employee_id`) VALUES ('PUR-8CD75A', 'FAR-001', 'RBK-GNT-01', '2026-11-24 16:42:43', 2250, 'Paid', NULL);
REPLACE INTO `input_purchases` (`purchase_id`, `farmer_id`, `rbk_id`, `purchase_date`, `total_amount`, `purchase_status`, `created_by_employee_id`) VALUES ('PUR-45FE84', 'FAR-001', 'RBK-GNT-01', '2026-11-24 16:52:27', 2250, 'Paid', NULL);
REPLACE INTO `input_purchases` (`purchase_id`, `farmer_id`, `rbk_id`, `purchase_date`, `total_amount`, `purchase_status`, `created_by_employee_id`) VALUES ('PUR-001', 'FAR-001', 'RBK-GNT-01', '2026-06-02 10:45:00', 3591.5, 'Paid', 'EMP-001');
REPLACE INTO `input_purchases` (`purchase_id`, `farmer_id`, `rbk_id`, `purchase_date`, `total_amount`, `purchase_status`, `created_by_employee_id`) VALUES ('PUR-002', 'FAR-002', 'RBK-GNT-01', '2026-06-04 11:20:00', 2700, 'Paid', 'EMP-001');
REPLACE INTO `input_purchases` (`purchase_id`, `farmer_id`, `rbk_id`, `purchase_date`, `total_amount`, `purchase_status`, `created_by_employee_id`) VALUES ('PUR-003', 'FAR-001', 'RBK-GNT-01', '2026-07-15 09:30:00', 1750, 'Paid', 'EMP-001');
REPLACE INTO `input_purchases` (`purchase_id`, `farmer_id`, `rbk_id`, `purchase_date`, `total_amount`, `purchase_status`, `created_by_employee_id`) VALUES ('FAR-PUR-004', 'FAR-001', 'RBK-GNT-01', '2026-08-01 14:15:00', 870, 'Paid', 'EMP-002');

-- Data for table `pre_booking_items` (5 records)
REPLACE INTO `pre_booking_items` (`item_id`, `preorder_id`, `product_id`, `requested_quantity`) VALUES ('PBI-001', 'PRE-001', 'PROD-01', 10);
REPLACE INTO `pre_booking_items` (`item_id`, `preorder_id`, `product_id`, `requested_quantity`) VALUES ('PBI-002', 'PRE-001', 'PROD-06', 4);
REPLACE INTO `pre_booking_items` (`item_id`, `preorder_id`, `product_id`, `requested_quantity`) VALUES ('PBI-003', 'PRE-002', 'PROD-03', 5);
REPLACE INTO `pre_booking_items` (`item_id`, `preorder_id`, `product_id`, `requested_quantity`) VALUES ('PBI-004', 'PRE-003', 'PROD-19', 3);
REPLACE INTO `pre_booking_items` (`item_id`, `preorder_id`, `product_id`, `requested_quantity`) VALUES ('PBI-005', 'PRE-004', 'PROD-02', 6);

-- Data for table `pre_booking_orders` (4 records)
REPLACE INTO `pre_booking_orders` (`preorder_id`, `farmer_id`, `rbk_id`, `preorder_number`, `target_season`, `target_year`, `order_status`, `created_at`) VALUES ('PRE-001', 'FAR-001', 'RBK-GNT-01', 'PBO-2026-001', 'Rabi 2026-27', 2026, 'Confirmed', '2026-11-24 17:37:29');
REPLACE INTO `pre_booking_orders` (`preorder_id`, `farmer_id`, `rbk_id`, `preorder_number`, `target_season`, `target_year`, `order_status`, `created_at`) VALUES ('PRE-002', 'FAR-004', 'RBK-GNT-01', 'PBO-2026-002', 'Rabi 2026-27', 2026, 'Pending', '2026-11-24 17:37:29');
REPLACE INTO `pre_booking_orders` (`preorder_id`, `farmer_id`, `rbk_id`, `preorder_number`, `target_season`, `target_year`, `order_status`, `created_at`) VALUES ('PRE-003', 'FAR-001', 'RBK-GNT-01', 'PBO-2026-003', 'Rabi 2026-27', 2026, 'Confirmed', '2026-11-24 17:37:29');
REPLACE INTO `pre_booking_orders` (`preorder_id`, `farmer_id`, `rbk_id`, `preorder_number`, `target_season`, `target_year`, `order_status`, `created_at`) VALUES ('PRE-004', 'FAR-002', 'RBK-GNT-02', 'PBO-2026-004', 'Rabi 2026-27', 2026, 'Confirmed', '2026-11-24 17:37:29');

-- Data for table `product_batches` (20 records)
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-01', 'PROD-01', 'BAT-UREA-2026-A', '2026-01-10', '2028-01-09', 'Active', 1000, 720);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-02', 'PROD-02', 'BAT-DAP-2026-B', '2026-02-05', '2028-02-04', 'Active', 800, 560);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-03', 'PROD-03', 'BAT-BPT-2026-C', '2026-03-12', '2027-03-11', 'Active', 500, 340);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-04', 'PROD-04', 'BAT-CONF-2026-D', '2026-02-18', '2028-02-17', 'Active', 300, 215);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-05', 'PROD-05', 'BAT-SAAF-2026-E', '2026-03-01', '2028-02-28', 'Active', 400, 310);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-06', 'PROD-06', 'BAT-MOP-2026-F', '2026-01-20', '2028-01-19', 'Active', 600, 480);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-07', 'PROD-07', 'BAT-2020-2026-G', '2026-02-15', '2028-02-14', 'Active', 750, 520);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-08', 'PROD-08', 'BAT-MTU-2026-H', '2026-03-25', '2027-03-24', 'Active', 450, 310);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-09', 'PROD-09', 'BAT-COT-2026-I', '2026-04-05', '2027-04-04', 'Active', 350, 240);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-10', 'PROD-10', 'BAT-AMP-2026-J', '2026-02-28', '2028-02-27', 'Active', 250, 185);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-11', 'PROD-11', 'BAT-NAT-2026-K', '2026-03-15', '2028-03-14', 'Active', 200, 145);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-12', 'PROD-12', 'BAT-IRI-2026-L', '2026-01-18', '2028-01-17', 'Active', 300, 220);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-13', 'PROD-13', 'BAT-NUREA-2026-M', '2026-04-10', '2028-04-09', 'Active', 600, 470);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-14', 'PROD-14', 'BAT-NDAP-2026-N', '2026-04-12', '2028-04-11', 'Active', 500, 380);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-15', 'PROD-15', 'BAT-VIP-2026-O', '2026-02-10', '2028-02-09', 'Active', 350, 260);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-16', 'PROD-16', 'BAT-ZN-2026-P', '2026-01-30', '2029-01-29', 'Active', 400, 290);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-17', 'PROD-17', 'BAT-TAF-2026-Q', '2026-03-05', '2028-03-04', 'Active', 280, 195);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-18', 'PROD-18', 'BAT-MAIZ-2026-R', '2026-04-01', '2027-03-31', 'Active', 320, 210);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-19', 'PROD-19', 'BAT-LBG-2026-S', '2026-03-20', '2027-03-19', 'Active', 400, 275);
REPLACE INTO `product_batches` (`product_batch_id`, `product_id`, `batch_number`, `manufacturing_date`, `expiry_date`, `batch_status`, `received_quantity`, `available_quantity`) VALUES ('PBAT-20', 'PROD-20', 'BAT-AMBI-2026-T', '2026-02-22', '2028-02-21', 'Active', 250, 180);

-- Data for table `product_categories` (8 records)
REPLACE INTO `product_categories` (`category_id`, `category_name`, `description`) VALUES ('PCAT-01', 'Certified Seeds', 'Government tested high yielding and hybrid varieties with >98% germination');
REPLACE INTO `product_categories` (`category_id`, `category_name`, `description`) VALUES ('PCAT-02', 'Chemical Fertilizers', 'Macro-nutrients including Granular Urea, DAP, MOP, Complex grades');
REPLACE INTO `product_categories` (`category_id`, `category_name`, `description`) VALUES ('PCAT-03', 'Bio-Fertilizers & Organic Inputs', 'Neem cake, Vermicompost, Phosphate solubilizing bio-cultures');
REPLACE INTO `product_categories` (`category_id`, `category_name`, `description`) VALUES ('PCAT-04', 'Crop Protection & Insecticides', 'Systemic and contact insecticides approved for integrated pest control');
REPLACE INTO `product_categories` (`category_id`, `category_name`, `description`) VALUES ('PCAT-05', 'Fungicides & Bactericides', 'Broad spectrum preventative and curative crop disease formulations');
REPLACE INTO `product_categories` (`category_id`, `category_name`, `description`) VALUES ('PCAT-06', 'Herbicides & Weedicides', 'Pre-emergence and post-emergence selective weed control chemicals');
REPLACE INTO `product_categories` (`category_id`, `category_name`, `description`) VALUES ('PCAT-07', 'Micro-Nutrients & Plant Tonics', 'Zinc, Boron, Ferrous, Magnesium and growth booster bio-stimulants');
REPLACE INTO `product_categories` (`category_id`, `category_name`, `description`) VALUES ('PCAT-08', 'Farm Equipment & Spraying Tools', 'Battery knapsack sprayers, pheromone traps, drip accessories');

-- Data for table `rbk_centres` (10 records)
REPLACE INTO `rbk_centres` (`rbk_id`, `rbk_name`, `location`, `district`, `contact`, `status`) VALUES ('RBK-GNT-01', 'Tenali Central RBK Kendra', 'Angalakuduru Junction, Tenali', 'Guntur', '9440112233', 'Active');
REPLACE INTO `rbk_centres` (`rbk_id`, `rbk_name`, `location`, `district`, `contact`, `status`) VALUES ('RBK-GNT-02', 'Mangalagiri Model RBK', 'GT Road, Mangalagiri', 'Guntur', '9440223344', 'Active');
REPLACE INTO `rbk_centres` (`rbk_id`, `rbk_name`, `location`, `district`, `contact`, `status`) VALUES ('RBK-GNT-03', 'Amaravati Farmer Assistance RBK', 'Dharanikota Center, Amaravati', 'Guntur', '9440334455', 'Active');
REPLACE INTO `rbk_centres` (`rbk_id`, `rbk_name`, `location`, `district`, `contact`, `status`) VALUES ('RBK-KRS-04', 'Vijayawada Rural RBK', 'Gannavaram Road, Enikepadu', 'Krishna', '9440445566', 'Active');
REPLACE INTO `rbk_centres` (`rbk_id`, `rbk_name`, `location`, `district`, `contact`, `status`) VALUES ('RBK-PRK-05', 'Ongole Farmers Service Kendra', 'Karavadi Junction, Ongole', 'Prakasam', '9440556677', 'Active');
REPLACE INTO `rbk_centres` (`rbk_id`, `rbk_name`, `location`, `district`, `contact`, `status`) VALUES ('RBK-BPT-06', 'Bapatla Coastal Agriculture RBK', 'Karlapalem Main Road, Bapatla', 'Bapatla', '9440667788', 'Active');
REPLACE INTO `rbk_centres` (`rbk_id`, `rbk_name`, `location`, `district`, `contact`, `status`) VALUES ('RBK-KRS-07', 'Gudivada Delta RBK', 'Billapadu Village, Gudivada', 'Krishna', '9440778899', 'Active');
REPLACE INTO `rbk_centres` (`rbk_id`, `rbk_name`, `location`, `district`, `contact`, `status`) VALUES ('RBK-PLN-08', 'Narasaraopet Model Kendra', 'Petlurivaripalem, Narasaraopet', 'Palnadu', '9440889900', 'Active');
REPLACE INTO `rbk_centres` (`rbk_id`, `rbk_name`, `location`, `district`, `contact`, `status`) VALUES ('RBK-EGD-09', 'Rajahmundry Riverbank RBK', 'Kadiyam Nurseries Road, Rajahmundry', 'East Godavari', '9440990011', 'Active');
REPLACE INTO `rbk_centres` (`rbk_id`, `rbk_name`, `location`, `district`, `contact`, `status`) VALUES ('RBK-WGD-10', 'Eluru Paddy Farmers Kendra', 'Sanivarapupeta, Eluru', 'West Godavari', '9440001122', 'Active');

-- Data for table `rbk_employees` (10 records)
REPLACE INTO `rbk_employees` (`employee_id`, `rbk_id`, `employee_name`, `designation`, `gender`, `phone`, `email`, `emp_password_id`, `joining_date`, `employment_status`, `created_at`) VALUES ('EMP-001', 'RBK-GNT-01', 'K. Subba Rao', 'Agriculture Extension Officer', 'Male', '9848556677', 'officer.tenali@agrichain.gov.in', 'PWD-001', '2021-08-01', 'Active', '2026-11-24 17:37:28');
REPLACE INTO `rbk_employees` (`employee_id`, `rbk_id`, `employee_name`, `designation`, `gender`, `phone`, `email`, `emp_password_id`, `joining_date`, `employment_status`, `created_at`) VALUES ('EMP-002', 'RBK-GNT-01', 'P. Anitha', 'Village Agriculture Assistant', 'Female', '9848667788', 'anitha.p@agrichain.gov.in', 'PWD-002', '2022-02-15', 'Active', '2026-11-24 17:37:28');
REPLACE INTO `rbk_employees` (`employee_id`, `rbk_id`, `employee_name`, `designation`, `gender`, `phone`, `email`, `emp_password_id`, `joining_date`, `employment_status`, `created_at`) VALUES ('EMP-003', 'RBK-GNT-02', 'M. Venkateswara Rao', 'RBK In-charge', 'Male', '9848778899', 'venkat.m@agrichain.gov.in', 'PWD-003', '2020-11-10', 'Active', '2026-11-24 17:37:28');
REPLACE INTO `rbk_employees` (`employee_id`, `rbk_id`, `employee_name`, `designation`, `gender`, `phone`, `email`, `emp_password_id`, `joining_date`, `employment_status`, `created_at`) VALUES ('EMP-004', 'RBK-GNT-03', 'S. Radhika', 'Village Agriculture Assistant', 'Female', '9848889900', 'radhika.s@agrichain.gov.in', 'PWD-004', '2022-05-18', 'Active', '2026-11-24 17:37:28');
REPLACE INTO `rbk_employees` (`employee_id`, `rbk_id`, `employee_name`, `designation`, `gender`, `phone`, `email`, `emp_password_id`, `joining_date`, `employment_status`, `created_at`) VALUES ('EMP-005', 'RBK-KRS-04', 'D. Suresh Kumar', 'Agriculture Extension Officer', 'Male', '9848990011', 'suresh.d@agrichain.gov.in', 'PWD-005', '2021-04-01', 'Active', '2026-11-24 17:37:28');
REPLACE INTO `rbk_employees` (`employee_id`, `rbk_id`, `employee_name`, `designation`, `gender`, `phone`, `email`, `emp_password_id`, `joining_date`, `employment_status`, `created_at`) VALUES ('EMP-006', 'RBK-PRK-05', 'G. Lakshmi Narayana', 'RBK In-charge', 'Male', '9848101112', 'narayana.g@agrichain.gov.in', 'PWD-006', '2020-09-01', 'Active', '2026-11-24 17:37:28');
REPLACE INTO `rbk_employees` (`employee_id`, `rbk_id`, `employee_name`, `designation`, `gender`, `phone`, `email`, `emp_password_id`, `joining_date`, `employment_status`, `created_at`) VALUES ('EMP-007', 'RBK-BPT-06', 'T. Bhavani Prasad', 'Village Horticulture Assistant', 'Male', '9848212223', 'bhavani.t@agrichain.gov.in', 'PWD-007', '2022-01-20', 'Active', '2026-11-24 17:37:28');
REPLACE INTO `rbk_employees` (`employee_id`, `rbk_id`, `employee_name`, `designation`, `gender`, `phone`, `email`, `emp_password_id`, `joining_date`, `employment_status`, `created_at`) VALUES ('EMP-008', 'RBK-KRS-07', 'V. Padmavathi', 'Village Agriculture Assistant', 'Female', '9848323334', 'padma.v@agrichain.gov.in', 'PWD-008', '2023-03-10', 'Active', '2026-11-24 17:37:28');
REPLACE INTO `rbk_employees` (`employee_id`, `rbk_id`, `employee_name`, `designation`, `gender`, `phone`, `email`, `emp_password_id`, `joining_date`, `employment_status`, `created_at`) VALUES ('EMP-009', 'RBK-PLN-08', 'B. Srinivasa Rao', 'Agriculture Extension Officer', 'Male', '9848434445', 'srinu.b@agrichain.gov.in', 'PWD-009', '2021-12-05', 'Active', '2026-11-24 17:37:28');
REPLACE INTO `rbk_employees` (`employee_id`, `rbk_id`, `employee_name`, `designation`, `gender`, `phone`, `email`, `emp_password_id`, `joining_date`, `employment_status`, `created_at`) VALUES ('EMP-010', 'RBK-EGD-09', 'C. Rama Krishna', 'RBK In-charge', 'Male', '9848545556', 'ramki.c@agrichain.gov.in', 'PWD-010', '2020-07-15', 'Active', '2026-11-24 17:37:28');

-- Data for table `rbk_inventory` (20 records)
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-01', 'RBK-GNT-01', 'PBAT-01', 180, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-02', 'RBK-GNT-01', 'PBAT-02', 140, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-03', 'RBK-GNT-01', 'PBAT-03', 95, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-04', 'RBK-GNT-01', 'PBAT-04', 45, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-05', 'RBK-GNT-01', 'PBAT-05', 80, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-06', 'RBK-GNT-01', 'PBAT-06', 110, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-07', 'RBK-GNT-01', 'PBAT-07', 130, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-08', 'RBK-GNT-01', 'PBAT-13', 160, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-09', 'RBK-GNT-01', 'PBAT-16', 35, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-10', 'RBK-GNT-02', 'PBAT-01', 210, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-11', 'RBK-GNT-02', 'PBAT-02', 160, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-12', 'RBK-GNT-02', 'PBAT-04', 65, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-13', 'RBK-GNT-02', 'PBAT-09', 40, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-14', 'RBK-GNT-03', 'PBAT-01', 190, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-15', 'RBK-GNT-03', 'PBAT-08', 120, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-16', 'RBK-KRS-04', 'PBAT-02', 175, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-17', 'RBK-KRS-04', 'PBAT-10', 75, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-18', 'RBK-PRK-05', 'PBAT-01', 200, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-19', 'RBK-BPT-06', 'PBAT-03', 130, '2026-11-24 17:37:28');
REPLACE INTO `rbk_inventory` (`inventory_id`, `rbk_id`, `product_batch_id`, `quantity`, `last_updated`) VALUES ('RINV-20', 'RBK-PLN-08', 'PBAT-09', 85, '2026-11-24 17:37:28');

-- Data for table `rbk_supply_items` (4 records)
REPLACE INTO `rbk_supply_items` (`item_id`, `supply_id`, `product_batch_id`, `ordered_quantity`, `received_quantity`, `rejected_quantity`, `unit_price`) VALUES ('SUPI-001', 'SUP-001', 'PBAT-01', 300, 300, 0, 266.5);
REPLACE INTO `rbk_supply_items` (`item_id`, `supply_id`, `product_batch_id`, `ordered_quantity`, `received_quantity`, `rejected_quantity`, `unit_price`) VALUES ('SUPI-002', 'SUP-001', 'PBAT-02', 80, 80, 0, 1350);
REPLACE INTO `rbk_supply_items` (`item_id`, `supply_id`, `product_batch_id`, `ordered_quantity`, `received_quantity`, `rejected_quantity`, `unit_price`) VALUES ('SUPI-003', 'SUP-002', 'PBAT-03', 100, 100, 0, 1125);
REPLACE INTO `rbk_supply_items` (`item_id`, `supply_id`, `product_batch_id`, `ordered_quantity`, `received_quantity`, `rejected_quantity`, `unit_price`) VALUES ('SUPI-004', 'SUP-003', 'PBAT-04', 150, 150, 0, 420);

-- Data for table `rbk_supply_orders` (4 records)
REPLACE INTO `rbk_supply_orders` (`supply_id`, `rbk_id`, `company_id`, `supply_date`, `expected_delivery_date`, `received_date`, `status`, `total_amount`, `created_by_employee_id`) VALUES ('SUP-001', 'RBK-GNT-01', 'COMP-01', '2026-05-10 10:00:00', '2026-05-15', '2026-05-14', 'Received', 188650, 'EMP-001');
REPLACE INTO `rbk_supply_orders` (`supply_id`, `rbk_id`, `company_id`, `supply_date`, `expected_delivery_date`, `received_date`, `status`, `total_amount`, `created_by_employee_id`) VALUES ('SUP-002', 'RBK-GNT-01', 'COMP-02', '2026-05-12 11:30:00', '2026-05-18', '2026-05-17', 'Received', 112500, 'EMP-001');
REPLACE INTO `rbk_supply_orders` (`supply_id`, `rbk_id`, `company_id`, `supply_date`, `expected_delivery_date`, `received_date`, `status`, `total_amount`, `created_by_employee_id`) VALUES ('SUP-003', 'RBK-GNT-01', 'COMP-03', '2026-05-15 14:00:00', '2026-05-20', '2026-05-19', 'Received', 63000, 'EMP-001');
REPLACE INTO `rbk_supply_orders` (`supply_id`, `rbk_id`, `company_id`, `supply_date`, `expected_delivery_date`, `received_date`, `status`, `total_amount`, `created_by_employee_id`) VALUES ('SUP-004', 'RBK-GNT-02', 'COMP-01', '2026-05-20 09:15:00', '2026-05-25', '2026-05-24', 'Received', 145000, 'EMP-003');

-- Data for table `sales_order_items` (10 records)
REPLACE INTO `sales_order_items` (`sales_item_id`, `sales_order_id`, `crop_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('SOI-630D68', 'SO-BD270D', 'CBAT-001', 1500, 32, 48000);
REPLACE INTO `sales_order_items` (`sales_item_id`, `sales_order_id`, `crop_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('SOI-81C6AC', 'SO-479E7E', 'CBAT-001', 1500, 32, 48000);
REPLACE INTO `sales_order_items` (`sales_item_id`, `sales_order_id`, `crop_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('SOI-E0F5E6', 'SO-9DBA73', 'CBAT-001', 1500, 32, 48000);
REPLACE INTO `sales_order_items` (`sales_item_id`, `sales_order_id`, `crop_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('SOI-466F59', 'SO-8370D9', 'CBAT-001', 1500, 32, 48000);
REPLACE INTO `sales_order_items` (`sales_item_id`, `sales_order_id`, `crop_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('SOI-83E9A9', 'SO-F0C153', 'CBAT-001', 1500, 32, 48000);
REPLACE INTO `sales_order_items` (`sales_item_id`, `sales_order_id`, `crop_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('SOI-4AA256', 'SO-0D1112', 'CBAT-001', 1500, 32, 48000);
REPLACE INTO `sales_order_items` (`sales_item_id`, `sales_order_id`, `crop_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('SOI-001', 'SO-001', 'CBAT-001', 2000, 26, 52000);
REPLACE INTO `sales_order_items` (`sales_item_id`, `sales_order_id`, `crop_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('SOI-002', 'SO-002', 'CBAT-002', 2500, 45, 112500);
REPLACE INTO `sales_order_items` (`sales_item_id`, `sales_order_id`, `crop_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('SOI-003', 'SO-003', 'CBAT-002', 1444.44, 45, 65000);
REPLACE INTO `sales_order_items` (`sales_item_id`, `sales_order_id`, `crop_batch_id`, `quantity`, `unit_price`, `subtotal`) VALUES ('SOI-004', 'SO-004', 'CBAT-003', 8500, 20, 170000);

-- Data for table `sales_orders` (10 records)
REPLACE INTO `sales_orders` (`sales_order_id`, `farmer_id`, `buyer_id`, `delivery_address`, `order_date`, `total_amount`, `payment_status`, `sales_channel`, `order_status`) VALUES ('SO-BD270D', 'FAR-001', 'BUY-002', 'ITC Hub, Guntur', '2026-11-22 13:22:38', 48000, 'Paid', 'Direct Contract', 'Placed');
REPLACE INTO `sales_orders` (`sales_order_id`, `farmer_id`, `buyer_id`, `delivery_address`, `order_date`, `total_amount`, `payment_status`, `sales_channel`, `order_status`) VALUES ('SO-479E7E', 'FAR-001', 'BUY-002', 'ITC Hub, Guntur', '2026-11-22 13:23:14', 48000, 'Paid', 'Direct Contract', 'Placed');
REPLACE INTO `sales_orders` (`sales_order_id`, `farmer_id`, `buyer_id`, `delivery_address`, `order_date`, `total_amount`, `payment_status`, `sales_channel`, `order_status`) VALUES ('SO-9DBA73', 'FAR-001', 'BUY-002', 'ITC Hub, Guntur', '2026-11-22 13:23:29', 48000, 'Paid', 'Direct Contract', 'Placed');
REPLACE INTO `sales_orders` (`sales_order_id`, `farmer_id`, `buyer_id`, `delivery_address`, `order_date`, `total_amount`, `payment_status`, `sales_channel`, `order_status`) VALUES ('SO-8370D9', 'FAR-001', 'BUY-002', 'ITC Hub, Guntur', '2026-11-24 16:37:38', 48000, 'Paid', 'Direct Contract', 'Placed');
REPLACE INTO `sales_orders` (`sales_order_id`, `farmer_id`, `buyer_id`, `delivery_address`, `order_date`, `total_amount`, `payment_status`, `sales_channel`, `order_status`) VALUES ('SO-F0C153', 'FAR-001', 'BUY-002', 'ITC Hub, Guntur', '2026-11-24 16:42:43', 48000, 'Paid', 'Direct Contract', 'Placed');
REPLACE INTO `sales_orders` (`sales_order_id`, `farmer_id`, `buyer_id`, `delivery_address`, `order_date`, `total_amount`, `payment_status`, `sales_channel`, `order_status`) VALUES ('SO-0D1112', 'FAR-001', 'BUY-002', 'ITC Hub, Guntur', '2026-11-24 16:52:27', 48000, 'Paid', 'Direct Contract', 'Placed');
REPLACE INTO `sales_orders` (`sales_order_id`, `farmer_id`, `buyer_id`, `delivery_address`, `order_date`, `total_amount`, `payment_status`, `sales_channel`, `order_status`) VALUES ('SO-001', 'FAR-003', 'BUY-001', 'ITC Procurement Hub, Industrial Road, Guntur', '2026-10-23 11:30:00', 52000, 'Paid', 'RBK E-Market', 'Delivered');
REPLACE INTO `sales_orders` (`sales_order_id`, `farmer_id`, `buyer_id`, `delivery_address`, `order_date`, `total_amount`, `payment_status`, `sales_channel`, `order_status`) VALUES ('SO-002', 'FAR-001', 'BUY-002', 'BigBasket Distribution Center, Vijayawada', '2026-11-02 14:15:00', 112500, 'Pending', 'Direct Contract', 'Placed');
REPLACE INTO `sales_orders` (`sales_order_id`, `farmer_id`, `buyer_id`, `delivery_address`, `order_date`, `total_amount`, `payment_status`, `sales_channel`, `order_status`) VALUES ('SO-003', 'FAR-001', 'BUY-001', 'ITC Processing Center, Tenali', '2026-11-10 10:00:00', 65000, 'Paid', 'Escrow Contract', 'Shipped');
REPLACE INTO `sales_orders` (`sales_order_id`, `farmer_id`, `buyer_id`, `delivery_address`, `order_date`, `total_amount`, `payment_status`, `sales_channel`, `order_status`) VALUES ('SO-004', 'FAR-004', 'BUY-003', 'Godrej Agrovet Sourcing Hub, Tenali', '2026-11-12 16:30:00', 170000, 'Paid', 'Direct Contract', 'Delivered');

-- Data for table `sales_payments` (9 records)
REPLACE INTO `sales_payments` (`payment_id`, `sales_order_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('SPAY-E5C195', 'SO-BD270D', 48000, 'RTGS', '2026-11-22 13:22:38', 'Completed', 'TXN-SO-D662A781');
REPLACE INTO `sales_payments` (`payment_id`, `sales_order_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('SPAY-CD142C', 'SO-479E7E', 48000, 'RTGS', '2026-11-22 13:23:14', 'Completed', 'TXN-SO-B07660A9');
REPLACE INTO `sales_payments` (`payment_id`, `sales_order_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('SPAY-1C6FE6', 'SO-9DBA73', 48000, 'RTGS', '2026-11-22 13:23:29', 'Completed', 'TXN-SO-867AE007');
REPLACE INTO `sales_payments` (`payment_id`, `sales_order_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('SPAY-21FFB1', 'SO-8370D9', 48000, 'RTGS', '2026-11-24 16:37:38', 'Completed', 'TXN-SO-7F877E95');
REPLACE INTO `sales_payments` (`payment_id`, `sales_order_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('SPAY-27AFA4', 'SO-F0C153', 48000, 'RTGS', '2026-11-24 16:42:43', 'Completed', 'TXN-SO-718C8CB3');
REPLACE INTO `sales_payments` (`payment_id`, `sales_order_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('SPAY-A38D15', 'SO-0D1112', 48000, 'RTGS', '2026-11-24 16:52:27', 'Completed', 'TXN-SO-3B5B19D7');
REPLACE INTO `sales_payments` (`payment_id`, `sales_order_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('SPAY-001', 'SO-001', 52000, 'RTGS / Bank Transfer', '2026-11-24 17:37:29', 'Completed', 'RTGS-SBIN2610239912');
REPLACE INTO `sales_payments` (`payment_id`, `sales_order_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('SPAY-002', 'SO-003', 65000, 'Escrow Auto-Release', '2026-11-24 17:37:29', 'Completed', 'ESCROW-HDFC-882299');
REPLACE INTO `sales_payments` (`payment_id`, `sales_order_id`, `amount`, `payment_method`, `payment_date`, `payment_status`, `transaction_reference`) VALUES ('SPAY-003', 'SO-004', 170000, 'Digital Corporate Transfer', '2026-11-24 17:37:29', 'Completed', 'RTGS-GODREJ-771144');

-- Data for table `seasonal_cultivator_rights` (4 records)
REPLACE INTO `seasonal_cultivator_rights` (`tenure_id`, `land_id`, `tenant_farmer_id`, `owner_farmer_id`, `agreement_type`, `non_encumbrance_clause`, `lease_expiry_date`, `approval_status`) VALUES ('TEN-001', 'LAND-007', 'FAR-006', 'FAR-001', 'Crop Cultivator Rights Card (CCRC)', 1, '2027-05-31', 'Approved');
REPLACE INTO `seasonal_cultivator_rights` (`tenure_id`, `land_id`, `tenant_farmer_id`, `owner_farmer_id`, `agreement_type`, `non_encumbrance_clause`, `lease_expiry_date`, `approval_status`) VALUES ('TEN-002', 'LAND-005', 'FAR-007', 'FAR-004', 'Seasonal Sharecropper Agreement', 1, '2027-04-30', 'Approved');
REPLACE INTO `seasonal_cultivator_rights` (`tenure_id`, `land_id`, `tenant_farmer_id`, `owner_farmer_id`, `agreement_type`, `non_encumbrance_clause`, `lease_expiry_date`, `approval_status`) VALUES ('TEN-003', 'LAND-006', 'FAR-008', 'FAR-005', 'Annual Oral Lease with Legal CCRC', 1, '2026-12-31', 'Under Verification');
REPLACE INTO `seasonal_cultivator_rights` (`tenure_id`, `land_id`, `tenant_farmer_id`, `owner_farmer_id`, `agreement_type`, `non_encumbrance_clause`, `lease_expiry_date`, `approval_status`) VALUES ('TEN-004', 'LAND-003', 'FAR-009', 'FAR-002', 'Fixed Cash Rental Tenure', 1, '2027-03-31', 'Approved');

-- Data for table `shipment_items` (3 records)
REPLACE INTO `shipment_items` (`shipment_item_id`, `shipment_id`, `crop_batch_id`, `sales_item_id`, `quantity`) VALUES ('SHPI-001', 'SHP-001', 'CBAT-001', 'SOI-001', 2000);
REPLACE INTO `shipment_items` (`shipment_item_id`, `shipment_id`, `crop_batch_id`, `sales_item_id`, `quantity`) VALUES ('SHPI-002', 'SHP-002', 'CBAT-002', 'SOI-003', 1444.44);
REPLACE INTO `shipment_items` (`shipment_item_id`, `shipment_id`, `crop_batch_id`, `sales_item_id`, `quantity`) VALUES ('SHPI-003', 'SHP-003', 'CBAT-003', 'SOI-004', 8500);

-- Data for table `shipments` (9 records)
REPLACE INTO `shipments` (`shipment_id`, `crop_batch_id`, `source_location`, `destination_location`, `vehicle_number`, `driver_name`, `dispatch_date`, `delivery_date`, `shipment_status`) VALUES ('SHP-544174', 'CBAT-001', 'APSWC Godown, Guntur', 'ITC Agri Logistics Park', 'AP 07 TJ 1122', 'Ramesh Driver', '2026-11-22 13:22:38', '2026-11-22 13:22:38', 'Delivered');
REPLACE INTO `shipments` (`shipment_id`, `crop_batch_id`, `source_location`, `destination_location`, `vehicle_number`, `driver_name`, `dispatch_date`, `delivery_date`, `shipment_status`) VALUES ('SHP-AFA150', 'CBAT-001', 'APSWC Godown, Guntur', 'ITC Agri Logistics Park', 'AP 07 TJ 1122', 'Ramesh Driver', '2026-11-22 13:23:14', '2026-11-22 13:23:14', 'Delivered');
REPLACE INTO `shipments` (`shipment_id`, `crop_batch_id`, `source_location`, `destination_location`, `vehicle_number`, `driver_name`, `dispatch_date`, `delivery_date`, `shipment_status`) VALUES ('SHP-024411', 'CBAT-001', 'APSWC Godown, Guntur', 'ITC Agri Logistics Park', 'AP 07 TJ 1122', 'Ramesh Driver', '2026-11-22 13:23:29', '2026-11-22 13:23:29', 'Delivered');
REPLACE INTO `shipments` (`shipment_id`, `crop_batch_id`, `source_location`, `destination_location`, `vehicle_number`, `driver_name`, `dispatch_date`, `delivery_date`, `shipment_status`) VALUES ('SHP-C42E6B', 'CBAT-001', 'APSWC Godown, Guntur', 'ITC Agri Logistics Park', 'AP 07 TJ 1122', 'Ramesh Driver', '2026-11-24 16:37:38', '2026-11-24 16:37:38', 'Delivered');
REPLACE INTO `shipments` (`shipment_id`, `crop_batch_id`, `source_location`, `destination_location`, `vehicle_number`, `driver_name`, `dispatch_date`, `delivery_date`, `shipment_status`) VALUES ('SHP-03F156', 'CBAT-001', 'APSWC Godown, Guntur', 'ITC Agri Logistics Park', 'AP 07 TJ 1122', 'Ramesh Driver', '2026-11-24 16:42:43', '2026-11-24 16:42:43', 'Delivered');
REPLACE INTO `shipments` (`shipment_id`, `crop_batch_id`, `source_location`, `destination_location`, `vehicle_number`, `driver_name`, `dispatch_date`, `delivery_date`, `shipment_status`) VALUES ('SHP-62BADA', 'CBAT-001', 'APSWC Godown, Guntur', 'ITC Agri Logistics Park', 'AP 07 TJ 1122', 'Ramesh Driver', '2026-11-24 16:52:27', '2026-11-24 16:52:27', 'Delivered');
REPLACE INTO `shipments` (`shipment_id`, `crop_batch_id`, `source_location`, `destination_location`, `vehicle_number`, `driver_name`, `dispatch_date`, `delivery_date`, `shipment_status`) VALUES ('SHP-001', 'CBAT-001', 'APSWC Central Godown, Guntur', 'ITC Procurement Hub, Guntur', 'AP 07 TJ 4455', 'K. Rambabu', '2026-10-24 09:00:00', '2026-10-24 15:30:00', 'Delivered');
REPLACE INTO `shipments` (`shipment_id`, `crop_batch_id`, `source_location`, `destination_location`, `vehicle_number`, `driver_name`, `dispatch_date`, `delivery_date`, `shipment_status`) VALUES ('SHP-002', 'CBAT-002', 'Tenali Market Yard Warehouse', 'ITC Processing Center, Tenali', 'AP 07 BK 9912', 'M. Venkatesh', '2026-11-11 08:30:00', '2026-11-11 12:00:00', 'Delivered');
REPLACE INTO `shipments` (`shipment_id`, `crop_batch_id`, `source_location`, `destination_location`, `vehicle_number`, `driver_name`, `dispatch_date`, `delivery_date`, `shipment_status`) VALUES ('SHP-003', 'CBAT-003', 'Vijayawada Logistics Hub', 'Godrej Agrovet Hub, Tenali', 'AP 16 TX 7788', 'D. Srinivasa Rao', '2026-11-13 07:00:00', NULL, 'In Transit');

-- Data for table `soil_health_records` (7 records)
REPLACE INTO `soil_health_records` (`test_id`, `field_id`, `ph_level`, `organic_carbon`, `nitrogen_kg_ha`, `phosphorus_kg_ha`, `potassium_kg_ha`, `test_date`) VALUES ('SOIL-001', 'FLD-001', 7.2, 0.68, 260, 24.5, 310, '2026-05-20');
REPLACE INTO `soil_health_records` (`test_id`, `field_id`, `ph_level`, `organic_carbon`, `nitrogen_kg_ha`, `phosphorus_kg_ha`, `potassium_kg_ha`, `test_date`) VALUES ('SOIL-002', 'FLD-002', 7.1, 0.62, 245, 21, 290, '2026-05-22');
REPLACE INTO `soil_health_records` (`test_id`, `field_id`, `ph_level`, `organic_carbon`, `nitrogen_kg_ha`, `phosphorus_kg_ha`, `potassium_kg_ha`, `test_date`) VALUES ('SOIL-003', 'FLD-003', 7.3, 0.7, 275, 26, 325, '2026-05-23');
REPLACE INTO `soil_health_records` (`test_id`, `field_id`, `ph_level`, `organic_carbon`, `nitrogen_kg_ha`, `phosphorus_kg_ha`, `potassium_kg_ha`, `test_date`) VALUES ('SOIL-004', 'FLD-004', 6.8, 0.55, 210, 18.5, 250, '2026-05-25');
REPLACE INTO `soil_health_records` (`test_id`, `field_id`, `ph_level`, `organic_carbon`, `nitrogen_kg_ha`, `phosphorus_kg_ha`, `potassium_kg_ha`, `test_date`) VALUES ('SOIL-005', 'FLD-005', 7.4, 0.72, 280, 28, 340, '2026-05-26');
REPLACE INTO `soil_health_records` (`test_id`, `field_id`, `ph_level`, `organic_carbon`, `nitrogen_kg_ha`, `phosphorus_kg_ha`, `potassium_kg_ha`, `test_date`) VALUES ('SOIL-006', 'FLD-006', 7, 0.65, 255, 22, 305, '2026-05-28');
REPLACE INTO `soil_health_records` (`test_id`, `field_id`, `ph_level`, `organic_carbon`, `nitrogen_kg_ha`, `phosphorus_kg_ha`, `potassium_kg_ha`, `test_date`) VALUES ('SOIL-007', 'FLD-007', 7.5, 0.75, 290, 30, 350, '2026-05-30');

-- Data for table `stock_movements` (15 records)
REPLACE INTO `stock_movements` (`movement_id`, `warehouse_id`, `crop_batch_id`, `movement_type`, `quantity`, `movement_date`, `reference_id`) VALUES ('SM-4AD8E5', 'WH-GNT-01', 'CBAT-C3CFAB', 'IN', 4800, '2026-11-15', 'HARV-BE9828');
REPLACE INTO `stock_movements` (`movement_id`, `warehouse_id`, `crop_batch_id`, `movement_type`, `quantity`, `movement_date`, `reference_id`) VALUES ('SM-6F8F25', 'WH-GNT-01', 'CBAT-001', 'OUT', 1000, '2026-11-22', 'SHP-544174');
REPLACE INTO `stock_movements` (`movement_id`, `warehouse_id`, `crop_batch_id`, `movement_type`, `quantity`, `movement_date`, `reference_id`) VALUES ('SM-F8AC0B', 'WH-GNT-01', 'CBAT-09ABC2', 'IN', 4800, '2026-11-15', 'HARV-5F4A5B');
REPLACE INTO `stock_movements` (`movement_id`, `warehouse_id`, `crop_batch_id`, `movement_type`, `quantity`, `movement_date`, `reference_id`) VALUES ('SM-F3DC70', 'WH-GNT-01', 'CBAT-001', 'OUT', 1000, '2026-11-22', 'SHP-AFA150');
REPLACE INTO `stock_movements` (`movement_id`, `warehouse_id`, `crop_batch_id`, `movement_type`, `quantity`, `movement_date`, `reference_id`) VALUES ('SM-50FF7D', 'WH-GNT-01', 'CBAT-7F5C49', 'IN', 4800, '2026-11-15', 'HARV-7348C5');
REPLACE INTO `stock_movements` (`movement_id`, `warehouse_id`, `crop_batch_id`, `movement_type`, `quantity`, `movement_date`, `reference_id`) VALUES ('SM-B33C2F', 'WH-GNT-01', 'CBAT-001', 'OUT', 1000, '2026-11-22', 'SHP-024411');
REPLACE INTO `stock_movements` (`movement_id`, `warehouse_id`, `crop_batch_id`, `movement_type`, `quantity`, `movement_date`, `reference_id`) VALUES ('SM-713FF0', 'WH-GNT-01', 'CBAT-A51896', 'IN', 4500, '2026-11-21', 'HARV-509BF3');
REPLACE INTO `stock_movements` (`movement_id`, `warehouse_id`, `crop_batch_id`, `movement_type`, `quantity`, `movement_date`, `reference_id`) VALUES ('SM-13EABB', 'WH-GNT-01', 'CBAT-F82472', 'IN', 4800, '2026-11-15', 'HARV-2AA99D');
REPLACE INTO `stock_movements` (`movement_id`, `warehouse_id`, `crop_batch_id`, `movement_type`, `quantity`, `movement_date`, `reference_id`) VALUES ('SM-64A6B5', 'WH-GNT-01', 'CBAT-001', 'OUT', 1000, '2026-11-24', 'SHP-C42E6B');
REPLACE INTO `stock_movements` (`movement_id`, `warehouse_id`, `crop_batch_id`, `movement_type`, `quantity`, `movement_date`, `reference_id`) VALUES ('SM-083B8E', 'WH-GNT-01', 'CBAT-FFF4ED', 'IN', 4800, '2026-11-15', 'HARV-05C723');
REPLACE INTO `stock_movements` (`movement_id`, `warehouse_id`, `crop_batch_id`, `movement_type`, `quantity`, `movement_date`, `reference_id`) VALUES ('SM-678B5E', 'WH-GNT-01', 'CBAT-001', 'OUT', 1000, '2026-11-24', 'SHP-03F156');
REPLACE INTO `stock_movements` (`movement_id`, `warehouse_id`, `crop_batch_id`, `movement_type`, `quantity`, `movement_date`, `reference_id`) VALUES ('SM-591D0B', 'WH-GNT-01', 'CBAT-B4F5B5', 'IN', 4800, '2026-11-15', 'HARV-078ABE');
REPLACE INTO `stock_movements` (`movement_id`, `warehouse_id`, `crop_batch_id`, `movement_type`, `quantity`, `movement_date`, `reference_id`) VALUES ('SM-7EBC7D', 'WH-GNT-01', 'CBAT-001', 'OUT', 1000, '2026-11-24', 'SHP-62BADA');
REPLACE INTO `stock_movements` (`movement_id`, `warehouse_id`, `crop_batch_id`, `movement_type`, `quantity`, `movement_date`, `reference_id`) VALUES ('SM-001', 'WH-GNT-01', 'CBAT-001', 'IN', 5800, '2026-10-18', 'HARV-001');
REPLACE INTO `stock_movements` (`movement_id`, `warehouse_id`, `crop_batch_id`, `movement_type`, `quantity`, `movement_date`, `reference_id`) VALUES ('SM-002', 'WH-GNT-01', 'CBAT-001', 'OUT', 2000, '2026-10-24', 'SO-001');

-- Data for table `system_users` (2 records)
REPLACE INTO `system_users` (`user_id`, `username`, `email`, `password_hash`, `full_name`, `role`, `status`, `created_at`) VALUES ('USR-ADMIN-01', 'admin', 'admin@agrichain.gov.in', 'b5a27f016cec0ac9e51c60aef04f63be4971ca637a36bfb86045e6c9930839de', 'System Administrator', 'Admin', 'Active', '2026-11-24 17:37:28');
REPLACE INTO `system_users` (`user_id`, `username`, `email`, `password_hash`, `full_name`, `role`, `status`, `created_at`) VALUES ('USR-OFFICER-01', 'rbk_officer', 'officer.tenali@agrichain.gov.in', '76dafe39ccd9b18c150b271bf23b5ddb7da99870b5a12b1482fc4cfe0a5794fd', 'K. Subba Rao', 'RBK Officer', 'Active', '2026-11-24 17:37:28');

-- Data for table `traceability_events` (31 records)
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-764064', 'CBAT-C3CFAB', 'Harvest & Batch Creation', 'Farm Site', '2026-11-15', 'Harvested 4800.0 kg. Batch code CB-2026-73E718 generated with QR: QR-AGRI-CB-2026-73E718-AP', 'RBK Quality Inspector');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-17442D', 'CBAT-001', 'Dispatched for Transport', 'APSWC Godown, Guntur', '2026-11-22 13:22:38', 'Loaded 1000.0 kg onto vehicle AP 07 TJ 1122 en route to ITC Agri Logistics Park.', 'Dispatch Officer');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-9F8B3D', 'CBAT-001', 'Delivered & Accepted', 'ITC Agri Logistics Park', '2026-11-22 13:22:38', 'Consignment successfully received and verified at destination.', 'Receiving Agent');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-4605D6', 'CBAT-09ABC2', 'Harvest & Batch Creation', 'Farm Site', '2026-11-15', 'Harvested 4800.0 kg. Batch code CB-2026-B63B05 generated with QR: QR-AGRI-CB-2026-B63B05-AP', 'RBK Quality Inspector');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-356CAA', 'CBAT-001', 'Dispatched for Transport', 'APSWC Godown, Guntur', '2026-11-22 13:23:14', 'Loaded 1000.0 kg onto vehicle AP 07 TJ 1122 en route to ITC Agri Logistics Park.', 'Dispatch Officer');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-AC63B2', 'CBAT-001', 'Delivered & Accepted', 'ITC Agri Logistics Park', '2026-11-22 13:23:14', 'Consignment successfully received and verified at destination.', 'Receiving Agent');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-452757', 'CBAT-7F5C49', 'Harvest & Batch Creation', 'Farm Site', '2026-11-15', 'Harvested 4800.0 kg. Batch code CB-2026-626EAF generated with QR: QR-AGRI-CB-2026-626EAF-AP', 'RBK Quality Inspector');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-98B4FF', 'CBAT-001', 'Dispatched for Transport', 'APSWC Godown, Guntur', '2026-11-22 13:23:29', 'Loaded 1000.0 kg onto vehicle AP 07 TJ 1122 en route to ITC Agri Logistics Park.', 'Dispatch Officer');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-F1D000', 'CBAT-001', 'Delivered & Accepted', 'ITC Agri Logistics Park', '2026-11-22 13:23:29', 'Consignment successfully received and verified at destination.', 'Receiving Agent');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-78C5E0', 'CBAT-A51896', 'Harvest & Batch Creation', 'Farm Site', '2026-11-21', 'Harvested 4500.0 kg. Batch code CB-2026-BCCC63 generated with QR: QR-AGRI-CB-2026-BCCC63-AP', 'RBK Quality Inspector');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-0EDA87', 'CBAT-F82472', 'Harvest & Batch Creation', 'Farm Site', '2026-11-15', 'Harvested 4800.0 kg. Batch code CB-2026-6BAE0D generated with QR: QR-AGRI-CB-2026-6BAE0D-AP', 'RBK Quality Inspector');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-E03892', 'CBAT-001', 'Dispatched for Transport', 'APSWC Godown, Guntur', '2026-11-24 16:37:38', 'Loaded 1000.0 kg onto vehicle AP 07 TJ 1122 en route to ITC Agri Logistics Park.', 'Dispatch Officer');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-FC7339', 'CBAT-001', 'Delivered & Accepted', 'ITC Agri Logistics Park', '2026-11-24 16:37:38', 'Consignment successfully received and verified at destination.', 'Receiving Agent');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-C2A286', 'CBAT-FFF4ED', 'Harvest & Batch Creation', 'Farm Site', '2026-11-15', 'Harvested 4800.0 kg. Batch code CB-2026-4F66A7 generated with QR: QR-AGRI-CB-2026-4F66A7-AP', 'RBK Quality Inspector');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-2EAF16', 'CBAT-001', 'Dispatched for Transport', 'APSWC Godown, Guntur', '2026-11-24 16:42:43', 'Loaded 1000.0 kg onto vehicle AP 07 TJ 1122 en route to ITC Agri Logistics Park.', 'Dispatch Officer');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-ADC229', 'CBAT-001', 'Delivered & Accepted', 'ITC Agri Logistics Park', '2026-11-24 16:42:43', 'Consignment successfully received and verified at destination.', 'Receiving Agent');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-24E36C', 'CBAT-B4F5B5', 'Harvest & Batch Creation', 'Farm Site', '2026-11-15', 'Harvested 4800.0 kg. Batch code CB-2026-150B94 generated with QR: QR-AGRI-CB-2026-150B94-AP', 'RBK Quality Inspector');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-FFB21A', 'CBAT-001', 'Dispatched for Transport', 'APSWC Godown, Guntur', '2026-11-24 16:52:27', 'Loaded 1000.0 kg onto vehicle AP 07 TJ 1122 en route to ITC Agri Logistics Park.', 'Dispatch Officer');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-01E8C0', 'CBAT-001', 'Delivered & Accepted', 'ITC Agri Logistics Park', '2026-11-24 16:52:27', 'Consignment successfully received and verified at destination.', 'Receiving Agent');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-01', 'CBAT-001', 'Land Preparation', 'Amaravati Farm Field #5', '2026-06-05 08:30:00', 'Rotavator soil tilth, certified organic vermicompost incorporated', 'Farmer: Lakshmi Devi');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-02', 'CBAT-001', 'Certified Sowing', 'Amaravati Farm Field #5', '2026-06-10 09:00:00', 'Sown MTU-1010 foundation seeds from RBK Center', 'VAA: P. Anitha');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-03', 'CBAT-001', 'Nutrient & Pest Check', 'Amaravati Farm Field #5', '2026-07-15 11:00:00', 'Applied certified neem cake and bio-culture, zero synthetic pesticides', 'AEO: K. Subba Rao');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-04', 'CBAT-001', 'Field Harvest', 'Amaravati Farm Field #5', '2026-10-15 16:00:00', 'Combined harvested 5800 kg at 16% field moisture', 'Farmer: Lakshmi Devi');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-05', 'CBAT-001', 'Quality Certification', 'Tenali Quality Lab', '2026-10-17 10:30:00', 'Passed Grade A specification with 13.2% moisture and 0.4% refraction', 'Inspector: Dr. R. Sharma');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-06', 'CBAT-001', 'Secure Warehousing', 'APSWC Godown, Guntur', '2026-10-18 14:00:00', 'Stored in scientific moisture-controlled warehouse bay #14', 'WH Mgr: G. Krishna');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-07', 'CBAT-001', 'Logistics Dispatch', 'Guntur APSWC to ITC Hub', '2026-10-24 09:15:00', 'Loaded 2000 kg on vehicle AP 07 TJ 4455 with digital seal #8812', 'Logistics Officer: M. Prasad');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-08', 'CBAT-001', 'Delivered & Accepted', 'ITC Agri Business, Guntur', '2026-10-24 15:30:00', 'Receipt confirmed and quality batch accepted by ITC Procurement team', 'Buyer Agent: V. Ramanathan');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-09', 'CBAT-002', 'Seed Purity Sowing', 'Angalakuduru Field #1', '2026-06-15 08:00:00', 'BPT-5204 foundation seed batch PBAT-03 with biometric issue', 'Farmer: Ramesh Babu Naidu');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-10', 'CBAT-002', 'Foliar Blast Defense', 'Angalakuduru Field #1', '2026-08-14 10:00:00', 'Saaf protective fungicide application recorded under audit', 'RBK Officer: K. Subba Rao');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-11', 'CBAT-002', 'Scientific Warehousing', 'Tenali Market Yard Warehouse', '2026-10-29 14:00:00', 'BPT-5204 Grade A+ premium stored under moisture seal', 'WH Officer: M. Joseph');
REPLACE INTO `traceability_events` (`event_id`, `crop_batch_id`, `event_type`, `location`, `event_date`, `description`, `recorded_by`) VALUES ('TRC-12', 'CBAT-002', 'Escrow Contract Dispatch', 'Tenali to ITC Processing', '2026-11-11 08:30:00', 'Dispatched 1444 kg via AP 07 BK 9912 under verified escrow SO-003', 'Buyer QA: ITC Team');

-- Data for table `warehouse_inventory` (10 records)
REPLACE INTO `warehouse_inventory` (`inventory_id`, `warehouse_id`, `crop_batch_id`, `quantity`, `storage_date`, `last_updated`) VALUES ('WINV-D220FC', 'WH-GNT-01', 'CBAT-C3CFAB', 4800, '2026-11-22 13:22:38', '2026-11-22 13:22:38');
REPLACE INTO `warehouse_inventory` (`inventory_id`, `warehouse_id`, `crop_batch_id`, `quantity`, `storage_date`, `last_updated`) VALUES ('WINV-03F54E', 'WH-GNT-01', 'CBAT-09ABC2', 4800, '2026-11-22 13:23:14', '2026-11-22 13:23:14');
REPLACE INTO `warehouse_inventory` (`inventory_id`, `warehouse_id`, `crop_batch_id`, `quantity`, `storage_date`, `last_updated`) VALUES ('WINV-AB2480', 'WH-GNT-01', 'CBAT-7F5C49', 4800, '2026-11-22 13:23:29', '2026-11-22 13:23:29');
REPLACE INTO `warehouse_inventory` (`inventory_id`, `warehouse_id`, `crop_batch_id`, `quantity`, `storage_date`, `last_updated`) VALUES ('WINV-EE8593', 'WH-GNT-01', 'CBAT-A51896', 4500, '2026-11-23 03:45:54', '2026-11-23 03:45:54');
REPLACE INTO `warehouse_inventory` (`inventory_id`, `warehouse_id`, `crop_batch_id`, `quantity`, `storage_date`, `last_updated`) VALUES ('WINV-98FF8E', 'WH-GNT-01', 'CBAT-F82472', 4800, '2026-11-24 16:37:38', '2026-11-24 16:37:38');
REPLACE INTO `warehouse_inventory` (`inventory_id`, `warehouse_id`, `crop_batch_id`, `quantity`, `storage_date`, `last_updated`) VALUES ('WINV-55D3F0', 'WH-GNT-01', 'CBAT-FFF4ED', 4800, '2026-11-24 16:42:43', '2026-11-24 16:42:43');
REPLACE INTO `warehouse_inventory` (`inventory_id`, `warehouse_id`, `crop_batch_id`, `quantity`, `storage_date`, `last_updated`) VALUES ('WINV-A60BE4', 'WH-GNT-01', 'CBAT-B4F5B5', 4800, '2026-11-24 16:52:27', '2026-11-24 16:52:27');
REPLACE INTO `warehouse_inventory` (`inventory_id`, `warehouse_id`, `crop_batch_id`, `quantity`, `storage_date`, `last_updated`) VALUES ('WINV-001', 'WH-GNT-01', 'CBAT-001', 3800, '2026-11-24 17:37:29', '2026-11-24 17:37:29');
REPLACE INTO `warehouse_inventory` (`inventory_id`, `warehouse_id`, `crop_batch_id`, `quantity`, `storage_date`, `last_updated`) VALUES ('WINV-002', 'WH-TNL-02', 'CBAT-002', 4500, '2026-11-24 17:37:29', '2026-11-24 17:37:29');
REPLACE INTO `warehouse_inventory` (`inventory_id`, `warehouse_id`, `crop_batch_id`, `quantity`, `storage_date`, `last_updated`) VALUES ('WINV-003', 'WH-VJA-03', 'CBAT-003', 8500, '2026-11-24 17:37:29', '2026-11-24 17:37:29');

-- Data for table `warehouses` (8 records)
REPLACE INTO `warehouses` (`warehouse_id`, `warehouse_name`, `location`, `district`, `capacity`, `contact_number`) VALUES ('WH-GNT-01', 'APSWC Central Godown - Guntur', 'Etukuru Road, Guntur', 'Guntur', 25000, '0863229988');
REPLACE INTO `warehouses` (`warehouse_id`, `warehouse_name`, `location`, `district`, `capacity`, `contact_number`) VALUES ('WH-TNL-02', 'Tenali Agricultural Market Yard Warehouse', 'Market Yard, Tenali', 'Guntur', 12000, '0864422558');
REPLACE INTO `warehouses` (`warehouse_id`, `warehouse_name`, `location`, `district`, `capacity`, `contact_number`) VALUES ('WH-VJA-03', 'CWC Regional Logistics Hub - Vijayawada', 'Enikepadu, Vijayawada', 'Krishna', 35000, '0866244779');
REPLACE INTO `warehouses` (`warehouse_id`, `warehouse_name`, `location`, `district`, `capacity`, `contact_number`) VALUES ('WH-ONG-04', 'Prakasam District Agro Godown - Ongole', 'Collectorate Road, Ongole', 'Prakasam', 18000, '0859223311');
REPLACE INTO `warehouses` (`warehouse_id`, `warehouse_name`, `location`, `district`, `capacity`, `contact_number`) VALUES ('WH-BPT-05', 'Bapatla Coastal Cold Storage & Silo', 'Port Road, Bapatla', 'Bapatla', 15000, '0864322445');
REPLACE INTO `warehouses` (`warehouse_id`, `warehouse_name`, `location`, `district`, `capacity`, `contact_number`) VALUES ('WH-GDV-06', 'Krishna Delta Storage Facility - Gudivada', 'Bantumilli Road, Gudivada', 'Krishna', 16000, '0867424488');
REPLACE INTO `warehouses` (`warehouse_id`, `warehouse_name`, `location`, `district`, `capacity`, `contact_number`) VALUES ('WH-NSP-07', 'Palnadu Grain Warehouse - Narasaraopet', 'Vinukonda Road, Narasaraopet', 'Palnadu', 20000, '0864723366');
REPLACE INTO `warehouses` (`warehouse_id`, `warehouse_name`, `location`, `district`, `capacity`, `contact_number`) VALUES ('WH-ELR-08', 'Godavari Agro Logistics Hub - Eluru', 'Powerpet, Eluru', 'Eluru', 22000, '0881223399');

SET FOREIGN_KEY_CHECKS = 1;

-- Total rows inserted across all tables: 488
