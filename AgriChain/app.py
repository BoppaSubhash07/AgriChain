"""Main WSGI Web Application for AgriChain (Python + Werkzeug + HTML + MySQL)."""

import json
import os
import socket
import sys
import threading
import webbrowser
from pathlib import Path

BASE_APP_DIR = Path(__file__).resolve().parent
if str(BASE_APP_DIR) not in sys.path:
    sys.path.insert(0, str(BASE_APP_DIR))

from markupsafe import Markup
from werkzeug.exceptions import HTTPException
from werkzeug.middleware.shared_data import SharedDataMiddleware
from werkzeug.routing import Map, Rule
from werkzeug.serving import run_simple
from werkzeug.wrappers import Request, Response
from werkzeug.utils import redirect

from auth import (
    FLASH_COOKIE,
    authenticate_buyer,
    authenticate_farmer_biometric,
    authenticate_farmer_password,
    authenticate_rbk_employee,
    clear_session_cookie,
    decode_signed_data,
    encode_signed_data,
    get_session,
    pop_flash,
    set_flash_cookie,
    set_session_cookie,
)
from config import APP_HOST, APP_PORT, BASE_DIR, DB_CONFIG, save_and_reload_db_config
from db import check_db_health, query_one, reset_pool
import init_db
from services import buyer_service, farmer_service, rbk_service
from templating import h, render_page, render_template
from views import (
    build_buyer_context,
    build_farmer_context,
    build_passport_html,
    build_rbk_context,
    serialize_context_fragments,
)

RESULT_COOKIE = "agrichain_result"


def _layout_ctx(request: Request, session: dict | None, page_title: str) -> tuple[dict, list[str]]:
    """Build layout header actions and pop flash cookies."""
    cookies_to_clear: list[str] = []
    flash_html = Markup("")
    flash = pop_flash(request)
    if flash:
        cookies_to_clear.append(FLASH_COOKIE)
        cat = flash.get("category", "info")
        cls = "flash-success" if cat == "success" else ("flash-error" if cat == "error" else "flash-info")
        flash_html = Markup(f'<div class="page-wrap" style="padding-bottom:0;"><div class="flash {cls}"><span>{h(flash.get("message", ""))}</span></div></div>')

    if session:
        role_names = {"rbk": "RBK Employee", "farmer": "Farmer", "buyer": "Buyer"}
        role_label = role_names.get(session.get("role", ""), "User")
        topbar_actions = Markup(
            f'<span class="role-pill">{h(role_label)}: {h(session.get("name", ""))}</span>'
            f'<a href="/logout" class="btn-logout">Sign Out</a>'
        )
    else:
        topbar_actions = Markup('<span class="role-pill">Role Portal Gateway</span>')

    return {
        "page_title": page_title,
        "topbar_actions": topbar_actions,
        "flash_html": flash_html,
    }, cookies_to_clear


def _html_response(html_str: str, clear_cookies: list[str] | None = None, status: int = 200) -> Response:
    resp = Response(html_str, status=status, content_type="text/html; charset=utf-8")
    for name in (clear_cookies or []):
        resp.delete_cookie(name, path="/")
    return resp


def _wants_json(request: Request) -> bool:
    return (
        request.headers.get("X-Requested-With") == "fetch"
        or "application/json" in (request.headers.get("Accept") or "")
    )


def _json_response(payload: dict, status: int = 200) -> Response:
    return Response(
        json.dumps(payload, default=str),
        status=status,
        content_type="application/json; charset=utf-8",
    )


def _redirect_with_flash(url: str, category: str, message: str, result_payload: dict | None = None):
    resp = redirect(url)
    set_flash_cookie(resp, category, message)
    if result_payload is not None:
        resp.set_cookie(
            RESULT_COOKIE,
            encode_signed_data(result_payload),
            httponly=True,
            samesite="Lax",
            max_age=120,
            path="/",
        )
    return resp


def _require_role(request: Request, role: str):
    session = get_session(request)
    if not session or session.get("role") != role:
        if _wants_json(request):
            return None, _json_response(
                {
                    "ok": False,
                    "redirect": f"/login/{role}",
                    "message": f"Session expired. Please sign in to the {role.upper()} portal.",
                },
                status=401,
            )
        return None, _redirect_with_flash(f"/login/{role}", "error", f"Please sign in to the {role.upper()} portal first.")
    return session, None


# ==================== ROUTE HANDLERS ====================

