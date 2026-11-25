"""HTML fragment builders (XSS-safe via MarkupSafe) for AgriChain portals."""

from decimal import Decimal
from markupsafe import Markup
from config import QUOTA_RULES_PER_ACRE, get_retail_unit_price
from templating import h


def _num(val, default=0.0) -> float:
    if val is None:
        return default
    if isinstance(val, Decimal):
        return float(val)
    return float(val)


def _money(val) -> str:
    return f"{_num(val):,.2f}"


def serialize_context_fragments(ctx: dict) -> dict[str, str]:
    """Convert template context Markup/values into plain strings for JSON API patches."""
    return {k: str(v) for k, v in ctx.items()}


def status_badge(text: str | None) -> Markup:
    val = str(text or "Unknown")
    upper = val.upper()
    if upper in ("VERIFIED", "VERIFIED_BY_VAA", "APPROVED", "ACTIVE", "PAID", "COMPLETED", "DELIVERED", "PASSED", "READY_FOR_SALE", "RECEIVED", "FULFILLED", "CONFIRMED", "IN"):
        cls = "badge-green"
    elif upper in ("PENDING", "UNDER VERIFICATION", "ORDERED", "PARTIALLY RECEIVED", "ESCROW_HELD", "PLACED", "SOWN", "GROWING", "IN STOCK", "SCHEDULED", "PARTIAL"):
        cls = "badge-gold"
    elif upper in ("IN_TRANSIT", "IN TRANSIT", "SHIPPED", "HARVESTED", "PROCESSING"):
        cls = "badge-blue"
    elif upper in ("FAILED", "REJECTED", "CANCELLED", "EXPIRED", "SUSPENDED", "REVOKED", "OUT"):
        cls = "badge-red"
    else:
        cls = "badge-gray"
    return Markup(f'<span class="badge {cls}">{h(val)}</span>')


