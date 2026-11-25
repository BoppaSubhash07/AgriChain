"""Configuration loader for AgriChain web application."""

import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent


def _load_dotenv(env_path: Path) -> None:
    """Load simple KEY=VALUE lines from .env without overriding existing env vars."""
    if not env_path.is_file():
        return
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


_load_dotenv(BASE_DIR / ".env")

DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "127.0.0.1"),
    "port": int(os.environ.get("DB_PORT", "3306")),
    "user": os.environ.get("DB_USER", "root"),
    "password": os.environ.get("DB_PASSWORD", ""),
    "database": os.environ.get("DB_NAME", "agri_management_database"),
    "charset": "utf8mb4",
    "use_unicode": True,
}

APP_HOST = os.environ.get("APP_HOST", "127.0.0.1")
APP_PORT = int(os.environ.get("APP_PORT", "5050"))
APP_SECRET = os.environ.get("APP_SECRET", "agrichain-rbk-2026-hmac-secret-key")


def save_and_reload_db_config(host: str, port: int, user: str, password: str, database: str) -> None:
    """Persist MySQL settings to .env and mutate DB_CONFIG in-place."""
    os.environ["DB_HOST"] = host
    os.environ["DB_PORT"] = str(port)
    os.environ["DB_USER"] = user
    os.environ["DB_PASSWORD"] = password
    os.environ["DB_NAME"] = database

    DB_CONFIG.update({
        "host": host,
        "port": int(port),
        "user": user,
        "password": password,
        "database": database,
    })

    env_content = (
        "# Auto-configured by AgriChain Setup\n"
        f"DB_HOST={host}\n"
        f"DB_PORT={int(port)}\n"
        f"DB_USER={user}\n"
        f"DB_PASSWORD={password}\n"
        f"DB_NAME={database}\n"
        f"APP_HOST={APP_HOST}\n"
        f"APP_PORT={APP_PORT}\n"
        f"APP_SECRET={APP_SECRET}\n"
    )
    (BASE_DIR / ".env").write_text(env_content, encoding="utf-8")


# Scientific input dosage quota per verified acre (bags / packs / bottles per acre per season)
QUOTA_RULES_PER_ACRE = {
    "Nitrogenous": 2.0,     # e.g., 2 acres of Paddy -> max 4 bags of Urea
    "Complex": 1.5,         # DAP / 20-20-0-13
    "Potassic": 1.0,        # MOP
    "Certified Seed": 2.0,
    "Hybrid Seed": 2.0,
    "Bio-Fertilizer": 2.0,
    "Insecticide": 2.0,
    "Fungicide": 2.0,
    "Herbicide": 2.0,
    "Micronutrient": 2.0,
    "Bio-Stimulant": 2.0,
    "Water Soluble": 1.5,
    "Soil Amendment": 3.0,
    "Packaging": 10.0,
}

# Exact private retail market price references for subsidy savings comparison on RBK POS receipts
# For Urea 45kg: RBK ₹266.50 vs Retail ₹401.50 => 4 bags = ₹1,066 paid, ₹540 saved!
RETAIL_MARKET_PRICES = {
    "PROD-01": 401.50,
    "PROD-21": 401.50,
    "PROD-02": 1680.00,
    "PROD-25": 1680.00,
    "PROD-03": 1425.00,
    "PROD-04": 540.00,
    "PROD-05": 485.00,
    "PROD-06": 2100.00,
    "PROD-07": 1560.00,
    "PROD-08": 1220.00,
    "PROD-13": 310.00,
    "PROD-14": 780.00,
    "PROD-16": 590.00,
    "PROD-22": 1820.00,
    "PROD-23": 2050.00,
    "PROD-24": 1790.00,
}


def get_retail_unit_price(product_id: str, rbk_unit_price: float) -> float:
    """Return private retail reference unit price for subsidy savings calculation."""
    if product_id in RETAIL_MARKET_PRICES:
        return float(RETAIL_MARKET_PRICES[product_id])
    return round(float(rbk_unit_price) * 1.32, 2)