def ensure_db_ready() -> tuple[bool, str]:
    """Verify MySQL connectivity and auto-upgrade/seed if trigger/data is not yet installed."""
    ok, msg = check_db_health()
    if not ok:
        # Check if database simply doesn't exist yet while MySQL credentials work
        if "Unknown database" in msg:
            try:
                init_db.initialize_database(force_fresh=True)
                reset_pool()
                return check_db_health()
            except Exception as exc:
                return False, str(exc)
        return False, msg

    try:
        trg = query_one(
            """
            SELECT TRIGGER_NAME FROM information_schema.TRIGGERS
             WHERE TRIGGER_SCHEMA = %s AND TRIGGER_NAME = 'trg_after_input_purchase_item_insert'
            """,
            (DB_CONFIG["database"],),
        )
        b_cnt = query_one("SELECT COUNT(*) AS cnt FROM buyers WHERE buyer_id = 'BUY-020'")
        f_cnt = query_one("SELECT COUNT(*) AS cnt FROM farmers WHERE farmer_id = 'FAR-012'")
        e_cnt = query_one("SELECT COUNT(*) AS cnt FROM rbk_employees WHERE employee_id = 'EMP-030'")
        if not trg or not b_cnt or b_cnt["cnt"] == 0 or not f_cnt or f_cnt["cnt"] == 0 or not e_cnt or e_cnt["cnt"] == 0:
            init_db.initialize_database(force_fresh=False)
            reset_pool()
    except Exception as exc:
        return False, str(exc)
    return True, msg


def handle_setup(request: Request) -> Response:
    error_html = Markup("")
    db_host = DB_CONFIG.get("host", "127.0.0.1")
    db_port = str(DB_CONFIG.get("port", 3306))
    db_user = DB_CONFIG.get("user", "root")
    db_name = DB_CONFIG.get("database", "agri_management_database")

    if request.method == "POST":
        db_host = (request.form.get("db_host") or "127.0.0.1").strip()
        db_port = (request.form.get("db_port") or "3306").strip()
        db_user = (request.form.get("db_user") or "root").strip()
        db_name = (request.form.get("db_name") or "agri_management_database").strip()
        db_password = request.form.get("db_password") or ""
        try:
            save_and_reload_db_config(db_host, int(db_port), db_user, db_password, db_name)
            reset_pool()
            init_db.initialize_database(force_fresh=False)
            reset_pool()
            return _redirect_with_flash(
                "/",
                "success",
                f"Connected to MySQL ({db_name}) and initialized all tables, triggers & seed data!",
            )
        except Exception as exc:
            error_html = Markup(f'<div class="flash flash-error">MySQL Setup Failed: {h(exc)}</div>')

    lctx, clear = _layout_ctx(request, None, "Database Setup")
    html_str = render_page(
        "setup.html",
        lctx,
        error_html=error_html,
        db_host=db_host,
        db_port=db_port,
        db_user=db_user,
        db_name=db_name,
    )
    return _html_response(html_str, clear)


def _query_gateway_metrics() -> dict:
    """Safely fetch lightweight live counts from MySQL for gateway & health endpoint."""
    metrics = {"farmers": 0, "batches_ready": 0, "orders": 0, "rbks": 0, "pending_ccrc": 0}
    try:
        row = query_one(
            """
            SELECT
              (SELECT COUNT(*) FROM farmers) AS farmers,
              (SELECT COUNT(*) FROM crop_batches WHERE batch_status IN ('READY_FOR_SALE', 'In Stock')) AS batches_ready,
              (SELECT COUNT(*) FROM sales_orders) AS orders,
              (SELECT COUNT(*) FROM rbk_centres WHERE status = 'Active') AS rbks,
              (SELECT COUNT(*) FROM seasonal_cultivator_rights WHERE approval_status IN ('Pending', 'Under Verification')) AS pending_ccrc
            """
        )
        if row:
            metrics = {k: int(row.get(k) or 0) for k in metrics}
    except Exception:
        pass
    return metrics


def handle_api_health(request: Request) -> Response:
    ok, msg = check_db_health()
    if not ok:
        return _json_response({"ok": False, "status": "offline", "message": msg, "metrics": {}})
    return _json_response({
        "ok": True,
        "status": "online",
        "message": msg,
        "metrics": _query_gateway_metrics(),
    })


