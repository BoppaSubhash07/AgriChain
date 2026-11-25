# AgriChain — RBK Digital Agriculture & Traceability System

Full-stack dynamic web application built with **Python (Werkzeug + MarkupSafe + mysql-connector-python)**, **HTML/CSS/JS**, and **MySQL 8+**.

## 1. Easiest Way to Run in VS Code (1 Click)

1. Open [run.py](run.py) (or [AgriChain/app.py](AgriChain/app.py)) in VS Code.
2. Click the **▶ Run Python File** button at the top-right (or press **F5**).
3. Your browser opens automatically:
   - If MySQL is not yet connected, it opens the **1-Click Database Setup page** (`/setup`) where you type your MySQL password once — AgriChain saves `.env`, creates/upgrades `agri_management_database`, installs `trg_after_input_purchase_item_insert`, seeds all master tables, and takes you straight to the Role Selection screen (`/`).
   - If MySQL is already configured, it opens the **Role Selection page** (`/`) immediately.

## 2. Optional Command-Line Setup (if preferred)

```bash
cd AgriChain
python3 app.py
```

## 3. Portals & Demo Credentials

| Portal | Login Field | Password / Auth | Sample Credentials |
|---|---|---|---|
| **RBK Employee** (`/login/rbk`) | Email / Employee ID / Username | `rbk@123` | `officer.tenali@agrichain.gov.in` (`EMP-001`), `anitha.p@agrichain.gov.in` (`EMP-002`), `madhava.custodian@agrichain.gov.in` (`EMP-011`) |
| **Farmer** (`/login/farmer`) | Farmer ID / Phone | `farmer@123` **or** Biometric Aadhaar Last-4 | `FAR-001` / `9848011223` (Aadhaar last-4: `9812`), `FAR-012` / `9848012412` (Aadhaar last-4: `4129`) |
| **Institutional Buyer** (`/login/buyer`) | Buyer ID / Org Email | `buyer@123` (or register new org) | `procure@itcagri.com` (`BUY-001`), `sourcing@bigbasket.com` (`BUY-002`), `spices.ap@allanasons.com` (`BUY-011`) |