def build_rbk_context(session: dict, data: dict, query_args: dict, pos_receipt: dict | None, qr_cert: dict | None) -> dict:
    """Build template context dictionary for templates/rbk_home.html."""
    centre = data["centre"] or {}
    inv = data["inventory"]
    total_units = sum(_num(r["quantity"]) for r in inv)
    pending_supply_ids = {r["supply_id"] for r in data["supply_orders"] if r["status"] in ("Ordered", "Partially Received")}
    pending_ccrc_cnt = sum(1 for r in data["ccrc_records"] if r["approval_status"] in ("Pending", "Under Verification"))

    selected_wiz_farmer = query_args.get("farmer_id", "")

    div_opts = []
    for d in data["divisions"]:
        div_opts.append(
            f'<option value="{h(d["region_id"])}" '
            f'data-state="{h(d["state_name"])}" data-district="{h(d["district_name"])}" '
            f'data-mandal="{h(d["mandal_name"])}" data-village="{h(d["village_name"])}" '
            f'data-pincode="{h(d["pincode"])}">'
            f'{h(d["district_name"])} &bull; {h(d["mandal_name"])} &bull; {h(d["village_name"])} ({h(d["pincode"])})'
            f"</option>"
        )

    wiz_farmer_opts = []
    farmer_opts = []
    pos_farmer_opts = []
    for f in data["farmers"]:
        sel = " selected" if f["farmer_id"] == selected_wiz_farmer else ""
        label = f"{f['farmer_name']} ({f['farmer_id']} - {f['phone']})"
        wiz_farmer_opts.append(f'<option value="{h(f["farmer_id"])}"{sel}>{h(label)}</option>')
        farmer_opts.append(f'<option value="{h(f["farmer_id"])}">{h(label)}</option>')
        aadhaar_last4 = str(f.get("aadhaar_number") or "")[-4:]
        pos_farmer_opts.append(
            f'<option value="{h(f["farmer_id"])}" '
            f'data-acres="{h(f["verified_acres"])}" '
            f'data-bio="{h(f["biometric_status"] or "Pending")}" '
            f'data-aadhaar="{h(aadhaar_last4)}" '
            f'data-kcc="{h(f["kcc_balance"])}">'
            f'{h(f["farmer_name"])} ({h(f["farmer_id"])}) &mdash; {h(f["verified_acres"])} ac [{h(f["biometric_status"] or "Pending")}]'
            f"</option>"
        )

    supply_rows = []
    for s in data["supply_orders"]:
        ordered = _num(s["ordered_quantity"])
        if s["status"] in ("Ordered", "Partially Received"):
            default_rec = max(0, ordered - 2) if ordered >= 20 else ordered
            default_rej = ordered - default_rec
            action_cell = (
                f'<form method="POST" action="/rbk/supply/confirm" data-supply-row data-ordered="{ordered}">'
                f'<input type="hidden" name="supply_id" value="{h(s["supply_id"])}">'
                f'<input type="hidden" name="item_id" value="{h(s["item_id"])}">'
                f'<div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;">'
                f'<label style="margin:0;font-size:0.75rem;">Accept:<input type="number" step="1" min="0" max="{ordered}" name="received_quantity" value="{default_rec:g}" data-received-input style="width:76px;padding:5px;"></label>'
                f'<label style="margin:0;font-size:0.75rem;">Reject:<input type="number" step="1" min="0" max="{ordered}" name="rejected_quantity" value="{default_rej:g}" data-rejected-input style="width:66px;padding:5px;"></label>'
                f'<button type="submit" class="btn btn-primary btn-sm">Confirm Delivery</button>'
                f"</div></form>"
            )
        else:
            action_cell = f'Accepted: <strong>{_num(s["received_quantity"]):g}</strong> | Rejected: <strong>{_num(s["rejected_quantity"]):g}</strong>'
        supply_rows.append(
            f'<tr><td><code class="mono">{h(s["supply_id"])}</code></td>'
            f'<td>{h(s["company_name"])}</td>'
            f'<td><strong>{h(s["product_name"])}</strong><br><span class="text-muted">Batch: {h(s["batch_number"])}</span></td>'
            f'<td>{ordered:g} {h(s["unit"])}</td>'
            f'<td>{status_badge(s["status"])}</td>'
            f'<td>{action_cell}</td></tr>'
        )

    comp_opts = [f'<option value="{h(c["company_id"])}">{h(c["company_name"])}</option>' for c in data["companies"]]
    all_batch_opts = [
        f'<option value="{h(b["product_batch_id"])}">{h(b["product_name"])} &bull; Lot: {h(b["batch_number"])} ({h(b["company_name"])})</option>'
        for b in data["product_batches"]
    ]

    inv_rows = [
        f'<tr><td><strong>{h(r["product_name"])}</strong><br><span class="text-muted">{h(r["product_type"])}</span></td>'
        f'<td><code class="mono">{h(r["batch_number"])}</code></td>'
        f'<td>{h(r["company_name"])}</td>'
        f'<td><strong>{_num(r["quantity"]):g}</strong> {h(r["unit"])}</td>'
        f'<td>&#8377;{_money(r["price"])}</td></tr>'
        for r in inv
    ]

    mov_rows = [
        f'<tr><td>{h(m["movement_date"])}</td><td>{status_badge(m["movement_type"])}</td>'
        f'<td>{h(m["product_name"])}<br><code class="mono text-muted">{h(m["batch_number"])}</code></td>'
        f'<td><strong>{_num(m["quantity"]):g}</strong></td>'
        f'<td><code class="mono">{h(m["reference_id"])}</code><br><span class="text-muted">{h(m["employee_name"])}</span></td></tr>'
        for m in data["stock_movements"]
    ]

    ccrc_rows = []
    for c in data["ccrc_records"]:
        clause = "Non-Encumbrance Guaranteed" if c["non_encumbrance_clause"] else "Pending Clause"
        if c["approval_status"] in ("Pending", "Under Verification"):
            act = (
                f'<form method="POST" action="/rbk/ccrc/verify" style="display:flex;gap:6px;flex-wrap:wrap;align-items:center;">'
                f'<input type="hidden" name="tenure_id" value="{h(c["tenure_id"])}">'
                f'<input type="hidden" name="agreement_type" value="{h(c["agreement_type"])}">'
                f'<input type="hidden" name="lease_months" value="11">'
                f'<label style="margin:0;font-size:0.75rem;display:flex;gap:4px;align-items:center;"><input type="checkbox" name="non_encumbrance_clause" value="1" checked style="width:auto;"> Non-Encumbrance</label>'
                f'<label style="margin:0;font-size:0.75rem;display:flex;gap:4px;align-items:center;"><input type="checkbox" name="owner_consent" value="1" checked style="width:auto;"> Owner OTP/Bio</label>'
                f'<button type="submit" name="decision" value="VERIFIED_BY_VAA" class="btn btn-primary btn-sm">Verify (VERIFIED_BY_VAA)</button>'
                f'</form>'
            )
        else:
            act = status_badge(c["approval_status"])
        ccrc_rows.append(
            f'<tr><td><code class="mono">{h(c["tenure_id"])}</code></td>'
            f'<td><strong>{h(c["survey_number"])}</strong> ({_num(c["land_area"]):g} ac)<br><span class="text-muted">{h(c["village"])}</span></td>'
            f'<td>{h(c["owner_name"])}</td>'
            f'<td><strong>{h(c["tenant_name"])}</strong><br><span class="text-muted">{h(c["tenant_phone"])}</span></td>'
            f'<td>{h(c["lease_expiry_date"])}<br><span class="text-muted">{h(clause)}</span></td>'
            f'<td>{act}</td></tr>'
        )

    land_opts = [
        f'<option value="{h(l["land_id"])}">{h(l["survey_number"])} &bull; {h(l["village"])} ({_num(l["land_area"]):g} ac) &mdash; Owner: {h(l["farmer_name"])}</option>'
        for l in data["land_records"]
    ]

    pos_inv_opts = []
    for r in inv:
        if _num(r["quantity"]) <= 0:
            continue
        per_acre = QUOTA_RULES_PER_ACRE.get(r["product_type"] or "Nitrogenous", 2.0)
        retail_p = get_retail_unit_price(r["product_id"], _num(r["price"]))
        pos_inv_opts.append(
            f'<option value="{h(r["product_batch_id"])}" '
            f'data-price="{_num(r["price"])}" data-retail="{retail_p}" '
            f'data-per-acre="{per_acre}" data-stock="{_num(r["quantity"])}" data-unit="{h(r["unit"])}">'
            f'{h(r["product_name"])} | Lot {h(r["batch_number"])} | Stock: {_num(r["quantity"]):g} | &#8377;{_money(r["price"])}'
            f"</option>"
        )

    kcc_opts = [
        f'<option value="{h(k["credit_account_id"])}">{h(k["farmer_name"])} &bull; {h(k["kcc_card_number"])} (Avail: &#8377;{_money(k["available_balance"])})</option>'
        for k in data["credit_accounts"]
    ]

    pos_receipt_html = Markup("")
    if pos_receipt:
        pos_receipt_html = Markup(
            f'<div class="receipt-box">'
            f'<div style="display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;">'
            f'<div><strong style="font-size:1.08rem;">RBK Subsidized Input Receipt #{h(pos_receipt["purchase_id"])}</strong>'
            f'<div class="text-muted">Farmer: {h(pos_receipt["farmer_name"])} ({h(pos_receipt["verified_acres"])} verified acres) &bull; Batch: {h(pos_receipt["batch_number"])}</div></div>'
            f'<button type="button" onclick="window.print()" class="btn btn-outline btn-sm no-print">Print Receipt</button>'
            f'</div>'
            f'<div class="mt-1">Item: <strong>{h(pos_receipt["product_name"])}</strong> &times; {_num(pos_receipt["quantity"]):g} {h(pos_receipt["unit"])} '
            f'&bull; Paid via <strong>{h(pos_receipt["payment_method"])}</strong> (Ref: <code class="mono">{h(pos_receipt["transaction_reference"])}</code>)</div>'
            f'<div class="savings-highlight">You paid &#8377;{_money(pos_receipt["total_amount"])} via RBK. You saved &#8377;{_money(pos_receipt["savings"])} over private retail market price (&#8377;{_money(pos_receipt["retail_total"])}).</div>'
            f'</div>'
        )

    purchase_rows = [
        f'<tr><td><code class="mono">{h(p["purchase_id"])}</code></td><td>{h(p["purchase_date"])}</td>'
        f'<td>{h(p["farmer_name"])}</td><td>{h(p["items_text"])}</td>'
        f'<td><strong>&#8377;{_money(p["total_amount"])}</strong></td>'
        f'<td>{h(p["payment_method"])}<br><span class="text-muted mono">{h(p["transaction_reference"])}</span></td></tr>'
        for p in data["recent_purchases"]
    ]

    cult_opts = [
        f'<option value="{h(c["cultivation_id"])}">{h(c["farmer_name"])} &bull; {h(c["crop_name"])} ({h(c["variety_name"])}) @ {h(c["field_name"])} [{h(c["season_name"])}]</option>'
        for c in data["cultivations"]
    ]

    adv_rows = [
        f'<tr><td>{h(a["application_date"])}</td><td><strong>{h(a["farmer_name"])}</strong><br><span class="text-muted">{h(a["field_name"])}</span></td>'
        f'<td>{h(a["crop_name"])}</td><td><strong>{h(a["product_name"])}</strong><br><code class="mono text-muted">{h(a["batch_number"])}</code></td>'
        f'<td>{_num(a["quantity_used"]):g} &bull; {h(a["application_method"])}</td><td>{h(a["remarks"])}</td></tr>'
        for a in data["advisories"]
    ]

    certified_qr_html = Markup("")
    if qr_cert:
        certified_qr_html = Markup(
            f'<div class="card" style="background:#f0fdf4;border-color:#16a34a;">'
            f'<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:14px;">'
            f'<div class="qr-sticker">'
            f'<div class="qr-box" data-qr-code="{h(qr_cert["qr_code"])}"></div>'
            f'<div><div style="font-weight:800;font-size:1.05rem;">{h(qr_cert["batch_code"])}</div>'
            f'<div class="mono" style="font-size:0.8rem;">{h(qr_cert["qr_code"])}</div>'
            f'<div class="mt-1">Grade: <strong>{h(qr_cert["quality_grade"])}</strong> &bull; Moisture: <strong>{h(qr_cert["moisture_percentage"])}%</strong> &bull; {_num(qr_cert["quantity"]):g} kg</div>'
            f'<div class="mt-1">{status_badge(qr_cert["batch_status"])}</div></div></div>'
            f'<button type="button" onclick="window.print()" class="btn btn-primary btn-sm no-print">Print Thermal QR Sticker</button>'
            f'</div></div>'
        )

    wh_opts = [
        f'<option value="{h(w["warehouse_id"])}">{h(w["warehouse_name"])} ({h(w["district"])})</option>'
        for w in data["warehouses"]
    ]

    dispatch_rows = [
        f'<tr><td><code class="mono">{h(o["sales_order_id"])}</code><br><span class="text-muted">{h(o["order_date"])}</span></td>'
        f'<td><strong>{h(o["buyer_name"])}</strong><br>{h(o["crop_name"])} (<code class="mono">{h(o["batch_code"])}</code>)</td>'
        f'<td>{_num(o["quantity"]):g} kg</td>'
        f'<td>{status_badge(o["order_status"])}<br>{status_badge(o["payment_status"])}</td>'
        f'<td><form method="POST" action="/rbk/dispatch" style="display:flex;gap:6px;flex-wrap:wrap;align-items:center;">'
        f'<input type="hidden" name="sales_order_id" value="{h(o["sales_order_id"])}">'
        f'<input type="hidden" name="sales_item_id" value="{h(o["sales_item_id"])}">'
        f'<input type="hidden" name="crop_batch_id" value="{h(o["crop_batch_id"])}">'
        f'<input type="hidden" name="quantity" value="{_num(o["quantity"])}">'
        f'<input type="hidden" name="source_location" value="{h(centre.get("rbk_name", "RBK Yard"))}">'
        f'<input type="hidden" name="destination_location" value="{h(o["delivery_address"] or o["buyer_name"])}">'
        f'<input type="text" name="vehicle_number" placeholder="AP-16-TX-9988" required style="width:130px;padding:6px;">'
        f'<input type="text" name="driver_name" placeholder="Driver Name" required style="width:120px;padding:6px;">'
        f'<button type="submit" class="btn btn-primary btn-sm">Scan QR &amp; Dispatch</button>'
        f'</form></td></tr>'
        for o in data["pending_dispatches"]
    ]

    batch_cards = [
        f'<div class="qr-sticker qr-sticker-interactive" style="justify-content:flex-start;width:100%;">'
        f'<div class="qr-box" data-qr-code="{h(cb["qr_code"])}"></div>'
        f'<div style="min-width:0;flex:1;">'
        f'<div style="font-weight:700;font-size:0.9rem;">{h(cb["crop_name"])} &bull; {h(cb["variety_name"])}</div>'
        f'<div class="mono" style="font-size:0.78rem;">{h(cb["batch_code"])}</div>'
        f'<div class="text-muted">{h(cb["farmer_name"])} ({h(cb["village"])})</div>'
        f'<div style="font-size:0.82rem;margin:4px 0;">{_num(cb["quantity"]):g} {h(cb["unit"])} &bull; Moisture: {h(cb["moisture_percentage"] or "-")}% &bull; {h(cb["quality_grade"] or cb["quality_status"])}</div>'
        f'<div style="display:flex;align-items:center;justify-content:space-between;gap:8px;margin-top:6px;">'
        f'{status_badge(cb["batch_status"])}'
        f'<button type="button" class="btn btn-outline btn-sm" data-audit-qr="{h(cb["batch_code"])}">Inspect Passport</button>'
        f'</div></div></div>'
        for cb in data["crop_batches"]
    ]

    preorder_rows = [
        f'<tr><td><code class="mono">{h(p["preorder_number"])}</code></td>'
        f'<td>{h(p["farmer_name"])}<br><span class="text-muted">{h(p["phone"])}</span></td>'
        f'<td>{h(p["target_season"])} ({h(p["target_year"])})</td>'
        f'<td>{h(p["items_summary"] or "-")}</td>'
        f'<td>{status_badge(p["order_status"])}</td>'
        f'<td><form method="POST" action="/rbk/preorder/status" style="display:flex;gap:5px;">'
        f'<input type="hidden" name="preorder_id" value="{h(p["preorder_id"])}">'
        f'<button type="submit" name="order_status" value="Confirmed" class="btn btn-outline btn-sm">Confirm</button>'
        f'<button type="submit" name="order_status" value="Fulfilled" class="btn btn-primary btn-sm">Fulfill</button>'
        f'</form></td></tr>'
        for p in data["pre_bookings"]
    ]

    farmer_dir_rows = [
        f'<tr><td><code class="mono">{h(f["farmer_id"])}</code></td>'
        f'<td><strong>{h(f["farmer_name"])}</strong><br><span class="text-muted">{h(f["village"] or "-")}, {h(f["district"] or "-")}</span></td>'
        f'<td>{h(f["phone"])}</td>'
        f'<td>{status_badge(f["biometric_status"] or "Pending")}<br><span class="text-muted mono">{h(f["aadhaar_number"] or "")}</span></td>'
        f'<td><strong>{h(f["verified_acres"])} ac</strong><br><span class="text-muted">(Leased-in: {h(f["leased_in_acres"])} ac)</span></td>'
        f'<td>&#8377;{_money(f["kcc_balance"])}</td></tr>'
        for f in data["farmers"]
    ]

    return {
        "rbk_id": session.get("rbk_id", ""),
        "rbk_name": centre.get("rbk_name", session.get("rbk_name", "RBK Center")),
        "employee_name": session.get("name", ""),
        "designation": session.get("designation", ""),
        "district": centre.get("district", session.get("district", "")),
        "kpi_inv_count": str(len(inv)),
        "kpi_inv_units": f"{total_units:g}",
        "kpi_pending_supply": str(len(pending_supply_ids)),
        "kpi_pending_ccrc": str(pending_ccrc_cnt),
        "kpi_crop_batches": str(len(data["crop_batches"])),
        "division_options": Markup("".join(div_opts)),
        "wizard_farmer_options": Markup("".join(wiz_farmer_opts)),
        "farmer_options": Markup("".join(farmer_opts)),
        "pos_farmer_options": Markup("".join(pos_farmer_opts)),
        "supply_orders_rows": Markup("".join(supply_rows) or '<tr><td colspan="6" class="text-muted">No supply orders found.</td></tr>'),
        "company_options": Markup("".join(comp_opts)),
        "all_batch_options": Markup("".join(all_batch_opts)),
        "rbk_inventory_rows": Markup("".join(inv_rows) or '<tr><td colspan="5" class="text-muted">No inventory stocked.</td></tr>'),
        "stock_movement_rows": Markup("".join(mov_rows) or '<tr><td colspan="5" class="text-muted">No stock movements logged.</td></tr>'),
        "ccrc_rows": Markup("".join(ccrc_rows) or '<tr><td colspan="6" class="text-muted">No tenant leases recorded.</td></tr>'),
        "land_record_options": Markup("".join(land_opts)),
        "pos_receipt_html": pos_receipt_html,
        "pos_inventory_options": Markup("".join(pos_inv_opts)),
        "kcc_options": Markup("".join(kcc_opts)),
        "recent_purchase_rows": Markup("".join(purchase_rows) or '<tr><td colspan="6" class="text-muted">No purchases yet.</td></tr>'),
        "cultivation_options": Markup("".join(cult_opts)),
        "advisory_rows": Markup("".join(adv_rows) or '<tr><td colspan="6" class="text-muted">No field advisories logged yet.</td></tr>'),
        "certified_qr_html": certified_qr_html,
        "warehouse_options": Markup("".join(wh_opts)),
        "pending_dispatch_rows": Markup("".join(dispatch_rows) or '<tr><td colspan="5" class="text-muted">No buyer orders awaiting truck dispatch.</td></tr>'),
        "crop_batch_cards": Markup("".join(batch_cards) or '<p class="text-muted">No crop batches certified yet.</p>'),
        "preorder_rows": Markup("".join(preorder_rows) or '<tr><td colspan="6" class="text-muted">No pre-bookings for this RBK.</td></tr>'),
        "farmer_directory_rows": Markup("".join(farmer_dir_rows)),
    }