def handle_role_select(request: Request) -> Response:
    ok, msg = check_db_health()
    if not ok:
        return _redirect_with_flash("/setup", "info", "Enter your MySQL password once below to connect and initialize AgriChain.")
    badge = Markup(f'<span class="badge badge-green">MySQL Online</span> <span class="text-muted">{h(msg)}</span>')
    session = get_session(request)
    lctx, clear = _layout_ctx(request, session, "AgriChain")
    metrics = _query_gateway_metrics()

    if session:
        role_paths = {"rbk": "/rbk", "farmer": "/farmer", "buyer": "/buyer"}
        role_names = {"rbk": "RBK Employee", "farmer": "Farmer", "buyer": "Buyer"}
        r_code = session.get("role", "")
        portal_href = role_paths.get(r_code, "#portals")
        portal_label = f"Open {role_names.get(r_code, 'Portal')}"
        nav_secondary_href = "/logout"
        nav_secondary_label = "Sign out"
        session_banner = Markup(
            f'<span class="hero-session">Signed in as <strong>{h(session.get("name", ""))}</strong> '
            f'(<a href="{h(portal_href)}">{h(role_names.get(r_code, "User"))} Home</a>)</span>'
        )
    else:
        portal_href = "#portals"
        portal_label = "Open portal"
        nav_secondary_href = "/login/farmer"
        nav_secondary_label = "Sign in"
        session_banner = Markup("")

    html_str = render_template(
        "role_select.html",
        db_status_badge=badge,
        db_message=msg,
        flash_html=lctx["flash_html"],
        portal_href=portal_href,
        portal_label=portal_label,
        nav_secondary_href=nav_secondary_href,
        nav_secondary_label=nav_secondary_label,
        session_banner=session_banner,
        metric_farmers=str(metrics["farmers"]),
        metric_batches=str(metrics["batches_ready"]),
        metric_orders=str(metrics["orders"]),
        metric_rbks=str(metrics["rbks"]),
    )
    return _html_response(html_str, clear)


def handle_login_rbk(request: Request) -> Response:
    error_html = Markup("")
    prev_ident = ""
    if request.method == "POST":
        prev_ident = (request.form.get("identifier") or "").strip()
        password = request.form.get("password") or ""
        try:
            user = authenticate_rbk_employee(prev_ident, password)
            if user:
                resp = _redirect_with_flash("/rbk", "success", f"Welcome, {user['name']} ({user['rbk_name']}).")
                set_session_cookie(resp, user)
                return resp
            error_html = Markup('<div class="flash flash-error">Invalid RBK Employee Username/Email or Password.</div>')
        except Exception as exc:
            error_html = Markup(f'<div class="flash flash-error">Database error: {h(exc)}</div>')

    lctx, clear = _layout_ctx(request, None, "RBK Employee Login")
    html_str = render_page("login_rbk.html", lctx, error_html=error_html, prev_identifier=prev_ident)
    return _html_response(html_str, clear)


def handle_login_farmer(request: Request) -> Response:
    error_html = Markup("")
    prev_ident = ""
    if request.method == "POST":
        prev_ident = (request.form.get("identifier") or "").strip()
        auth_mode = (request.form.get("auth_mode") or "password").strip()
        try:
            if auth_mode == "biometric":
                last4 = request.form.get("aadhaar_last4") or ""
                user, err = authenticate_farmer_biometric(prev_ident, last4)
                if user:
                    resp = _redirect_with_flash("/farmer", "success", f"Biometric verified! Welcome, {user['name']}.")
                    set_session_cookie(resp, user)
                    return resp
                error_html = Markup(f'<div class="flash flash-error">{h(err)}</div>')
            else:
                password = request.form.get("password") or ""
                user = authenticate_farmer_password(prev_ident, password)
                if user:
                    resp = _redirect_with_flash("/farmer", "success", f"Welcome back, {user['name']}.")
                    set_session_cookie(resp, user)
                    return resp
                error_html = Markup('<div class="flash flash-error">Invalid Farmer ID / Phone or Password.</div>')
        except Exception as exc:
            error_html = Markup(f'<div class="flash flash-error">Database error: {h(exc)}</div>')

    lctx, clear = _layout_ctx(request, None, "Farmer Login")
    html_str = render_page("login_farmer.html", lctx, error_html=error_html, prev_identifier=prev_ident)
    return _html_response(html_str, clear)


def handle_login_buyer(request: Request) -> Response:
    error_html = Markup("")
    prev_ident = ""
    if request.method == "POST":
        prev_ident = (request.form.get("identifier") or "").strip()
        password = request.form.get("password") or ""
        try:
            user = authenticate_buyer(prev_ident, password)
            if user:
                resp = _redirect_with_flash("/buyer", "success", f"Signed in as {user['name']} ({user['buyer_type']}).")
                set_session_cookie(resp, user)
                return resp
            error_html = Markup('<div class="flash flash-error">Invalid Buyer ID / Organization Email or Password.</div>')
        except Exception as exc:
            error_html = Markup(f'<div class="flash flash-error">Database error: {h(exc)}</div>')

    lctx, clear = _layout_ctx(request, None, "Buyer Login")
    html_str = render_page("login_buyer.html", lctx, error_html=error_html, prev_identifier=prev_ident)
    return _html_response(html_str, clear)


def handle_buyer_register(request: Request) -> Response:
    try:
        res = buyer_service.register_buyer(request.form)
        user = authenticate_buyer(res["buyer_id"], request.form.get("password") or "")
        if user:
            resp = _redirect_with_flash("/buyer", "success", f"Organization '{res['buyer_name']}' registered ({res['buyer_id']}) and verified.")
            set_session_cookie(resp, user)
            return resp
        return _redirect_with_flash("/login/buyer", "success", f"Buyer registered ({res['buyer_id']}). Please sign in.")
    except Exception as exc:
        return _redirect_with_flash("/login/buyer", "error", f"Onboarding failed: {exc}")


