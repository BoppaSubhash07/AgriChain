/* ======================================================================
   AGRICHAIN - SCHEMA UPGRADES, BASE + MAXIMUM SEED DATA & TRIGGERS
   Safe, idempotent script for `agri_management_database` (MySQL 8+).
   Works cleanly whether the existing database is empty structure-only,
   partially seeded, or already has base data.
   ====================================================================== */

USE agri_management_database;
SET SQL_SAFE_UPDATES = 0;

/* ---------- 1. SAFE SCHEMA & CHECK CONSTRAINT UPGRADES ---------- */
CREATE TABLE IF NOT EXISTS administrative_regions (
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

CREATE OR REPLACE VIEW administrative_divisions AS
SELECT * FROM administrative_regions;

CREATE TABLE IF NOT EXISTS system_users (
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

DROP PROCEDURE IF EXISTS sp_agrichain_upgrade_constraints;
DELIMITER $$
CREATE PROCEDURE sp_agrichain_upgrade_constraints()
BEGIN
    /* Add buyers.buyer_password_hash if DB was built from older DDL */
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'buyers'
          AND COLUMN_NAME = 'buyer_password_hash'
    ) THEN
        ALTER TABLE buyers ADD COLUMN buyer_password_hash VARCHAR(255) NULL AFTER registration_number;
    END IF;

    /* Allow 'VERIFIED_BY_VAA' and 'Under Verification' in seasonal_cultivator_rights */
    IF EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'seasonal_cultivator_rights'
          AND CONSTRAINT_NAME = 'chk_scr_status'
    ) THEN
        ALTER TABLE seasonal_cultivator_rights DROP CHECK chk_scr_status;
    END IF;
    ALTER TABLE seasonal_cultivator_rights
        ADD CONSTRAINT chk_scr_status
        CHECK (approval_status IN ('Pending','Under Verification','VERIFIED_BY_VAA','Approved','Rejected','Expired'));

    /* Allow 'Leased Out' in farmer_land_records */
    IF EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'farmer_land_records'
          AND CONSTRAINT_NAME = 'chk_land_owner'
    ) THEN
        ALTER TABLE farmer_land_records DROP CHECK chk_land_owner;
    END IF;
    ALTER TABLE farmer_land_records
        ADD CONSTRAINT chk_land_owner
        CHECK (ownership_type IN ('Owned','Leased','Leased Out','Joint'));

    /* Allow 'ESCROW_HELD' and 'COMPLETED' in sales_payments */
    IF EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'sales_payments'
          AND CONSTRAINT_NAME = 'chk_sp_status'
    ) THEN
        ALTER TABLE sales_payments DROP CHECK chk_sp_status;
    END IF;
    ALTER TABLE sales_payments
        ADD CONSTRAINT chk_sp_status
        CHECK (payment_status IN ('Pending','ESCROW_HELD','Completed','COMPLETED','Failed','Refunded'));

    /* Allow 'ESCROW_HELD' in sales_orders.payment_status */
    IF EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'sales_orders'
          AND CONSTRAINT_NAME = 'chk_so_pay'
    ) THEN
        ALTER TABLE sales_orders DROP CHECK chk_so_pay;
    END IF;
    ALTER TABLE sales_orders
        ADD CONSTRAINT chk_so_pay
        CHECK (payment_status IN ('Pending','Partial','ESCROW_HELD','Paid','Refunded'));
END$$
DELIMITER ;

CALL sp_agrichain_upgrade_constraints();
DROP PROCEDURE IF EXISTS sp_agrichain_upgrade_constraints;

/* Drop trigger during seeding so seed input_purchase_items do not double-deduct stock */
DROP TRIGGER IF EXISTS trg_after_input_purchase_item_insert;

/* ---------- 2. MAXIMUM SEED DATA FOR REQUESTED MASTER TABLES ---------- */

/* (a) administrative_divisions (via underlying administrative_regions) - 40 records */
INSERT INTO administrative_regions (region_id, state_name, district_name, mandal_name, village_name, pincode) VALUES
('REG-01', 'Andhra Pradesh', 'Guntur', 'Tenali', 'Angalakuduru', '522202'),
('REG-02', 'Andhra Pradesh', 'Guntur', 'Mangalagiri', 'Navuluru', '522503'),
('REG-03', 'Andhra Pradesh', 'Guntur', 'Amaravati', 'Dharanikota', '522020'),
('REG-04', 'Andhra Pradesh', 'Krishna', 'Vijayawada Rural', 'Enikepadu', '521108'),
('REG-05', 'Andhra Pradesh', 'Prakasam', 'Ongole', 'Karavadi', '523182'),
('REG-06', 'Andhra Pradesh', 'Bapatla', 'Bapatla Urban', 'Karlapalem', '522101'),
('REG-07', 'Andhra Pradesh', 'Krishna', 'Gudivada', 'Billapadu', '521301'),
('REG-08', 'Andhra Pradesh', 'Palnadu', 'Narasaraopet', 'Petlurivaripalem', '522601'),
('REG-09', 'Andhra Pradesh', 'East Godavari', 'Rajahmundry', 'Kadiyam', '533126'),
('REG-10', 'Andhra Pradesh', 'West Godavari', 'Eluru', 'Sanivarapupeta', '534005'),
('REG-11', 'Andhra Pradesh', 'Kurnool', 'Nandyal', 'Panyam', '518112'),
('REG-12', 'Andhra Pradesh', 'SPSR Nellore', 'Kavali', 'Musunuru', '524201'),
('REG-13', 'Andhra Pradesh', 'Chittoor', 'Madanapalle', 'Valasapalle', '517325'),
('REG-14', 'Andhra Pradesh', 'Anantapur', 'Tadipatri', 'Yerraguntapalli', '515411'),
('REG-15', 'Andhra Pradesh', 'Visakhapatnam', 'Anakapalle', 'Kasimkota', '531031'),
('REG-16', 'Andhra Pradesh', 'Guntur', 'Ponnur', 'Nidubrolu', '522124'),
('REG-17', 'Andhra Pradesh', 'Guntur', 'Tadikonda', 'Lam', '522034'),
('REG-18', 'Andhra Pradesh', 'Guntur', 'Duggirala', 'Chiluvuru', '522330'),
('REG-19', 'Andhra Pradesh', 'Palnadu', 'Gurzala', 'Jangamaheswarapuram', '522415'),
('REG-20', 'Andhra Pradesh', 'Palnadu', 'Sattenapalli', 'Kankanalapalli', '522403'),
('REG-21', 'Andhra Pradesh', 'Palnadu', 'Chilakaluripet', 'Purushothapatnam', '522616'),
('REG-22', 'Andhra Pradesh', 'Bapatla', 'Repalle', 'Penumudi', '522265'),
('REG-23', 'Andhra Pradesh', 'Bapatla', 'Chirala', 'Epurupalem', '523166'),
('REG-24', 'Andhra Pradesh', 'NTR', 'Nandigama', 'Kanchikacherla', '521180'),
('REG-25', 'Andhra Pradesh', 'NTR', 'Mylavaram', 'Velvadam', '521230'),
('REG-26', 'Andhra Pradesh', 'Krishna', 'Machilipatnam', 'Chilakalapudi', '521002'),
('REG-27', 'Andhra Pradesh', 'Eluru', 'Nuzvid', 'Agiripalli', '521211'),
('REG-28', 'Andhra Pradesh', 'West Godavari', 'Bhimavaram', 'Undi', '534199'),
('REG-29', 'Andhra Pradesh', 'Konaseema', 'Amalapuram', 'Ambajipeta', '533214'),
('REG-30', 'Andhra Pradesh', 'Kakinada', 'Samalkot', 'Vetlapalem', '533434'),
('REG-31', 'Andhra Pradesh', 'Prakasam', 'Markapur', 'Tarlupadu', '523332'),
('REG-32', 'Andhra Pradesh', 'SPSR Nellore', 'Gudur', 'Chillakur', '524412'),
('REG-33', 'Andhra Pradesh', 'Tirupati', 'Srikalahasti', 'Thondamanadu', '517640'),
('REG-34', 'Andhra Pradesh', 'YSR Kadapa', 'Proddatur', 'Korrapadu', '516360'),
('REG-35', 'Andhra Pradesh', 'Annamayya', 'Rayachoti', 'Galiveedu', '516267'),
('REG-36', 'Andhra Pradesh', 'Nandyal', 'Allagadda', 'Chagalamarri', '518553'),
('REG-37', 'Andhra Pradesh', 'Kurnool', 'Adoni', 'Alur', '518395'),
('REG-38', 'Andhra Pradesh', 'Sri Sathya Sai', 'Hindupur', 'Lepakshi', '515331'),
('REG-39', 'Andhra Pradesh', 'Vizianagaram', 'Bobbili', 'Seethanagaram', '535546'),
('REG-40', 'Andhra Pradesh', 'Srikakulam', 'Amadalavalasa', 'Burja', '532185')
ON DUPLICATE KEY UPDATE
    state_name = VALUES(state_name),
    district_name = VALUES(district_name),
    mandal_name = VALUES(mandal_name),
    village_name = VALUES(village_name),
    pincode = VALUES(pincode);

/* (b.1) agro_companies - 20 records */
INSERT INTO agro_companies (company_id, company_name, registration_number, phone, email, GST_number, address, established_date) VALUES
('COMP-01', 'Coromandel International Ltd', 'REG-COR-AP-001', '0863223344', 'contact@coromandel.biz', '37AAACC1234A1Z9', 'Coromandel House, Guntur', '1961-04-10'),
('COMP-02', 'Syngenta India Ltd', 'REG-SYN-IN-002', '0863234455', 'customercare@syngenta.com', '37AAACS5678B1Z7', 'Highway Road, Vijayawada', '2000-01-15'),
('COMP-03', 'Bayer CropScience Ltd', 'REG-BAY-IN-003', '0863245566', 'india@bayer.com', '37AAACB9012C1Z5', 'APIIC Industrial Area, Tenali', '1995-08-20'),
('COMP-04', 'UPL India Ltd', 'REG-UPL-IN-004', '0863256677', 'connect@upl-ltd.com', '37AAACU3456D1Z3', 'Ring Road, Guntur', '1980-05-29'),
('COMP-05', 'Godrej Agrovet Ltd', 'REG-GOD-AP-005', '0863267788', 'agri@godrejagrovet.com', '37AAACG7890E1Z1', 'Industrial Estate, Tenali', '1991-11-24'),
('COMP-06', 'Nagarjuna Fertilizers and Chemicals Ltd', 'REG-NFCL-006', '0863278899', 'sales@nagarjuna.com', '37AAACN4455F1Z2', 'Nagarjuna Hills, Vijayawada', '1985-03-12'),
('COMP-07', 'Kaveri Seed Company Ltd', 'REG-KAV-007', '0863289900', 'info@kaveriseeds.in', '37AAACK1122G1Z4', 'Seed Park, Guntur', '1986-09-05'),
('COMP-08', 'Rallis India Ltd (Tata Enterprise)', 'REG-RAL-008', '0863290011', 'agro@rallis.com', '37AAACR3344H1Z6', 'Benz Circle, Vijayawada', '1948-08-23'),
('COMP-09', 'National Seeds Corporation Ltd', 'REG-NSC-009', '0863211122', 'support@indiaseeds.gov.in', '37AAACN9988I1Z8', 'Central Godown, Guntur', '1963-03-01'),
('COMP-10', 'IFFCO AP Marketing Federation', 'REG-IFF-010', '0863222233', 'coop@iffco.in', '37AAAII7766J1Z0', 'Fertilizer Bhavan, Vijayawada', '1967-11-03'),
('COMP-11', 'KRIBHCO Cooperative Fertilizers', 'REG-KRI-011', '0866241122', 'ap@kribhco.net', '37AAACK6611K1Z1', 'MG Road, Vijayawada', '1980-04-17'),
('COMP-12', 'Rashtriya Chemicals & Fertilizers (RCF)', 'REG-RCF-012', '0863231144', 'marketing@rcfltd.com', '37AAACR2233L1Z2', 'Autonagar Phase II, Guntur', '1978-03-06'),
('COMP-13', 'Mahyco Private Limited', 'REG-MAH-013', '0863241155', 'seeds@mahyco.com', '37AAACM4455M1Z3', 'Seed Corridor, Guntur', '1964-06-12'),
('COMP-14', 'Nuziveedu Seeds Ltd', 'REG-NUZ-014', '0865622334', 'care@nuziveeduseeds.com', '37AAACN7788N1Z4', 'Seed Park, Nuzvid', '1973-07-01'),
('COMP-15', 'Chambal Fertilisers and Chemicals Ltd', 'REG-CHA-015', '0866255566', 'uttam@chambal.in', '37AAACC8899O1Z5', 'Kakinada Port Hub, Kakinada', '1985-05-07'),
('COMP-16', 'Zuari Agro Chemicals Ltd', 'REG-ZUA-016', '0863266688', 'jai@zuari.in', '37AAACZ1199P1Z6', 'Etukuru Road, Guntur', '1967-05-12'),
('COMP-17', 'PI Industries Ltd', 'REG-PI-017', '0866277799', 'cropcare@piind.com', '37AAACP3322Q1Z7', 'Patamata, Vijayawada', '1947-01-10'),
('COMP-18', 'FMC India Agricultural Sciences', 'REG-FMC-018', '0863288800', 'ag.india@fmc.com', '37AAACF5544R1Z8', 'Lakshmipuram, Guntur', '1994-09-14'),
('COMP-19', 'Corteva Agriscience India', 'REG-CRT-019', '0866299911', 'pioneer.ap@corteva.com', '37AAACC6677S1Z9', 'Bypass Hub, Vijayawada', '2018-02-26'),
('COMP-20', 'BASF India Crop Protection', 'REG-BAS-020', '0863200022', 'agro.ap@basf.com', '37AAACB7788T1Z0', 'Brodipet, Guntur', '1943-05-13')
ON DUPLICATE KEY UPDATE
    company_name = VALUES(company_name),
    phone = VALUES(phone),
    email = VALUES(email),
    GST_number = VALUES(GST_number),
    address = VALUES(address);

