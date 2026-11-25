"""Business logic and MySQL operations for the RBK Employee Portal."""

from decimal import Decimal
from config import QUOTA_RULES_PER_ACRE, get_retail_unit_price
from db import gen_id, query_all, query_one, transaction
from auth import hash_password


def _to_float(val, default=0.0) -> float:
    if val is None:
        return default
    if isinstance(val, Decimal):
        return float(val)
    return float(val)


def get_farmer_verified_acreage(farmer_id: str) -> dict:
    """Calculate total verified cultivable acreage: owned (not leased out) + verified CCRC leases."""
    owned = query_one(
        """
        SELECT COALESCE(SUM(land_area), 0) AS acres
          FROM farmer_land_records flr
         WHERE flr.farmer_id = %s
           AND flr.ownership_type IN ('Owned', 'Joint')
           AND NOT EXISTS (
               SELECT 1 FROM seasonal_cultivator_rights scr
                WHERE scr.land_id = flr.land_id
                  AND scr.owner_farmer_id = flr.farmer_id
                  AND scr.approval_status IN ('VERIFIED_BY_VAA', 'Approved')
                  AND (scr.lease_expiry_date IS NULL OR scr.lease_expiry_date >= CURDATE())
           )
        """,
        (farmer_id,),
    )
    leased_in = query_one(
        """
        SELECT COALESCE(SUM(flr.land_area), 0) AS acres
          FROM seasonal_cultivator_rights scr
          JOIN farmer_land_records flr ON flr.land_id = scr.land_id
         WHERE scr.tenant_farmer_id = %s
           AND scr.approval_status IN ('VERIFIED_BY_VAA', 'Approved')
           AND (scr.lease_expiry_date IS NULL OR scr.lease_expiry_date >= CURDATE())
        """,
        (farmer_id,),
    )
    owned_acres = _to_float(owned["acres"] if owned else 0)
    leased_acres = _to_float(leased_in["acres"] if leased_in else 0)
    return {
        "owned_acres": round(owned_acres, 2),
        "leased_in_acres": round(leased_acres, 2),
        "total_acres": round(owned_acres + leased_acres, 2),
    }


