"""Business logic and MySQL queries for the Farmer 360 Portal."""

from decimal import Decimal
from db import gen_id, query_all, query_one, transaction


def _f(v, default=0.0) -> float:
    if v is None:
        return default
    if isinstance(v, Decimal):
        return float(v)
    return float(v)


def get_farmer_dashboard_data(farmer_id: str) -> dict:
    """Retrieve complete 360-degree dataset scoped strictly to the logged-in farmer."""
    profile = query_one(
        """
        SELECT f.*, b.authentication_id, b.aadhaar_number, b.biometric_type,
               b.status AS biometric_status, b.authenticated_at
          FROM farmers f
          LEFT JOIN biometric_authentication b ON b.farmer_id = f.farmer_id
         WHERE f.farmer_id = %s
        """,
        (farmer_id,),
    )
    addresses = query_all(
        "SELECT * FROM farmer_addresses WHERE farmer_id = %s ORDER BY address_type",
        (farmer_id,),
    )
    land_records = query_all(
        "SELECT * FROM farmer_land_records WHERE farmer_id = %s ORDER BY survey_number",
        (farmer_id,),
    )
    credit_accounts = query_all(
        "SELECT * FROM farmer_credit_accounts WHERE farmer_id = %s ORDER BY account_status, kcc_card_number",
        (farmer_id,),
    )
    for ca in credit_accounts:
        ca["outstanding_debt"] = round(
            max(0.0, _f(ca["total_credit_limit"]) - _f(ca["available_balance"])), 2
        )

    farm_fields = query_all(
        """
        SELECT ff.*, flr.survey_number, flr.village, flr.ownership_type,
               CASE WHEN flr.farmer_id = %s THEN 'Owned Plot' ELSE 'CCRC Leased-In Plot' END AS access_role
          FROM farm_fields ff
          JOIN farmer_land_records flr ON flr.land_id = ff.land_id
         WHERE flr.farmer_id = %s
            OR EXISTS (
                SELECT 1 FROM seasonal_cultivator_rights scr
                 WHERE scr.land_id = flr.land_id
                   AND scr.tenant_farmer_id = %s
                   AND scr.approval_status IN ('VERIFIED_BY_VAA', 'Approved')
                   AND (scr.lease_expiry_date IS NULL OR scr.lease_expiry_date >= CURDATE())
            )
         ORDER BY access_role, ff.field_name
        """,
        (farmer_id, farmer_id, farmer_id),
    )

    seasonal_rights = query_all(
        """
        SELECT scr.*, flr.survey_number, flr.land_area, flr.village, flr.passbook_number,
               tf.farmer_name AS tenant_name, tf.phone AS tenant_phone,
               ofar.farmer_name AS owner_name, ofar.phone AS owner_phone,
               CASE WHEN scr.owner_farmer_id = %s THEN 'Given on Lease (Owner)'
                    ELSE 'Taken on Lease (Tenant)' END AS farmer_lease_role
          FROM seasonal_cultivator_rights scr
          JOIN farmer_land_records flr ON flr.land_id = scr.land_id
          JOIN farmers tf ON tf.farmer_id = scr.tenant_farmer_id
          JOIN farmers ofar ON ofar.farmer_id = scr.owner_farmer_id
         WHERE scr.owner_farmer_id = %s OR scr.tenant_farmer_id = %s
         ORDER BY scr.lease_expiry_date DESC
        """,
        (farmer_id, farmer_id, farmer_id),
    )

    input_purchases = query_all(
        """
        SELECT ip.purchase_id, ip.purchase_date, ip.total_amount, ip.purchase_status,
               rc.rbk_name, rc.district,
               ipay.payment_id, ipay.payment_method, ipay.payment_status AS payment_state,
               ipay.transaction_reference, ipay.amount AS paid_amount,
               ap.product_name, ap.product_type, ap.unit, pb.batch_number,
               ipi.quantity, ipi.unit_price, ipi.subtotal
          FROM input_purchases ip
          JOIN rbk_centres rc ON rc.rbk_id = ip.rbk_id
          LEFT JOIN input_payments ipay ON ipay.purchase_id = ip.purchase_id
          LEFT JOIN input_purchase_items ipi ON ipi.purchase_id = ip.purchase_id
          LEFT JOIN product_batches pb ON pb.product_batch_id = ipi.product_batch_id
          LEFT JOIN agricultural_products ap ON ap.product_id = pb.product_id
         WHERE ip.farmer_id = %s
         ORDER BY ip.purchase_date DESC, ip.purchase_id
        """,
        (farmer_id,),
    )

    pre_bookings = query_all(
        """
        SELECT pbo.*, rc.rbk_name, rc.district,
               pbi.item_id, pbi.requested_quantity,
               ap.product_name, ap.unit, ap.price
          FROM pre_booking_orders pbo
          JOIN rbk_centres rc ON rc.rbk_id = pbo.rbk_id
          LEFT JOIN pre_booking_items pbi ON pbi.preorder_id = pbo.preorder_id
          LEFT JOIN agricultural_products ap ON ap.product_id = pbi.product_id
         WHERE pbo.farmer_id = %s
         ORDER BY pbo.created_at DESC
        """,
        (farmer_id,),
    )

    buyer_orders = query_all(
        """
        SELECT so.sales_order_id, so.order_date, so.total_amount, so.payment_status,
               so.sales_channel, so.order_status, so.delivery_address,
               b.buyer_name, b.buyer_type, b.registration_number,
               sp.payment_status AS escrow_status, sp.payment_method, sp.transaction_reference,
               soi.quantity, soi.unit_price, soi.subtotal,
               cb.batch_code, cb.qr_code, cb.quality_status,
               cr.crop_name, cv.variety_name,
               shp.vehicle_number, shp.shipment_status
          FROM sales_orders so
          JOIN buyers b ON b.buyer_id = so.buyer_id
          LEFT JOIN sales_payments sp ON sp.sales_order_id = so.sales_order_id
          LEFT JOIN sales_order_items soi ON soi.sales_order_id = so.sales_order_id
          LEFT JOIN crop_batches cb ON cb.crop_batch_id = soi.crop_batch_id
          LEFT JOIN harvest_records hr ON hr.harvest_id = cb.harvest_id
          LEFT JOIN cultivations c ON c.cultivation_id = hr.cultivation_id
          LEFT JOIN crop_varieties cv ON cv.variety_id = c.variety_id
          LEFT JOIN crops cr ON cr.crop_id = cv.crop_id
          LEFT JOIN shipments shp ON shp.crop_batch_id = cb.crop_batch_id
         WHERE so.farmer_id = %s
         ORDER BY so.order_date DESC
        """,
        (farmer_id,),
    )

    soil_health = query_all(
        """
        SELECT shr.*, ff.field_name, flr.survey_number, flr.village
          FROM soil_health_records shr
          JOIN farm_fields ff ON ff.field_id = shr.field_id
          JOIN farmer_land_records flr ON flr.land_id = ff.land_id
         WHERE flr.farmer_id = %s
            OR EXISTS (
                SELECT 1 FROM seasonal_cultivator_rights scr
                 WHERE scr.land_id = flr.land_id
                   AND scr.tenant_farmer_id = %s
                   AND scr.approval_status IN ('VERIFIED_BY_VAA', 'Approved')
            )
         ORDER BY shr.test_date DESC
        """,
        (farmer_id, farmer_id),
    )

    cultivations = query_all(
        """
        SELECT c.*, ff.field_name, ff.field_area, cr.crop_name, cv.variety_name,
               cs.season_name,
               COALESCE((SELECT SUM(ca.expense) FROM cultivation_activities ca WHERE ca.cultivation_id = c.cultivation_id), 0) AS total_activity_expense
          FROM cultivations c
          JOIN farm_fields ff ON ff.field_id = c.field_id
          JOIN crop_varieties cv ON cv.variety_id = c.variety_id
          JOIN crops cr ON cr.crop_id = cv.crop_id
          JOIN cultivation_seasons cs ON cs.season_id = c.season_id
         WHERE c.farmer_id = %s
         ORDER BY c.sowing_date DESC
        """,
        (farmer_id,),
    )

    cultivation_activities = query_all(
        """
        SELECT ca.*, cr.crop_name, cv.variety_name, ff.field_name, cs.season_name
          FROM cultivation_activities ca
          JOIN cultivations c ON c.cultivation_id = ca.cultivation_id
          JOIN farm_fields ff ON ff.field_id = c.field_id
          JOIN crop_varieties cv ON cv.variety_id = c.variety_id
          JOIN crops cr ON cr.crop_id = cv.crop_id
          JOIN cultivation_seasons cs ON cs.season_id = c.season_id
         WHERE c.farmer_id = %s
         ORDER BY ca.activity_date DESC
        """,
        (farmer_id,),
    )

    seasonal_inputs_used = query_all(
        """
        SELECT ia.*, ap.product_name, ap.product_type, ap.unit, ap.price,
               pb.batch_number, ac.company_name,
               cr.crop_name, cv.variety_name, cs.season_name, ff.field_name
          FROM input_applications ia
          JOIN cultivations c ON c.cultivation_id = ia.cultivation_id
          JOIN agricultural_products ap ON ap.product_id = ia.product_id
          JOIN agro_companies ac ON ac.company_id = ap.company_id
          JOIN product_batches pb ON pb.product_batch_id = ia.product_batch_id
          JOIN farm_fields ff ON ff.field_id = c.field_id
          JOIN crop_varieties cv ON cv.variety_id = c.variety_id
          JOIN crops cr ON cr.crop_id = cv.crop_id
          JOIN cultivation_seasons cs ON cs.season_id = c.season_id
         WHERE c.farmer_id = %s
         ORDER BY ia.application_date DESC
        """,
        (farmer_id,),
    )

    rbk_centres = query_all("SELECT * FROM rbk_centres WHERE status = 'Active' ORDER BY district, rbk_name")
    products = query_all(
        """
        SELECT ap.*, ac.company_name
          FROM agricultural_products ap
          JOIN agro_companies ac ON ac.company_id = ap.company_id
         WHERE ap.status = 'Active'
         ORDER BY ap.product_name
        """
    )
    seasons = query_all("SELECT * FROM cultivation_seasons ORDER BY start_date DESC")
    varieties = query_all(
        """
        SELECT cv.*, cr.crop_name
          FROM crop_varieties cv
          JOIN crops cr ON cr.crop_id = cv.crop_id
         ORDER BY cr.crop_name, cv.variety_name
        """
    )

    return {
        "profile": profile,
        "addresses": addresses,
        "land_records": land_records,
        "credit_accounts": credit_accounts,
        "farm_fields": farm_fields,
        "seasonal_rights": seasonal_rights,
        "input_purchases": input_purchases,
        "pre_bookings": pre_bookings,
        "buyer_orders": buyer_orders,
        "soil_health": soil_health,
        "cultivations": cultivations,
        "cultivation_activities": cultivation_activities,
        "seasonal_inputs_used": seasonal_inputs_used,
        "rbk_centres": rbk_centres,
        "products": products,
        "seasons": seasons,
        "varieties": varieties,
    }