/* (b.2) product_categories - 12 records */
INSERT INTO product_categories (category_id, category_name, description) VALUES
('PCAT-01', 'Certified Seeds', 'Government tested high yielding and hybrid varieties with >98% germination'),
('PCAT-02', 'Chemical Fertilizers', 'Macro-nutrients including Neem Coated Urea, DAP, MOP, Complex grades'),
('PCAT-03', 'Bio-Fertilizers & Organic Inputs', 'Nano fertilizers, Neem cake, Vermicompost, Phosphate solubilizing bio-cultures'),
('PCAT-04', 'Crop Protection & Insecticides', 'Systemic and contact insecticides approved for integrated pest control'),
('PCAT-05', 'Fungicides & Bactericides', 'Broad spectrum preventative and curative crop disease formulations'),
('PCAT-06', 'Herbicides & Weedicides', 'Pre-emergence and post-emergence selective weed control chemicals'),
('PCAT-07', 'Micro-Nutrients & Plant Tonics', 'Zinc, Boron, Ferrous, Magnesium and growth booster bio-stimulants'),
('PCAT-08', 'Farm Equipment & Spraying Tools', 'Battery knapsack sprayers, pheromone traps, drip accessories'),
('PCAT-09', 'Soil Conditioners & Amendments', 'Agricultural gypsum, humic acid granules, pH reclamation amendments'),
('PCAT-10', 'Water-Soluble Drip Fertilizers', '100% water-soluble 19:19:19, 13:0:45 fertigation grades for horticulture'),
('PCAT-11', 'Growth Regulators & Bio-Stimulants', 'Seaweed extracts, amino acid & gibberellic flowering enhancers'),
('PCAT-12', 'Post-Harvest Storage & Packaging', 'Hermetic super-grain bags, moisture meters, gunny sacks and tarpaulins')
ON DUPLICATE KEY UPDATE
    category_name = VALUES(category_name),
    description = VALUES(description);

/* (b.3) agricultural_products - 36 records */
INSERT INTO agricultural_products (product_id, company_id, category_id, product_name, description, price, unit, product_code, product_type, status) VALUES
('PROD-01', 'COMP-01', 'PCAT-02', 'Gromor Urea 46% N (45kg)', 'High nitrogen granulated fertilizer for vigorous vegetative growth', 266.50, 'Bag (45kg)', 'FERT-UREA-45', 'Nitrogenous', 'Active'),
('PROD-02', 'COMP-01', 'PCAT-02', 'Gromor DAP 18-46-0 (50kg)', 'Essential phosphatic fertilizer for root establishment and tillering', 1350.00, 'Bag (50kg)', 'FERT-DAP-50', 'Complex', 'Active'),
('PROD-03', 'COMP-02', 'PCAT-01', 'Certified BPT-5204 Paddy Seeds (25kg)', 'Tested 98% germination certified paddy foundation seeds', 1125.00, 'Bag (25kg)', 'SEED-BPT5204-25', 'Certified Seed', 'Active'),
('PROD-04', 'COMP-03', 'PCAT-04', 'Confidor 200 SL Imidacloprid (250ml)', 'Systemic insecticide for sucking pests in chilli and cotton', 420.00, 'Bottle (250ml)', 'PEST-CONF-250', 'Insecticide', 'Active'),
('PROD-05', 'COMP-04', 'PCAT-05', 'UPL Saaf Fungicide Carbendazim+Mancozeb (500g)', 'Broad spectrum protective and curative fungicide', 380.00, 'Pack (500g)', 'FUNG-SAAF-500', 'Fungicide', 'Active'),
('PROD-06', 'COMP-01', 'PCAT-02', 'Muriate of Potash MOP 60% K2O (50kg)', 'Potassic fertilizer improving grain weight, disease tolerance, and shine', 1700.00, 'Bag (50kg)', 'FERT-MOP-50', 'Potassic', 'Active'),
('PROD-07', 'COMP-01', 'PCAT-02', 'Gromor 20-20-0-13 Ammonium Phosphate Sulphate (50kg)', 'NPKS complex fertilizer with 13% essential sulphur for pulses & oilseeds', 1250.00, 'Bag (50kg)', 'FERT-2020-50', 'Complex', 'Active'),
('PROD-08', 'COMP-09', 'PCAT-01', 'NSC Certified MTU-1010 Paddy Seeds (25kg)', 'Certified seed with high vigor, disease tested by seed certification agency', 950.00, 'Bag (25kg)', 'SEED-MTU1010-25', 'Certified Seed', 'Active'),
('PROD-09', 'COMP-07', 'PCAT-01', 'Kaveri Jaadoo Bt-Cotton Seeds (450g)', 'BG-II hybrid bollworm resistant high fiber yield hybrid seeds', 864.00, 'Pkt (450g)', 'SEED-COTTON-450', 'Hybrid Seed', 'Active'),
('PROD-10', 'COMP-02', 'PCAT-04', 'Ampligo Chlorantraniliprole+Lambda (100ml)', 'Advanced dual-action insecticide for fall armyworm and pod borers', 780.00, 'Bottle (100ml)', 'PEST-AMPLI-100', 'Insecticide', 'Active'),
('PROD-11', 'COMP-03', 'PCAT-05', 'Nativo Tebuconazole+Trifloxystrobin (100g)', 'Premium systemic fungicide for sheath blight and blast control in paddy', 850.00, 'Pack (100g)', 'FUNG-NATI-100', 'Fungicide', 'Active'),
('PROD-12', 'COMP-04', 'PCAT-06', 'UPL Iris Herbicide Sodium Acifluorfen+Clodinafop (400ml)', 'Broad spectrum post-emergence herbicide for soybean and pulses', 620.00, 'Bottle (400ml)', 'HERB-IRIS-400', 'Herbicide', 'Active'),
('PROD-13', 'COMP-10', 'PCAT-03', 'IFFCO Nano Urea Liquid (500ml)', 'Nanotechnology liquid nitrogen fertilizer for direct foliar spray efficiency', 225.00, 'Bottle (500ml)', 'NANO-UREA-500', 'Bio-Fertilizer', 'Active'),
('PROD-14', 'COMP-10', 'PCAT-03', 'IFFCO Nano DAP Liquid (500ml)', 'Nano-scale bio-available phosphorus source reducing conventional fertilizer by 50%', 600.00, 'Bottle (500ml)', 'NANO-DAP-500', 'Bio-Fertilizer', 'Active'),
('PROD-15', 'COMP-05', 'PCAT-03', 'Godrej VIPUL Plant Growth Regulator Triacontanol (500ml)', 'Photosynthetic booster and flowering stimulant', 320.00, 'Bottle (500ml)', 'PGR-VIPUL-500', 'Bio-Stimulant', 'Active'),
('PROD-16', 'COMP-06', 'PCAT-07', 'Nagarjuna Zinc Sulphate Monohydrate 33% (5kg)', 'Essential micronutrient preventing Khaira disease in paddy delta soils', 450.00, 'Pack (5kg)', 'MICRO-ZN33-5', 'Micronutrient', 'Active'),
('PROD-17', 'COMP-08', 'PCAT-04', 'Tata Rallis Tafgor Dimethoate 30% EC (500ml)', 'Proven systemic insecticide for thrips, aphids and jassids', 310.00, 'Bottle (500ml)', 'PEST-TAF-500', 'Insecticide', 'Active'),
('PROD-18', 'COMP-07', 'PCAT-01', 'Kaveri KMH-258 Hybrid Maize Seeds (4kg)', 'High cob weight orange flint grain high yielding hybrid', 980.00, 'Pack (4kg)', 'SEED-MAIZE-4', 'Hybrid Seed', 'Active'),
('PROD-19', 'COMP-09', 'PCAT-01', 'NSC Certified LBG-752 Black Gram Seeds (10kg)', 'Certified seed lot suitable for zero-tillage rice fallow sowing', 1200.00, 'Bag (10kg)', 'SEED-BG752-10', 'Certified Seed', 'Active'),
('PROD-20', 'COMP-03', 'PCAT-07', 'Bayer Ambition Amino Acid Micronutrient Tonic (1L)', 'Bio-activator with fulvic and amino acids for heat/drought stress recovery', 1150.00, 'Bottle (1L)', 'TONIC-AMBI-1L', 'Micronutrient', 'Active'),
('PROD-21', 'COMP-10', 'PCAT-02', 'IFFCO Neem Coated Urea 46% N (45kg)', 'Slow-release neem-coated subsidized urea preventing nitrogen leaching', 266.50, 'Bag (45kg)', 'IFFCO-NCU-45', 'Nitrogenous', 'Active'),
('PROD-22', 'COMP-03', 'PCAT-04', 'Bayer Coragen Chlorantraniliprole 18.5% SC (150ml)', 'Recommended at 0.4 ml/liter for paddy yellow stem borer & leaf folder', 1480.00, 'Bottle (150ml)', 'PEST-CORA-150', 'Insecticide', 'Active'),
('PROD-23', 'COMP-02', 'PCAT-01', 'Syngenta NK 6240 Hybrid Maize Seeds (5kg)', 'High-density export grade maize hybrid with strong standability', 1650.00, 'Bag (5kg)', 'SEED-NK6240-5', 'Hybrid Seed', 'Active'),
('PROD-24', 'COMP-13', 'PCAT-01', 'Mahyco Teja S17 Chilli Hybrid Seeds (100g)', 'High capsaicin export-grade Guntur Teja chilli hybrid seeds', 1420.00, 'Tin (100g)', 'SEED-TEJA-100G', 'Hybrid Seed', 'Active'),
('PROD-25', 'COMP-11', 'PCAT-02', 'KRIBHCO DAP 18-46-0 Imported Grade (50kg)', 'Cooperative high-solubility diammonium phosphate fertilizer', 1350.00, 'Bag (50kg)', 'KRIB-DAP-50', 'Complex', 'Active'),
('PROD-26', 'COMP-12', 'PCAT-02', 'RCF Suphala 15-15-15 Complex Fertilizer (50kg)', 'Balanced granular NPK complex for paddy, chilli and cotton', 1450.00, 'Bag (50kg)', 'RCF-SUPH-50', 'Complex', 'Active'),
('PROD-27', 'COMP-17', 'PCAT-06', 'PI Industries Nominee Gold Bispyribac Sodium (250ml)', 'Post-emergence broad-spectrum selective herbicide for paddy weeds', 940.00, 'Bottle (250ml)', 'HERB-NOMG-250', 'Herbicide', 'Active'),
('PROD-28', 'COMP-18', 'PCAT-04', 'FMC Ferterra Granular Insecticide (4kg)', 'Chlorantraniliprole granular formulation for early rice stem borer protection', 760.00, 'Pack (4kg)', 'PEST-FERT-4KG', 'Insecticide', 'Active'),
('PROD-29', 'COMP-19', 'PCAT-04', 'Corteva Delegate Spinetoram 11.7% SC (100ml)', 'Low-residue insecticide for thrips & fruit borer in chilli & cotton', 1520.00, 'Bottle (100ml)', 'PEST-DELE-100', 'Insecticide', 'Active'),
('PROD-30', 'COMP-20', 'PCAT-05', 'BASF Cabrio Top Metiram+Pyraclostrobin (500g)', 'Export-compliant fungicide for anthracnose and powdery mildew in chilli', 1180.00, 'Pack (500g)', 'FUNG-CABR-500', 'Fungicide', 'Active'),
('PROD-31', 'COMP-14', 'PCAT-01', 'Nuziveedu Bhakti Bt-Cotton Seeds (475g)', 'Sucking-pest tolerant high-boll BG-II hybrid cotton packet', 864.00, 'Pkt (475g)', 'SEED-BHAK-475', 'Hybrid Seed', 'Active'),
('PROD-32', 'COMP-15', 'PCAT-02', 'Chambal Uttam NPK 12-32-16 (50kg)', 'High phosphorus starter complex for groundnut and pulses', 1470.00, 'Bag (50kg)', 'CHAM-1232-50', 'Complex', 'Active'),
('PROD-33', 'COMP-16', 'PCAT-10', 'Zuari Jai Kisaan 19-19-19 Water Soluble (25kg)', '100% water-soluble fertigation fertilizer for drip chilli and horticulture', 2650.00, 'Bag (25kg)', 'DRIP-1919-25', 'Water Soluble', 'Active'),
('PROD-34', 'COMP-01', 'PCAT-09', 'Coromandel Gromor Gypsum Soil Conditioner (50kg)', 'Calcium and sulphur amendment for alkaline delta and black soils', 320.00, 'Bag (50kg)', 'SOIL-GYPS-50', 'Soil Amendment', 'Active'),
('PROD-35', 'COMP-05', 'PCAT-11', 'Godrej Double Yield Flower & Boll Booster (250ml)', 'Homobrassinolide plant bio-stimulant for stress resilience', 490.00, 'Bottle (250ml)', 'STIM-DOUB-250', 'Bio-Stimulant', 'Active'),
('PROD-36', 'COMP-09', 'PCAT-12', 'NSC Hermetic SuperGrain Storage Bags (50kg Pack of 10)', 'Triple-layer hermetic grain storage bags preventing insect infestation', 1100.00, 'Bundle (10)', 'STOR-HERM-10', 'Packaging', 'Active')
ON DUPLICATE KEY UPDATE
    product_name = VALUES(product_name),
    description = VALUES(description),
    price = VALUES(price),
    unit = VALUES(unit),
    product_type = VALUES(product_type);

