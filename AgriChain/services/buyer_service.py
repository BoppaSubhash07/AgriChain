"""Business logic and MySQL operations for the Institutional Buyer Portal."""

from decimal import Decimal
from auth import hash_password
from db import gen_id, query_all, query_one, transaction


def _f(v, default=0.0) -> float:
    if v is None:
        return default
    if isinstance(v, Decimal):
        return float(v)
    return float(v)


def register_buyer(form: dict) -> dict:
    """Workflow 1: Onboard & classify a new institutional buyer (Exporter/Processor/Retailer/Wholesaler)."""
    buyer_name = (form.get("buyer_name") or "").strip()
    buyer_type = (form.get("buyer_type") or "Exporter").strip()
    phone = (form.get("phone") or "").strip()
    email = (form.get("email") or "").strip()
    address = (form.get("address") or "").strip()
    reg_no = (form.get("registration_number") or "").strip()
    password = (form.get("password") or "").strip()

    if not buyer_name or not phone or not email or not reg_no or not password:
        raise ValueError("Organization Name, Type, Phone, Email, GST/Registration No., and Password are required.")
    if buyer_type not in ("Wholesaler", "Retailer", "Processor", "Exporter", "Other"):
        raise ValueError("Invalid buyer classification.")

    buyer_id = gen_id("BUY")
    pwd_hash = hash_password(password)
    with transaction() as cur:
        cur.execute(
            """
            INSERT INTO buyers
                (buyer_id, buyer_name, buyer_type, phone, email, address, registration_number, buyer_password_hash)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (buyer_id, buyer_name, buyer_type, phone, email, address, reg_no, pwd_hash),
        )
    return {"buyer_id": buyer_id, "buyer_name": buyer_name, "email": email}


def get_buyer_dashboard_data(buyer_id: str, passport_code: str | None = None) -> dict:
    """Fetch buyer profile, digitized crop marketplace, orders, escrow payments, warehouses, and shipments."""
    buyer = query_one("SELECT * FROM buyers WHERE buyer_id = %s", (buyer_id,))
    crop_categories = query_all("SELECT * FROM crop_categories ORDER BY category_name")

    marketplace_batches = query_all(
        """
        SELECT cb.*, hr.harvest_date, c.cultivation_id, c.farmer_id,
               f.farmer_name, f.phone AS farmer_phone,
               ff.field_name, flr.village, flr.survey_number,
               cr.crop_name, cc.category_name, cv.variety_name,
               cqt.moisture_percentage, cqt.quality_grade, cqt.test_result, cqt.remarks AS test_remarks,
               wi.warehouse_id, w.warehouse_name, w.district AS warehouse_district,
               COALESCE(wi.quantity, cb.quantity) AS available_kg,
               (SELECT COUNT(*) FROM input_applications ia WHERE ia.cultivation_id = c.cultivation_id) AS spray_log_count
          FROM crop_batches cb
          JOIN harvest_records hr ON hr.harvest_id = cb.harvest_id
          JOIN cultivations c ON c.cultivation_id = hr.cultivation_id
          JOIN farmers f ON f.farmer_id = c.farmer_id
          JOIN farm_fields ff ON ff.field_id = c.field_id
          JOIN farmer_land_records flr ON flr.land_id = ff.land_id
          JOIN crop_varieties cv ON cv.variety_id = c.variety_id
          JOIN crops cr ON cr.crop_id = cv.crop_id
          JOIN crop_categories cc ON cc.category_id = cr.category_id
          LEFT JOIN crop_quality_tests cqt ON cqt.crop_batch_id = cb.crop_batch_id
          LEFT JOIN warehouse_inventory wi ON wi.crop_batch_id = cb.crop_batch_id
          LEFT JOIN warehouses w ON w.warehouse_id = wi.warehouse_id
         WHERE cb.batch_status IN ('READY_FOR_SALE', 'In Stock')
         ORDER BY FIELD(cb.batch_status, 'READY_FOR_SALE', 'In Stock'), cb.created_at DESC
        """
    )

    orders = query_all(
        """
        SELECT so.*, f.farmer_name, f.phone AS farmer_phone,
               sp.payment_id, sp.payment_status AS escrow_status, sp.payment_method, sp.transaction_reference,
               soi.sales_item_id, soi.crop_batch_id, soi.quantity, soi.unit_price, soi.subtotal,
               cb.batch_code, cb.qr_code, cb.batch_status, cb.quality_status,
               cr.crop_name, cv.variety_name,
               shp.shipment_id, shp.vehicle_number, shp.driver_name, shp.shipment_status,
               shp.source_location, shp.destination_location, shp.dispatch_date, shp.delivery_date,
               COALESCE((SELECT SUM(fca.total_credit_limit - fca.available_balance)
                           FROM farmer_credit_accounts fca
                          WHERE fca.farmer_id = so.farmer_id AND fca.account_status = 'Active'), 0) AS farmer_kcc_debt
          FROM sales_orders so
          JOIN farmers f ON f.farmer_id = so.farmer_id
          LEFT JOIN sales_payments sp ON sp.sales_order_id = so.sales_order_id
          LEFT JOIN sales_order_items soi ON soi.sales_order_id = so.sales_order_id
          LEFT JOIN crop_batches cb ON cb.crop_batch_id = soi.crop_batch_id
          LEFT JOIN harvest_records hr ON hr.harvest_id = cb.harvest_id
          LEFT JOIN cultivations c ON c.cultivation_id = hr.cultivation_id
          LEFT JOIN crop_varieties cv ON cv.variety_id = c.variety_id
          LEFT JOIN crops cr ON cr.crop_id = cv.crop_id
          LEFT JOIN shipments shp ON shp.crop_batch_id = cb.crop_batch_id
         WHERE so.buyer_id = %s
         ORDER BY so.order_date DESC
        """,
        (buyer_id,),
    )

    warehouses = query_all(
        """
        SELECT w.*,
               COALESCE(SUM(wi.quantity), 0) AS stored_quantity,
               COUNT(wi.crop_batch_id) AS batch_count
          FROM warehouses w
          LEFT JOIN warehouse_inventory wi ON wi.warehouse_id = w.warehouse_id
         GROUP BY w.warehouse_id
         ORDER BY w.district, w.warehouse_name
        """
    )

    all_batches_index = query_all(
        """
        SELECT cb.crop_batch_id, cb.batch_code, cb.qr_code, cr.crop_name, f.farmer_name
          FROM crop_batches cb
          JOIN harvest_records hr ON hr.harvest_id = cb.harvest_id
          JOIN cultivations c ON c.cultivation_id = hr.cultivation_id
          JOIN farmers f ON f.farmer_id = c.farmer_id
          JOIN crop_varieties cv ON cv.variety_id = c.variety_id
          JOIN crops cr ON cr.crop_id = cv.crop_id
         ORDER BY cb.created_at DESC
        """
    )

    selected_passport = None
    if passport_code:
        selected_passport = get_batch_passport(passport_code)
    elif marketplace_batches:
        selected_passport = get_batch_passport(marketplace_batches[0]["batch_code"])

    return {
        "buyer": buyer,
        "crop_categories": crop_categories,
        "marketplace_batches": marketplace_batches,
        "orders": orders,
        "warehouses": warehouses,
        "all_batches_index": all_batches_index,
        "passport": selected_passport,
    }


def get_batch_passport(code_or_id: str) -> dict | None:
    """Workflow 4: Retrieve full Agronomic Passport & EU/US Residue Audit for a batch QR/code."""
    term = (code_or_id or "").strip()
    if not term:
        return None
    batch = query_one(
        """
        SELECT cb.*, hr.harvest_date, hr.total_quantity AS harvest_qty, hr.remarks AS harvest_remarks,
               c.cultivation_id, c.sowing_date, c.expected_harvest_date, c.cultivation_status,
               f.farmer_id, f.farmer_name, f.phone AS farmer_phone,
               ff.field_id, ff.field_name, ff.field_area, ff.soil_type, ff.irrigation_type,
               flr.survey_number, flr.passbook_number, flr.village,
               cr.crop_name, cc.category_name, cv.variety_name, cv.duration_days,
               cs.season_name,
               cqt.moisture_percentage, cqt.quality_grade, cqt.test_date, cqt.test_result, cqt.remarks AS quality_remarks
          FROM crop_batches cb
          JOIN harvest_records hr ON hr.harvest_id = cb.harvest_id
          JOIN cultivations c ON c.cultivation_id = hr.cultivation_id
          JOIN farmers f ON f.farmer_id = c.farmer_id
          JOIN farm_fields ff ON ff.field_id = c.field_id
          JOIN farmer_land_records flr ON flr.land_id = ff.land_id
          JOIN crop_varieties cv ON cv.variety_id = c.variety_id
          JOIN crops cr ON cr.crop_id = cv.crop_id
          JOIN crop_categories cc ON cc.category_id = cr.category_id
          JOIN cultivation_seasons cs ON cs.season_id = c.season_id
          LEFT JOIN crop_quality_tests cqt ON cqt.crop_batch_id = cb.crop_batch_id
         WHERE cb.crop_batch_id = %s OR cb.batch_code = %s OR cb.qr_code = %s
         LIMIT 1
        """,
        (term, term, term),
    )
    if not batch:
        return None

    applications = query_all(
        """
        SELECT ia.*, ap.product_name, ap.product_type, ap.product_code,
               pb.batch_number, ac.company_name
          FROM input_applications ia
          JOIN agricultural_products ap ON ap.product_id = ia.product_id
          JOIN agro_companies ac ON ac.company_id = ap.company_id
          JOIN product_batches pb ON pb.product_batch_id = ia.product_batch_id
         WHERE ia.cultivation_id = %s
         ORDER BY ia.application_date ASC
        """,
        (batch["cultivation_id"],),
    )
    activities = query_all(
        """
        SELECT * FROM cultivation_activities
         WHERE cultivation_id = %s
         ORDER BY activity_date ASC
        """,
        (batch["cultivation_id"],),
    )
    soil = query_one(
        """
        SELECT * FROM soil_health_records
         WHERE field_id = %s
         ORDER BY test_date DESC LIMIT 1
        """,
        (batch["field_id"],),
    )
    events = query_all(
        """
        SELECT * FROM traceability_events
         WHERE crop_batch_id = %s
         ORDER BY event_date ASC
        """,
        (batch["crop_batch_id"],),
    )
    return {
        "batch": batch,
        "applications": applications,
        "activities": activities,
        "soil": soil,
        "events": events,
    }


def place_escrow_purchase_order(buyer_id: str, buyer_name: str, form: dict) -> dict:
    """Workflow 3: Place purchase order (SALES_ORDERS) and lock full value in Escrow (ESCROW_HELD)."""
    crop_batch_id = (form.get("crop_batch_id") or "").strip()
    quantity = float(form.get("quantity") or 0)
    unit_price = float(form.get("unit_price") or 0)
    delivery_address = (form.get("delivery_address") or "").strip()
    sales_channel = (form.get("sales_channel") or "Escrow Contract").strip()

    if not crop_batch_id or quantity <= 0 or unit_price <= 0 or not delivery_address:
        raise ValueError("Crop Batch, positive Quantity (kg), Unit Price (₹/kg), and Delivery Address are required.")

    batch = query_one(
        """
        SELECT cb.*, c.farmer_id, f.farmer_name, cr.crop_name
          FROM crop_batches cb
          JOIN harvest_records hr ON hr.harvest_id = cb.harvest_id
          JOIN cultivations c ON c.cultivation_id = hr.cultivation_id
          JOIN farmers f ON f.farmer_id = c.farmer_id
          JOIN crop_varieties cv ON cv.variety_id = c.variety_id
          JOIN crops cr ON cr.crop_id = cv.crop_id
         WHERE cb.crop_batch_id = %s
        """,
        (crop_batch_id,),
    )
    if not batch:
        raise ValueError("Selected crop batch not found.")
    avail = _f(batch["quantity"])
    if quantity > avail:
        raise ValueError(f"Requested {quantity} kg exceeds available batch quantity ({avail} kg).")

    total_amount = round(quantity * unit_price, 2)
    sales_order_id = gen_id("SO")
    sales_item_id = gen_id("SOI")
    payment_id = gen_id("SPAY")
    escrow_ref = gen_id("ESCROW", 8)

    with transaction() as cur:
        cur.execute(
            """
            INSERT INTO sales_orders
                (sales_order_id, farmer_id, buyer_id, delivery_address, order_date,
                 total_amount, payment_status, sales_channel, order_status)
            VALUES (%s, %s, %s, %s, NOW(), %s, 'ESCROW_HELD', %s, 'Placed')
            """,
            (sales_order_id, batch["farmer_id"], buyer_id, delivery_address, total_amount, sales_channel),
        )
        cur.execute(
            """
            INSERT INTO sales_order_items
                (sales_item_id, sales_order_id, crop_batch_id, quantity, unit_price)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (sales_item_id, sales_order_id, crop_batch_id, quantity, unit_price),
        )
        cur.execute(
            """
            INSERT INTO sales_payments
                (payment_id, sales_order_id, amount, payment_method, payment_date, payment_status, transaction_reference)
            VALUES (%s, %s, %s, 'Escrow Account Lock (RTGS)', NOW(), 'ESCROW_HELD', %s)
            """,
            (payment_id, sales_order_id, total_amount, escrow_ref),
        )
        cur.execute(
            """
            INSERT INTO traceability_events
                (event_id, crop_batch_id, event_type, location, event_date, description, recorded_by)
            VALUES (%s, %s, 'Escrow Contract & Price Locked', %s, NOW(), %s, %s)
            """,
            (
                gen_id("TRC"),
                crop_batch_id,
                delivery_address,
                f"Buyer {buyer_name} locked ₹{total_amount:,.2f} in Escrow ({escrow_ref}) for {quantity} kg of {batch['crop_name']}.",
                buyer_name,
            ),
        )
    return {
        "sales_order_id": sales_order_id,
        "escrow_ref": escrow_ref,
        "total_amount": total_amount,
        "farmer_name": batch["farmer_name"],
        "batch_code": batch["batch_code"],
    }


