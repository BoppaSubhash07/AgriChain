"""Verification suite for AgriChain routes, templates, SQL parsing, and service workflows."""

import hashlib
import re
import sys
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from werkzeug.test import Client
from werkzeug.wrappers import Response
import app as agrichain_app
import auth
import init_db
from services import buyer_service, rbk_service


class TestStaticAndTemplates(unittest.TestCase):
    def test_all_templates_present_and_non_empty(self):
        templates_dir = ROOT / "templates"
        expected = {
            "layout.html",
            "role_select.html",
            "login_rbk.html",
            "login_farmer.html",
            "login_buyer.html",
            "rbk_home.html",
            "farmer_home.html",
            "buyer_home.html",
        }
        actual = {p.name for p in templates_dir.glob("*.html")}
        self.assertTrue(expected.issubset(actual))
        for html_file in templates_dir.glob("*.html"):
            self.assertGreater(len(html_file.read_text(encoding="utf-8")), 100)

    def test_sql_splitter_parses_upgrade_and_full_scripts(self):
        upg_stmts = init_db.split_sql_statements(
            (ROOT / "sql" / "agrichain_upgrade_and_seed.sql").read_text(encoding="utf-8")
        )
        full_stmts = init_db.split_sql_statements(
            (ROOT / "sql" / "agrichain_full_database.sql").read_text(encoding="utf-8")
        )
        self.assertGreater(len(upg_stmts), 20)
        self.assertGreater(len(full_stmts), 100)
        self.assertTrue(
            any("trg_after_input_purchase_item_insert" in s for s in upg_stmts),
            "Missing MySQL trigger trg_after_input_purchase_item_insert",
        )

    def test_auth_password_hashing_and_signed_cookies(self):
        h1 = auth.hash_password("rbk@123")
        self.assertTrue(auth.verify_password("rbk@123", h1))
        self.assertFalse(auth.verify_password("wrong", h1))

        sha = hashlib.sha256(b"farmer@123").hexdigest()
        self.assertTrue(auth.verify_password("farmer@123", sha))

        tok = auth.encode_signed_data({"role": "rbk", "user_id": "EMP-001"})
        decoded = auth.decode_signed_data(tok)
        self.assertEqual(decoded["user_id"], "EMP-001")
        self.assertIsNone(auth.decode_signed_data(tok + "tampered"))