/* (b.4) product_batches - 45 records */
INSERT INTO product_batches (product_batch_id, product_id, batch_number, manufacturing_date, expiry_date, batch_status, received_quantity, available_quantity) VALUES
('PBAT-01', 'PROD-01', 'BAT-UREA-2026-A', '2026-01-10', '2028-01-09', 'Active', 1000.00, 720.00),
('PBAT-02', 'PROD-02', 'BAT-DAP-2026-B', '2026-02-05', '2028-02-04', 'Active', 800.00, 560.00),
('PBAT-03', 'PROD-03', 'BAT-BPT-2026-C', '2026-03-12', '2027-03-11', 'Active', 500.00, 340.00),
('PBAT-04', 'PROD-04', 'BAT-CONF-2026-D', '2026-02-18', '2028-02-17', 'Active', 300.00, 215.00),
('PBAT-05', 'PROD-05', 'BAT-SAAF-2026-E', '2026-03-01', '2028-02-28', 'Active', 400.00, 310.00),
('PBAT-06', 'PROD-06', 'BAT-MOP-2026-F', '2026-01-20', '2028-01-19', 'Active', 600.00, 480.00),
('PBAT-07', 'PROD-07', 'BAT-2020-2026-G', '2026-02-15', '2028-02-14', 'Active', 750.00, 520.00),
('PBAT-08', 'PROD-08', 'BAT-MTU-2026-H', '2026-03-25', '2027-03-24', 'Active', 450.00, 310.00),
('PBAT-09', 'PROD-09', 'BAT-COT-2026-I', '2026-04-05', '2027-04-04', 'Active', 350.00, 240.00),
('PBAT-10', 'PROD-10', 'BAT-AMP-2026-J', '2026-02-28', '2028-02-27', 'Active', 250.00, 185.00),
('PBAT-11', 'PROD-11', 'BAT-NAT-2026-K', '2026-03-15', '2028-03-14', 'Active', 200.00, 145.00),
('PBAT-12', 'PROD-12', 'BAT-IRI-2026-L', '2026-01-18', '2028-01-17', 'Active', 300.00, 220.00),
('PBAT-13', 'PROD-13', 'BAT-NUREA-2026-M', '2026-04-10', '2028-04-09', 'Active', 600.00, 470.00),
('PBAT-14', 'PROD-14', 'BAT-NDAP-2026-N', '2026-04-12', '2028-04-11', 'Active', 500.00, 380.00),
('PBAT-15', 'PROD-15', 'BAT-VIP-2026-O', '2026-02-10', '2028-02-09', 'Active', 350.00, 260.00),
('PBAT-16', 'PROD-16', 'BAT-ZN-2026-P', '2026-01-30', '2029-01-29', 'Active', 400.00, 290.00),
('PBAT-17', 'PROD-17', 'BAT-TAF-2026-Q', '2026-03-05', '2028-03-04', 'Active', 280.00, 195.00),
('PBAT-18', 'PROD-18', 'BAT-MAIZ-2026-R', '2026-04-01', '2027-03-31', 'Active', 320.00, 210.00),
('PBAT-19', 'PROD-19', 'BAT-LBG-2026-S', '2026-03-20', '2027-03-19', 'Active', 400.00, 275.00),
('PBAT-20', 'PROD-20', 'BAT-AMBI-2026-T', '2026-02-22', '2028-02-21', 'Active', 250.00, 180.00),
('PBAT-21', 'PROD-21', 'IFFCO-NCU-2026-01', '2026-05-01', '2028-05-01', 'Active', 1500.00, 1200.00),
('PBAT-21B', 'PROD-21', 'IFFCO-NCU-2026-02', '2026-10-01', '2028-10-01', 'Active', 1000.00, 1000.00),
('PBAT-22', 'PROD-22', 'BAY-CORA-2026-88', '2026-04-15', '2028-04-14', 'Active', 400.00, 350.00),
('PBAT-22B', 'PROD-22', 'BAY-CORA-2026-99', '2026-08-10', '2028-08-09', 'Active', 300.00, 280.00),
('PBAT-23', 'PROD-23', 'SYN-NK6240-2026-01', '2026-03-18', '2027-09-18', 'Active', 600.00, 490.00),
('PBAT-24', 'PROD-24', 'MAH-TEJA-2026-01', '2026-05-10', '2027-11-10', 'Active', 500.00, 420.00),
('PBAT-25', 'PROD-25', 'KRI-DAP-2026-01', '2026-04-20', '2028-04-19', 'Active', 900.00, 760.00),
('PBAT-26', 'PROD-26', 'RCF-SUPH-2026-01', '2026-03-22', '2028-03-21', 'Active', 800.00, 650.00),
('PBAT-27', 'PROD-27', 'PI-NOMG-2026-01', '2026-04-02', '2028-04-01', 'Active', 350.00, 280.00),
('PBAT-28', 'PROD-28', 'FMC-FERT-2026-01', '2026-05-12', '2028-05-11', 'Active', 450.00, 390.00),
('PBAT-29', 'PROD-29', 'CRT-DELE-2026-01', '2026-06-01', '2028-05-31', 'Active', 300.00, 240.00),
('PBAT-30', 'PROD-30', 'BAS-CABR-2026-01', '2026-05-25', '2028-05-24', 'Active', 420.00, 360.00),
('PBAT-31', 'PROD-31', 'NUZ-BHAK-2026-01', '2026-04-08', '2027-04-07', 'Active', 500.00, 410.00),
('PBAT-32', 'PROD-32', 'CHA-1232-2026-01', '2026-03-14', '2028-03-13', 'Active', 700.00, 590.00),
('PBAT-33', 'PROD-33', 'ZUA-1919-2026-01', '2026-02-20', '2028-02-19', 'Active', 300.00, 250.00),
('PBAT-34', 'PROD-34', 'COR-GYPS-2026-01', '2026-01-15', '2029-01-14', 'Active', 1200.00, 980.00),
('PBAT-35', 'PROD-35', 'GOD-DOUB-2026-01', '2026-04-18', '2028-04-17', 'Active', 380.00, 310.00),
('PBAT-36', 'PROD-36', 'NSC-HERM-2026-01', '2026-06-15', '2030-06-14', 'Active', 600.00, 520.00),
('PBAT-37', 'PROD-01', 'BAT-UREA-2026-B', '2026-07-01', '2028-06-30', 'Active', 900.00, 810.00),
('PBAT-38', 'PROD-02', 'BAT-DAP-2026-C', '2026-07-15', '2028-07-14', 'Active', 650.00, 590.00),
('PBAT-39', 'PROD-03', 'BAT-BPT-2026-D', '2026-08-01', '2027-07-31', 'Active', 400.00, 360.00),
('PBAT-40', 'PROD-08', 'BAT-MTU-2026-I', '2026-08-12', '2027-08-11', 'Active', 500.00, 440.00),
('PBAT-41', 'PROD-13', 'BAT-NUREA-2026-N', '2026-09-01', '2028-08-31', 'Active', 800.00, 740.00),
('PBAT-42', 'PROD-14', 'BAT-NDAP-2026-O', '2026-09-05', '2028-09-04', 'Active', 700.00, 650.00),
('PBAT-43', 'PROD-23', 'SYN-NK6240-2026-02', '2026-09-10', '2028-03-09', 'Active', 450.00, 410.00)
ON DUPLICATE KEY UPDATE
    available_quantity = VALUES(available_quantity),
    batch_status = VALUES(batch_status);

/* (c.1) rbk_centres - 26 records */
INSERT INTO rbk_centres (rbk_id, rbk_name, location, district, contact, status) VALUES
('RBK-GNT-01', 'Tenali Central RBK Kendra', 'Angalakuduru Junction, Tenali', 'Guntur', '9440112233', 'Active'),
('RBK-GNT-02', 'Mangalagiri Model RBK', 'GT Road, Mangalagiri', 'Guntur', '9440223344', 'Active'),
('RBK-GNT-03', 'Amaravati Farmer Assistance RBK', 'Dharanikota Center, Amaravati', 'Guntur', '9440334455', 'Active'),
('RBK-KRS-04', 'Vijayawada Rural RBK', 'Gannavaram Road, Enikepadu', 'Krishna', '9440445566', 'Active'),
('RBK-PRK-05', 'Ongole Farmers Service Kendra', 'Karavadi Junction, Ongole', 'Prakasam', '9440556677', 'Active'),
('RBK-BPT-06', 'Bapatla Coastal Agriculture RBK', 'Karlapalem Main Road, Bapatla', 'Bapatla', '9440667788', 'Active'),
('RBK-KRS-07', 'Gudivada Delta RBK', 'Billapadu Village, Gudivada', 'Krishna', '9440778899', 'Active'),
('RBK-PLN-08', 'Narasaraopet Model Kendra', 'Petlurivaripalem, Narasaraopet', 'Palnadu', '9440889900', 'Active'),
('RBK-EGD-09', 'Rajahmundry Riverbank RBK', 'Kadiyam Nurseries Road, Rajahmundry', 'East Godavari', '9440990011', 'Active'),
('RBK-WGD-10', 'Eluru Paddy Farmers Kendra', 'Sanivarapupeta, Eluru', 'West Godavari', '9440001122', 'Active'),
('RBK-GNT-11', 'Ponnur Canal Command RBK', 'Nidubrolu Main Road, Ponnur', 'Guntur', '9440112244', 'Active'),
('RBK-GNT-12', 'Duggirala Turmeric & Paddy RBK', 'Chiluvuru Cross, Duggirala', 'Guntur', '9440112255', 'Active'),
('RBK-PLN-13', 'Sattenapalli Chilli Cluster RBK', 'Kankanalapalli, Sattenapalli', 'Palnadu', '9440112266', 'Active'),
('RBK-PLN-14', 'Chilakaluripet Cotton RBK', 'Purushothapatnam, Chilakaluripet', 'Palnadu', '9440112277', 'Active'),
('RBK-BPT-15', 'Repalle Delta Paddy RBK', 'Penumudi Center, Repalle', 'Bapatla', '9440112288', 'Active'),
('RBK-NTR-16', 'Nandigama Pulse & Cotton RBK', 'Kanchikacherla, NTR', 'NTR', '9440112299', 'Active'),
('RBK-ELR-17', 'Nuzvid Horticulture RBK', 'Agiripalli Road, Nuzvid', 'Eluru', '9440221100', 'Active'),
('RBK-KNS-18', 'Amalapuram Coconut & Paddy RBK', 'Ambajipeta, Konaseema', 'Konaseema', '9440221111', 'Active'),
('RBK-KKD-19', 'Samalkot Delta Inputs RBK', 'Vetlapalem, Kakinada', 'Kakinada', '9440221122', 'Active'),
('RBK-NDL-20', 'Nandyal Black Soil RBK', 'Panyam Road, Nandyal', 'Nandyal', '9440221133', 'Active'),
('RBK-KRN-21', 'Adoni Cotton & Groundnut RBK', 'Alur Cross, Adoni', 'Kurnool', '9440221144', 'Active'),
('RBK-ATP-22', 'Tadipatri Horticulture RBK', 'Yerraguntapalli, Tadipatri', 'Anantapur', '9440221155', 'Active'),
('RBK-NLR-23', 'Kavali Coastal Paddy RBK', 'Musunuru, Kavali', 'SPSR Nellore', '9440221166', 'Active'),
('RBK-CTR-24', 'Madanapalle Tomato & Mango RBK', 'Valasapalle, Madanapalle', 'Chittoor', '9440221177', 'Active'),
('RBK-VZM-25', 'Bobbili Tribal & Maize RBK', 'Seethanagaram, Bobbili', 'Vizianagaram', '9440221188', 'Active'),
('RBK-SKL-26', 'Amadalavalasa North Delta RBK', 'Burja Road, Amadalavalasa', 'Srikakulam', '9440221199', 'Active')
ON DUPLICATE KEY UPDATE
    rbk_name = VALUES(rbk_name),
    location = VALUES(location),
    district = VALUES(district),
    contact = VALUES(contact),
    status = VALUES(status);