def build_farmer_context(session: dict, data: dict) -> dict:
    """Build template context dictionary for templates/farmer_home.html."""
    p = data["profile"] or {}
    total_acres = sum(_num(l["land_area"]) for l in data["land_records"] if l["ownership_type"] != "Leased Out")
    kcc_avail = sum(_num(c["available_balance"]) for c in data["credit_accounts"] if c["account_status"] == "Active")
    kcc_limit = sum(_num(c["total_credit_limit"]) for c in data["credit_accounts"] if c["account_status"] == "Active")
    kcc_debt = sum(_num(c["outstanding_debt"]) for c in data["credit_accounts"] if c["account_status"] == "Active")

    seen_pur = set()
    input_spend = 0.0
    for r in data["input_purchases"]:
        if r["purchase_id"] not in seen_pur:
            seen_pur.add(r["purchase_id"])
            input_spend += _num(r["total_amount"])

    seen_so = set()
    sales_rev = 0.0
    for s in data["buyer_orders"]:
        if s["sales_order_id"] not in seen_so:
            seen_so.add(s["sales_order_id"])
            sales_rev += _num(s["total_amount"])

    profile_html = Markup(
        f'<div class="table-wrap"><table><tbody>'
        f'<tr><th>Farmer ID</th><td><code class="mono">{h(p.get("farmer_id"))}</code></td></tr>'
        f'<tr><th>Full Name</th><td><strong>{h(p.get("farmer_name"))}</strong></td></tr>'
        f'<tr><th>Date of Birth / Gender</th><td>{h(p.get("dob") or "-")} &bull; {h(p.get("gender") or "-")}</td></tr>'
        f'<tr><th>Mobile / Email</th><td>{h(p.get("phone"))} &bull; {h(p.get("email") or "-")}</td></tr>'
        f'<tr><th>Biometric Auth</th><td>{status_badge(p.get("biometric_status") or "Pending")} ({h(p.get("biometric_type") or "-")}) &bull; <code class="mono">{h(p.get("aadhaar_number") or "-")}</code></td></tr>'
        f'<tr><th>Registered Since</th><td>{h(p.get("registration_date"))}</td></tr>'
        f'</tbody></table></div>'
    )

    addr_rows = [
        f'<tr><td>{status_badge(a["address_type"])}</td><td>{h(a["house_number"] or "-")}</td>'
        f'<td>{h(a["village"])}, {h(a["mandal"])}</td><td>{h(a["district"])}, {h(a["state"])} - {h(a["pincode"])}</td></tr>'
        for a in data["addresses"]
    ]
    credit_rows = []
    for c in data["credit_accounts"]:
        limit_val = _num(c["total_credit_limit"])
        avail_val = _num(c["available_balance"])
        debt_val = _num(c["outstanding_debt"])
        used_pct = min(100.0, max(0.0, round((debt_val / limit_val) * 100, 1))) if limit_val > 0 else 0.0
        credit_rows.append(
            f'<tr><td><strong>{h(c["institution_name"])}</strong>'
            f'<div class="meter-track mt-1" title="Utilization: {used_pct:g}%"><div class="meter-fill {"meter-warn" if used_pct > 70 else ""}" style="width:{used_pct}%"></div></div>'
            f'<div class="text-muted">{used_pct:g}% utilized</div></td>'
            f'<td><code class="mono">{h(c["kcc_card_number"])}</code></td>'
            f'<td>&#8377;{_money(limit_val)}</td><td style="color:#15803d;font-weight:700;">&#8377;{_money(avail_val)}</td>'
            f'<td style="color:#b91c1c;font-weight:700;">&#8377;{_money(debt_val)}</td>'
            f'<td>{h(c["repayment_due_date"] or "-")}</td><td>{status_badge(c["account_status"])}</td></tr>'
        )
    land_rows = [
        f'<tr><td><strong>{h(l["survey_number"])}</strong></td><td><code class="mono">{h(l["passbook_number"])}</code></td>'
        f'<td>{_num(l["land_area"]):g} ac</td><td>{status_badge(l["ownership_type"])}</td>'
        f'<td>{h(l["village"])}</td><td>{h(l["verified_by"] or "-")}</td></tr>'
        for l in data["land_records"]
    ]
    field_rows = [
        f'<tr><td><strong>{h(ff["field_name"])}</strong></td><td>{h(ff["survey_number"])} ({h(ff["village"])})</td>'
        f'<td>{_num(ff["field_area"]):g} ac</td><td>{h(ff["soil_type"] or "-")}</td>'
        f'<td>{h(ff["irrigation_type"] or "-")}</td><td>{status_badge(ff["access_role"])}</td></tr>'
        for ff in data["farm_fields"]
    ]
    lease_rows = [
        f'<tr><td>{status_badge(l["farmer_lease_role"])}</td>'
        f'<td><strong>{h(l["survey_number"])}</strong> ({_num(l["land_area"]):g} ac) - {h(l["village"])}</td>'
        f'<td>{h(l["owner_name"])}</td><td>{h(l["tenant_name"])}</td>'
        f'<td>{h(l["agreement_type"])}</td>'
        f'<td>{"Yes (Title Protected)" if l["non_encumbrance_clause"] else "No"}</td>'
        f'<td>{h(l["lease_expiry_date"])}</td><td>{status_badge(l["approval_status"])}</td></tr>'
        for l in data["seasonal_rights"]
    ]
    soil_rows = []
    for s in data["soil_health"]:
        ph = _num(s["ph_level"], 7.0)
        ph_state = "Optimal" if 6.0 <= ph <= 7.8 else ("Acidic" if ph < 6.0 else "Alkaline")
        ph_cls = "badge-green" if ph_state == "Optimal" else "badge-gold"
        soil_rows.append(
            f'<tr><td>{h(s["test_date"])}</td><td><strong>{h(s["field_name"])}</strong> ({h(s["survey_number"])})</td>'
            f'<td><strong>{h(s["ph_level"])}</strong> <span class="badge {ph_cls}">{ph_state}</span></td>'
            f'<td>{h(s["organic_carbon"])}%</td>'
            f'<td>{h(s["nitrogen_kg_ha"])}</td><td>{h(s["phosphorus_kg_ha"])}</td><td>{h(s["potassium_kg_ha"])}</td></tr>'
        )
    cult_rows = [
        f'<tr><td><code class="mono">{h(c["cultivation_id"])}</code></td><td>{h(c["season_name"])}</td>'
        f'<td>{h(c["field_name"])}</td><td><strong>{h(c["crop_name"])}</strong><br><span class="text-muted">{h(c["variety_name"])}</span></td>'
        f'<td>{h(c["sowing_date"])}</td><td>{h(c["expected_harvest_date"] or "-")}</td>'
        f'<td>&#8377;{_money(c["total_activity_expense"])}</td><td>{status_badge(c["cultivation_status"])}</td></tr>'
        for c in data["cultivations"]
    ]
    act_rows = [
        f'<tr><td>{h(a["activity_date"])}</td><td>{h(a["field_name"])}<br><span class="text-muted">{h(a["crop_name"])}</span></td>'
        f'<td><strong>{h(a["activity_type"])}</strong></td><td>{h(a["description"] or "-")}</td>'
        f'<td>&#8377;{_money(a["expense"])}</td></tr>'
        for a in data["cultivation_activities"]
    ]
    used_rows = [
        f'<tr><td>{h(u["application_date"])}</td><td>{h(u["season_name"])}<br><span class="text-muted">{h(u["crop_name"])} @ {h(u["field_name"])}</span></td>'
        f'<td><strong>{h(u["product_name"])}</strong><br><span class="text-muted">{h(u["company_name"])}</span></td>'
        f'<td><code class="mono">{h(u["batch_number"])}</code></td>'
        f'<td>{_num(u["quantity_used"]):g} {h(u["unit"])}</td>'
        f'<td>{h(u["application_method"] or "-")}<br><span class="text-muted">{h(u["remarks"] or "")}</span></td></tr>'
        for u in data["seasonal_inputs_used"]
    ]
    pre_rows = [
        f'<tr><td><code class="mono">{h(pr["preorder_number"])}</code></td><td>{h(pr["rbk_name"])}</td>'
        f'<td>{h(pr["target_season"])} ({h(pr["target_year"])})</td>'
        f'<td><strong>{h(pr["product_name"] or "-")}</strong></td>'
        f'<td>{_num(pr["requested_quantity"]):g} {h(pr["unit"] or "")}</td>'
        f'<td>&#8377;{_money(_num(pr["requested_quantity"]) * _num(pr["price"]))}</td>'
        f'<td>{status_badge(pr["order_status"])}</td></tr>'
        for pr in data["pre_bookings"]
    ]
    pur_rows = [
        f'<tr><td><code class="mono">{h(ip["purchase_id"])}</code><br><span class="text-muted">{h(ip["purchase_date"])}</span></td>'
        f'<td>{h(ip["rbk_name"])}</td>'
        f'<td><strong>{h(ip["product_name"] or "-")}</strong><br><code class="mono text-muted">{h(ip["batch_number"] or "")}</code></td>'
        f'<td>{_num(ip["quantity"]):g} &times; &#8377;{_money(ip["unit_price"])}</td>'
        f'<td><strong>&#8377;{_money(ip["subtotal"] or ip["total_amount"])}</strong></td>'
        f'<td>{h(ip["payment_method"] or "-")}<br><code class="mono text-muted">{h(ip["transaction_reference"] or "")}</code></td>'
        f'<td>{status_badge(ip["purchase_status"])}</td></tr>'
        for ip in data["input_purchases"]
    ]
    bo_rows = [
        f'<tr><td><code class="mono">{h(o["sales_order_id"])}</code><br><span class="text-muted">{h(o["order_date"])}</span></td>'
        f'<td><strong>{h(o["buyer_name"])}</strong><br>{status_badge(o["buyer_type"])}</td>'
        f'<td>{h(o["crop_name"] or "-")} ({h(o["variety_name"] or "-")})<br><code class="mono text-muted">{h(o["batch_code"] or "")}</code> {status_badge(o["quality_status"] or "-")}</td>'
        f'<td>{_num(o["quantity"]):g} kg &times; &#8377;{_money(o["unit_price"])}</td>'
        f'<td><strong>&#8377;{_money(o["total_amount"])}</strong></td>'
        f'<td>{status_badge(o["escrow_status"] or o["payment_status"])}<br><span class="text-muted">{h(o["payment_method"] or "")}</span></td>'
        f'<td>{status_badge(o["order_status"])}<br><span class="text-muted">{h(o["vehicle_number"] or "Pending truck")}</span></td></tr>'
        for o in data["buyer_orders"]
    ]

    return {
        "farmer_id": p.get("farmer_id", session.get("user_id", "")),
        "farmer_name": p.get("farmer_name", session.get("name", "")),
        "phone": p.get("phone", session.get("phone", "")),
        "biometric_status": p.get("biometric_status") or "Pending",
        "aadhaar_number": p.get("aadhaar_number") or "Not Linked",
        "kpi_kcc_avail": _money(kcc_avail),
        "kpi_total_acres": f"{total_acres:g}",
        "kpi_field_count": str(len(data["farm_fields"])),
        "kpi_kcc_debt": _money(kcc_debt),
        "kpi_kcc_limit": _money(kcc_limit),
        "kpi_input_spend": _money(input_spend),
        "kpi_prebook_count": str(len(data["pre_bookings"])),
        "kpi_sales_rev": _money(sales_rev),
        "kpi_sales_count": str(len(seen_so)),
        "profile_details_html": profile_html,
        "address_rows": Markup("".join(addr_rows) or '<tr><td colspan="4" class="text-muted">No addresses registered.</td></tr>'),
        "credit_rows": Markup("".join(credit_rows) or '<tr><td colspan="7" class="text-muted">No KCC credit accounts linked.</td></tr>'),
        "land_rows": Markup("".join(land_rows) or '<tr><td colspan="6" class="text-muted">No land records registered.</td></tr>'),
        "field_rows": Markup("".join(field_rows) or '<tr><td colspan="6" class="text-muted">No farm fields mapped.</td></tr>'),
        "lease_rows": Markup("".join(lease_rows) or '<tr><td colspan="8" class="text-muted">No seasonal cultivation lease records.</td></tr>'),
        "soil_rows": Markup("".join(soil_rows) or '<tr><td colspan="7" class="text-muted">No soil health test records yet.</td></tr>'),
        "farmer_field_options": Markup("".join(f'<option value="{h(ff["field_id"])}">{h(ff["field_name"])} ({_num(ff["field_area"]):g} ac - {h(ff["access_role"])})</option>' for ff in data["farm_fields"])),
        "variety_options": Markup("".join(f'<option value="{h(v["variety_id"])}">{h(v["crop_name"])} &bull; {h(v["variety_name"])}</option>' for v in data["varieties"])),
        "season_options": Markup("".join(f'<option value="{h(s["season_id"])}">{h(s["season_name"])}</option>' for s in data["seasons"])),
        "season_name_options": Markup("".join(f'<option value="{h(s["season_name"])}">{h(s["season_name"])}</option>' for s in data["seasons"])),
        "farmer_cultivation_options": Markup("".join(f'<option value="{h(c["cultivation_id"])}">{h(c["crop_name"])} @ {h(c["field_name"])} ({h(c["season_name"])})</option>' for c in data["cultivations"])),
        "cultivation_rows": Markup("".join(cult_rows) or '<tr><td colspan="8" class="text-muted">No cultivations logged.</td></tr>'),
        "activity_rows": Markup("".join(act_rows) or '<tr><td colspan="5" class="text-muted">No cultivation activities logged.</td></tr>'),
        "season_inputs_rows": Markup("".join(used_rows) or '<tr><td colspan="6" class="text-muted">No input applications recorded for this season yet.</td></tr>'),
        "rbk_options": Markup("".join(f'<option value="{h(r["rbk_id"])}">{h(r["rbk_name"])} ({h(r["district"])})</option>' for r in data["rbk_centres"])),
        "product_options": Markup("".join(f'<option value="{h(pr["product_id"])}">{h(pr["product_name"])} ({h(pr["company_name"])}) &mdash; &#8377;{_money(pr["price"])}/{h(pr["unit"])}</option>' for pr in data["products"])),
        "preorder_rows": Markup("".join(pre_rows) or '<tr><td colspan="7" class="text-muted">No pre-booking orders placed yet.</td></tr>'),
        "input_purchase_rows": Markup("".join(pur_rows) or '<tr><td colspan="7" class="text-muted">No RBK input purchases found.</td></tr>'),
        "buyer_order_rows": Markup("".join(bo_rows) or '<tr><td colspan="7" class="text-muted">No institutional buyer orders placed for your produce yet.</td></tr>'),
    }