class TestBusinessWorkflows(unittest.TestCase):
    def test_ccrc_requires_non_encumbrance_and_max_11_months(self):
        with self.assertRaises(ValueError) as ctx:
            rbk_service.verify_tenant_ccrc({
                "tenure_id": "TEN-412",
                "lease_months": "11",
                "owner_consent": "1",
                "decision": "VERIFIED_BY_VAA",
            })
        self.assertIn("Non-Encumbrance", str(ctx.exception))

        with self.assertRaises(ValueError) as ctx2:
            rbk_service.verify_tenant_ccrc({
                "tenure_id": "TEN-412",
                "lease_months": "18",
                "non_encumbrance_clause": "1",
                "owner_consent": "1",
                "decision": "VERIFIED_BY_VAA",
            })
        self.assertIn("11 months", str(ctx2.exception))

    def test_pos_quota_lock_and_exact_savings_receipt(self):
        bio_row = {"farmer_name": "Demo Farmer", "aadhaar_number": "XXXX-XXXX-9812", "biometric_type": "Fingerprint", "status": "Verified"}
        inv_row = {
            "inventory_id": "RINV-21",
            "stock_qty": 198,
            "product_id": "PROD-21",
            "product_name": "IFFCO Neem Coated Urea 46% N (45kg)",
            "price": 266.50,
            "product_type": "Nitrogenous",
            "unit": "Bag (45kg)",
            "batch_number": "IFFCO-NCU-2026-01",
        }
        acre_info = {"owned_acres": 2.0, "leased_in_acres": 0.0, "total_acres": 2.0}

        # Requesting 20 bags for 2 acres (max 4 bags) must lock sale
        with patch("services.rbk_service.query_one", side_effect=[bio_row, inv_row]), \
             patch("services.rbk_service.get_farmer_verified_acreage", return_value=acre_info):
            with self.assertRaises(ValueError) as err:
                rbk_service.dispense_input_pos(
                    "RBK-GNT-01",
                    "EMP-001",
                    {"farmer_id": "FAR-001", "product_batch_id": "PBAT-21", "quantity": "20", "payment_method": "Cash", "biometric_verified": "1"},
                )
            self.assertIn("QUOTA VIOLATION LOCKED", str(err.exception))

        # Requesting 4 bags of Urea via KCC succeeds with ₹1,066 paid and ₹540 saved
        mock_cur = MagicMock()
        mock_cur.fetchone.return_value = {"credit_account_id": "CRED-001", "available_balance": 50000.0}

        @contextmanager
        def fake_tx():
            yield mock_cur

        with patch("services.rbk_service.query_one", side_effect=[bio_row, inv_row]), \
             patch("services.rbk_service.get_farmer_verified_acreage", return_value=acre_info), \
             patch("services.rbk_service.transaction", fake_tx):
            receipt = rbk_service.dispense_input_pos(
                "RBK-GNT-01",
                "EMP-001",
                {"farmer_id": "FAR-001", "product_batch_id": "PBAT-21", "quantity": "4", "payment_method": "KCC", "biometric_verified": "1"},
            )
        self.assertEqual(receipt["total_amount"], 1066.0)
        self.assertEqual(receipt["savings"], 540.0)

    def test_buyer_credit_offset_settlement_math(self):
        mock_cur = MagicMock()
        mock_cur.fetchone.side_effect = [
            {"sales_order_id": "SO-005", "farmer_id": "FAR-001", "farmer_name": "Ramesh Babu", "total_amount": 145000.0, "order_status": "Shipped", "payment_status": "ESCROW_HELD", "delivery_address": "ITC Guntur"},
            {"payment_id": "SPAY-004"},
        ]
        mock_cur.fetchall.side_effect = [
            [{"crop_batch_id": "CBAT-002"}],
            [{"credit_account_id": "CRED-001", "total_credit_limit": 350000.0, "available_balance": 325000.0}],
        ]

        @contextmanager
        def fake_tx():
            yield mock_cur

        with patch("services.buyer_service.transaction", fake_tx):
            res = buyer_service.confirm_delivery_and_settle("BUY-001", "ITC Agri", "SO-005")
        self.assertEqual(res["gross_amount"], 145000.0)
        self.assertEqual(res["kcc_debt_before"], 25000.0)
        self.assertEqual(res["offset_deducted"], 25000.0)
        self.assertEqual(res["net_dbt_payout"], 120000.0)