def get_rbk_dashboard_data(rbk_id: str) -> dict:
    """Fetch complete operational dataset for the RBK Employee Home Page."""
    centre = query_one("SELECT * FROM rbk_centres WHERE rbk_id = %s", (rbk_id,))
    divisions = query_all(
        "SELECT * FROM administrative_divisions ORDER BY district_name, mandal_name, village_name"
    )
    companies = query_all("SELECT * FROM agro_companies ORDER BY company_name")
    product_batches = query_all(
        """
        SELECT pb.*, ap.product_name, ap.price, ap.unit, ap.product_type, ap.product_code,
               ac.company_name
          FROM product_batches pb
          JOIN agricultural_products ap ON ap.product_id = pb.product_id
          JOIN agro_companies ac ON ac.company_id = ap.company_id
         WHERE pb.batch_status = 'Active'
         ORDER BY ap.product_name, pb.batch_number
        """
    )
    products = query_all(
        """
        SELECT ap.*, ac.company_name, pc.category_name
          FROM agricultural_products ap
          JOIN agro_companies ac ON ac.company_id = ap.company_id
          JOIN product_categories pc ON pc.category_id = ap.category_id
         WHERE ap.status = 'Active'
         ORDER BY ap.product_name
        """
    )
    inventory = query_all(
        """
        SELECT ri.*, pb.batch_number, pb.expiry_date, ap.product_id, ap.product_name,
               ap.price, ap.unit, ap.product_type, ap.product_code, ac.company_name
          FROM rbk_inventory ri
          JOIN product_batches pb ON pb.product_batch_id = ri.product_batch_id
          JOIN agricultural_products ap ON ap.product_id = pb.product_id
          JOIN agro_companies ac ON ac.company_id = ap.company_id
         WHERE ri.rbk_id = %s
         ORDER BY ap.product_name, pb.batch_number
        """,
        (rbk_id,),
    )
    supply_orders = query_all(
        """
        SELECT rso.*, ac.company_name,
               rsi.item_id, rsi.product_batch_id, rsi.ordered_quantity,
               rsi.received_quantity, rsi.rejected_quantity, rsi.unit_price,
               pb.batch_number, ap.product_name, ap.unit
          FROM rbk_supply_orders rso
          JOIN agro_companies ac ON ac.company_id = rso.company_id
          JOIN rbk_supply_items rsi ON rsi.supply_id = rso.supply_id
          JOIN product_batches pb ON pb.product_batch_id = rsi.product_batch_id
          JOIN agricultural_products ap ON ap.product_id = pb.product_id
         WHERE rso.rbk_id = %s
         ORDER BY FIELD(rso.status, 'Ordered', 'Partially Received', 'Received', 'Cancelled'),
                  rso.supply_date DESC
        """,
        (rbk_id,),
    )
    stock_movements = query_all(
        """
        SELECT rsm.*, pb.batch_number, ap.product_name, e.employee_name
          FROM rbk_stock_movements rsm
          JOIN rbk_inventory ri ON ri.inventory_id = rsm.inventory_id
          JOIN product_batches pb ON pb.product_batch_id = ri.product_batch_id
          JOIN agricultural_products ap ON ap.product_id = pb.product_id
          JOIN rbk_employees e ON e.employee_id = rsm.employee_id
         WHERE ri.rbk_id = %s
         ORDER BY rsm.movement_date DESC, rsm.movement_id DESC
         LIMIT 30
        """,
        (rbk_id,),
    )
    farmers = query_all(
        """
        SELECT f.farmer_id, f.farmer_name, f.phone, f.email, f.gender, f.registration_date,
               b.status AS biometric_status, b.aadhaar_number, b.biometric_type,
               fa.village, fa.mandal, fa.district,
               COALESCE((SELECT SUM(flr.land_area) FROM farmer_land_records flr WHERE flr.farmer_id = f.farmer_id), 0) AS owned_listed_acres,
               COALESCE((SELECT SUM(fca.available_balance) FROM farmer_credit_accounts fca WHERE fca.farmer_id = f.farmer_id AND fca.account_status = 'Active'), 0) AS kcc_balance
          FROM farmers f
          LEFT JOIN biometric_authentication b ON b.farmer_id = f.farmer_id
          LEFT JOIN farmer_addresses fa ON fa.farmer_id = f.farmer_id AND fa.address_type = 'Permanent'
         ORDER BY f.registration_date DESC, f.farmer_name
        """
    )
    for f in farmers:
        acre_info = get_farmer_verified_acreage(f["farmer_id"])
        f["verified_acres"] = acre_info["total_acres"]
        f["leased_in_acres"] = acre_info["leased_in_acres"]

    credit_accounts = query_all(
        """
        SELECT fca.*, f.farmer_name
          FROM farmer_credit_accounts fca
          JOIN farmers f ON f.farmer_id = fca.farmer_id
         WHERE fca.account_status = 'Active'
         ORDER BY f.farmer_name
        """
    )
    land_records = query_all(
        """
        SELECT flr.*, f.farmer_name, f.phone
          FROM farmer_land_records flr
          JOIN farmers f ON f.farmer_id = flr.farmer_id
         ORDER BY flr.village, flr.survey_number
        """
    )
    ccrc_records = query_all(
        """
        SELECT scr.*, flr.survey_number, flr.land_area, flr.village, flr.passbook_number,
               tf.farmer_name AS tenant_name, tf.phone AS tenant_phone,
               ofar.farmer_name AS owner_name, ofar.phone AS owner_phone
          FROM seasonal_cultivator_rights scr
          JOIN farmer_land_records flr ON flr.land_id = scr.land_id
          JOIN farmers tf ON tf.farmer_id = scr.tenant_farmer_id
          JOIN farmers ofar ON ofar.farmer_id = scr.owner_farmer_id
         ORDER BY FIELD(scr.approval_status, 'Pending', 'Under Verification', 'VERIFIED_BY_VAA', 'Approved', 'Rejected', 'Expired'),
                  scr.lease_expiry_date DESC
        """
    )
    cultivations = query_all(
        """
        SELECT c.*, f.farmer_name, ff.field_name, ff.field_area, ff.soil_type,
               cv.variety_name, cr.crop_name, cs.season_name
          FROM cultivations c
          JOIN farmers f ON f.farmer_id = c.farmer_id
          JOIN farm_fields ff ON ff.field_id = c.field_id
          JOIN crop_varieties cv ON cv.variety_id = c.variety_id
          JOIN crops cr ON cr.crop_id = cv.crop_id
          JOIN cultivation_seasons cs ON cs.season_id = c.season_id
         ORDER BY c.sowing_date DESC
        """
    )
    advisories = query_all(
        """
        SELECT ia.*, ap.product_name, pb.batch_number, f.farmer_name, ff.field_name, cr.crop_name
          FROM input_applications ia
          JOIN agricultural_products ap ON ap.product_id = ia.product_id
          JOIN product_batches pb ON pb.product_batch_id = ia.product_batch_id
          JOIN cultivations c ON c.cultivation_id = ia.cultivation_id
          JOIN farmers f ON f.farmer_id = c.farmer_id
          JOIN farm_fields ff ON ff.field_id = c.field_id
          JOIN crop_varieties cv ON cv.variety_id = c.variety_id
          JOIN crops cr ON cr.crop_id = cv.crop_id
         ORDER BY ia.application_date DESC
         LIMIT 25
        """
    )
    crop_batches = query_all(
        """
        SELECT cb.*, hr.harvest_date, c.cultivation_id, f.farmer_name, ff.field_name,
               flr.village, cr.crop_name, cv.variety_name,
               cqt.moisture_percentage, cqt.quality_grade, cqt.test_result
          FROM crop_batches cb
          JOIN harvest_records hr ON hr.harvest_id = cb.harvest_id
          JOIN cultivations c ON c.cultivation_id = hr.cultivation_id
          JOIN farmers f ON f.farmer_id = c.farmer_id
          JOIN farm_fields ff ON ff.field_id = c.field_id
          JOIN farmer_land_records flr ON flr.land_id = ff.land_id
          JOIN crop_varieties cv ON cv.variety_id = c.variety_id
          JOIN crops cr ON cr.crop_id = cv.crop_id
          LEFT JOIN crop_quality_tests cqt ON cqt.crop_batch_id = cb.crop_batch_id
         ORDER BY cb.created_at DESC
        """
    )
    warehouses = query_all("SELECT * FROM warehouses ORDER BY warehouse_name")
    pending_dispatches = query_all(
        """
        SELECT so.sales_order_id, so.order_date, so.total_amount, so.order_status, so.payment_status,
               so.delivery_address, b.buyer_name, f.farmer_name,
               soi.sales_item_id, soi.crop_batch_id, soi.quantity,
               cb.batch_code, cb.qr_code, cr.crop_name
          FROM sales_orders so
          JOIN buyers b ON b.buyer_id = so.buyer_id
          JOIN farmers f ON f.farmer_id = so.farmer_id
          JOIN sales_order_items soi ON soi.sales_order_id = so.sales_order_id
          JOIN crop_batches cb ON cb.crop_batch_id = soi.crop_batch_id
          JOIN harvest_records hr ON hr.harvest_id = cb.harvest_id
          JOIN cultivations c ON c.cultivation_id = hr.cultivation_id
          JOIN crop_varieties cv ON cv.variety_id = c.variety_id
          JOIN crops cr ON cr.crop_id = cv.crop_id
         WHERE so.order_status IN ('Placed', 'Processing')
         ORDER BY so.order_date DESC
        """
    )
    pre_bookings = query_all(
        """
        SELECT pbo.*, f.farmer_name, f.phone,
               GROUP_CONCAT(CONCAT(ap.product_name, ' x ', pbi.requested_quantity) SEPARATOR '; ') AS items_summary
          FROM pre_booking_orders pbo
          JOIN farmers f ON f.farmer_id = pbo.farmer_id
          LEFT JOIN pre_booking_items pbi ON pbi.preorder_id = pbo.preorder_id
          LEFT JOIN agricultural_products ap ON ap.product_id = pbi.product_id
         WHERE pbo.rbk_id = %s
         GROUP BY pbo.preorder_id
         ORDER BY pbo.created_at DESC
        """,
        (rbk_id,),
    )
    recent_purchases = query_all(
        """
        SELECT ip.purchase_id, ip.purchase_date, ip.total_amount, ip.purchase_status,
               f.farmer_name, f.farmer_id,
               ipay.payment_method, ipay.transaction_reference,
               GROUP_CONCAT(CONCAT(ap.product_name, ' (', ipi.quantity, ')') SEPARATOR ', ') AS items_text
          FROM input_purchases ip
          JOIN farmers f ON f.farmer_id = ip.farmer_id
          LEFT JOIN input_payments ipay ON ipay.purchase_id = ip.purchase_id
          LEFT JOIN input_purchase_items ipi ON ipi.purchase_id = ip.purchase_id
          LEFT JOIN product_batches pb ON pb.product_batch_id = ipi.product_batch_id
          LEFT JOIN agricultural_products ap ON ap.product_id = pb.product_id
         WHERE ip.rbk_id = %s
         GROUP BY ip.purchase_id, ipay.payment_method, ipay.transaction_reference
         ORDER BY ip.purchase_date DESC
         LIMIT 20
        """,
        (rbk_id,),
    )

    return {
        "centre": centre,
        "divisions": divisions,
        "companies": companies,
        "product_batches": product_batches,
        "products": products,
        "inventory": inventory,
        "supply_orders": supply_orders,
        "stock_movements": stock_movements,
        "farmers": farmers,
        "credit_accounts": credit_accounts,
        "land_records": land_records,
        "ccrc_records": ccrc_records,
        "cultivations": cultivations,
        "advisories": advisories,
        "crop_batches": crop_batches,
        "warehouses": warehouses,
        "pending_dispatches": pending_dispatches,
        "pre_bookings": pre_bookings,
        "recent_purchases": recent_purchases,
        "quota_rules": QUOTA_RULES_PER_ACRE,
    }