/* (c.2 & c.3) rbk_employees (30 records) & emp_password (30 records) */
INSERT INTO rbk_employees (employee_id, rbk_id, employee_name, designation, gender, phone, email, emp_password_id, joining_date, employment_status) VALUES
('EMP-001', 'RBK-GNT-01', 'K. Subba Rao', 'Agriculture Extension Officer', 'Male', '9848556677', 'officer.tenali@agrichain.gov.in', NULL, '2021-08-01', 'Active'),
('EMP-002', 'RBK-GNT-01', 'P. Anitha', 'Village Agriculture Assistant', 'Female', '9848667788', 'anitha.p@agrichain.gov.in', NULL, '2022-02-15', 'Active'),
('EMP-003', 'RBK-GNT-02', 'M. Venkateswara Rao', 'RBK In-charge', 'Male', '9848778899', 'venkat.m@agrichain.gov.in', NULL, '2020-11-10', 'Active'),
('EMP-004', 'RBK-GNT-03', 'S. Radhika', 'Village Agriculture Assistant', 'Female', '9848889900', 'radhika.s@agrichain.gov.in', NULL, '2022-05-18', 'Active'),
('EMP-005', 'RBK-KRS-04', 'D. Suresh Kumar', 'Agriculture Extension Officer', 'Male', '9848990011', 'suresh.d@agrichain.gov.in', NULL, '2021-04-01', 'Active'),
('EMP-006', 'RBK-PRK-05', 'G. Lakshmi Narayana', 'RBK In-charge', 'Male', '9848101112', 'narayana.g@agrichain.gov.in', NULL, '2020-09-01', 'Active'),
('EMP-007', 'RBK-BPT-06', 'T. Bhavani Prasad', 'Village Horticulture Assistant', 'Male', '9848212223', 'bhavani.t@agrichain.gov.in', NULL, '2022-01-20', 'Active'),
('EMP-008', 'RBK-KRS-07', 'V. Padmavathi', 'Village Agriculture Assistant', 'Female', '9848323334', 'padma.v@agrichain.gov.in', NULL, '2023-03-10', 'Active'),
('EMP-009', 'RBK-PLN-08', 'B. Srinivasa Rao', 'Agriculture Extension Officer', 'Male', '9848434445', 'srinu.b@agrichain.gov.in', NULL, '2021-12-05', 'Active'),
('EMP-010', 'RBK-EGD-09', 'C. Rama Krishna', 'RBK In-charge', 'Male', '9848545556', 'ramki.c@agrichain.gov.in', NULL, '2020-07-15', 'Active'),
('EMP-011', 'RBK-GNT-01', 'R. Madhava Rao', 'Warehouse Custodian', 'Male', '9848556601', 'madhava.custodian@agrichain.gov.in', NULL, '2021-06-15', 'Active'),
('EMP-012', 'RBK-WGD-10', 'N. Swapna', 'Village Agriculture Assistant', 'Female', '9848556602', 'swapna.n@agrichain.gov.in', NULL, '2022-03-12', 'Active'),
('EMP-013', 'RBK-GNT-11', 'K. Harish Babu', 'Village Agriculture Assistant', 'Male', '9848556603', 'harish.k@agrichain.gov.in', NULL, '2022-07-18', 'Active'),
('EMP-014', 'RBK-GNT-12', 'P. Sailaja', 'Village Horticulture Assistant', 'Female', '9848556604', 'sailaja.p@agrichain.gov.in', NULL, '2023-01-10', 'Active'),
('EMP-015', 'RBK-PLN-13', 'M. Nagendra', 'Agriculture Extension Officer', 'Male', '9848556605', 'nagendra.m@agrichain.gov.in', NULL, '2021-09-22', 'Active'),
('EMP-016', 'RBK-PLN-14', 'V. Jyothi', 'Village Agriculture Assistant', 'Female', '9848556606', 'jyothi.v@agrichain.gov.in', NULL, '2022-11-01', 'Active'),
('EMP-017', 'RBK-BPT-15', 'S. Prasad Reddy', 'Warehouse Custodian', 'Male', '9848556607', 'prasad.s@agrichain.gov.in', NULL, '2021-05-14', 'Active'),
('EMP-018', 'RBK-NTR-16', 'G. Kalyani', 'Village Agriculture Assistant', 'Female', '9848556608', 'kalyani.g@agrichain.gov.in', NULL, '2023-04-03', 'Active'),
('EMP-019', 'RBK-ELR-17', 'T. Rajasekhar', 'Village Horticulture Assistant', 'Male', '9848556609', 'rajasekhar.t@agrichain.gov.in', NULL, '2021-10-19', 'Active'),
('EMP-020', 'RBK-KNS-18', 'A. Satyanarayana', 'RBK In-charge', 'Male', '9848556610', 'satya.a@agrichain.gov.in', NULL, '2020-08-12', 'Active'),
('EMP-021', 'RBK-KKD-19', 'B. Swathi', 'Village Agriculture Assistant', 'Female', '9848556611', 'swathi.b@agrichain.gov.in', NULL, '2022-08-25', 'Active'),
('EMP-022', 'RBK-NDL-20', 'Y. Sudhakar', 'Agriculture Extension Officer', 'Male', '9848556612', 'sudhakar.y@agrichain.gov.in', NULL, '2021-03-11', 'Active'),
('EMP-023', 'RBK-KRN-21', 'K. Mallikarjuna', 'Village Agriculture Assistant', 'Male', '9848556613', 'malli.k@agrichain.gov.in', NULL, '2022-06-07', 'Active'),
('EMP-024', 'RBK-ATP-22', 'R. Sunitha', 'Village Horticulture Assistant', 'Female', '9848556614', 'sunitha.r@agrichain.gov.in', NULL, '2023-02-14', 'Active'),
('EMP-025', 'RBK-NLR-23', 'D. Venkatramana', 'RBK In-charge', 'Male', '9848556615', 'venkatramana.d@agrichain.gov.in', NULL, '2020-12-01', 'Active'),
('EMP-026', 'RBK-CTR-24', 'L. Lavanya', 'Village Horticulture Assistant', 'Female', '9848556616', 'lavanya.l@agrichain.gov.in', NULL, '2022-09-09', 'Active'),
('EMP-027', 'RBK-VZM-25', 'P. Appala Naidu', 'Village Agriculture Assistant', 'Male', '9848556617', 'appalanaidu.p@agrichain.gov.in', NULL, '2021-11-28', 'Active'),
('EMP-028', 'RBK-SKL-26', 'M. Sravani', 'Village Agriculture Assistant', 'Female', '9848556618', 'sravani.m@agrichain.gov.in', NULL, '2023-05-16', 'Active'),
('EMP-029', 'RBK-GNT-02', 'C. Kishore Kumar', 'Warehouse Custodian', 'Male', '9848556619', 'kishore.c@agrichain.gov.in', NULL, '2021-07-21', 'Active'),
('EMP-030', 'RBK-KRS-04', 'K. Deepika', 'Village Agriculture Assistant', 'Female', '9848556620', 'deepika.k@agrichain.gov.in', NULL, '2023-06-01', 'Active')
ON DUPLICATE KEY UPDATE
    rbk_id = VALUES(rbk_id),
    employee_name = VALUES(employee_name),
    designation = VALUES(designation),
    employment_status = VALUES(employment_status);

INSERT INTO emp_password (emp_password_id, employee_id, password_hash, confirm_password_hash) VALUES
('PWD-001', 'EMP-001', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-002', 'EMP-002', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-003', 'EMP-003', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-004', 'EMP-004', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-005', 'EMP-005', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-006', 'EMP-006', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-007', 'EMP-007', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-008', 'EMP-008', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-009', 'EMP-009', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-010', 'EMP-010', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-011', 'EMP-011', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-012', 'EMP-012', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-013', 'EMP-013', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-014', 'EMP-014', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-015', 'EMP-015', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-016', 'EMP-016', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-017', 'EMP-017', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-018', 'EMP-018', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-019', 'EMP-019', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-020', 'EMP-020', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-021', 'EMP-021', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-022', 'EMP-022', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-023', 'EMP-023', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-024', 'EMP-024', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-025', 'EMP-025', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-026', 'EMP-026', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-027', 'EMP-027', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-028', 'EMP-028', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-029', 'EMP-029', SHA2('rbk@123', 256), SHA2('rbk@123', 256)),
('PWD-030', 'EMP-030', SHA2('rbk@123', 256), SHA2('rbk@123', 256))
ON DUPLICATE KEY UPDATE
    password_hash = VALUES(password_hash),
    confirm_password_hash = VALUES(confirm_password_hash);

UPDATE rbk_employees e
JOIN emp_password p ON p.employee_id = e.employee_id
SET e.emp_password_id = p.emp_password_id
WHERE e.emp_password_id IS NULL OR e.emp_password_id <> p.emp_password_id;

/* (c.4) rbk_inventory - 66 records */
INSERT INTO rbk_inventory (inventory_id, rbk_id, product_batch_id, quantity) VALUES
('RINV-01', 'RBK-GNT-01', 'PBAT-01', 180.00),
('RINV-02', 'RBK-GNT-01', 'PBAT-02', 140.00),
('RINV-03', 'RBK-GNT-01', 'PBAT-03', 95.00),
('RINV-04', 'RBK-GNT-01', 'PBAT-04', 45.00),
('RINV-05', 'RBK-GNT-01', 'PBAT-05', 80.00),
('RINV-06', 'RBK-GNT-01', 'PBAT-06', 110.00),
('RINV-07', 'RBK-GNT-01', 'PBAT-07', 130.00),
('RINV-08', 'RBK-GNT-01', 'PBAT-13', 160.00),
('RINV-09', 'RBK-GNT-01', 'PBAT-16', 35.00),
('RINV-10', 'RBK-GNT-02', 'PBAT-01', 210.00),
('RINV-11', 'RBK-GNT-02', 'PBAT-02', 160.00),
('RINV-12', 'RBK-GNT-02', 'PBAT-04', 65.00),
('RINV-13', 'RBK-GNT-02', 'PBAT-09', 40.00),
('RINV-14', 'RBK-GNT-03', 'PBAT-01', 190.00),
('RINV-15', 'RBK-GNT-03', 'PBAT-08', 120.00),
('RINV-16', 'RBK-KRS-04', 'PBAT-02', 175.00),
('RINV-17', 'RBK-KRS-04', 'PBAT-10', 75.00),
('RINV-18', 'RBK-PRK-05', 'PBAT-01', 200.00),
('RINV-19', 'RBK-BPT-06', 'PBAT-03', 130.00),
('RINV-20', 'RBK-PLN-08', 'PBAT-09', 85.00),
('RINV-21', 'RBK-GNT-01', 'PBAT-21', 240.00),
('RINV-22', 'RBK-GNT-01', 'PBAT-22', 65.00),
('RINV-23', 'RBK-GNT-01', 'PBAT-23', 110.00),
('RINV-24', 'RBK-GNT-01', 'PBAT-24', 90.00),
('RINV-25', 'RBK-GNT-01', 'PBAT-27', 75.00),
('RINV-26', 'RBK-GNT-01', 'PBAT-28', 120.00),
('RINV-27', 'RBK-GNT-01', 'PBAT-30', 80.00),
('RINV-28', 'RBK-GNT-01', 'PBAT-34', 250.00),
('RINV-29', 'RBK-GNT-02', 'PBAT-21', 195.00),
('RINV-30', 'RBK-GNT-02', 'PBAT-22', 55.00),
('RINV-31', 'RBK-GNT-02', 'PBAT-24', 70.00),
('RINV-32', 'RBK-GNT-02', 'PBAT-25', 140.00),
('RINV-33', 'RBK-GNT-03', 'PBAT-21', 220.00),
('RINV-34', 'RBK-GNT-03', 'PBAT-23', 95.00),
('RINV-35', 'RBK-GNT-03', 'PBAT-29', 45.00),
('RINV-36', 'RBK-KRS-04', 'PBAT-21', 260.00),
('RINV-37', 'RBK-KRS-04', 'PBAT-22', 80.00),
('RINV-38', 'RBK-KRS-04', 'PBAT-23', 135.00),
('RINV-39', 'RBK-PRK-05', 'PBAT-24', 110.00),
('RINV-40', 'RBK-PRK-05', 'PBAT-31', 90.00),
('RINV-41', 'RBK-BPT-06', 'PBAT-21', 170.00),
('RINV-42', 'RBK-BPT-06', 'PBAT-26', 145.00),
('RINV-43', 'RBK-KRS-07', 'PBAT-08', 150.00),
('RINV-44', 'RBK-KRS-07', 'PBAT-21', 200.00),
('RINV-45', 'RBK-PLN-08', 'PBAT-24', 130.00),
('RINV-46', 'RBK-PLN-08', 'PBAT-30', 95.00),
('RINV-47', 'RBK-EGD-09', 'PBAT-21', 180.00),
('RINV-48', 'RBK-EGD-09', 'PBAT-33', 60.00),
('RINV-49', 'RBK-WGD-10', 'PBAT-03', 140.00),
('RINV-50', 'RBK-WGD-10', 'PBAT-22', 75.00),
('RINV-51', 'RBK-GNT-11', 'PBAT-21', 190.00),
('RINV-52', 'RBK-GNT-12', 'PBAT-35', 85.00),
('RINV-53', 'RBK-PLN-13', 'PBAT-24', 115.00),
('RINV-54', 'RBK-PLN-14', 'PBAT-09', 95.00),
('RINV-55', 'RBK-BPT-15', 'PBAT-39', 130.00),
('RINV-56', 'RBK-NTR-16', 'PBAT-23', 125.00),
('RINV-57', 'RBK-ELR-17', 'PBAT-33', 70.00),
('RINV-58', 'RBK-KNS-18', 'PBAT-41', 150.00),
('RINV-59', 'RBK-KKD-19', 'PBAT-42', 140.00),
('RINV-60', 'RBK-NDL-20', 'PBAT-32', 120.00),
('RINV-61', 'RBK-KRN-21', 'PBAT-31', 100.00),
('RINV-62', 'RBK-ATP-22', 'PBAT-33', 80.00),
('RINV-63', 'RBK-NLR-23', 'PBAT-40', 160.00),
('RINV-64', 'RBK-CTR-24', 'PBAT-35', 90.00),
('RINV-65', 'RBK-VZM-25', 'PBAT-43', 110.00),
('RINV-66', 'RBK-SKL-26', 'PBAT-36', 100.00)
ON DUPLICATE KEY UPDATE
    quantity = GREATEST(rbk_inventory.quantity, VALUES(quantity));