def build_passport_html(pass_data: dict | None) -> Markup:
    """Render Agronomic Passport card with QR sticker, chemical MRL log, soil profile, and timeline."""
    if not pass_data:
        return Markup('<p class="text-muted">Select or scan a crop batch to inspect its Agronomic Passport.</p>')

    pb = pass_data["batch"]
    soil = pass_data["soil"]
    apps_html = "".join(
        f'<tr><td>{h(a["application_date"])}</td><td><strong>{h(a["product_name"])}</strong> ({h(a["product_type"])})</td>'
        f'<td><code class="mono">{h(a["batch_number"])}</code></td><td>{_num(a["quantity_used"]):g} &bull; {h(a["application_method"])}</td>'
        f'<td>{h(a["remarks"])}</td></tr>'
        for a in pass_data["applications"]
    ) or '<tr><td colspan="5" class="text-muted">No chemical/seed inputs recorded for this cultivation.</td></tr>'

    ev_html = "".join(
        f'<li><strong>{h(e["event_type"])}</strong> &mdash; <span class="text-muted">{h(e["event_date"])} &bull; {h(e["location"])}</span>'
        f'<div>{h(e["description"])}</div><div class="text-muted">Recorded by: {h(e["recorded_by"])}</div></li>'
        for e in pass_data["events"]
    ) or '<li>No chain-of-custody events recorded yet.</li>'

    if soil:
        ph_val = _num(soil.get("ph_level"), 7.0)
        soil_summary = (
            f'<div class="soil-pills">'
            f'<span class="badge badge-blue">pH {h(soil["ph_level"])}</span>'
            f'<span class="badge badge-green">OC {h(soil["organic_carbon"])}%</span>'
            f'<span class="badge badge-gray">N {h(soil["nitrogen_kg_ha"])} &middot; P {h(soil["phosphorus_kg_ha"])} &middot; K {h(soil["potassium_kg_ha"])} kg/ha</span>'
            f'</div>'
        )
    else:
        soil_summary = '<span class="text-muted">No lab soil test linked</span>'

    return Markup(
        f'<div class="card passport-card">'
        f'<div class="passport-head">'
        f'<div class="qr-sticker"><div class="qr-box" data-qr-code="{h(pb["qr_code"])}"></div>'
        f'<div><div class="passport-title">{h(pb["crop_name"])} &mdash; {h(pb["variety_name"])}</div>'
        f'<div class="mono passport-code">{h(pb["batch_code"])} | {h(pb["qr_code"])}</div>'
        f'<div>Farmer: <strong>{h(pb["farmer_name"])}</strong> &bull; {h(pb["village"])} ({h(pb["survey_number"])})</div>'
        f'<div class="mt-1">Moisture: <strong>{h(pb["moisture_percentage"] or "-")}%</strong> &bull; Grade: {status_badge(pb["quality_grade"] or pb["quality_status"])} &bull; {status_badge(pb["batch_status"])}</div>'
        f'</div></div>'
        f'<div class="passport-meta"><div><strong>Season:</strong> {h(pb["season_name"])}</div>'
        f'<div><strong>Sowing &rarr; Harvest:</strong> {h(pb["sowing_date"])} &rarr; {h(pb["harvest_date"])}</div>'
        f'<div><strong>Soil Profile:</strong> {soil_summary}</div></div></div>'
        f'<h3 class="sub-heading">Verified Seeds &amp; Agro-Chemical Applications (<code class="mono">input_applications</code>)</h3>'
        f'<div class="table-wrap mb-2"><table><thead><tr><th>Date</th><th>Product</th><th>Lot #</th><th>Dosage &amp; Method</th><th>Compliance Remarks</th></tr></thead>'
        f'<tbody>{apps_html}</tbody></table></div>'
        f'<h3 class="sub-heading">Chain-of-Custody Timeline (<code class="mono">traceability_events</code>)</h3>'
        f'<ul class="timeline">{ev_html}</ul></div>'
    )