def register_farmer_step1(form: dict) -> str:
    """Step 1 of sequential farmer onboarding: farmers + biometric_authentication + farmer_addresses."""
    farmer_name = (form.get("farmer_name") or "").strip()
    phone = (form.get("phone") or "").strip()
    email = (form.get("email") or "").strip() or None
    dob = (form.get("dob") or "").strip() or None
    gender = (form.get("gender") or "").strip() or None
    password = (form.get("password") or "").strip()
    aadhaar_raw = (form.get("aadhaar_number") or "").strip()
    biometric_type = (form.get("biometric_type") or "Fingerprint").strip()
    biometric_status = (form.get("biometric_status") or "Verified").strip()
    house_number = (form.get("house_number") or "").strip()
    village = (form.get("village") or "").strip()
    mandal = (form.get("mandal") or "").strip()
    district = (form.get("district") or "").strip()
    state = (form.get("state") or "Andhra Pradesh").strip()
    pincode = (form.get("pincode") or "").strip()

    if not farmer_name or not phone or not password or not aadhaar_raw or not village or not mandal or not district or not pincode:
        raise ValueError("Please fill all required Step 1 farmer, Aadhaar biometric, and address fields.")
    if len(pincode) != 6 or not pincode.isdigit():
        raise ValueError("Pincode must be a 6-digit number.")

    digits = "".join(ch for ch in aadhaar_raw if ch.isalnum())
    last4 = digits[-4:] if len(digits) >= 4 else digits.zfill(4)
    masked_aadhaar = f"XXXX-XXXX-{last4}"

    farmer_id = gen_id("FAR")
    auth_id = gen_id("BIO")
    addr_id = gen_id("ADDR")
    pwd_hash = hash_password(password)

    with transaction() as cur:
        cur.execute(
            """
            INSERT INTO farmers (farmer_id, farmer_name, dob, gender, phone, email, password_hash, authentication_id)
            VALUES (%s, %s, %s, %s, %s, %s, %s, NULL)
            """,
            (farmer_id, farmer_name, dob, gender, phone, email, pwd_hash),
        )
        cur.execute(
            """
            INSERT INTO biometric_authentication
                (authentication_id, farmer_id, aadhaar_number, biometric_type, status, authenticated_at)
            VALUES (%s, %s, %s, %s, %s, NOW())
            """,
            (auth_id, farmer_id, masked_aadhaar, biometric_type, biometric_status),
        )
        cur.execute(
            "UPDATE farmers SET authentication_id = %s WHERE farmer_id = %s",
            (auth_id, farmer_id),
        )
        cur.execute(
            """
            INSERT INTO farmer_addresses
                (address_id, farmer_id, house_number, village, mandal, district, state, pincode, address_type)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'Permanent')
            """,
            (addr_id, farmer_id, house_number, village, mandal, district, state, pincode),
        )
    return farmer_id