/* (c.5) cultivation_seasons - 12 records */
INSERT INTO cultivation_seasons (season_id, season_name, start_date, end_date, description) VALUES
('SEAS-2023-KH', 'Kharif 2023', '2023-06-01', '2023-11-30', 'Monsoon paddy, chilli & cotton cycle 2023'),
('SEAS-2023-RB', 'Rabi 2023-24', '2023-10-15', '2024-03-31', 'Winter pulses, maize & rice-fallow black gram'),
('SEAS-2024-KH', 'Kharif 2024', '2024-06-01', '2024-11-30', 'Monsoon sowing cycle 2024'),
('SEAS-2024-RB', 'Rabi 2024-25', '2024-10-15', '2025-03-31', 'Winter Bengal gram, maize & chilli cycle'),
('SEAS-2025-ZD', 'Zaid 2025', '2025-03-01', '2025-06-15', 'Summer short-duration green gram and fodder'),
('SEAS-2025-KH', 'Kharif 2025', '2025-06-01', '2025-11-30', 'Monsoon season sowing Paddy, Cotton, Pulses'),
('SEAS-2025-RB', 'Rabi 2025-26', '2025-10-15', '2026-03-31', 'Winter cultivation for Bengal Gram, Maize, Chilli'),
('SEAS-2026-ZD', 'Zaid 2026', '2026-03-01', '2026-06-15', 'Summer short-duration vegetables and fodder crops'),
('SEAS-2026-KH', 'Kharif 2026', '2026-06-01', '2026-11-30', 'Active monsoon cultivation season'),
('SEAS-2026-RB', 'Rabi 2026-27', '2026-10-15', '2027-03-31', 'Active winter crop cycle for Maize, Pulses & Chilli'),
('SEAS-2027-ZD', 'Zaid 2027', '2027-03-01', '2027-06-15', 'Summer short-duration pulse and fodder cycle'),
('SEAS-2027-KH', 'Kharif 2027', '2027-06-01', '2027-11-30', 'Upcoming monsoon planning cycle')
ON DUPLICATE KEY UPDATE
    season_name = VALUES(season_name),
    start_date = VALUES(start_date),
    end_date = VALUES(end_date),
    description = VALUES(description);

/* (d.1) warehouses - 20 records */
INSERT INTO warehouses (warehouse_id, warehouse_name, location, district, capacity, contact_number) VALUES
('WH-GNT-01', 'APSWC Central Godown - Guntur', 'Etukuru Road, Guntur', 'Guntur', 25000.00, '0863229988'),
('WH-TNL-02', 'Tenali Agricultural Market Yard Warehouse', 'Market Yard, Tenali', 'Guntur', 12000.00, '0864422558'),
('WH-VJA-03', 'CWC Regional Logistics Hub - Vijayawada', 'Enikepadu, Vijayawada', 'Krishna', 35000.00, '0866244779'),
('WH-ONG-04', 'Prakasam District Agro Godown - Ongole', 'Collectorate Road, Ongole', 'Prakasam', 18000.00, '0859223311'),
('WH-BPT-05', 'Bapatla Coastal Cold Storage & Silo', 'Port Road, Bapatla', 'Bapatla', 15000.00, '0864322445'),
('WH-GDV-06', 'Krishna Delta Storage Facility - Gudivada', 'Bantumilli Road, Gudivada', 'Krishna', 16000.00, '0867424488'),
('WH-NSP-07', 'Palnadu Grain Warehouse - Narasaraopet', 'Vinukonda Road, Narasaraopet', 'Palnadu', 20000.00, '0864723366'),
('WH-ELR-08', 'Godavari Agro Logistics Hub - Eluru', 'Powerpet, Eluru', 'Eluru', 22000.00, '0881223399'),
('WH-GNT-09', 'Guntur Chilli Yard Cold Storage Complex', 'Mirchi Yard, Guntur', 'Guntur', 30000.00, '0863235577'),
('WH-GNT-10', 'Duggirala Turmeric & Spice Godown', 'Market Yard, Duggirala', 'Guntur', 14000.00, '0864425566'),
('WH-KKD-11', 'Kakinada Deep Water Export Silos', 'Port Industrial Park, Kakinada', 'Kakinada', 45000.00, '0884237788'),
('WH-RJY-12', 'Rajahmundry CWC Riverfront Warehouse', 'Dowleswaram, East Godavari', 'East Godavari', 24000.00, '0883241122'),
('WH-NDL-13', 'Nandyal Kurnool Grain Silo Complex', 'NH-40 Industrial Park, Nandyal', 'Nandyal', 28000.00, '0851422334'),
('WH-ATP-14', 'Anantapur Dryland Oilseed Godown', 'Gooty Road, Anantapur', 'Anantapur', 19000.00, '0855424455'),
('WH-NLR-15', 'Krishnapatnam Port Agri Export Hub', 'Port Approach Road, Nellore', 'SPSR Nellore', 40000.00, '0861239900'),
('WH-VSK-16', 'Visakhapatnam VPT Agro Logistics Terminal', 'Gajuwaka Port Zone, Visakhapatnam', 'Visakhapatnam', 38000.00, '0891256677'),
('WH-TPT-17', 'Tirupati Mango & Pulp Cold Chain Hub', 'Renigunta Industrial Estate, Tirupati', 'Tirupati', 16500.00, '0877224488'),
('WH-KDP-18', 'Kadapa Banana & Pulses Warehouse', 'Pulivendula Road, YSR Kadapa', 'YSR Kadapa', 17500.00, '0856223344'),
('WH-BVM-19', 'Bhimavaram Aqua & Paddy Buffer Godown', 'Undi Road, Bhimavaram', 'West Godavari', 21000.00, '0881622559'),
('WH-SKL-20', 'Srikakulam North Coastal CWC Godown', 'NH-16 Etcherla, Srikakulam', 'Srikakulam', 15500.00, '0894222889')
ON DUPLICATE KEY UPDATE
    warehouse_name = VALUES(warehouse_name),
    location = VALUES(location),
    district = VALUES(district),
    capacity = VALUES(capacity),
    contact_number = VALUES(contact_number);

/* (d.2) crop_categories - 14 records */
INSERT INTO crop_categories (category_id, category_name, description) VALUES
('CCAT-01', 'Cereals & Grains', 'Staple food crops including Paddy, Maize, Wheat, Jowar'),
('CCAT-02', 'Pulses & Legumes', 'Protein rich crops like Black Gram, Red Gram, Green Gram, Bengal Gram'),
('CCAT-03', 'Commercial & Cash Crops', 'High value crops including Cotton, Tobacco, Sugarcane, Jute'),
('CCAT-04', 'Spices & Condiments', 'Chilli, Turmeric, Coriander, Ginger, Garlic, Cumin'),
('CCAT-05', 'Oilseeds', 'Groundnut, Sunflower, Mustard, Sesame, Soybean'),
('CCAT-06', 'Horticulture Fruits', 'Mango, Banana, Guava, Sweet Orange, Papaya, Pomegranate'),
('CCAT-07', 'Vegetables & Greens', 'Tomato, Brinjal, Bhendi, Onion, Gourds, Leafy vegetables'),
('CCAT-08', 'Plantation Crops', 'Coconut, Oil Palm, Cashewnut, Cocoa, Coffee'),
('CCAT-09', 'Millets & Nutri-Cereals', 'Foxtail Millet, Pearl Millet (Bajra), Finger Millet (Ragi), Sorghum'),
('CCAT-10', 'Medicinal & Aromatic Plants', 'Ashwagandha, Lemongrass, Aloe Vera, Tulsi, Palmarosa'),
('CCAT-11', 'Floriculture & Ornamentals', 'Jasmine, Marigold, Rose, Chrysanthemum, Crossandra'),
('CCAT-12', 'Fodder & Green Manure Crops', 'Pillipesara, Sunhemp, Dhaincha, Hybrid Napier Grass'),
('CCAT-13', 'Tuber & Root Crops', 'Cassava (Tapioca), Sweet Potato, Elephant Foot Yam, Colocasia'),
('CCAT-14', 'Organic Export Certified Crops', 'NPOP/NOP organic certified spices, basmati, pulses & millets')
ON DUPLICATE KEY UPDATE
    category_name = VALUES(category_name),
    description = VALUES(description);

/* (d.3) buyers - 20 records (Demo password for all seeded buyers: buyer@123) */
INSERT INTO buyers (buyer_id, buyer_name, buyer_type, phone, email, address, registration_number, buyer_password_hash) VALUES
('BUY-001', 'ITC Agri Business Division', 'Exporter', '9848111222', 'procure@itcagri.com', 'ITC Agri Tower, Guntur AP', 'GSTIN37AAACI1234F1Z1', SHA2('buyer@123', 256)),
('BUY-002', 'BigBasket Fresh Sourcing', 'Retailer', '9848222333', 'sourcing@bigbasket.com', 'DC-4, Autonagar, Vijayawada', 'GSTIN37AABCB9876E1Z5', SHA2('buyer@123', 256)),
('BUY-003', 'Godrej Agrovet Ltd', 'Processor', '9848333444', 'support@godrejagrovet.com', 'Industrial Estate, Tenali', 'GSTIN37AACCG5544D1Z8', SHA2('buyer@123', 256)),
('BUY-004', 'Southern Agro Exports Ltd', 'Exporter', '9848444555', 'exports@southernagro.in', 'Port Road, Krishnapatnam', 'GSTIN37AAACS6677A1Z3', SHA2('buyer@123', 256)),
('BUY-005', 'Reliance Retail Agro Procurement', 'Retailer', '9848555666', 'agro.south@ril.com', 'Reliance Logistics Hub, Gannavaram', 'GSTIN37AAACR7788B1Z5', SHA2('buyer@123', 256)),
('BUY-006', 'Olam Agri India Pvt Ltd', 'Exporter', '9848666777', 'procure.ap@olamagri.com', 'Port Area, Kakinada', 'GSTIN37AAACO8899C1Z7', SHA2('buyer@123', 256)),
('BUY-007', 'Heritage Foods Agri Division', 'Processor', '9848777888', 'agri@heritagefoods.in', 'Dinnedevarapadu, Guntur', 'GSTIN37AAACH9900D1Z9', SHA2('buyer@123', 256)),
('BUY-008', 'Adani Wilmar Commodity Desk', 'Processor', '9848888999', 'commodities@adaniwilmar.in', 'Marthand Complex, Guntur', 'GSTIN37AAACA1122E1Z1', SHA2('buyer@123', 256)),
('BUY-009', 'Tata Chemicals Rallis Produce Sourcing', 'Wholesaler', '9848999000', 'sourcing@tatachemicals.com', 'Autonagar, Guntur', 'GSTIN37AAACT3344F1Z3', SHA2('buyer@123', 256)),
('BUY-010', 'Patanjali Agro Andhra Division', 'Processor', '9848000111', 'ap.sourcing@patanjaliayurved.org', 'Industrial Hub, Vijayawada', 'GSTIN37AAACP5566G1Z5', SHA2('buyer@123', 256)),
('BUY-011', 'Allanasons Export Spices & Grains', 'Exporter', '9848121212', 'spices.ap@allanasons.com', 'Guntur Chilli Park, Guntur', 'GSTIN37AAACA7711H1Z2', SHA2('buyer@123', 256)),
('BUY-012', 'Cargill India Grain & Maize Millers', 'Processor', '9848131313', 'maize.procure@cargill.com', 'Logistics Park, Vijayawada', 'GSTIN37AAACC8822I1Z4', SHA2('buyer@123', 256)),
('BUY-013', 'DMart Avenue Supermarts Agri Desk', 'Retailer', '9848141414', 'agri.ap@dmartindia.com', 'Mangalagiri Highway Hub, Guntur', 'GSTIN37AAACD9933J1Z6', SHA2('buyer@123', 256)),
('BUY-014', 'Spices Board Accredited Export House', 'Exporter', '9848151515', 'eu.audit@spicesexport.in', 'Spices Park, Edlapadu, Palnadu', 'GSTIN37AAACS1044K1Z8', SHA2('buyer@123', 256)),
('BUY-015', 'Britannia Industries Wheat & Millet Hub', 'Processor', '9848161616', 'grain.south@britannia.co.in', 'APIIC Park, Nandyal', 'GSTIN37AAACB2155L1Z0', SHA2('buyer@123', 256)),
('BUY-016', 'Marico Oilseed Procurement Desk', 'Processor', '9848171717', 'oilseeds@marico.com', 'Gooty Road, Anantapur', 'GSTIN37AAACM3266M1Z2', SHA2('buyer@123', 256)),
('BUY-017', 'Spencer Retail Fresh Farm Connect', 'Retailer', '9848181818', 'fresh.ap@spencers.in', 'Autonagar, Visakhapatnam', 'GSTIN37AAACS4377N1Z4', SHA2('buyer@123', 256)),
('BUY-018', 'AgroCorp Global Commodity Traders', 'Wholesaler', '9848191919', 'desk.ap@agrocorp.com', 'Port Terminal, Kakinada', 'GSTIN37AAACA5488O1Z6', SHA2('buyer@123', 256)),
('BUY-019', 'Nafed State Cooperative Procurement', 'Wholesaler', '9848202020', 'ap.msp@nafed-india.com', 'Benz Circle, Vijayawada', 'GSTIN37AAACN6599P1Z8', SHA2('buyer@123', 256)),
('BUY-020', 'MTR Foods Spice & Pulse Sourcing', 'Processor', '9848212121', 'chilli.buy@mtrfoods.com', 'Mirchi Yard Annex, Guntur', 'GSTIN37AAACM7600Q1Z0', SHA2('buyer@123', 256))
ON DUPLICATE KEY UPDATE
    buyer_name = VALUES(buyer_name),
    buyer_type = VALUES(buyer_type),
    phone = VALUES(phone),
    email = VALUES(email),
    address = VALUES(address),
    buyer_password_hash = VALUES(buyer_password_hash);