def handle_logout(request: Request) -> Response:
    resp = _redirect_with_flash("/", "info", "You have signed out cleanly.")
    clear_session_cookie(resp)
    return resp


# ==================== RBK HOME & ACTIONS ====================

def _rbk_fragments(session: dict, query_args: dict | None = None, pos_receipt: dict | None = None, qr_cert: dict | None = None) -> dict[str, str]:
    data = rbk_service.get_rbk_dashboard_data(session["rbk_id"])
    ctx = build_rbk_context(session, data, query_args or {}, pos_receipt, qr_cert)
    return serialize_context_fragments(ctx)


def _farmer_fragments(session: dict) -> dict[str, str]:
    data = farmer_service.get_farmer_dashboard_data(session["user_id"])
    ctx = build_farmer_context(session, data)
    return serialize_context_fragments(ctx)


def _buyer_fragments(session: dict, passport_code: str | None = None, settlement: dict | None = None) -> dict[str, str]:
    data = buyer_service.get_buyer_dashboard_data(session["user_id"], passport_code=passport_code)
    ctx = build_buyer_context(session, data, settlement)
    return serialize_context_fragments(ctx)


def handle_api_rbk_state(request: Request) -> Response:
    session, err = _require_role(request, "rbk")
    if err:
        return err
    try:
        return _json_response({"ok": True, "fragments": _rbk_fragments(session, request.args)})
    except Exception as exc:
        return _json_response({"ok": False, "message": str(exc)}, status=500)


def handle_api_farmer_state(request: Request) -> Response:
    session, err = _require_role(request, "farmer")
    if err:
        return err
    try:
        return _json_response({"ok": True, "fragments": _farmer_fragments(session)})
    except Exception as exc:
        return _json_response({"ok": False, "message": str(exc)}, status=500)


def handle_api_buyer_state(request: Request) -> Response:
    session, err = _require_role(request, "buyer")
    if err:
        return err
    try:
        p_code = (request.args.get("passport_code") or request.args.get("passport") or "").strip() or None
        return _json_response({"ok": True, "fragments": _buyer_fragments(session, passport_code=p_code)})
    except Exception as exc:
        return _json_response({"ok": False, "message": str(exc)}, status=500)


def handle_api_buyer_passport(request: Request) -> Response:
    session = get_session(request)
    if not session or session.get("role") not in ("buyer", "rbk"):
        return _json_response({"ok": False, "message": "Authentication required."}, status=401)
    code = (request.args.get("code") or request.args.get("passport") or request.args.get("passport_code") or "").strip()
    if not code:
        return _json_response({"ok": False, "message": "Enter or select a Batch Code or QR Code."}, status=400)
    try:
        pass_data = buyer_service.get_batch_passport(code)
        html_markup = build_passport_html(pass_data)
        if not pass_data:
            return _json_response({"ok": False, "code": code, "message": f"No batch found matching '{code}'.", "html": str(html_markup)}, status=404)
        return _json_response({
            "ok": True,
            "code": pass_data["batch"]["batch_code"],
            "qr_code": pass_data["batch"]["qr_code"],
            "html": str(html_markup),
        })
    except Exception as exc:
        return _json_response({"ok": False, "message": str(exc)}, status=500)


def handle_rbk_home(request: Request) -> Response:
    session, redir = _require_role(request, "rbk")
    if redir:
        return redir

    lctx, clear = _layout_ctx(request, session, "RBK Employee Home")
    res_data = decode_signed_data(request.cookies.get(RESULT_COOKIE))
    if res_data:
        clear.append(RESULT_COOKIE)

    pos_receipt = res_data.get("pos_receipt") if res_data else None
    qr_cert = res_data.get("qr_cert") if res_data else None

    data = rbk_service.get_rbk_dashboard_data(session["rbk_id"])
    ctx = build_rbk_context(session, data, request.args, pos_receipt, qr_cert)
    return _html_response(render_page("rbk_home.html", lctx, **ctx), clear)


def handle_rbk_farmer_step1(request: Request) -> Response:
    session, redir = _require_role(request, "rbk")
    if redir:
        return redir
    try:
        farmer_id = rbk_service.register_farmer_step1(request.form)
        msg = f"Step 1 Saved: Farmer ({farmer_id}), Biometric & Address inserted into MySQL. Proceed with Land Details."
        if _wants_json(request):
            return _json_response({
                "ok": True,
                "message": msg,
                "tab": "tab-register",
                "step": "2",
                "farmer_id": farmer_id,
                "fragments": _rbk_fragments(session, {"farmer_id": farmer_id}),
            })
        return _redirect_with_flash(f"/rbk?tab=tab-register&step=2&farmer_id={farmer_id}", "success", msg)
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"Step 1 error: {exc}"}, status=400)
        return _redirect_with_flash("/rbk?tab=tab-register&step=1", "error", f"Step 1 error: {exc}")