def register_farmer_step2(form: dict, officer_name: str) -> tuple[str, str]:
    """Step 2 of sequential farmer onboarding: farmer_land_records + farm_fields + optional soil_health_records."""
    farmer_id = (form.get("farmer_id") or "").strip()
    survey_number = (form.get("survey_number") or "").strip()
    passbook_number = (form.get("passbook_number") or "").strip()
    land_area = float(form.get("land_area") or 0)
    ownership_type = (form.get("ownership_type") or "Owned").strip()
    village = (form.get("village") or "").strip()
    field_name = (form.get("field_name") or "").strip() or f"Plot {survey_number}"
    field_area = float(form.get("field_area") or land_area or 0)
    soil_type = (form.get("soil_type") or "Black Alluvial").strip()
    irrigation_type = (form.get("irrigation_type") or "Canal Irrigation").strip()

    if not farmer_id or not survey_number or not passbook_number or land_area <= 0 or not village:
        raise ValueError("Farmer, Survey Number, Passbook Number, positive Land Area, and Village are required.")
    if field_area <= 0 or field_area > land_area:
        field_area = land_area

    land_id = gen_id("LAND")
    field_id = gen_id("FLD")

    with transaction() as cur:
        cur.execute(
            """
            INSERT INTO farmer_land_records
                (land_id, farmer_id, survey_number, passbook_number, land_area, ownership_type,
                 village, registration_date, verified_by, verified_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, CURDATE(), %s, NOW())
            """,
            (land_id, farmer_id, survey_number, passbook_number, land_area, ownership_type, village, officer_name),
        )
        cur.execute(
            """
            INSERT INTO farm_fields
                (field_id, land_id, field_name, field_area, soil_type, irrigation_type)
            VALUES (%s, %s, %s, %s, %s, %s)
            """,
            (field_id, land_id, field_name, field_area, soil_type, irrigation_type),
        )
        ph = (form.get("ph_level") or "").strip()
        if ph:
            cur.execute(
                """
                INSERT INTO soil_health_records
                    (test_id, field_id, ph_level, organic_carbon, nitrogen_kg_ha, phosphorus_kg_ha, potassium_kg_ha, test_date)
                VALUES (%s, %s, %s, %s, %s, %s, %s, CURDATE())
                """,
                (
                    gen_id("SOIL"),
                    field_id,
                    float(ph),
                    float(form.get("organic_carbon") or 0.65),
                    float(form.get("nitrogen_kg_ha") or 250),
                    float(form.get("phosphorus_kg_ha") or 22),
                    float(form.get("potassium_kg_ha") or 300),
                ),
            )
    return land_id, field_id


def register_farmer_step3(form: dict) -> str:
    """Step 3 of sequential farmer onboarding: farmer_credit_accounts (KCC)."""
    farmer_id = (form.get("farmer_id") or "").strip()
    institution_name = (form.get("institution_name") or "").strip()
    kcc_card_number = (form.get("kcc_card_number") or "").strip()
    total_limit = float(form.get("total_credit_limit") or 0)
    avail_balance = float(form.get("available_balance") or total_limit)
    repayment_due_date = (form.get("repayment_due_date") or "").strip() or None

    if not farmer_id or not institution_name or not kcc_card_number or total_limit < 0:
        raise ValueError("Farmer, Bank/Institution, KCC Card Number, and valid credit limit are required.")
    if avail_balance < 0 or avail_balance > total_limit:
        raise ValueError("Available KCC balance must be between 0 and Total Credit Limit.")

    credit_id = gen_id("CRED")
    with transaction() as cur:
        cur.execute(
            """
            INSERT INTO farmer_credit_accounts
                (credit_account_id, farmer_id, institution_name, kcc_card_number,
                 total_credit_limit, available_balance, repayment_due_date, account_status)
            VALUES (%s, %s, %s, %s, %s, %s, %s, 'Active')
            """,
            (credit_id, farmer_id, institution_name, kcc_card_number, total_limit, avail_balance, repayment_due_date),
        )
    return credit_id


def create_supply_order(rbk_id: str, employee_id: str, form: dict) -> str:
    """Create a new incoming agro-company shipment manifest (rbk_supply_orders + rbk_supply_items)."""
    company_id = (form.get("company_id") or "").strip()
    product_batch_id = (form.get("product_batch_id") or "").strip()
    ordered_qty = float(form.get("ordered_quantity") or 0)
    expected_date = (form.get("expected_delivery_date") or "").strip() or None

    if not company_id or not product_batch_id or ordered_qty <= 0:
        raise ValueError("Select an Agro-Company, Product Batch, and positive quantity.")

    batch = query_one(
        """
        SELECT pb.product_batch_id, ap.price
          FROM product_batches pb
          JOIN agricultural_products ap ON ap.product_id = pb.product_id
         WHERE pb.product_batch_id = %s
        """,
        (product_batch_id,),
    )
    if not batch:
        raise ValueError("Product batch not found.")

    unit_price = _to_float(batch["price"])
    total_amount = round(ordered_qty * unit_price, 2)
    supply_id = gen_id("SUP")
    item_id = gen_id("SUPI")

    with transaction() as cur:
        cur.execute(
            """
            INSERT INTO rbk_supply_orders
                (supply_id, rbk_id, company_id, supply_date, expected_delivery_date,
                 status, total_amount, created_by_employee_id)
            VALUES (%s, %s, %s, NOW(), %s, 'Ordered', %s, %s)
            """,
            (supply_id, rbk_id, company_id, expected_date, total_amount, employee_id),
        )
        cur.execute(
            """
            INSERT INTO rbk_supply_items
                (item_id, supply_id, product_batch_id, ordered_quantity, received_quantity, rejected_quantity, unit_price)
            VALUES (%s, %s, %s, %s, 0, 0, %s)
            """,
            (item_id, supply_id, product_batch_id, ordered_qty, unit_price),
        )
    return supply_id