/* ---------- 3. BASE CROPS, FARMERS, LAND, FIELDS, CREDIT & WORKFLOW DATA ---------- */
INSERT IGNORE INTO crops (crop_id, category_id, crop_name, description) VALUES
('CROP-01', 'CCAT-01', 'Paddy (Rice)', 'Major food crop of coastal Andhra Pradesh delta.'),
('CROP-02', 'CCAT-01', 'Maize (Corn)', 'High yielding feed and grain crop.'),
('CROP-03', 'CCAT-02', 'Black Gram (Urad)', 'Pulse crop suitable for relay cropping in rice fallows.'),
('CROP-04', 'CCAT-03', 'Cotton', 'Major cash crop known for superior fiber quality.'),
('CROP-05', 'CCAT-04', 'Guntur Red Chilli', 'World renowned pungent spice crop.'),
('CROP-06', 'CCAT-02', 'Bengal Gram (Chana)', 'Major winter pulse cultivated in black soils.'),
('CROP-07', 'CCAT-05', 'Groundnut', 'Important oilseed crop with high oil and protein value.'),
('CROP-08', 'CCAT-04', 'Turmeric (Haldi)', 'Curcumin-rich spice crop of Duggirala and Guntur belt.');

INSERT IGNORE INTO crop_varieties (variety_id, crop_id, variety_name, duration_days, description) VALUES
('VAR-01', 'CROP-01', 'BPT-5204 (Samba Masuri)', 145, 'Fine grain premium rice variety with excellent cooking quality.'),
('VAR-02', 'CROP-01', 'MTU-1010 (Cottondora Sannalu)', 120, 'Short duration high yielding blast-resistant paddy.'),
('VAR-03', 'CROP-04', 'Bt-Cotton (Mallika)', 160, 'Bollworm resistant hybrid with high ginning percentage.'),
('VAR-04', 'CROP-05', 'Teja Guntur S17 Chilli', 150, 'Deep red high capsaicin pungency export variety.'),
('VAR-05', 'CROP-03', 'LBG-752 (Black Gram)', 75, 'High yielding bold black seeded pulse.'),
('VAR-06', 'CROP-02', 'Pioneer P3396 Maize', 110, 'High yielding hybrid maize with uniform cob filling.'),
('VAR-07', 'CROP-06', 'JG-11 Bengal Gram', 95, 'Wilt tolerant bold seeded chana variety.'),
('VAR-08', 'CROP-07', 'Kadiri-6 Groundnut', 105, 'Drought tolerant Spanish bunch high oil groundnut.');

INSERT IGNORE INTO farmers (farmer_id, farmer_name, dob, gender, phone, email, password_hash, authentication_id) VALUES
('FAR-001', 'Ramesh Babu Naidu', '1978-04-12', 'Male', '9848011223', 'ramesh.naidu@gmail.com', SHA2('farmer@123', 256), NULL),
('FAR-002', 'Venkat Rao Chowdary', '1982-08-25', 'Male', '9848022334', 'venkat.rao@gmail.com', SHA2('farmer@123', 256), NULL),
('FAR-003', 'Lakshmi Devi Korrapati', '1985-11-14', 'Female', '9848033445', 'lakshmi.k@gmail.com', SHA2('farmer@123', 256), NULL),
('FAR-004', 'Siva Rama Krishna Reddy', '1975-02-18', 'Male', '9848044556', 'siva.reddy@gmail.com', SHA2('farmer@123', 256), NULL),
('FAR-005', 'Apparao Kollipara', '1980-07-30', 'Male', '9848055667', 'apparao.k@gmail.com', SHA2('farmer@123', 256), NULL),
('FAR-006', 'Ch. Subbaiah (Tenant Farmer)', '1984-03-15', 'Male', '9848066778', 'subbaiah.ch@gmail.com', SHA2('farmer@123', 256), NULL),
('FAR-007', 'G. Mallikarjuna Rao', '1972-10-08', 'Male', '9848077889', 'malli.g@gmail.com', SHA2('farmer@123', 256), NULL),
('FAR-008', 'K. Parvathi Amma', '1988-06-22', 'Female', '9848088990', 'parvathi.k@gmail.com', SHA2('farmer@123', 256), NULL),
('FAR-009', 'T. Narayana Murthy', '1969-12-01', 'Male', '9848099001', 'narayana.t@gmail.com', SHA2('farmer@123', 256), NULL),
('FAR-010', 'Y. Ramachandra Raju', '1986-09-19', 'Male', '9848000222', 'raju.y@gmail.com', SHA2('farmer@123', 256), NULL),
('FAR-011', 'K. Venkata Subba Rao (Senior Owner)', '1954-05-10', 'Male', '9848011412', 'subbarao.412@gmail.com', SHA2('farmer@123', 256), NULL),
('FAR-012', 'M. Srinivasulu (Tenant Cultivator)', '1987-08-19', 'Male', '9848012412', 'srinivasulu.tenant@gmail.com', SHA2('farmer@123', 256), NULL);

UPDATE farmers SET password_hash = SHA2('farmer@123', 256) WHERE farmer_id <> '';

INSERT IGNORE INTO biometric_authentication (authentication_id, farmer_id, aadhaar_number, biometric_type, status, authenticated_at) VALUES
('BIO-001', 'FAR-001', 'XXXX-XXXX-9812', 'Fingerprint & Iris', 'Verified', '2026-01-10 10:30:00'),
('BIO-002', 'FAR-002', 'XXXX-XXXX-4521', 'Fingerprint', 'Verified', '2026-01-12 11:15:00'),
('BIO-003', 'FAR-003', 'XXXX-XXXX-7834', 'Iris Scan', 'Verified', '2026-01-15 14:00:00'),
('BIO-004', 'FAR-004', 'XXXX-XXXX-3319', 'Fingerprint', 'Verified', '2026-01-18 09:45:00'),
('BIO-005', 'FAR-005', 'XXXX-XXXX-6628', 'Fingerprint', 'Verified', '2026-01-20 16:20:00'),
('BIO-006', 'FAR-006', 'XXXX-XXXX-1123', 'Fingerprint', 'Verified', '2026-02-05 10:00:00'),
('BIO-007', 'FAR-007', 'XXXX-XXXX-2234', 'Fingerprint & Iris', 'Verified', '2026-02-12 11:30:00'),
('BIO-008', 'FAR-008', 'XXXX-XXXX-3345', 'Fingerprint', 'Verified', '2026-02-18 14:15:00'),
('BIO-009', 'FAR-009', 'XXXX-XXXX-4456', 'Iris Scan', 'Verified', '2026-02-25 09:30:00'),
('BIO-010', 'FAR-010', 'XXXX-XXXX-5567', 'Fingerprint', 'Verified', '2026-03-02 15:45:00'),
('BIO-011', 'FAR-011', 'XXXX-XXXX-4120', 'Fingerprint', 'Verified', '2026-01-15 10:00:00'),
('BIO-012', 'FAR-012', 'XXXX-XXXX-4129', 'Fingerprint', 'Verified', '2026-02-10 11:20:00');

UPDATE farmers f
JOIN biometric_authentication b ON b.farmer_id = f.farmer_id
SET f.authentication_id = b.authentication_id
WHERE f.authentication_id IS NULL;

INSERT IGNORE INTO farmer_addresses (address_id, farmer_id, house_number, village, mandal, district, state, pincode, address_type) VALUES
('ADDR-001', 'FAR-001', '4-52/A', 'Angalakuduru', 'Tenali', 'Guntur', 'Andhra Pradesh', '522202', 'Permanent'),
('ADDR-002', 'FAR-002', '12-104', 'Navuluru', 'Mangalagiri', 'Guntur', 'Andhra Pradesh', '522503', 'Permanent'),
('ADDR-003', 'FAR-003', '2-19', 'Dharanikota', 'Amaravati', 'Guntur', 'Andhra Pradesh', '522020', 'Permanent'),
('ADDR-004', 'FAR-004', '7-88', 'Enikepadu', 'Vijayawada Rural', 'Krishna', 'Andhra Pradesh', '521108', 'Permanent'),
('ADDR-005', 'FAR-005', '3-45', 'Karavadi', 'Ongole', 'Prakasam', 'Andhra Pradesh', '523182', 'Permanent'),
('ADDR-006', 'FAR-006', '1-88/C', 'Karlapalem', 'Bapatla Urban', 'Bapatla', 'Andhra Pradesh', '522101', 'Permanent'),
('ADDR-007', 'FAR-007', '8-112', 'Billapadu', 'Gudivada', 'Krishna', 'Andhra Pradesh', '521301', 'Permanent'),
('ADDR-008', 'FAR-008', '5-34', 'Petlurivaripalem', 'Narasaraopet', 'Palnadu', 'Andhra Pradesh', '522601', 'Permanent'),
('ADDR-009', 'FAR-009', '11-20', 'Kadiyam', 'Rajahmundry', 'East Godavari', 'Andhra Pradesh', '533126', 'Permanent'),
('ADDR-010', 'FAR-010', '6-77', 'Sanivarapupeta', 'Eluru', 'West Godavari', 'Andhra Pradesh', '534005', 'Permanent'),
('ADDR-011', 'FAR-011', '1-14', 'Angalakuduru', 'Tenali', 'Guntur', 'Andhra Pradesh', '522202', 'Permanent'),
('ADDR-012', 'FAR-012', '3-89', 'Angalakuduru', 'Tenali', 'Guntur', 'Andhra Pradesh', '522202', 'Current');

INSERT IGNORE INTO farmer_land_records (land_id, farmer_id, survey_number, passbook_number, land_area, ownership_type, village, registration_date, verified_by, verified_at) VALUES
('LAND-001', 'FAR-001', 'Sy. No. 142/2A', 'AP-GNT-109283', 4.50, 'Owned', 'Angalakuduru', '2015-06-10', 'Tahsildar Tenali', '2021-03-15 11:00:00'),
('LAND-002', 'FAR-001', 'Sy. No. 143/1', 'AP-GNT-109284', 2.20, 'Owned', 'Angalakuduru', '2017-08-15', 'Tahsildar Tenali', '2021-03-15 11:30:00'),
('LAND-003', 'FAR-002', 'Sy. No. 89/1B', 'AP-GNT-208374', 6.20, 'Owned', 'Navuluru', '2018-02-20', 'Tahsildar Mangalagiri', '2021-04-10 10:00:00'),
('LAND-004', 'FAR-003', 'Sy. No. 305/4', 'AP-GNT-304912', 3.00, 'Owned', 'Dharanikota', '2016-09-12', 'Tahsildar Amaravati', '2021-05-22 15:30:00'),
('LAND-005', 'FAR-004', 'Sy. No. 55/3C', 'AP-KRS-401928', 8.50, 'Owned', 'Enikepadu', '2012-11-05', 'Tahsildar Vijayawada', '2021-06-18 14:15:00'),
('LAND-006', 'FAR-005', 'Sy. No. 120/4', 'AP-PRK-502819', 5.00, 'Owned', 'Karavadi', '2019-01-20', 'Tahsildar Ongole', '2021-07-05 16:00:00'),
('LAND-007', 'FAR-001', 'Sy. No. 150/B', 'AP-GNT-109999', 3.50, 'Leased Out', 'Angalakuduru', '2020-04-10', 'Tahsildar Tenali', '2021-03-15 12:00:00'),
('LAND-412', 'FAR-011', 'Sy. No. 412', 'AP-GNT-412001', 3.00, 'Owned', 'Angalakuduru', '1998-06-15', 'Tahsildar Tenali', '2021-04-01 10:00:00');

INSERT IGNORE INTO farm_fields (field_id, land_id, field_name, field_area, soil_type, irrigation_type) VALUES
('FLD-001', 'LAND-001', 'North Delta Canal Field', 2.50, 'Deep Black Alluvial', 'Krishna Canal Drip'),
('FLD-002', 'LAND-001', 'South Well Agro Plot', 2.00, 'Clayey Loam', 'Submersible Borewell'),
('FLD-003', 'LAND-002', 'East Feeder Plot', 2.20, 'Alluvial Delta Soil', 'Canal Water'),
('FLD-004', 'LAND-003', 'Hill Slope Red Plot', 3.20, 'Red Sandy Loam', 'Borewell Sprinkler'),
('FLD-005', 'LAND-003', 'River Bank Flat Field', 3.00, 'Rich Black Cotton', 'River Lift Irrigation'),
('FLD-006', 'LAND-004', 'Heritage Fertile Field', 3.00, 'Alluvial Silt Loam', 'Canal Water'),
('FLD-007', 'LAND-005', 'Enikepadu Black Soil Parcel', 5.00, 'Heavy Black Cotton', 'Drip & Canal'),
('FLD-008', 'LAND-007', 'Leased Out Delta Parcel', 3.50, 'Medium Black Alluvial', 'Canal Irrigation'),
('FLD-412', 'LAND-412', 'Survey 412 Canal Paddy Plot', 3.00, 'Deep Black Alluvial', 'Krishna Western Canal');

INSERT IGNORE INTO farmer_credit_accounts (credit_account_id, farmer_id, institution_name, kcc_card_number, total_credit_limit, available_balance, repayment_due_date, account_status) VALUES
('CRED-001', 'FAR-001', 'State Bank of India - Tenali', 'KCC-SBIN-892147', 350000.00, 215000.00, '2027-03-31', 'Active'),
('CRED-002', 'FAR-002', 'Union Bank of India - Mangalagiri', 'KCC-UBIN-445892', 450000.00, 310000.00, '2027-03-31', 'Active'),
('CRED-003', 'FAR-003', 'Canara Bank - Amaravati', 'KCC-CNRB-119284', 200000.00, 140000.00, '2027-03-31', 'Active'),
('CRED-004', 'FAR-004', 'HDFC Bank - Vijayawada', 'KCC-HDFC-993821', 600000.00, 425000.00, '2027-03-31', 'Active'),
('CRED-005', 'FAR-005', 'Andhra Pragathi Grameena Bank', 'KCC-APGB-771122', 300000.00, 195000.00, '2027-03-31', 'Active'),
('CRED-006', 'FAR-006', 'SBI Agricultural Branch Bapatla', 'KCC-SBIN-102938', 150000.00, 95000.00, '2027-03-31', 'Active'),
('CRED-012', 'FAR-012', 'State Bank of India - Tenali', 'KCC-SBIN-412999', 150000.00, 125000.00, '2027-03-31', 'Active');