def handle_rbk_farmer_step2(request: Request) -> Response:
    session, redir = _require_role(request, "rbk")
    if redir:
        return redir
    farmer_id = (request.form.get("farmer_id") or "").strip()
    try:
        land_id, field_id = rbk_service.register_farmer_step2(request.form, session["name"])
        msg = f"Step 2 Saved: Land ({land_id}) & Field ({field_id}) inserted into MySQL. Proceed to KCC Credit Account."
        if _wants_json(request):
            return _json_response({
                "ok": True,
                "message": msg,
                "tab": "tab-register",
                "step": "3",
                "farmer_id": farmer_id,
                "fragments": _rbk_fragments(session, {"farmer_id": farmer_id}),
            })
        return _redirect_with_flash(f"/rbk?tab=tab-register&step=3&farmer_id={farmer_id}", "success", msg)
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"Step 2 error: {exc}"}, status=400)
        return _redirect_with_flash(f"/rbk?tab=tab-register&step=2&farmer_id={farmer_id}", "error", f"Step 2 error: {exc}")


def handle_rbk_farmer_step3(request: Request) -> Response:
    session, redir = _require_role(request, "rbk")
    if redir:
        return redir
    farmer_id = (request.form.get("farmer_id") or "").strip()
    try:
        credit_id = rbk_service.register_farmer_step3(request.form)
        msg = f"Step 3 Complete: KCC Account ({credit_id}) activated for {farmer_id}. Sequential farmer registration complete!"
        if _wants_json(request):
            return _json_response({
                "ok": True,
                "message": msg,
                "tab": "tab-directory",
                "fragments": _rbk_fragments(session),
            })
        return _redirect_with_flash("/rbk?tab=tab-directory", "success", msg)
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"Step 3 error: {exc}"}, status=400)
        return _redirect_with_flash(f"/rbk?tab=tab-register&step=3&farmer_id={farmer_id}", "error", f"Step 3 error: {exc}")


def handle_rbk_supply_create(request: Request) -> Response:
    session, redir = _require_role(request, "rbk")
    if redir:
        return redir
    try:
        supply_id = rbk_service.create_supply_order(session["rbk_id"], session["user_id"], request.form)
        msg = f"Supply order {supply_id} created and awaiting truck arrival."
        if _wants_json(request):
            return _json_response({"ok": True, "message": msg, "tab": "tab-supply", "fragments": _rbk_fragments(session)})
        return _redirect_with_flash("/rbk?tab=tab-supply", "success", msg)
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"Could not create supply order: {exc}"}, status=400)
        return _redirect_with_flash("/rbk?tab=tab-supply", "error", f"Could not create supply order: {exc}")


def handle_rbk_supply_confirm(request: Request) -> Response:
    session, redir = _require_role(request, "rbk")
    if redir:
        return redir
    try:
        res = rbk_service.confirm_supply_delivery(session["rbk_id"], session["user_id"], request.form)
        msg = f"Delivery Confirmed ({res['supply_id']}): {res['received_quantity']:g} accepted into rbk_inventory (IN movement logged), {res['rejected_quantity']:g} damaged rejected."
        if _wants_json(request):
            return _json_response({"ok": True, "message": msg, "tab": "tab-supply", "fragments": _rbk_fragments(session)})
        return _redirect_with_flash("/rbk?tab=tab-supply", "success", msg)
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"Confirm delivery failed: {exc}"}, status=400)
        return _redirect_with_flash("/rbk?tab=tab-supply", "error", f"Confirm delivery failed: {exc}")


def handle_rbk_ccrc_verify(request: Request) -> Response:
    session, redir = _require_role(request, "rbk")
    if redir:
        return redir
    try:
        tenure_id = rbk_service.verify_tenant_ccrc(request.form)
        msg = f"CCRC Lease {tenure_id} updated: approval_status = 'VERIFIED_BY_VAA'. Tenant farmer is now entitled to subsidized inputs & credit!"
        if _wants_json(request):
            return _json_response({"ok": True, "message": msg, "tab": "tab-ccrc", "fragments": _rbk_fragments(session)})
        return _redirect_with_flash("/rbk?tab=tab-ccrc", "success", msg)
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"CCRC verification blocked: {exc}"}, status=400)
        return _redirect_with_flash("/rbk?tab=tab-ccrc", "error", f"CCRC verification blocked: {exc}")