def build_buyer_context(session: dict, data: dict, settlement: dict | None) -> dict:
    """Build template context dictionary for templates/buyer_home.html."""
    buyer = data["buyer"] or {}
    market = data["marketplace_batches"]
    orders = data["orders"]
    total_market_kg = sum(_num(b["available_kg"]) for b in market)
    seen_orders = set()
    order_val = 0.0
    escrow_cnt = 0
    for o in orders:
        if o["sales_order_id"] not in seen_orders:
            seen_orders.add(o["sales_order_id"])
            order_val += _num(o["total_amount"])
            if o["escrow_status"] == "ESCROW_HELD" or o["payment_status"] == "ESCROW_HELD":
                escrow_cnt += 1

    settlement_html = Markup("")
    if settlement:
        gross = _num(settlement["gross_amount"])
        offset = _num(settlement["offset_deducted"])
        offset_pct = min(100.0, max(0.0, round((offset / gross) * 100, 1))) if gross > 0 else 0.0
        net_pct = round(100.0 - offset_pct, 1)
        settlement_html = Markup(
            f'<div class="card card-accent-success">'
            f'<h2 class="card-title">Automated Settlement &amp; Smart KCC Credit Offset Completed ({h(settlement["sales_order_id"])})</h2>'
            f'<div class="grid-3 mt-1">'
            f'<div><div class="kpi-label">Gross Escrow Released</div><div class="kpi-value">&#8377;{_money(gross)}</div><div class="kpi-sub">payment_status = COMPLETED</div></div>'
            f'<div><div class="kpi-label">KCC Input Loan Auto-Cleared</div><div class="kpi-value" style="color:#b45309;">-&#8377;{_money(offset)}</div><div class="kpi-sub">Prior KCC debt: &#8377;{_money(settlement["kcc_debt_before"])}</div></div>'
            f'<div><div class="kpi-label">Net DBT Bank Payout</div><div class="kpi-value" style="color:#15803d;">&#8377;{_money(settlement["net_dbt_payout"])}</div><div class="kpi-sub">Deposited to {h(settlement["farmer_name"])}</div></div>'
            f'</div>'
            f'<div class="split-bar mt-2" aria-label="Settlement breakdown">'
            f'<div class="split-bar-offset" style="width:{offset_pct}%"><span>KCC Cleared ({offset_pct:g}%)</span></div>'
            f'<div class="split-bar-net" style="width:{net_pct}%"><span>Net DBT ({net_pct:g}%)</span></div>'
            f'</div></div>'
        )

    market_rows = []
    batch_opts = []
    for b in market:
        sugg_price = 185 if "Chilli" in (b["crop_name"] or "") else (28 if "Maize" in (b["crop_name"] or "") else 42)
        grade_val = b["quality_grade"] or b["quality_status"] or "Standard"
        moisture_val = _num(b["moisture_percentage"], 0.0)
        market_rows.append(
            f'<tr data-grade="{h(grade_val)}" data-moisture="{moisture_val}" data-crop="{h(b["crop_name"])}">'
            f'<td><code class="mono">{h(b["batch_code"])}</code><br>{status_badge(b["batch_status"])}</td>'
            f'<td><strong>{h(b["crop_name"])}</strong><br><span class="text-muted">{h(b["variety_name"])} &bull; {h(b["spray_log_count"])} field logs</span></td>'
            f'<td>{h(b["farmer_name"])}<br><span class="text-muted">{h(b["village"])} ({h(b["survey_number"])})</span></td>'
            f'<td>Moisture: <strong>{h(b["moisture_percentage"] or "-")}%</strong><br>{status_badge(grade_val)}</td>'
            f'<td><strong>{_num(b["available_kg"]):g} kg</strong></td>'
            f'<td>{h(b["warehouse_name"] or "Village RBK Yard")}<br><span class="text-muted">{h(b["warehouse_district"] or "")}</span></td>'
            f'<td><div class="btn-group-inline">'
            f'<button type="button" class="btn btn-outline btn-sm" data-audit-qr="{h(b["batch_code"])}">Audit QR</button>'
            f'<button type="button" class="btn btn-blue btn-sm" data-order-batch="{h(b["crop_batch_id"])}" data-max-qty="{_num(b["available_kg"])}" data-suggested-price="{sugg_price}">Order &amp; Escrow</button>'
            f'</div></td></tr>'
        )
        batch_opts.append(
            f'<option value="{h(b["crop_batch_id"])}" data-max-qty="{_num(b["available_kg"])}" data-suggested-price="{sugg_price}">'
            f'{h(b["batch_code"])} &bull; {h(b["crop_name"])} ({_num(b["available_kg"]):g} kg &bull; {h(grade_val)})</option>'
        )

    pass_data = data.get("passport")
    selected_bcode = pass_data["batch"]["batch_code"] if pass_data else ""
    passport_opts = [
        f'<option value="{h(idx["batch_code"])}"{" selected" if idx["batch_code"] == selected_bcode else ""}>'
        f'{h(idx["batch_code"])} &bull; {h(idx["crop_name"])} ({h(idx["farmer_name"])})</option>'
        for idx in data["all_batches_index"]
    ]

    passport_html = build_passport_html(pass_data)

    order_rows = []
    for o in orders:
        kcc_debt = _num(o["farmer_kcc_debt"])
        is_delivered = o["order_status"] == "Delivered"
        is_shipped = o["order_status"] not in ("Placed", "Processing") and not is_delivered
        step_html = (
            f'<div class="lifecycle-steps">'
            f'<span class="lc-step done">Escrow Held</span>'
            f'<span class="lc-step {"done" if is_shipped or is_delivered else "active"}">In Transit</span>'
            f'<span class="lc-step {"done" if is_delivered else ""}">Delivered &amp; Settled</span>'
            f'</div>'
        )
        if o["order_status"] in ("Placed", "Processing"):
            action_block = (
                f'{step_html}'
                f'<form method="POST" action="/buyer/dispatch" class="inline-action-form mt-1">'
                f'<input type="hidden" name="sales_order_id" value="{h(o["sales_order_id"])}">'
                f'<input type="text" name="vehicle_number" value="AP-16-TX-9988" required style="width:128px;padding:6px;" title="Vehicle License">'
                f'<input type="text" name="driver_name" value="R. Koteswara Rao" required style="width:124px;padding:6px;" title="Driver">'
                f'<input type="hidden" name="source_location" value="RBK / APSWC Warehouse">'
                f'<input type="hidden" name="destination_location" value="{h(o["delivery_address"] or buyer.get("address", "Buyer Plant"))}">'
                f'<button type="submit" class="btn btn-outline btn-sm">Dispatch Truck (IN_TRANSIT)</button>'
                f'</form>'
            )
        elif not is_delivered:
            action_block = (
                f'{step_html}'
                f'<div class="text-muted mb-1 mt-1">Truck: <strong>{h(o["vehicle_number"] or "-")}</strong> ({h(o["driver_name"] or "-")}) &bull; {status_badge(o["shipment_status"] or "In Transit")}</div>'
                f'<form method="POST" action="/buyer/settle">'
                f'<input type="hidden" name="sales_order_id" value="{h(o["sales_order_id"])}">'
                f'<button type="submit" class="btn btn-primary btn-sm">Inspect Seals &amp; Confirm Delivery (Release Escrow &amp; Credit Offset)</button>'
                f'</form>'
            )
        else:
            action_block = (
                f'{step_html}'
                f'<div class="mt-1">{status_badge("Delivered")} {status_badge("COMPLETED")}</div>'
                f'<div class="text-muted">Vehicle: {h(o["vehicle_number"] or "-")} &bull; Delivered: {h(o["delivery_date"] or "-")}</div>'
            )

        order_rows.append(
            f'<tr data-order-status="{h(o["order_status"])}">'
            f'<td><code class="mono">{h(o["sales_order_id"])}</code><br><strong>{h(o["farmer_name"])}</strong><br><span class="text-muted">{h(o["order_date"])}</span></td>'
            f'<td><strong>{h(o["crop_name"] or "-")}</strong><br><code class="mono text-muted">{h(o["batch_code"] or "")}</code><br>{_num(o["quantity"]):g} kg @ &#8377;{_money(o["unit_price"])}</td>'
            f'<td><strong>&#8377;{_money(o["total_amount"])}</strong><br>{status_badge(o["escrow_status"] or o["payment_status"])}<br><code class="mono text-muted">{h(o["transaction_reference"] or "")}</code></td>'
            f'<td style="color:#b45309;font-weight:700;">&#8377;{_money(kcc_debt)}<br><span class="text-muted">Auto-cleared on delivery</span></td>'
            f'<td>{action_block}</td>'
            f'</tr>'
        )

    buyer_profile_html = Markup(
        f'<div class="table-wrap"><table><tbody>'
        f'<tr><th>Buyer ID</th><td><code class="mono">{h(buyer.get("buyer_id"))}</code></td></tr>'
        f'<tr><th>Organization</th><td><strong>{h(buyer.get("buyer_name"))}</strong></td></tr>'
        f'<tr><th>Classification</th><td>{status_badge(buyer.get("buyer_type"))}</td></tr>'
        f'<tr><th>Registration / GSTIN</th><td><code class="mono">{h(buyer.get("registration_number"))}</code></td></tr>'
        f'<tr><th>Contact</th><td>{h(buyer.get("phone"))} &bull; {h(buyer.get("email"))}</td></tr>'
        f'<tr><th>Address</th><td>{h(buyer.get("address"))}</td></tr>'
        f'</tbody></table></div>'
    )

    wh_rows = []
    for w in data["warehouses"]:
        cap_kg = _num(w["capacity"]) * 1000.0
        stored_kg = _num(w["stored_quantity"])
        fill_pct = min(100.0, max(0.0, round((stored_kg / cap_kg) * 100, 1))) if cap_kg > 0 else 0.0
        wh_rows.append(
            f'<tr><td><code class="mono">{h(w["warehouse_id"])}</code></td><td><strong>{h(w["warehouse_name"])}</strong><br><span class="text-muted">{h(w["location"])}</span></td>'
            f'<td>{h(w["district"])}</td><td>{_num(w["capacity"]):,.0f} MT</td>'
            f'<td>{_num(stored_kg):,.0f} kg<div class="meter-track mt-1"><div class="meter-fill" style="width:{fill_pct}%"></div></div></td>'
            f'<td>{h(w["batch_count"])}</td><td>{h(w["contact_number"] or "-")}</td></tr>'
        )

    ccat_rows = [
        f'<tr><td><code class="mono">{h(c["category_id"])}</code></td><td><strong>{h(c["category_name"])}</strong></td><td>{h(c["description"])}</td></tr>'
        for c in data["crop_categories"]
    ]

    return {
        "buyer_type": buyer.get("buyer_type", session.get("buyer_type", "Buyer")),
        "buyer_id": buyer.get("buyer_id", session.get("user_id", "")),
        "buyer_name": buyer.get("buyer_name", session.get("name", "")),
        "registration_number": buyer.get("registration_number", ""),
        "email": buyer.get("email", ""),
        "default_buyer_address": buyer.get("address") or "Buyer Processing Facility",
        "kpi_order_value": _money(order_val),
        "kpi_market_lots": str(len(market)),
        "kpi_market_kg": f"{total_market_kg:,.0f}",
        "kpi_orders_count": str(len(seen_orders)),
        "kpi_escrow_count": str(escrow_cnt),
        "kpi_warehouse_count": str(len(data["warehouses"])),
        "settlement_banner_html": settlement_html,
        "marketplace_rows": Markup("".join(market_rows) or '<tr><td colspan="7" class="text-muted">No batches currently listed for sale.</td></tr>'),
        "order_batch_options": Markup("".join(batch_opts)),
        "passport_options": Markup("".join(passport_opts)),
        "passport_html": passport_html,
        "buyer_orders_rows": Markup("".join(order_rows) or '<tr><td colspan="5" class="text-muted">No purchase orders placed yet.</td></tr>'),
        "buyer_profile_html": buyer_profile_html,
        "warehouse_rows": Markup("".join(wh_rows)),
        "crop_category_rows": Markup("".join(ccat_rows)),
    }