INSERT IGNORE INTO soil_health_records (test_id, field_id, ph_level, organic_carbon, nitrogen_kg_ha, phosphorus_kg_ha, potassium_kg_ha, test_date) VALUES
('SOIL-001', 'FLD-001', 7.20, 0.68, 260.00, 24.50, 310.00, '2026-05-20'),
('SOIL-002', 'FLD-002', 7.10, 0.62, 245.00, 21.00, 290.00, '2026-05-22'),
('SOIL-003', 'FLD-003', 7.30, 0.70, 275.00, 26.00, 325.00, '2026-05-23'),
('SOIL-004', 'FLD-004', 6.80, 0.55, 210.00, 18.50, 250.00, '2026-05-25'),
('SOIL-005', 'FLD-005', 7.40, 0.72, 280.00, 28.00, 340.00, '2026-05-26'),
('SOIL-006', 'FLD-006', 7.00, 0.65, 255.00, 22.00, 305.00, '2026-05-28'),
('SOIL-007', 'FLD-007', 7.50, 0.75, 290.00, 30.00, 350.00, '2026-05-30');

INSERT IGNORE INTO seasonal_cultivator_rights (tenure_id, land_id, tenant_farmer_id, owner_farmer_id, agreement_type, non_encumbrance_clause, lease_expiry_date, approval_status) VALUES
('TEN-001', 'LAND-007', 'FAR-006', 'FAR-001', 'Crop Cultivator Rights Card (CCRC)', 1, '2027-05-31', 'Approved'),
('TEN-002', 'LAND-005', 'FAR-007', 'FAR-004', 'Seasonal Sharecropper Agreement', 1, '2027-04-30', 'Approved'),
('TEN-003', 'LAND-006', 'FAR-008', 'FAR-005', 'Annual Oral Lease with Legal CCRC', 1, '2026-12-31', 'Under Verification'),
('TEN-004', 'LAND-003', 'FAR-009', 'FAR-002', 'Fixed Cash Rental Tenure', 1, '2027-03-31', 'Approved'),
('TEN-412', 'LAND-412', 'FAR-012', 'FAR-011', '11-Month Oral Lease -> CCRC Card', 1, DATE_ADD(CURDATE(), INTERVAL 11 MONTH), 'Pending');

INSERT IGNORE INTO cultivations (cultivation_id, farmer_id, field_id, variety_id, season_id, sowing_date, expected_harvest_date, cultivation_status) VALUES
('CULT-001', 'FAR-001', 'FLD-001', 'VAR-01', 'SEAS-2026-KH', '2026-06-15', '2026-11-10', 'Growing'),
('CULT-002', 'FAR-001', 'FLD-002', 'VAR-04', 'SEAS-2026-KH', '2026-07-01', '2026-12-05', 'Growing'),
('CULT-003', 'FAR-002', 'FLD-004', 'VAR-03', 'SEAS-2026-KH', '2026-06-25', '2026-12-15', 'Growing'),
('CULT-004', 'FAR-003', 'FLD-006', 'VAR-02', 'SEAS-2026-KH', '2026-06-10', '2026-10-15', 'Harvested'),
('CULT-005', 'FAR-004', 'FLD-007', 'VAR-06', 'SEAS-2026-KH', '2026-06-18', '2026-10-25', 'Harvested'),
('CULT-006', 'FAR-006', 'FLD-008', 'VAR-01', 'SEAS-2026-KH', '2026-06-20', '2026-11-15', 'Growing'),
('CULT-007', 'FAR-001', 'FLD-002', 'VAR-04', 'SEAS-2026-KH', '2026-06-20', '2026-11-18', 'Harvested'),
('CULT-008', 'FAR-004', 'FLD-007', 'VAR-06', 'SEAS-2026-KH', '2026-06-15', '2026-10-20', 'Harvested');

INSERT IGNORE INTO cultivation_activities (activity_id, cultivation_id, activity_type, activity_date, description, expense) VALUES
('ACT-001', 'CULT-001', 'Deep Summer Ploughing & Puddling', '2026-06-08', 'Field prepared with rotavator and leveled with tractor', 3500.00),
('ACT-002', 'CULT-001', 'Transplantation of 25-day Seedlings', '2026-06-15', 'Line transplanting with recommended 20x15 cm spacing', 4800.00),
('ACT-003', 'CULT-001', 'First Top Dressing & Weeding', '2026-07-10', 'Manual weeding and basal fertilizer incorporation', 2200.00),
('ACT-004', 'CULT-001', 'Foliar Spraying for Blast Prevention', '2026-08-14', 'Sprayed Saaf fungicide as per RBK advisory', 1150.00),
('ACT-005', 'CULT-002', 'Raised Bed Preparation & Drip Laying', '2026-06-25', 'Chilli nursery transplantation on plastic mulch beds', 5200.00),
('ACT-006', 'CULT-002', 'Sucking Pest Chemical Management', '2026-07-28', 'Applied Confidor at recommended dosage of 0.5ml/L', 980.00),
('ACT-007', 'CULT-004', 'Mechanical Combine Harvesting', '2026-10-15', 'Paddy harvested, threshed and bagged in field', 6500.00),
('ACT-008', 'CULT-005', 'Maize Mechanical Shelling & Bagging', '2026-10-25', 'Harvested 8500 kg grain, moisture test completed', 5800.00);

INSERT IGNORE INTO input_applications (application_id, cultivation_id, product_id, product_batch_id, quantity_used, application_date, application_method, remarks) VALUES
('APP-001', 'CULT-001', 'PROD-01', 'PBAT-01', 45.00, '2026-06-15', 'Basal Soil Incorporation', 'Basal Urea application before transplanting'),
('APP-002', 'CULT-001', 'PROD-02', 'PBAT-02', 50.00, '2026-06-16', 'Basal Placement', 'Full dose DAP applied for vigorous root tillering'),
('APP-003', 'CULT-001', 'PROD-16', 'PBAT-16', 5.00, '2026-07-05', 'Broadcasting', 'Zinc Sulphate applied to prevent Khaira deficiency'),
('APP-004', 'CULT-001', 'PROD-05', 'PBAT-05', 0.50, '2026-08-14', 'Foliar Spray', 'Preventative spray for sheath blight with battery sprayer'),
('APP-005', 'CULT-001', 'PROD-13', 'PBAT-13', 0.50, '2026-08-25', 'Foliar Spray', 'Nano Urea foliar top dressing at panicle initiation'),
('APP-006', 'CULT-002', 'PROD-04', 'PBAT-04', 0.25, '2026-07-28', 'Knapsack Spraying', 'Confidor systemic spray for chilli thrips and whiteflies'),
('APP-007', 'CULT-002', 'PROD-15', 'PBAT-15', 0.50, '2026-08-20', 'Foliar Spray', 'Vipul plant growth promoter for profuse flowering and pod set'),
('APP-008', 'CULT-004', 'PROD-01', 'PBAT-01', 90.00, '2026-06-12', 'Split Top Dressing', 'Applied in two equal splits at active tillering'),
('APP-009', 'CULT-004', 'PROD-11', 'PBAT-11', 0.10, '2026-08-10', 'Foliar Spray', 'Nativo spray for neck blast and sheath rot protection'),
('APP-010', 'CULT-007', 'PROD-24', 'PBAT-24', 0.20, '2026-06-20', 'Nursery Raising', 'Mahyco Teja S17 certified chilli nursery raised'),
('APP-011', 'CULT-007', 'PROD-22', 'PBAT-22', 0.15, '2026-08-28', 'Foliar Spray (0.4 ml/L)', 'VAA Advisory: Bayer Coragen applied at safe 0.4 ml/liter dosage against fruit borer'),
('APP-012', 'CULT-008', 'PROD-23', 'PBAT-23', 10.00, '2026-06-15', 'Precision Seed Drill', 'Syngenta NK 6240 hybrid maize seeds planted'),
('APP-013', 'CULT-008', 'PROD-22', 'PBAT-22', 0.15, '2026-07-22', 'Foliar Spray (0.4 ml/L)', 'Bayer Coragen applied within EU/US MRL safety limits');

INSERT IGNORE INTO harvest_records (harvest_id, cultivation_id, harvest_date, total_quantity, unit, remarks) VALUES
('HARV-001', 'CULT-004', '2026-10-15', 5800.00, 'kg', 'Bumper yield MTU-1010 high grain density'),
('HARV-002', 'CULT-001', '2026-10-28', 4500.00, 'kg', 'Sample harvest BPT-5204 premium quality aromatic grain'),
('HARV-003', 'CULT-005', '2026-10-25', 8500.00, 'kg', 'Maize hybrid high cob grain recovery'),
('HARV-004', 'CULT-007', '2026-11-18', 2500.00, 'kg', 'Sun-dried Teja Guntur S17 Chilli - 50 bags of 50kg'),
('HARV-005', 'CULT-008', '2026-10-22', 12000.00, 'kg', 'Export grade shelled Maize lot from Enikepadu');

INSERT IGNORE INTO crop_batches (crop_batch_id, harvest_id, batch_code, qr_code, quantity, quality_status, unit, packing_date, batch_status) VALUES
('CBAT-001', 'HARV-001', 'CB-2026-MTU-001', 'QR-AGRI-MTU1010-GNT-01', 5800.00, 'Grade A', 'kg', '2026-10-16', 'In Stock'),
('CBAT-002', 'HARV-002', 'CB-2026-BPT-002', 'QR-AGRI-BPT5204-GNT-02', 4500.00, 'Grade A+', 'kg', '2026-10-29', 'In Stock'),
('CBAT-003', 'HARV-003', 'CB-2026-MAIZ-003', 'QR-AGRI-MAIZ3396-KRS-03', 8500.00, 'Grade A', 'kg', '2026-10-26', 'In Stock'),
('CBAT-004', 'HARV-004', 'BATCH-GNT-CHILLI-2026-08', 'QR-BATCH-GNT-CHILLI-2026-08', 2500.00, 'GRADE_A', 'kg', '2026-11-19', 'READY_FOR_SALE'),
('CBAT-005', 'HARV-005', 'BATCH-KRS-MAIZE-2026-11', 'QR-BATCH-KRS-MAIZE-2026-11', 12000.00, 'GRADE_A', 'kg', '2026-10-24', 'READY_FOR_SALE');

INSERT IGNORE INTO crop_quality_tests (quality_test_id, crop_batch_id, moisture_percentage, quality_grade, test_date, test_result, remarks) VALUES
('TEST-001', 'CBAT-001', 13.20, 'Grade A', '2026-10-17', 'Passed', 'Moisture optimal for storage, foreign matter 0.4%, MSP Grade approved'),
('TEST-002', 'CBAT-002', 12.50, 'Grade A+', '2026-10-30', 'Passed', 'Superior aromatic quality, head rice recovery 68%, Export Eligible'),
('TEST-003', 'CBAT-003', 13.80, 'Grade A', '2026-10-27', 'Passed', 'Uniform moisture, zero aflatoxin, approved for starch processing'),
('TEST-004', 'CBAT-004', 9.50, 'GRADE_A', '2026-11-19', 'Passed', 'Uniform deep-red capsaicin grade, zero fungal spots, export residue compliant'),
('TEST-005', 'CBAT-005', 11.40, 'GRADE_A', '2026-10-24', 'Passed', 'Zero aflatoxin, uniform kernel size, ready for institutional buyer escrow');

INSERT IGNORE INTO warehouse_inventory (inventory_id, warehouse_id, crop_batch_id, quantity) VALUES
('WINV-001', 'WH-GNT-01', 'CBAT-001', 3800.00),
('WINV-002', 'WH-TNL-02', 'CBAT-002', 4500.00),
('WINV-003', 'WH-VJA-03', 'CBAT-003', 8500.00),
('WINV-004', 'WH-GNT-09', 'CBAT-004', 2500.00),
('WINV-005', 'WH-VJA-03', 'CBAT-005', 12000.00);

INSERT IGNORE INTO stock_movements (movement_id, warehouse_id, crop_batch_id, movement_type, quantity, movement_date, reference_id) VALUES
('SM-001', 'WH-GNT-01', 'CBAT-001', 'IN', 5800.00, '2026-10-18', 'HARV-001'),
('SM-002', 'WH-GNT-01', 'CBAT-001', 'OUT', 2000.00, '2026-10-24', 'SO-001');

INSERT IGNORE INTO rbk_supply_orders (supply_id, rbk_id, company_id, supply_date, expected_delivery_date, received_date, status, total_amount, created_by_employee_id) VALUES
('SUP-001', 'RBK-GNT-01', 'COMP-01', '2026-05-10 10:00:00', '2026-05-15', '2026-05-14', 'Received', 188650.00, 'EMP-001'),
('SUP-002', 'RBK-GNT-01', 'COMP-02', '2026-05-12 11:30:00', '2026-05-18', '2026-05-17', 'Received', 112500.00, 'EMP-001'),
('SUP-003', 'RBK-GNT-01', 'COMP-03', '2026-05-15 14:00:00', '2026-05-20', '2026-05-19', 'Received', 63000.00, 'EMP-001'),
('SUP-004', 'RBK-GNT-02', 'COMP-01', '2026-05-20 09:15:00', '2026-05-25', '2026-05-24', 'Received', 145000.00, 'EMP-003'),
('SUP-005', 'RBK-GNT-01', 'COMP-10', '2026-11-25 08:30:00', '2026-11-25', NULL, 'Ordered', 53300.00, 'EMP-011');