def confirm_supply_delivery(rbk_id: str, employee_id: str, form: dict) -> dict:
    """Workflow 1: Confirm delivery at RBK loading dock, increment rbk_inventory, log IN movement."""
    supply_id = (form.get("supply_id") or "").strip()
    item_id = (form.get("item_id") or "").strip()
    received_qty = float(form.get("received_quantity") or 0)
    rejected_qty = float(form.get("rejected_quantity") or 0)

    if not supply_id or not item_id or received_qty < 0 or rejected_qty < 0:
        raise ValueError("Invalid supply confirmation values.")

    with transaction() as cur:
        cur.execute(
            """
            SELECT rsi.*, rso.rbk_id, rso.status
              FROM rbk_supply_items rsi
              JOIN rbk_supply_orders rso ON rso.supply_id = rsi.supply_id
             WHERE rsi.item_id = %s AND rsi.supply_id = %s AND rso.rbk_id = %s
             FOR UPDATE
            """,
            (item_id, supply_id, rbk_id),
        )
        item = cur.fetchone()
        if not item:
            raise ValueError("Supply manifest item not found for this RBK.")
        if item["status"] == "Received":
            raise ValueError("This shipment manifest has already been confirmed and received.")

        ordered = _to_float(item["ordered_quantity"])
        if received_qty + rejected_qty > ordered:
            raise ValueError(
                f"Accepted ({received_qty}) + Rejected ({rejected_qty}) cannot exceed Ordered ({ordered})."
            )

        cur.execute(
            """
            UPDATE rbk_supply_items
               SET received_quantity = %s, rejected_quantity = %s
             WHERE item_id = %s
            """,
            (received_qty, rejected_qty, item_id),
        )

        batch_id = item["product_batch_id"]
        if received_qty > 0:
            cur.execute(
                """
                SELECT inventory_id, quantity
                  FROM rbk_inventory
                 WHERE rbk_id = %s AND product_batch_id = %s
                 FOR UPDATE
                """,
                (rbk_id, batch_id),
            )
            inv = cur.fetchone()
            if inv:
                inv_id = inv["inventory_id"]
                cur.execute(
                    "UPDATE rbk_inventory SET quantity = quantity + %s WHERE inventory_id = %s",
                    (received_qty, inv_id),
                )
            else:
                inv_id = gen_id("RINV")
                cur.execute(
                    "INSERT INTO rbk_inventory (inventory_id, rbk_id, product_batch_id, quantity) VALUES (%s, %s, %s, %s)",
                    (inv_id, rbk_id, batch_id, received_qty),
                )

            cur.execute(
                """
                INSERT INTO rbk_stock_movements
                    (movement_id, inventory_id, employee_id, movement_type, quantity, movement_date, reference_id)
                VALUES (%s, %s, %s, 'IN', %s, CURDATE(), %s)
                """,
                (gen_id("RSM"), inv_id, employee_id, received_qty, supply_id),
            )

        new_status = "Received" if (received_qty + rejected_qty) >= ordered else "Partially Received"
        cur.execute(
            """
            UPDATE rbk_supply_orders
               SET status = %s, received_date = CURDATE()
             WHERE supply_id = %s
            """,
            (new_status, supply_id),
        )
    return {
        "supply_id": supply_id,
        "received_quantity": received_qty,
        "rejected_quantity": rejected_qty,
        "status": new_status,
    }


def verify_tenant_ccrc(form: dict) -> str:
    """Workflow 2: Verify/create 11-month CCRC seasonal cultivator rights with non-encumbrance consent."""
    tenure_id = (form.get("tenure_id") or "").strip()
    land_id = (form.get("land_id") or "").strip()
    tenant_farmer_id = (form.get("tenant_farmer_id") or "").strip()
    agreement_type = (form.get("agreement_type") or "Crop Cultivator Rights Card (CCRC)").strip()
    lease_months = int(form.get("lease_months") or 11)
    non_encumbrance = form.get("non_encumbrance_clause") in ("1", "true", "on", "yes")
    owner_consent = form.get("owner_consent") in ("1", "true", "on", "yes")
    decision = (form.get("decision") or "VERIFIED_BY_VAA").strip()

    if decision == "VERIFIED_BY_VAA":
        if not non_encumbrance:
            raise ValueError("Explicit Non-Encumbrance Clause must be confirmed so the landowner cannot lose their land.")
        if not owner_consent:
            raise ValueError("Landowner OTP / Biometric consent is required before VAA approval.")
        if lease_months < 1 or lease_months > 11:
            raise ValueError("CCRC lease duration must strictly be 11 months or less.")

    with transaction() as cur:
        if tenure_id:
            cur.execute("SELECT * FROM seasonal_cultivator_rights WHERE tenure_id = %s FOR UPDATE", (tenure_id,))
            existing = cur.fetchone()
            if not existing:
                raise ValueError("CCRC record not found.")
            cur.execute(
                """
                UPDATE seasonal_cultivator_rights
                   SET agreement_type = %s,
                       non_encumbrance_clause = %s,
                       lease_expiry_date = DATE_ADD(CURDATE(), INTERVAL %s MONTH),
                       approval_status = %s
                 WHERE tenure_id = %s
                """,
                (agreement_type, 1 if non_encumbrance else 0, lease_months, decision, tenure_id),
            )
            return tenure_id

        if not land_id or not tenant_farmer_id:
            raise ValueError("Select both the Land Record (Survey No.) and the Tenant Farmer.")

        cur.execute("SELECT farmer_id FROM farmer_land_records WHERE land_id = %s", (land_id,))
        land = cur.fetchone()
        if not land:
            raise ValueError("Land record not found.")
        owner_farmer_id = land["farmer_id"]
        if owner_farmer_id == tenant_farmer_id:
            raise ValueError("Tenant farmer and landowner cannot be the same farmer.")

        new_tenure_id = gen_id("TEN")
        cur.execute(
            """
            INSERT INTO seasonal_cultivator_rights
                (tenure_id, land_id, tenant_farmer_id, owner_farmer_id, agreement_type,
                 non_encumbrance_clause, lease_expiry_date, approval_status)
            VALUES (%s, %s, %s, %s, %s, %s, DATE_ADD(CURDATE(), INTERVAL %s MONTH), %s)
            """,
            (
                new_tenure_id,
                land_id,
                tenant_farmer_id,
                owner_farmer_id,
                agreement_type,
                1 if non_encumbrance else 0,
                lease_months,
                decision,
            ),
        )
        return new_tenure_id