def create_pre_booking(farmer_id: str, form: dict) -> str:
    """Insert a farmer's seasonal input pre-booking into pre_booking_orders and pre_booking_items."""
    rbk_id = (form.get("rbk_id") or "").strip()
    product_id = (form.get("product_id") or "").strip()
    requested_qty = float(form.get("requested_quantity") or 0)
    target_season = (form.get("target_season") or "Rabi 2026-27").strip()
    target_year = int(form.get("target_year") or 2026)

    if not rbk_id or not product_id or requested_qty <= 0:
        raise ValueError("Select an RBK center, Product, and positive quantity.")

    preorder_id = gen_id("PRE")
    preorder_number = gen_id("PBO-2026", 4)
    with transaction() as cur:
        cur.execute(
            """
            INSERT INTO pre_booking_orders
                (preorder_id, farmer_id, rbk_id, preorder_number, target_season, target_year, order_status)
            VALUES (%s, %s, %s, %s, %s, %s, 'Pending')
            """,
            (preorder_id, farmer_id, rbk_id, preorder_number, target_season, target_year),
        )
        cur.execute(
            """
            INSERT INTO pre_booking_items (item_id, preorder_id, product_id, requested_quantity)
            VALUES (%s, %s, %s, %s)
            """,
            (gen_id("PBI"), preorder_id, product_id, requested_qty),
        )
    return preorder_number