INSERT IGNORE INTO rbk_supply_items (item_id, supply_id, product_batch_id, ordered_quantity, received_quantity, rejected_quantity, unit_price) VALUES
('SUPI-001', 'SUP-001', 'PBAT-01', 300.00, 300.00, 0.00, 266.50),
('SUPI-002', 'SUP-001', 'PBAT-02', 80.00, 80.00, 0.00, 1350.00),
('SUPI-003', 'SUP-002', 'PBAT-03', 100.00, 100.00, 0.00, 1125.00),
('SUPI-004', 'SUP-003', 'PBAT-04', 150.00, 150.00, 0.00, 420.00),
('SUPI-005', 'SUP-005', 'PBAT-21', 200.00, 0.00, 0.00, 266.50);

INSERT IGNORE INTO input_purchases (purchase_id, farmer_id, rbk_id, purchase_date, total_amount, purchase_status, created_by_employee_id) VALUES
('PUR-001', 'FAR-001', 'RBK-GNT-01', '2026-06-02 10:45:00', 3316.00, 'Paid', 'EMP-001'),
('PUR-002', 'FAR-002', 'RBK-GNT-01', '2026-06-04 11:20:00', 2700.00, 'Paid', 'EMP-001'),
('PUR-003', 'FAR-001', 'RBK-GNT-01', '2026-07-15 09:30:00', 1700.00, 'Paid', 'EMP-001'),
('FAR-PUR-004', 'FAR-001', 'RBK-GNT-01', '2026-08-01 14:15:00', 870.00, 'Paid', 'EMP-002');

INSERT IGNORE INTO input_purchase_items (item_id, purchase_id, product_batch_id, quantity, unit_price) VALUES
('PURI-001', 'PUR-001', 'PBAT-01', 4.00, 266.50),
('PURI-002', 'PUR-001', 'PBAT-03', 2.00, 1125.00),
('PURI-003', 'PUR-002', 'PBAT-02', 2.00, 1350.00),
('PURI-004', 'PUR-003', 'PBAT-06', 1.00, 1700.00),
('PURI-005', 'FAR-PUR-004', 'PBAT-04', 1.00, 420.00),
('PURI-006', 'FAR-PUR-004', 'PBAT-16', 1.00, 450.00);

INSERT IGNORE INTO input_payments (payment_id, purchase_id, amount, payment_method, payment_date, payment_status, transaction_reference) VALUES
('IPAY-001', 'PUR-001', 3316.00, 'KCC Card Swipe (Biometric)', '2026-06-02 10:46:00', 'Completed', 'UPI-KCC-99882211'),
('IPAY-002', 'PUR-002', 2700.00, 'Direct UPI / QR', '2026-06-04 11:21:00', 'Completed', 'UPI-GNT-55443322'),
('IPAY-003', 'PUR-003', 1700.00, 'KCC Card Swipe', '2026-07-15 09:32:00', 'Completed', 'UPI-KCC-11223344'),
('IPAY-004', 'FAR-PUR-004', 870.00, 'Cash Counter', '2026-08-01 14:16:00', 'Completed', 'CSH-RBK-GNT-8812');

INSERT IGNORE INTO pre_booking_orders (preorder_id, farmer_id, rbk_id, preorder_number, target_season, target_year, order_status) VALUES
('PRE-001', 'FAR-001', 'RBK-GNT-01', 'PBO-2026-001', 'Rabi 2026-27', 2026, 'Confirmed'),
('PRE-002', 'FAR-004', 'RBK-GNT-01', 'PBO-2026-002', 'Rabi 2026-27', 2026, 'Pending'),
('PRE-003', 'FAR-001', 'RBK-GNT-01', 'PBO-2026-003', 'Rabi 2026-27', 2026, 'Confirmed'),
('PRE-004', 'FAR-002', 'RBK-GNT-02', 'PBO-2026-004', 'Rabi 2026-27', 2026, 'Confirmed');

INSERT IGNORE INTO pre_booking_items (item_id, preorder_id, product_id, requested_quantity) VALUES
('PBI-001', 'PRE-001', 'PROD-01', 10.00),
('PBI-002', 'PRE-001', 'PROD-06', 4.00),
('PBI-003', 'PRE-002', 'PROD-03', 5.00),
('PBI-004', 'PRE-003', 'PROD-19', 3.00),
('PBI-005', 'PRE-004', 'PROD-02', 6.00);

INSERT IGNORE INTO sales_orders (sales_order_id, farmer_id, buyer_id, delivery_address, order_date, total_amount, payment_status, sales_channel, order_status) VALUES
('SO-001', 'FAR-003', 'BUY-001', 'ITC Procurement Hub, Industrial Road, Guntur', '2026-10-23 11:30:00', 52000.00, 'Paid', 'RBK E-Market', 'Delivered'),
('SO-002', 'FAR-001', 'BUY-002', 'BigBasket Distribution Center, Vijayawada', '2026-11-02 14:15:00', 112500.00, 'Pending', 'Direct Contract', 'Placed'),
('SO-003', 'FAR-001', 'BUY-001', 'ITC Processing Center, Tenali', '2026-11-10 10:00:00', 65000.00, 'Paid', 'Escrow Contract', 'Shipped'),
('SO-004', 'FAR-004', 'BUY-003', 'Godrej Agrovet Sourcing Hub, Tenali', '2026-11-12 16:30:00', 170000.00, 'Paid', 'Direct Contract', 'Delivered'),
('SO-005', 'FAR-001', 'BUY-001', 'ITC Spices Export Processing Plant, Guntur', '2026-11-24 11:00:00', 145000.00, 'ESCROW_HELD', 'Escrow Contract', 'Shipped');

INSERT IGNORE INTO sales_order_items (sales_item_id, sales_order_id, crop_batch_id, quantity, unit_price) VALUES
('SOI-001', 'SO-001', 'CBAT-001', 2000.00, 26.00),
('SOI-002', 'SO-002', 'CBAT-002', 2500.00, 45.00),
('SOI-003', 'SO-003', 'CBAT-002', 1444.44, 45.00),
('SOI-004', 'SO-004', 'CBAT-003', 8500.00, 20.00),
('SOI-005', 'SO-005', 'CBAT-002', 500.00, 290.00);

INSERT IGNORE INTO sales_payments (payment_id, sales_order_id, amount, payment_method, payment_date, payment_status, transaction_reference) VALUES
('SPAY-001', 'SO-001', 52000.00, 'RTGS / Bank Transfer', '2026-10-24 16:00:00', 'Completed', 'RTGS-SBIN2610239912'),
('SPAY-002', 'SO-003', 65000.00, 'Escrow Auto-Release', '2026-11-11 13:00:00', 'Completed', 'ESCROW-HDFC-882299'),
('SPAY-003', 'SO-004', 170000.00, 'Digital Corporate Transfer', '2026-11-13 10:00:00', 'Completed', 'RTGS-GODREJ-771144'),
('SPAY-004', 'SO-005', 145000.00, 'Escrow Account Lock (RTGS)', '2026-11-24 11:05:00', 'ESCROW_HELD', 'ESCROW-ITC-2026-412');

INSERT IGNORE INTO shipments (shipment_id, crop_batch_id, source_location, destination_location, vehicle_number, driver_name, dispatch_date, delivery_date, shipment_status) VALUES
('SHP-001', 'CBAT-001', 'APSWC Central Godown, Guntur', 'ITC Procurement Hub, Guntur', 'AP 07 TJ 4455', 'K. Rambabu', '2026-10-24 09:00:00', '2026-10-24 15:30:00', 'Delivered'),
('SHP-002', 'CBAT-002', 'Tenali Market Yard Warehouse', 'ITC Processing Center, Tenali', 'AP 07 BK 9912', 'M. Venkatesh', '2026-11-11 08:30:00', '2026-11-11 12:00:00', 'Delivered'),
('SHP-003', 'CBAT-003', 'Vijayawada Logistics Hub', 'Godrej Agrovet Hub, Tenali', 'AP 16 TX 7788', 'D. Srinivasa Rao', '2026-11-13 07:00:00', NULL, 'In Transit'),
('SHP-004', 'CBAT-002', 'Tenali Central RBK / WH-TNL-02', 'ITC Spices Export Processing Plant, Guntur', 'AP-16-TX-9988', 'P. Venkateswarlu', '2026-11-24 14:30:00', NULL, 'In Transit');

INSERT IGNORE INTO shipment_items (shipment_item_id, shipment_id, crop_batch_id, sales_item_id, quantity) VALUES
('SHPI-001', 'SHP-001', 'CBAT-001', 'SOI-001', 2000.00),
('SHPI-002', 'SHP-002', 'CBAT-002', 'SOI-003', 1444.44),
('SHPI-003', 'SHP-003', 'CBAT-003', 'SOI-004', 8500.00),
('SHPI-004', 'SHP-004', 'CBAT-002', 'SOI-005', 500.00);

INSERT IGNORE INTO traceability_events (event_id, crop_batch_id, event_type, location, event_date, description, recorded_by) VALUES
('TRC-01', 'CBAT-001', 'Land Preparation', 'Amaravati Farm Field #5', '2026-06-05 08:30:00', 'Rotavator soil tilth, certified organic vermicompost incorporated', 'Farmer: Lakshmi Devi'),
('TRC-02', 'CBAT-001', 'Certified Sowing', 'Amaravati Farm Field #5', '2026-06-10 09:00:00', 'Sown MTU-1010 foundation seeds from RBK Center', 'VAA: P. Anitha'),
('TRC-05', 'CBAT-001', 'Quality Certification', 'Tenali Quality Lab', '2026-10-17 10:30:00', 'Passed Grade A specification with 13.2% moisture', 'Inspector: Dr. R. Sharma'),
('TRC-09', 'CBAT-002', 'Seed Purity Sowing', 'Angalakuduru Field #1', '2026-06-15 08:00:00', 'BPT-5204 foundation seed batch PBAT-03 with biometric issue', 'Farmer: Ramesh Babu Naidu'),
('TRC-10', 'CBAT-002', 'Foliar Blast Defense', 'Angalakuduru Field #1', '2026-08-14 10:00:00', 'Saaf protective fungicide application recorded under audit', 'RBK Officer: K. Subba Rao'),
('TRC-013', 'CBAT-004', 'Agronomic Advisory & Spray', 'Angalakuduru South Well Plot', '2026-08-28 09:30:00', 'Applied Bayer Coragen (Lot BAY-CORA-2026-88) at 0.4 ml/L under VAA supervision', 'VAA: P. Anitha'),
('TRC-014', 'CBAT-004', 'Harvest Quality Certification', 'Tenali Central RBK Collection Yard', '2026-11-19 11:00:00', 'Digital moisture meter 9.5%, Visual Grade: GRADE_A. QR labels printed.', 'VAA: P. Anitha'),
('TRC-015', 'CBAT-005', 'Agronomic Passport Verified', 'Enikepadu Black Soil Parcel', '2026-07-22 10:15:00', 'Syngenta NK 6240 sown; Bayer Coragen within MRL threshold.', 'AEO: D. Suresh Kumar'),
('TRC-016', 'CBAT-005', 'Harvest Quality Certification', 'CWC Regional Hub Vijayawada', '2026-10-24 14:00:00', 'Moisture 11.4%, Grade A certified and listed READY_FOR_SALE.', 'AEO: D. Suresh Kumar');

INSERT IGNORE INTO system_users (user_id, username, email, password_hash, full_name, role, status) VALUES
('USR-ADMIN-01', 'admin', 'admin@agrichain.gov.in', SHA2('rbk@123', 256), 'System Administrator', 'Admin', 'Active'),
('USR-OFFICER-01', 'rbk_officer', 'officer.tenali@agrichain.gov.in', SHA2('rbk@123', 256), 'K. Subba Rao', 'RBK Officer', 'Active');

/* ---------- 4. DATABASE TRIGGER FOR AUTOMATED RBK POS INVENTORY ---------- */
DELIMITER $$
CREATE TRIGGER trg_after_input_purchase_item_insert
AFTER INSERT ON input_purchase_items
FOR EACH ROW
BEGIN
    DECLARE v_rbk_id CHAR(36);
    DECLARE v_emp_id CHAR(36);
    DECLARE v_inv_id CHAR(36);
    DECLARE v_cur_qty DECIMAL(12,2);

    SELECT rbk_id, created_by_employee_id
      INTO v_rbk_id, v_emp_id
      FROM input_purchases
     WHERE purchase_id = NEW.purchase_id;

    IF v_emp_id IS NULL THEN
        SELECT employee_id INTO v_emp_id
          FROM rbk_employees
         WHERE rbk_id = v_rbk_id AND employment_status = 'Active'
         LIMIT 1;
    END IF;

    IF v_emp_id IS NULL THEN
        SELECT employee_id INTO v_emp_id
          FROM rbk_employees
         LIMIT 1;
    END IF;

    SELECT inventory_id, quantity
      INTO v_inv_id, v_cur_qty
      FROM rbk_inventory
     WHERE rbk_id = v_rbk_id AND product_batch_id = NEW.product_batch_id
     LIMIT 1;

    IF v_inv_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Selected product batch is not stocked in this RBK inventory.';
    END IF;

    IF v_cur_qty < NEW.quantity THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Insufficient stock in RBK inventory for the requested quantity.';
    END IF;

    UPDATE rbk_inventory
       SET quantity = quantity - NEW.quantity
     WHERE inventory_id = v_inv_id;

    INSERT INTO rbk_stock_movements (
        movement_id, inventory_id, employee_id, movement_type, quantity, movement_date, reference_id
    ) VALUES (
        CONCAT('RSM-', UPPER(LEFT(REPLACE(UUID(), '-', ''), 8))),
        v_inv_id,
        v_emp_id,
        'OUT',
        NEW.quantity,
        CURDATE(),
        NEW.purchase_id
    );
END$$
DELIMITER ;

SET SQL_SAFE_UPDATES = 1;