def dispense_input_pos(rbk_id: str, employee_id: str, form: dict) -> dict:
    """Workflow 3: Biometric verification, dosage quota check, KCC/UPI/Cash billing, trigger inventory deduction."""
    farmer_id = (form.get("farmer_id") or "").strip()
    product_batch_id = (form.get("product_batch_id") or "").strip()
    quantity = float(form.get("quantity") or 0)
    payment_method = (form.get("payment_method") or "Cash").strip()
    aadhaar_last4 = (form.get("aadhaar_last4") or "").strip()
    biometric_verified = form.get("biometric_verified") in ("1", "true", "on", "yes")
    kcc_account_id = (form.get("kcc_account_id") or "").strip()

    if not farmer_id or not product_batch_id or quantity <= 0:
        raise ValueError("Select a Farmer, Product Batch, and positive quantity.")
    if not biometric_verified:
        raise ValueError("Biometric thumbprint authentication at RBK kiosk is mandatory before dispensing subsidized inputs.")

    # 1. Verify farmer biometric profile
    bio = query_one(
        """
        SELECT f.farmer_name, b.aadhaar_number, b.biometric_type, b.status
          FROM farmers f
          LEFT JOIN biometric_authentication b ON b.farmer_id = f.farmer_id
         WHERE f.farmer_id = %s
        """,
        (farmer_id,),
    )
    if not bio:
        raise ValueError("Farmer ID not found.")
    if bio["status"] != "Verified":
        raise ValueError(
            f"Sale Blocked: Biometric status for {bio['farmer_name']} is '{bio['status'] or 'Unregistered'}'. Cannot dispense without verified Aadhaar biometrics."
        )
    if aadhaar_last4 and not str(bio["aadhaar_number"]).lower().endswith(aadhaar_last4.lower()):
        raise ValueError("Biometric Verification Failed: Aadhaar last-4 PIN does not match the farmer on file.")

    # 2. Check RBK inventory & product details
    inv = query_one(
        """
        SELECT ri.inventory_id, ri.quantity AS stock_qty,
               ap.product_id, ap.product_name, ap.price, ap.product_type, ap.unit,
               pb.batch_number
          FROM rbk_inventory ri
          JOIN product_batches pb ON pb.product_batch_id = ri.product_batch_id
          JOIN agricultural_products ap ON ap.product_id = pb.product_id
         WHERE ri.rbk_id = %s AND ri.product_batch_id = %s
        """,
        (rbk_id, product_batch_id),
    )
    if not inv:
        raise ValueError("Selected product batch is not stocked at this RBK center.")
    if _to_float(inv["stock_qty"]) < quantity:
        raise ValueError(
            f"Insufficient RBK stock: Requested {quantity}, Available {inv['stock_qty']} ({inv['product_name']})."
        )

    # 3. Scientific Dosage Quota Check based on verified acreage
    acre_info = get_farmer_verified_acreage(farmer_id)
    verified_acres = acre_info["total_acres"]
    if verified_acres <= 0:
        raise ValueError(
            f"Quota Lock: {bio['farmer_name']} has 0.0 verified owned or CCRC-leased acres. Register land or verify CCRC tenure first."
        )

    ptype = inv["product_type"] or "Nitrogenous"
    per_acre_limit = QUOTA_RULES_PER_ACRE.get(ptype, 2.0)
    max_allowed = round(verified_acres * per_acre_limit, 2)
    if quantity > max_allowed:
        raise ValueError(
            f"QUOTA VIOLATION LOCKED: {bio['farmer_name']} has {verified_acres} verified acres "
            f"(max allowed: {max_allowed:g} {inv['unit']} of {ptype} @ {per_acre_limit:g}/acre). "
            f"Requested {quantity:g} exceeds legal quota and was blocked to prevent hoarding/resale."
        )

    unit_price = _to_float(inv["price"])
    total_amount = round(quantity * unit_price, 2)
    retail_unit = get_retail_unit_price(inv["product_id"], unit_price)
    retail_total = round(quantity * retail_unit, 2)
    savings = max(0.0, round(retail_total - total_amount, 2))

    purchase_id = gen_id("PUR")
    item_id = gen_id("PURI")
    payment_id = gen_id("IPAY")
    txn_ref = gen_id("TXN", 8)

    if payment_method == "KCC":
        pay_label = "Kisan Credit Card (KCC)"
    elif payment_method == "UPI":
        pay_label = "Direct UPI / QR"
    else:
        pay_label = "Cash at Counter"

    # 4. Atomic transaction: check/debit KCC -> insert purchase -> insert item (fires trigger!) -> insert payment
    with transaction() as cur:
        if payment_method == "KCC":
            if kcc_account_id:
                cur.execute(
                    """
                    SELECT * FROM farmer_credit_accounts
                     WHERE credit_account_id = %s AND farmer_id = %s AND account_status = 'Active'
                     FOR UPDATE
                    """,
                    (kcc_account_id, farmer_id),
                )
            else:
                cur.execute(
                    """
                    SELECT * FROM farmer_credit_accounts
                     WHERE farmer_id = %s AND account_status = 'Active'
                     ORDER BY available_balance DESC LIMIT 1
                     FOR UPDATE
                    """,
                    (farmer_id,),
                )
            kcc = cur.fetchone()
            if not kcc:
                raise ValueError(f"No active Kisan Credit Card (KCC) account found for {bio['farmer_name']}.")
            avail = _to_float(kcc["available_balance"])
            if avail < total_amount:
                raise ValueError(
                    f"Insufficient KCC Balance: Available ₹{avail:,.2f}, Required ₹{total_amount:,.2f}."
                )
            cur.execute(
                "UPDATE farmer_credit_accounts SET available_balance = available_balance - %s WHERE credit_account_id = %s",
                (total_amount, kcc["credit_account_id"]),
            )

        cur.execute(
            """
            INSERT INTO input_purchases
                (purchase_id, farmer_id, rbk_id, purchase_date, total_amount, purchase_status, created_by_employee_id)
            VALUES (%s, %s, %s, NOW(), %s, 'Paid', %s)
            """,
            (purchase_id, farmer_id, rbk_id, total_amount, employee_id),
        )
        # Fires MySQL trigger `trg_after_input_purchase_item_insert`
        cur.execute(
            """
            INSERT INTO input_purchase_items
                (item_id, purchase_id, product_batch_id, quantity, unit_price)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (item_id, purchase_id, product_batch_id, quantity, unit_price),
        )
        cur.execute(
            """
            INSERT INTO input_payments
                (payment_id, purchase_id, amount, payment_method, payment_date, payment_status, transaction_reference)
            VALUES (%s, %s, %s, %s, NOW(), 'Completed', %s)
            """,
            (payment_id, purchase_id, total_amount, pay_label, txn_ref),
        )

    return {
        "purchase_id": purchase_id,
        "farmer_name": bio["farmer_name"],
        "product_name": inv["product_name"],
        "batch_number": inv["batch_number"],
        "quantity": quantity,
        "unit": inv["unit"],
        "verified_acres": verified_acres,
        "max_allowed": max_allowed,
        "payment_method": pay_label,
        "transaction_reference": txn_ref,
        "total_amount": total_amount,
        "retail_total": retail_total,
        "savings": savings,
    }


def log_agronomic_advisory(form: dict, employee_name: str) -> str:
    """Workflow 4: Record VAA field agronomic advisory & chemical lot application."""
    cultivation_id = (form.get("cultivation_id") or "").strip()
    product_batch_id = (form.get("product_batch_id") or "").strip()
    quantity_used = float(form.get("quantity_used") or 0)
    application_date = (form.get("application_date") or "").strip()
    application_method = (form.get("application_method") or "").strip()
    remarks = (form.get("remarks") or "").strip()

    if not cultivation_id or not product_batch_id or quantity_used <= 0 or not application_date:
        raise ValueError("Select Cultivation, Chemical/Product Lot, positive quantity, and application date.")

    batch = query_one(
        """
        SELECT pb.product_id, pb.batch_number, ap.product_name
          FROM product_batches pb
          JOIN agricultural_products ap ON ap.product_id = pb.product_id
         WHERE pb.product_batch_id = %s
        """,
        (product_batch_id,),
    )
    if not batch:
        raise ValueError("Product batch not found.")

    app_id = gen_id("APP")
    with transaction() as cur:
        cur.execute(
            """
            INSERT INTO input_applications
                (application_id, cultivation_id, product_id, product_batch_id,
                 quantity_used, application_date, application_method, remarks)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                app_id,
                cultivation_id,
                batch["product_id"],
                product_batch_id,
                quantity_used,
                application_date,
                application_method or "Foliar Spray",
                f"{remarks} [Logged by {employee_name}]".strip(),
            ),
        )
    return app_id