def book_transport_dispatch(buyer_id: str, buyer_name: str, form: dict) -> str:
    """Workflow 5: Buyer creates transport manifest -> shipments + shipment_items + IN_TRANSIT."""
    sales_order_id = (form.get("sales_order_id") or "").strip()
    vehicle_number = (form.get("vehicle_number") or "").strip()
    driver_name = (form.get("driver_name") or "").strip()
    source_location = (form.get("source_location") or "").strip()
    destination_location = (form.get("destination_location") or "").strip()

    if not sales_order_id or not vehicle_number or not driver_name or not source_location or not destination_location:
        raise ValueError("Sales Order, Vehicle Number, Driver Name, Source, and Destination are required.")

    order_row = query_one(
        """
        SELECT so.sales_order_id, soi.sales_item_id, soi.crop_batch_id, soi.quantity
          FROM sales_orders so
          JOIN sales_order_items soi ON soi.sales_order_id = so.sales_order_id
         WHERE so.sales_order_id = %s AND so.buyer_id = %s
         LIMIT 1
        """,
        (sales_order_id, buyer_id),
    )
    if not order_row:
        raise ValueError("Sales order item not found for your buyer account.")

    shipment_id = gen_id("SHP")
    crop_batch_id = order_row["crop_batch_id"]
    qty = _f(order_row["quantity"])

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
        cur.execute(
            """
            INSERT INTO shipment_items
                (shipment_item_id, shipment_id, crop_batch_id, sales_item_id, quantity)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (gen_id("SHPI"), shipment_id, crop_batch_id, order_row["sales_item_id"], qty),
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
            (crop_batch_id, qty),
        )
        winv = cur.fetchone()
        if winv:
            cur.execute(
                "UPDATE warehouse_inventory SET quantity = quantity - %s WHERE inventory_id = %s",
                (qty, winv["inventory_id"]),
            )
            cur.execute(
                """
                INSERT INTO stock_movements
                    (movement_id, warehouse_id, crop_batch_id, movement_type, quantity, movement_date, reference_id)
                VALUES (%s, %s, %s, 'OUT', %s, CURDATE(), %s)
                """,
                (gen_id("SM"), winv["warehouse_id"], crop_batch_id, qty, shipment_id),
            )
        cur.execute(
            """
            INSERT INTO traceability_events
                (event_id, crop_batch_id, event_type, location, event_date, description, recorded_by)
            VALUES (%s, %s, 'Buyer Truck Dispatched (IN_TRANSIT)', %s, NOW(), %s, %s)
            """,
            (
                gen_id("TRC"),
                crop_batch_id,
                source_location,
                f"Manifest {shipment_id}: Vehicle {vehicle_number} (Driver: {driver_name}) dispatched {qty} kg to {destination_location}.",
                buyer_name,
            ),
        )
    return shipment_id


def confirm_delivery_and_settle(buyer_id: str, buyer_name: str, sales_order_id: str) -> dict:
    """Workflow 6: Confirm mill delivery, release Escrow (COMPLETED), clear KCC debt & compute DBT payout."""
    if not sales_order_id:
        raise ValueError("Missing Sales Order ID.")

    with transaction() as cur:
        cur.execute(
            """
            SELECT so.*, f.farmer_name
              FROM sales_orders so
              JOIN farmers f ON f.farmer_id = so.farmer_id
             WHERE so.sales_order_id = %s AND so.buyer_id = %s
             FOR UPDATE
            """,
            (sales_order_id, buyer_id),
        )
        order = cur.fetchone()
        if not order:
            raise ValueError("Sales order not found for your buyer account.")
        if order["order_status"] == "Delivered" and order["payment_status"] == "Paid":
            raise ValueError("This sales order has already been delivered and settled.")

        gross_amount = _f(order["total_amount"])
        farmer_id = order["farmer_id"]

        # 1. Release Escrow -> COMPLETED
        cur.execute("SELECT payment_id FROM sales_payments WHERE sales_order_id = %s LIMIT 1 FOR UPDATE", (sales_order_id,))
        sp = cur.fetchone()
        if sp:
            cur.execute(
                "UPDATE sales_payments SET payment_status = 'COMPLETED', payment_date = NOW() WHERE payment_id = %s",
                (sp["payment_id"],),
            )
        else:
            cur.execute(
                """
                INSERT INTO sales_payments
                    (payment_id, sales_order_id, amount, payment_method, payment_date, payment_status, transaction_reference)
                VALUES (%s, %s, %s, 'Escrow Auto-Release', NOW(), 'COMPLETED', %s)
                """,
                (gen_id("SPAY"), sales_order_id, gross_amount, gen_id("DBT", 8)),
            )

        cur.execute(
            "UPDATE sales_orders SET order_status = 'Delivered', payment_status = 'Paid' WHERE sales_order_id = %s",
            (sales_order_id,),
        )

        # 2. Update shipments and crop_batches
        cur.execute(
            """
            SELECT soi.crop_batch_id
              FROM sales_order_items soi
             WHERE soi.sales_order_id = %s
            """,
            (sales_order_id,),
        )
        batch_rows = cur.fetchall()
        for br in batch_rows:
            cb_id = br["crop_batch_id"]
            cur.execute(
                """
                UPDATE shipments
                   SET shipment_status = 'Delivered', delivery_date = NOW()
                 WHERE crop_batch_id = %s AND shipment_status <> 'Delivered'
                """,
                (cb_id,),
            )
            cur.execute(
                "UPDATE crop_batches SET batch_status = 'DELIVERED' WHERE crop_batch_id = %s",
                (cb_id,),
            )

        # 3. Smart Debt-Clearing Credit Offset against farmer_credit_accounts
        cur.execute(
            """
            SELECT * FROM farmer_credit_accounts
             WHERE farmer_id = %s AND account_status = 'Active'
             ORDER BY (total_credit_limit - available_balance) DESC
             FOR UPDATE
            """,
            (farmer_id,),
        )
        kcc_accounts = cur.fetchall()
        remaining_payout = gross_amount
        total_debt_before = 0.0
        total_offset = 0.0

        for kcc in kcc_accounts:
            limit_amt = _f(kcc["total_credit_limit"])
            avail_amt = _f(kcc["available_balance"])
            debt = max(0.0, round(limit_amt - avail_amt, 2))
            total_debt_before += debt
            if debt > 0 and remaining_payout > 0:
                repay = min(debt, remaining_payout)
                new_avail = round(avail_amt + repay, 2)
                cur.execute(
                    "UPDATE farmer_credit_accounts SET available_balance = %s WHERE credit_account_id = %s",
                    (new_avail, kcc["credit_account_id"]),
                )
                total_offset = round(total_offset + repay, 2)
                remaining_payout = round(remaining_payout - repay, 2)

        net_dbt = round(gross_amount - total_offset, 2)

        for br in batch_rows:
            cur.execute(
                """
                INSERT INTO traceability_events
                    (event_id, crop_batch_id, event_type, location, event_date, description, recorded_by)
                VALUES (%s, %s, 'Delivery Confirmed & Credit Offset Settled', %s, NOW(), %s, %s)
                """,
                (
                    gen_id("TRC"),
                    br["crop_batch_id"],
                    order["delivery_address"] or "Buyer Receiving Dock",
                    f"Escrow COMPLETED (₹{gross_amount:,.2f}). Smart KCC Debt Offset: ₹{total_offset:,.2f}. Net DBT Payout to {order['farmer_name']}: ₹{net_dbt:,.2f}.",
                    buyer_name,
                ),
            )

    return {
        "sales_order_id": sales_order_id,
        "farmer_name": order["farmer_name"],
        "gross_amount": gross_amount,
        "kcc_debt_before": round(total_debt_before, 2),
        "offset_deducted": total_offset,
        "net_dbt_payout": net_dbt,
    }