class TestWsgiRoutingAndMockedPortals(unittest.TestCase):
    def setUp(self):
        self.client = Client(agrichain_app.application, Response)

    def test_public_pages_render_and_eye_svg_present(self):
        with patch("app.check_db_health", return_value=(True, "Mocked MySQL OK")):
            resp = self.client.get("/")
            self.assertEqual(resp.status_code, 200)
            body = resp.get_data(as_text=True)
            self.assertIn("RBK Employee", body)
            self.assertIn("Farmer", body)
            self.assertIn("Institutional Buyer", body)

        for path in ("/setup", "/login/rbk", "/login/farmer", "/login/buyer"):
            resp = self.client.get(path)
            self.assertEqual(resp.status_code, 200)
            body = resp.get_data(as_text=True)
            self.assertIn("data-eye-toggle", body, f"Animated eye missing on {path}")
            self.assertIn("eye-lid-upper", body)

        with patch("app.check_db_health", return_value=(False, "Access denied")):
            resp = self.client.get("/")
            self.assertEqual(resp.status_code, 302)
            self.assertTrue(resp.headers["Location"].endswith("/setup"))

        farmer_login = self.client.get("/login/farmer").get_data(as_text=True)
        self.assertIn("Biometric Sign-In", farmer_login)

    def test_protected_routes_redirect_when_unauthenticated(self):
        for route, expected_login in (("/rbk", "/login/rbk"), ("/farmer", "/login/farmer"), ("/buyer", "/login/buyer")):
            resp = self.client.get(route)
            self.assertEqual(resp.status_code, 302)
            self.assertTrue(resp.headers["Location"].endswith(expected_login))

    def test_static_assets_served(self):
        for asset in ("/static/css/style.css", "/static/js/login.js", "/static/js/qr.js", "/static/js/portal.js"):
            resp = self.client.get(asset)
            self.assertEqual(resp.status_code, 200)
            resp.close()

    def test_all_three_portals_render_cleanly_with_session(self):
        rbk_mock = {
            "centre": {"rbk_id": "RBK-GNT-01", "rbk_name": "Tenali Central RBK", "district": "Guntur"},
            "divisions": [{"region_id": "REG-01", "state_name": "Andhra Pradesh", "district_name": "Guntur", "mandal_name": "Tenali", "village_name": "Angalakuduru", "pincode": "522202"}],
            "companies": [{"company_id": "COMP-10", "company_name": "IFFCO"}],
            "product_batches": [{"product_batch_id": "PBAT-21", "product_id": "PROD-21", "batch_number": "IFFCO-NCU-2026-01", "product_name": "IFFCO Neem Coated Urea", "price": 266.5, "unit": "Bag (45kg)", "product_type": "Nitrogenous", "company_name": "IFFCO"}],
            "products": [],
            "inventory": [{"inventory_id": "RINV-21", "product_id": "PROD-21", "product_batch_id": "PBAT-21", "batch_number": "IFFCO-NCU-2026-01", "product_name": "IFFCO Neem Coated Urea", "product_type": "Nitrogenous", "company_name": "IFFCO", "quantity": 198, "unit": "Bag (45kg)", "price": 266.5}],
            "supply_orders": [{"supply_id": "SUP-005", "item_id": "SUPI-005", "company_name": "IFFCO", "product_name": "Neem Coated Urea", "batch_number": "IFFCO-NCU-2026-01", "ordered_quantity": 200, "received_quantity": 0, "rejected_quantity": 0, "unit": "Bag", "status": "Ordered"}],
            "stock_movements": [],
            "farmers": [{"farmer_id": "FAR-001", "farmer_name": "Ramesh Babu", "phone": "9848011223", "village": "Angalakuduru", "district": "Guntur", "biometric_status": "Verified", "aadhaar_number": "XXXX-XXXX-9812", "verified_acres": 4.5, "leased_in_acres": 0, "kcc_balance": 215000}],
            "credit_accounts": [],
            "land_records": [],
            "ccrc_records": [],
            "cultivations": [],
            "advisories": [],
            "crop_batches": [],
            "warehouses": [{"warehouse_id": "WH-GNT-01", "warehouse_name": "APSWC Guntur", "district": "Guntur"}],
            "pending_dispatches": [],
            "pre_bookings": [],
            "recent_purchases": [],
            "quota_rules": {},
        }
        farmer_mock = {
            "profile": {"farmer_id": "FAR-001", "farmer_name": "Ramesh Babu", "phone": "9848011223", "biometric_status": "Verified", "aadhaar_number": "XXXX-XXXX-9812", "registration_date": "2026-01-01"},
            "addresses": [], "land_records": [], "credit_accounts": [], "farm_fields": [],
            "seasonal_rights": [], "input_purchases": [], "pre_bookings": [], "buyer_orders": [],
            "soil_health": [], "cultivations": [], "cultivation_activities": [], "seasonal_inputs_used": [],
            "rbk_centres": [], "products": [], "seasons": [], "varieties": [],
        }
        buyer_mock = {
            "buyer": {"buyer_id": "BUY-001", "buyer_name": "ITC Agri Business", "buyer_type": "Exporter", "registration_number": "GSTIN37AAACI1234F1Z1", "email": "procure@itcagri.com", "phone": "9848111222", "address": "Guntur"},
            "crop_categories": [], "marketplace_batches": [], "orders": [], "warehouses": [], "all_batches_index": [], "passport": None,
        }

        with patch("app.authenticate_rbk_employee", return_value={"role": "rbk", "user_id": "EMP-001", "name": "K. Subba Rao", "designation": "AEO", "rbk_id": "RBK-GNT-01", "rbk_name": "Tenali Central RBK", "district": "Guntur"}):
            with patch("services.rbk_service.get_rbk_dashboard_data", return_value=rbk_mock):
                login_resp = self.client.post("/login/rbk", data={"identifier": "EMP-001", "password": "rbk@123"})
                self.assertEqual(login_resp.status_code, 302)
                page_resp = self.client.get("/rbk")
                self.assertEqual(page_resp.status_code, 200)
                rbk_html = page_resp.get_data(as_text=True)
                self.assertIn("Tenali Central RBK", rbk_html)
                self.assertNotRegex(rbk_html, re.compile(r"\{\{[a-zA-Z0-9_]+\}\}"))

        with patch("app.authenticate_farmer_password", return_value={"role": "farmer", "user_id": "FAR-001", "name": "Ramesh Babu", "phone": "9848011223"}):
            with patch("services.farmer_service.get_farmer_dashboard_data", return_value=farmer_mock):
                self.client.post("/login/farmer", data={"identifier": "FAR-001", "password": "farmer@123"})
                page_resp = self.client.get("/farmer")
                self.assertEqual(page_resp.status_code, 200)
                f_html = page_resp.get_data(as_text=True)
                self.assertIn("Ramesh Babu", f_html)
                self.assertNotRegex(f_html, re.compile(r"\{\{[a-zA-Z0-9_]+\}\}"))

        with patch("app.authenticate_buyer", return_value={"role": "buyer", "user_id": "BUY-001", "name": "ITC Agri Business", "buyer_type": "Exporter"}):
            with patch("services.buyer_service.get_buyer_dashboard_data", return_value=buyer_mock):
                self.client.post("/login/buyer", data={"identifier": "BUY-001", "password": "buyer@123"})
                page_resp = self.client.get("/buyer")
                self.assertEqual(page_resp.status_code, 200)
                b_html = page_resp.get_data(as_text=True)
                self.assertIn("ITC Agri Business", b_html)
                self.assertNotRegex(b_html, re.compile(r"\{\{[a-zA-Z0-9_]+\}\}"))

    def test_dynamic_api_endpoints_and_async_posts(self):
        # 1. /api/health telemetry endpoint
        sample_metrics = {
            "farmers_count": 3,
            "rbk_centers_count": 2,
            "crop_batches_count": 4,
            "certified_kg": 9200.0,
            "sales_orders_count": 2,
            "db_latency_ms": 1.4,
        }
        with patch("app.check_db_health", return_value=(True, "Connected")):
            with patch("app._query_gateway_metrics", return_value=sample_metrics):
                resp = self.client.get("/api/health")
                self.assertEqual(resp.status_code, 200)
                payload = resp.get_json()
                self.assertTrue(payload["ok"])
                self.assertEqual(payload["metrics"]["farmers_count"], 3)

        # 2. Unauthenticated /api/*/state returns 401 JSON redirect instead of HTML 302
        unauth = self.client.get("/api/rbk/state", headers={"X-Requested-With": "fetch"})
        self.assertEqual(unauth.status_code, 401)
        unauth_data = unauth.get_json()
        self.assertFalse(unauth_data["ok"])
        self.assertEqual(unauth_data["redirect"], "/login/rbk")

        # 3. Authenticated RBK state sync + async Step 1 POST
        with patch("app.authenticate_rbk_employee", return_value={"role": "rbk", "user_id": "EMP-001", "name": "S. Venkateswara Rao", "designation": "AEO", "rbk_id": "RBK-GNT-01", "rbk_name": "Tenali Central RBK", "district": "Guntur"}):
            self.client.post("/login/rbk", data={"identifier": "EMP-001", "password": "rbk@123"})
            with patch("app._rbk_fragments", return_value={"kpi_inv_count": "9", "farmer_directory_rows": "<tr></tr>"}):
                state_resp = self.client.get("/api/rbk/state")
                self.assertEqual(state_resp.status_code, 200)
                state_json = state_resp.get_json()
                self.assertTrue(state_json["ok"])
                self.assertEqual(state_json["fragments"]["kpi_inv_count"], "9")

                with patch("services.rbk_service.register_farmer_step1", return_value="FRM-099"):
                    post_resp = self.client.post(
                        "/rbk/farmer/step1",
                        data={"farmer_name": "K. Rao", "phone": "9848011122", "village": "Tenali", "mandal": "Tenali", "district": "Guntur", "pincode": "522201", "aadhaar_number": "999988887777", "password": "pw"},
                        headers={"X-Requested-With": "fetch", "Accept": "application/json"},
                    )
                    self.assertEqual(post_resp.status_code, 200)
                    post_json = post_resp.get_json()
                    self.assertTrue(post_json["ok"])
                    self.assertEqual(str(post_json["step"]), "2")
                    self.assertEqual(post_json["farmer_id"], "FRM-099")

        # 4. Authenticated Farmer state sync + async preorder POST
        with patch("app.authenticate_farmer_password", return_value={"role": "farmer", "user_id": "FRM-001", "name": "R. Narayana", "phone": "9848011223"}):
            self.client.post("/login/farmer", data={"login_mode": "password", "identifier": "FRM-001", "password": "farmer@123"})
            with patch("app._farmer_fragments", return_value={"kpi_prebook_count": "4"}):
                f_state = self.client.get("/api/farmer/state")
                self.assertEqual(f_state.status_code, 200)
                self.assertEqual(f_state.get_json()["fragments"]["kpi_prebook_count"], "4")

                with patch("services.farmer_service.create_pre_booking", return_value="PRE-900"):
                    f_post = self.client.post(
                        "/farmer/preorder/add",
                        data={"rbk_id": "RBK-GNT-01", "product_id": "PRD-01", "requested_quantity": "3", "target_season": "Kharif", "target_year": "2026"},
                        headers={"X-Requested-With": "fetch", "Accept": "application/json"},
                    )
                    self.assertEqual(f_post.status_code, 200)
                    self.assertTrue(f_post.get_json()["ok"])

        # 5. Authenticated Buyer state sync, passport lookup JSON, & async order POST
        with patch("app.authenticate_buyer", return_value={"role": "buyer", "user_id": "BUY-001", "name": "ITC Agri Business", "buyer_type": "Exporter"}):
            self.client.post("/login/buyer", data={"identifier": "BUY-001", "password": "buyer@123"})
            with patch("app._buyer_fragments", return_value={"kpi_market_lots": "5"}):
                b_state = self.client.get("/api/buyer/state")
                self.assertEqual(b_state.status_code, 200)
                self.assertEqual(b_state.get_json()["fragments"]["kpi_market_lots"], "5")

                with patch("services.buyer_service.place_escrow_purchase_order", return_value={"sales_order_id": "ORD-999", "total_amount": 13000.0, "escrow_ref": "ESC-999"}):
                    b_post = self.client.post(
                        "/buyer/order/create",
                        data={"crop_batch_id": "CB-001", "order_quantity": "500", "unit_price": "26.00", "delivery_address": "Guntur Port"},
                        headers={"X-Requested-With": "fetch", "Accept": "application/json"},
                    )
                    self.assertEqual(b_post.status_code, 200)
                    self.assertTrue(b_post.get_json()["ok"])

            with patch("services.buyer_service.get_batch_passport", return_value={"batch": {"batch_code": "CB-001", "qr_code": "AGRI-QR-001", "crop_name": "Paddy", "variety_name": "BPT 5204", "farmer_name": "R. Narayana", "village": "Tenali", "survey_number": "Sy. 214", "moisture_percentage": 11.2, "quality_grade": "Grade A+", "quality_status": "Passed", "batch_status": "READY_FOR_SALE", "season_name": "Kharif 2026", "sowing_date": "2026-06-15", "harvest_date": "2026-11-20"}, "soil": None, "applications": [], "events": []}):
                p_resp = self.client.get("/api/buyer/passport?code=AGRI-QR-001")
                self.assertEqual(p_resp.status_code, 200)
                p_json = p_resp.get_json()
                self.assertTrue(p_json["ok"])
                self.assertIn("AGRI-QR-001", p_json["html"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