def certify_harvest_batch(form: dict, employee_name: str) -> dict:
    """Workflow 5a: Record harvest moisture/grade test, create QR crop_batch (READY_FOR_SALE), stock warehouse."""
    cultivation_id = (form.get("cultivation_id") or "").strip()
    harvest_date = (form.get("harvest_date") or "").strip()
    total_quantity = float(form.get("total_quantity") or 0)
    moisture_pct = float(form.get("moisture_percentage") or 0)
    quality_grade = (form.get("quality_grade") or "GRADE_A").strip()
    test_result = (form.get("test_result") or "Passed").strip()
    warehouse_id = (form.get("warehouse_id") or "").strip()
    remarks = (form.get("remarks") or "").strip()

    if not cultivation_id or not harvest_date or total_quantity <= 0 or not warehouse_id:
        raise ValueError("Cultivation, Harvest Date, positive Quantity (kg), and Destination Warehouse are required.")

    cult = query_one(
        """
        SELECT c.cultivation_id, cr.crop_name, flr.village
          FROM cultivations c
          JOIN crop_varieties cv ON cv.variety_id = c.variety_id
          JOIN crops cr ON cr.crop_id = cv.crop_id
          JOIN farm_fields ff ON ff.field_id = c.field_id
          JOIN farmer_land_records flr ON flr.land_id = ff.land_id
         WHERE c.cultivation_id = %s
        """,
        (cultivation_id,),
    )
    if not cult:
        raise ValueError("Cultivation record not found.")

    crop_tag = "".join(ch for ch in cult["crop_name"].upper() if ch.isalpha())[:6] or "CROP"
    suffix = gen_id(crop_tag, 4)
    batch_code = f"BATCH-AP-{suffix}"
    qr_code = f"QR-{batch_code}"
    harvest_id = gen_id("HARV")
    crop_batch_id = gen_id("CBAT")
    qtest_id = gen_id("TEST")
    batch_status = "READY_FOR_SALE" if test_result == "Passed" else "In Stock"

    with transaction() as cur:
        cur.execute(
            """
            INSERT INTO harvest_records (harvest_id, cultivation_id, harvest_date, total_quantity, unit, remarks)
            VALUES (%s, %s, %s, %s, 'kg', %s)
            """,
            (harvest_id, cultivation_id, harvest_date, total_quantity, remarks or "RBK Yard Weighment"),
        )
        cur.execute(
            "UPDATE cultivations SET cultivation_status = 'Harvested' WHERE cultivation_id = %s",
            (cultivation_id,),
        )
        cur.execute(
            """
            INSERT INTO crop_batches
                (crop_batch_id, harvest_id, batch_code, qr_code, quantity, quality_status, unit, packing_date, batch_status)
            VALUES (%s, %s, %s, %s, %s, %s, 'kg', CURDATE(), %s)
            """,
            (crop_batch_id, harvest_id, batch_code, qr_code, total_quantity, quality_grade, batch_status),
        )
        cur.execute(
            """
            INSERT INTO crop_quality_tests
                (quality_test_id, crop_batch_id, moisture_percentage, quality_grade, test_date, test_result, remarks)
            VALUES (%s, %s, %s, %s, CURDATE(), %s, %s)
            """,
            (qtest_id, crop_batch_id, moisture_pct, quality_grade, test_result, remarks),
        )
        cur.execute(
            """
            INSERT INTO warehouse_inventory (inventory_id, warehouse_id, crop_batch_id, quantity)
            VALUES (%s, %s, %s, %s)
            ON DUPLICATE KEY UPDATE quantity = quantity + VALUES(quantity)
            """,
            (gen_id("WINV"), warehouse_id, crop_batch_id, total_quantity),
        )
        cur.execute(
            """
            INSERT INTO stock_movements (movement_id, warehouse_id, crop_batch_id, movement_type, quantity, movement_date, reference_id)
            VALUES (%s, %s, %s, 'IN', %s, CURDATE(), %s)
            """,
            (gen_id("SM"), warehouse_id, crop_batch_id, total_quantity, harvest_id),
        )
        cur.execute(
            """
            INSERT INTO traceability_events (event_id, crop_batch_id, event_type, location, event_date, description, recorded_by)
            VALUES (%s, %s, 'Quality Certification & QR Tagging', %s, NOW(), %s, %s)
            """,
            (
                gen_id("TRC"),
                crop_batch_id,
                f"RBK Collection Yard ({cult['village']})",
                f"Moisture {moisture_pct}%, Grade {quality_grade}, Result {test_result}. Thermal QR {qr_code} printed; listed {batch_status}.",
                employee_name,
            ),
        )
    return {
        "crop_batch_id": crop_batch_id,
        "batch_code": batch_code,
        "qr_code": qr_code,
        "quality_grade": quality_grade,
        "moisture_percentage": moisture_pct,
        "quantity": total_quantity,
        "batch_status": batch_status,
    }