def handle_rbk_pos_dispense(request: Request) -> Response:
    session, redir = _require_role(request, "rbk")
    if redir:
        return redir
    try:
        receipt = rbk_service.dispense_input_pos(session["rbk_id"], session["user_id"], request.form)
        msg = f"POS Sale {receipt['purchase_id']} complete! Trigger updated rbk_inventory & logged OUT movement."
        if _wants_json(request):
            return _json_response({
                "ok": True,
                "message": msg,
                "tab": "tab-pos",
                "pos_receipt": receipt,
                "fragments": _rbk_fragments(session, pos_receipt=receipt),
            })
        return _redirect_with_flash("/rbk?tab=tab-pos", "success", msg, result_payload={"pos_receipt": receipt})
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"POS Transaction Blocked: {exc}"}, status=400)
        return _redirect_with_flash("/rbk?tab=tab-pos", "error", f"POS Transaction Blocked: {exc}")


def handle_rbk_advisory_log(request: Request) -> Response:
    session, redir = _require_role(request, "rbk")
    if redir:
        return redir
    try:
        app_id = rbk_service.log_agronomic_advisory(request.form, session["name"])
        msg = f"Agronomic advisory {app_id} recorded in input_applications with chemical lot traceability."
        if _wants_json(request):
            return _json_response({"ok": True, "message": msg, "tab": "tab-advisory", "fragments": _rbk_fragments(session)})
        return _redirect_with_flash("/rbk?tab=tab-advisory", "success", msg)
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"Advisory log failed: {exc}"}, status=400)
        return _redirect_with_flash("/rbk?tab=tab-advisory", "error", f"Advisory log failed: {exc}")


def handle_rbk_quality_certify(request: Request) -> Response:
    session, redir = _require_role(request, "rbk")
    if redir:
        return redir
    try:
        cert = rbk_service.certify_harvest_batch(request.form, session["name"])
        msg = f"Batch {cert['batch_code']} certified ({cert['quality_grade']}, {cert['moisture_percentage']}%) and listed {cert['batch_status']}!"
        if _wants_json(request):
            return _json_response({
                "ok": True,
                "message": msg,
                "tab": "tab-quality",
                "qr_cert": cert,
                "fragments": _rbk_fragments(session, qr_cert=cert),
            })
        return _redirect_with_flash("/rbk?tab=tab-quality", "success", msg, result_payload={"qr_cert": cert})
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"Certification failed: {exc}"}, status=400)
        return _redirect_with_flash("/rbk?tab=tab-quality", "error", f"Certification failed: {exc}")


def handle_rbk_dispatch(request: Request) -> Response:
    session, redir = _require_role(request, "rbk")
    if redir:
        return redir
    try:
        shp_id = rbk_service.dispatch_sales_order(request.form, session["name"])
        msg = f"Truck dispatch manifest {shp_id} confirmed! Batch status updated to IN_TRANSIT."
        if _wants_json(request):
            return _json_response({"ok": True, "message": msg, "tab": "tab-quality", "fragments": _rbk_fragments(session)})
        return _redirect_with_flash("/rbk?tab=tab-quality", "success", msg)
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"Dispatch failed: {exc}"}, status=400)
        return _redirect_with_flash("/rbk?tab=tab-quality", "error", f"Dispatch failed: {exc}")


def handle_rbk_preorder_status(request: Request) -> Response:
    session, redir = _require_role(request, "rbk")
    if redir:
        return redir
    try:
        rbk_service.update_preorder_status(
            (request.form.get("preorder_id") or "").strip(),
            (request.form.get("order_status") or "").strip(),
        )
        msg = "Pre-booking order status updated."
        if _wants_json(request):
            return _json_response({"ok": True, "message": msg, "tab": "tab-directory", "fragments": _rbk_fragments(session)})
        return _redirect_with_flash("/rbk?tab=tab-directory", "success", msg)
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"Update failed: {exc}"}, status=400)
        return _redirect_with_flash("/rbk?tab=tab-directory", "error", f"Update failed: {exc}")


# ==================== FARMER HOME & ACTIONS ====================

def handle_farmer_home(request: Request) -> Response:
    session, redir = _require_role(request, "farmer")
    if redir:
        return redir
    lctx, clear = _layout_ctx(request, session, "Farmer Home")
    data = farmer_service.get_farmer_dashboard_data(session["user_id"])
    ctx = build_farmer_context(session, data)
    return _html_response(render_page("farmer_home.html", lctx, **ctx), clear)


def handle_farmer_preorder(request: Request) -> Response:
    session, redir = _require_role(request, "farmer")
    if redir:
        return redir
    try:
        pbo = farmer_service.create_pre_booking(session["user_id"], request.form)
        msg = f"Pre-booking {pbo} submitted to RBK."
        if _wants_json(request):
            return _json_response({"ok": True, "message": msg, "tab": "ftab-inputs", "fragments": _farmer_fragments(session)})
        return _redirect_with_flash("/farmer?tab=ftab-inputs", "success", msg)
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"Pre-booking failed: {exc}"}, status=400)
        return _redirect_with_flash("/farmer?tab=ftab-inputs", "error", f"Pre-booking failed: {exc}")