def create_cultivation(farmer_id: str, form: dict) -> str:
    """Create a new crop cultivation record for the logged-in farmer."""
    field_id = (form.get("field_id") or "").strip()
    variety_id = (form.get("variety_id") or "").strip()
    season_id = (form.get("season_id") or "").strip()
    sowing_date = (form.get("sowing_date") or "").strip()
    expected_harvest_date = (form.get("expected_harvest_date") or "").strip() or None

    if not field_id or not variety_id or not season_id or not sowing_date:
        raise ValueError("Field, Crop Variety, Season, and Sowing Date are required.")

    cult_id = gen_id("CULT")
    with transaction() as cur:
        cur.execute(
            """
            INSERT INTO cultivations
                (cultivation_id, farmer_id, field_id, variety_id, season_id,
                 sowing_date, expected_harvest_date, cultivation_status)
            VALUES (%s, %s, %s, %s, %s, %s, %s, 'Sown')
            """,
            (cult_id, farmer_id, field_id, variety_id, season_id, sowing_date, expected_harvest_date),
        )
    return cult_id


def add_cultivation_activity(farmer_id: str, form: dict) -> str:
    """Log a cultivation activity & expense for a farmer's cultivation."""
    cultivation_id = (form.get("cultivation_id") or "").strip()
    activity_type = (form.get("activity_type") or "").strip()
    activity_date = (form.get("activity_date") or "").strip()
    description = (form.get("description") or "").strip()
    expense = float(form.get("expense") or 0)

    if not cultivation_id or not activity_type or not activity_date or expense < 0:
        raise ValueError("Cultivation, Activity Type, Date, and non-negative Expense are required.")

    owner_check = query_one(
        "SELECT cultivation_id FROM cultivations WHERE cultivation_id = %s AND farmer_id = %s",
        (cultivation_id, farmer_id),
    )
    if not owner_check:
        raise ValueError("Selected cultivation does not belong to your account.")

    act_id = gen_id("ACT")
    with transaction() as cur:
        cur.execute(
            """
            INSERT INTO cultivation_activities
                (activity_id, cultivation_id, activity_type, activity_date, description, expense)
            VALUES (%s, %s, %s, %s, %s, %s)
            """,
            (act_id, cultivation_id, activity_type, activity_date, description, expense),
        )
    return act_id