def dispatch_sales_order(form: dict, employee_name: str) -> str:
    """Workflow 5b: Load buyer order sacks onto transport truck and scan QR codes -> IN_TRANSIT."""
    sales_order_id = (form.get("sales_order_id") or "").strip()
    sales_item_id = (form.get("sales_item_id") or "").strip()
    crop_batch_id = (form.get("crop_batch_id") or "").strip()
    quantity = float(form.get("quantity") or 0)
    source_location = (form.get("source_location") or "").strip()
    destination_location = (form.get("destination_location") or "").strip()
    vehicle_number = (form.get("vehicle_number") or "").strip()
    driver_name = (form.get("driver_name") or "").strip()

    if not sales_order_id or not crop_batch_id or not vehicle_number or not driver_name or quantity <= 0:
        raise ValueError("Sales Order, Crop Batch, Vehicle License, Driver Name, and Quantity are required.")

    shipment_id = gen_id("SHP")
    with transaction() as cur:
        cur.execute(
            """
            INSERT INTO shipments
                (shipment_id, crop_batch_id, source_location, destination_location,
                 vehicle_number, driver_name, dispatch_date, shipment_status)
            VALUES (%s, %s, %s, %s, %s, %s, NOW(), 'In Transit')
            """,
            (shipment_id, crop_batch_id, source_location, destination_location, vehicle_number, driver_name),
        )
        if sales_item_id:
            cur.execute(
                """
                INSERT INTO shipment_items (shipment_item_id, shipment_id, crop_batch_id, sales_item_id, quantity)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (gen_id("SHPI"), shipment_id, crop_batch_id, sales_item_id, quantity),
            )
        cur.execute(
            "UPDATE crop_batches SET batch_status = 'IN_TRANSIT' WHERE crop_batch_id = %s",
            (crop_batch_id,),
        )
        cur.execute(
            "UPDATE sales_orders SET order_status = 'Shipped' WHERE sales_order_id = %s",
            (sales_order_id,),
        )
        cur.execute(
            """
            SELECT inventory_id, warehouse_id, quantity
              FROM warehouse_inventory
             WHERE crop_batch_id = %s AND quantity >= %s
             LIMIT 1 FOR UPDATE
            """,
            (crop_batch_id, quantity),
        )
        winv = cur.fetchone()
        if winv:
            cur.execute(
                "UPDATE warehouse_inventory SET quantity = quantity - %s WHERE inventory_id = %s",
                (quantity, winv["inventory_id"]),
            )
            cur.execute(
                """
                INSERT INTO stock_movements (movement_id, warehouse_id, crop_batch_id, movement_type, quantity, movement_date, reference_id)
                VALUES (%s, %s, %s, 'OUT', %s, CURDATE(), %s)
                """,
                (gen_id("SM"), winv["warehouse_id"], crop_batch_id, quantity, shipment_id),
            )
        cur.execute(
            """
            INSERT INTO traceability_events (event_id, crop_batch_id, event_type, location, event_date, description, recorded_by)
            VALUES (%s, %s, 'RBK Truck Dispatch (QR Scanned)', %s, NOW(), %s, %s)
            """,
            (
                gen_id("TRC"),
                crop_batch_id,
                source_location,
                f"Dispatched {quantity} kg on truck {vehicle_number} (Driver: {driver_name}) to {destination_location}. Batch status -> IN_TRANSIT.",
                employee_name,
            ),
        )
    return shipment_id


def update_preorder_status(preorder_id: str, new_status: str) -> None:
    """Confirm or fulfill a farmer's pre-booking order at the RBK."""
    if new_status not in ("Pending", "Confirmed", "Fulfilled", "Cancelled"):
        raise ValueError("Invalid pre-booking order status.")
    with transaction() as cur:
        cur.execute(
            "UPDATE pre_booking_orders SET order_status = %s WHERE preorder_id = %s",
            (new_status, preorder_id),
        )