def handle_farmer_cultivation(request: Request) -> Response:
    session, redir = _require_role(request, "farmer")
    if redir:
        return redir
    try:
        cid = farmer_service.create_cultivation(session["user_id"], request.form)
        msg = f"Cultivation {cid} registered."
        if _wants_json(request):
            return _json_response({"ok": True, "message": msg, "tab": "ftab-cultivation", "fragments": _farmer_fragments(session)})
        return _redirect_with_flash("/farmer?tab=ftab-cultivation", "success", msg)
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"Cultivation failed: {exc}"}, status=400)
        return _redirect_with_flash("/farmer?tab=ftab-cultivation", "error", f"Cultivation failed: {exc}")


def handle_farmer_activity(request: Request) -> Response:
    session, redir = _require_role(request, "farmer")
    if redir:
        return redir
    try:
        aid = farmer_service.add_cultivation_activity(session["user_id"], request.form)
        msg = f"Activity {aid} recorded."
        if _wants_json(request):
            return _json_response({"ok": True, "message": msg, "tab": "ftab-cultivation", "fragments": _farmer_fragments(session)})
        return _redirect_with_flash("/farmer?tab=ftab-cultivation", "success", msg)
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"Activity error: {exc}"}, status=400)
        return _redirect_with_flash("/farmer?tab=ftab-cultivation", "error", f"Activity error: {exc}")


# ==================== BUYER HOME & ACTIONS ====================

def handle_buyer_home(request: Request) -> Response:
    session, redir = _require_role(request, "buyer")
    if redir:
        return redir
    lctx, clear = _layout_ctx(request, session, "Buyer Home")
    res_data = decode_signed_data(request.cookies.get(RESULT_COOKIE))
    if res_data:
        clear.append(RESULT_COOKIE)
    settlement = res_data.get("settlement") if res_data else None

    passport_code = (request.args.get("passport_code") or request.args.get("passport") or "").strip() or None
    data = buyer_service.get_buyer_dashboard_data(session["user_id"], passport_code=passport_code)
    ctx = build_buyer_context(session, data, settlement)
    return _html_response(render_page("buyer_home.html", lctx, **ctx), clear)


def handle_buyer_order_create(request: Request) -> Response:
    session, redir = _require_role(request, "buyer")
    if redir:
        return redir
    try:
        res = buyer_service.place_escrow_purchase_order(session["user_id"], session["name"], request.form)
        msg = f"Order {res['sales_order_id']} created! ₹{res['total_amount']:,.2f} locked in Escrow ({res['escrow_ref']}, payment_status='ESCROW_HELD')."
        if _wants_json(request):
            return _json_response({"ok": True, "message": msg, "tab": "btab-logistics", "fragments": _buyer_fragments(session)})
        return _redirect_with_flash("/buyer?tab=btab-logistics", "success", msg)
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"Order failed: {exc}"}, status=400)
        return _redirect_with_flash("/buyer?tab=btab-market", "error", f"Order failed: {exc}")


def handle_buyer_dispatch(request: Request) -> Response:
    session, redir = _require_role(request, "buyer")
    if redir:
        return redir
    try:
        shp_id = buyer_service.book_transport_dispatch(session["user_id"], session["name"], request.form)
        msg = f"Dispatch manifest {shp_id} created! Batch is now IN_TRANSIT."
        if _wants_json(request):
            return _json_response({"ok": True, "message": msg, "tab": "btab-logistics", "fragments": _buyer_fragments(session)})
        return _redirect_with_flash("/buyer?tab=btab-logistics", "success", msg)
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"Dispatch failed: {exc}"}, status=400)
        return _redirect_with_flash("/buyer?tab=btab-logistics", "error", f"Dispatch failed: {exc}")


def handle_buyer_settle(request: Request) -> Response:
    session, redir = _require_role(request, "buyer")
    if redir:
        return redir
    try:
        summary = buyer_service.confirm_delivery_and_settle(
            session["user_id"],
            session["name"],
            (request.form.get("sales_order_id") or "").strip(),
        )
        msg = f"Delivery Confirmed! Escrow COMPLETED. ₹{summary['offset_deducted']:,.2f} cleared KCC debt; ₹{summary['net_dbt_payout']:,.2f} DBT transferred to {summary['farmer_name']}."
        if _wants_json(request):
            return _json_response({
                "ok": True,
                "message": msg,
                "tab": "btab-logistics",
                "settlement": summary,
                "fragments": _buyer_fragments(session, settlement=summary),
            })
        return _redirect_with_flash("/buyer?tab=btab-logistics", "success", msg, result_payload={"settlement": summary})
    except Exception as exc:
        if _wants_json(request):
            return _json_response({"ok": False, "message": f"Settlement failed: {exc}"}, status=400)
        return _redirect_with_flash("/buyer?tab=btab-logistics", "error", f"Settlement failed: {exc}")


URL_MAP = Map([
    Rule("/", endpoint=handle_role_select, methods=["GET"]),
    Rule("/api/health", endpoint=handle_api_health, methods=["GET"]),
    Rule("/api/rbk/state", endpoint=handle_api_rbk_state, methods=["GET"]),
    Rule("/api/farmer/state", endpoint=handle_api_farmer_state, methods=["GET"]),
    Rule("/api/buyer/state", endpoint=handle_api_buyer_state, methods=["GET"]),
    Rule("/api/buyer/passport", endpoint=handle_api_buyer_passport, methods=["GET"]),

    Rule("/setup", endpoint=handle_setup, methods=["GET", "POST"]),
    Rule("/login/rbk", endpoint=handle_login_rbk, methods=["GET", "POST"]),
    Rule("/login/farmer", endpoint=handle_login_farmer, methods=["GET", "POST"]),
    Rule("/login/buyer", endpoint=handle_login_buyer, methods=["GET", "POST"]),
    Rule("/buyer/register", endpoint=handle_buyer_register, methods=["POST"]),
    Rule("/logout", endpoint=handle_logout, methods=["GET"]),

    Rule("/rbk", endpoint=handle_rbk_home, methods=["GET"]),
    Rule("/rbk/farmer/step1", endpoint=handle_rbk_farmer_step1, methods=["POST"]),
    Rule("/rbk/farmer/step2", endpoint=handle_rbk_farmer_step2, methods=["POST"]),
    Rule("/rbk/farmer/step3", endpoint=handle_rbk_farmer_step3, methods=["POST"]),
    Rule("/rbk/supply/create", endpoint=handle_rbk_supply_create, methods=["POST"]),
    Rule("/rbk/supply/confirm", endpoint=handle_rbk_supply_confirm, methods=["POST"]),
    Rule("/rbk/ccrc/verify", endpoint=handle_rbk_ccrc_verify, methods=["POST"]),
    Rule("/rbk/pos/dispense", endpoint=handle_rbk_pos_dispense, methods=["POST"]),
    Rule("/rbk/advisory/log", endpoint=handle_rbk_advisory_log, methods=["POST"]),
    Rule("/rbk/quality/certify", endpoint=handle_rbk_quality_certify, methods=["POST"]),
    Rule("/rbk/dispatch", endpoint=handle_rbk_dispatch, methods=["POST"]),
    Rule("/rbk/preorder/status", endpoint=handle_rbk_preorder_status, methods=["POST"]),

    Rule("/farmer", endpoint=handle_farmer_home, methods=["GET"]),
    Rule("/farmer/preorder/add", endpoint=handle_farmer_preorder, methods=["POST"]),
    Rule("/farmer/cultivation/add", endpoint=handle_farmer_cultivation, methods=["POST"]),
    Rule("/farmer/activity/add", endpoint=handle_farmer_activity, methods=["POST"]),

    Rule("/buyer", endpoint=handle_buyer_home, methods=["GET"]),
    Rule("/buyer/order/create", endpoint=handle_buyer_order_create, methods=["POST"]),
    Rule("/buyer/dispatch", endpoint=handle_buyer_dispatch, methods=["POST"]),
    Rule("/buyer/settle", endpoint=handle_buyer_settle, methods=["POST"]),
])


def wsgi_app(environ, start_response):
    request = Request(environ)
    adapter = URL_MAP.bind_to_environ(environ)
    try:
        endpoint, values = adapter.match()
        response = endpoint(request, **values)
    except HTTPException as exc:
        response = exc.get_response(environ)
    return response(environ, start_response)


application = SharedDataMiddleware(
    wsgi_app,
    {"/static": str(BASE_DIR / "static")},
)


def _find_available_port(host: str, start_port: int) -> int:
    for port in range(start_port, start_port + 20):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            if sock.connect_ex((host, port)) != 0:
                return port
    return start_port


def main():
    ok, msg = ensure_db_ready()
    port = _find_available_port(APP_HOST, APP_PORT)
    target_path = "/" if ok else "/setup"
    url = f"http://{APP_HOST}:{port}{target_path}"

    print("\n========================================================")
    print("  AgriChain Web Application is Starting!")
    print(f"  Open in browser: {url}")
    if ok:
        print(f"  MySQL Status:    READY ({msg})")
    else:
        print("  MySQL Status:    Setup needed (opening /setup page in browser)")
    print("  Press Ctrl+C in terminal to stop the server.")
    print("========================================================\n")

    if os.environ.get("AGRICHAIN_NO_BROWSER") != "1":
        threading.Timer(0.9, lambda: webbrowser.open(url)).start()

    run_simple(APP_HOST, port, application, use_debugger=False, use_reloader=False, threaded=True)


if __name__ == "__main__":
    main()
