"""Database initialization and upgrade runner for AgriChain (MySQL)."""

import re
import sys
from pathlib import Path
import mysql.connector
from config import BASE_DIR, DB_CONFIG


def split_sql_statements(sql_text: str) -> list[str]:
    """Split a MySQL script respecting DELIMITER directives and quoted strings."""
    statements: list[str] = []
    delimiter = ";"
    buf: list[str] = []

    for line in sql_text.splitlines():
        stripped = line.strip()
        if stripped.upper().startswith("DELIMITER "):
            pending = "\n".join(buf).strip()
            if pending:
                statements.append(pending)
                buf.clear()
            delimiter = stripped.split(None, 1)[1].strip()
            continue

        buf.append(line)
        joined = "\n".join(buf)
        if joined.rstrip().endswith(delimiter):
            stmt = joined.rstrip()[:-len(delimiter)].strip()
            if stmt:
                statements.append(stmt)
            buf.clear()

    tail = "\n".join(buf).strip()
    if tail:
        if tail.endswith(delimiter):
            tail = tail[:-len(delimiter)].strip()
        if tail:
            statements.append(tail)

    # Filter out pure comment blocks
    cleaned: list[str] = []
    for stmt in statements:
        no_comments = re.sub(r"/\*.*?\*/", "", stmt, flags=re.S)
        lines = [ln for ln in no_comments.splitlines() if not ln.strip().startswith("--")]
        if "\n".join(lines).strip():
            cleaned.append(stmt)
    return cleaned


def run_sql_file(conn, path: Path) -> int:
    """Execute all statements in a SQL script on an open MySQL connection."""
    sql_text = path.read_text(encoding="utf-8")
    stmts = split_sql_statements(sql_text)
    cur = conn.cursor()
    executed = 0
    for stmt in stmts:
        cur.execute(stmt)
        while cur.nextset():
            pass
        executed += 1
    conn.commit()
    cur.close()
    return executed


def initialize_database(force_fresh: bool = False) -> None:
    """Create or upgrade agri_management_database and print verification counts."""
    conn_cfg = dict(DB_CONFIG)
    db_name = conn_cfg.pop("database")
    conn = mysql.connector.connect(**conn_cfg)
    try:
        cur = conn.cursor()
        cur.execute("SHOW DATABASES LIKE %s", (db_name,))
        exists = cur.fetchone() is not None
        has_tables = False
        if exists:
            conn.database = db_name
            cur.execute("SHOW TABLES LIKE 'farmers'")
            has_tables = cur.fetchone() is not None
        cur.close()

        if force_fresh or not exists or not has_tables:
            full_sql = BASE_DIR / "sql" / "agrichain_full_database.sql"
            print(f"Initializing fresh database `{db_name}` from {full_sql.name}...")
            count = run_sql_file(conn, full_sql)
            print(f"Executed {count} SQL statements cleanly.")
        else:
            conn.database = db_name
            upg_sql = BASE_DIR / "sql" / "agrichain_upgrade_and_seed.sql"
            print(f"Upgrading & seeding existing `{db_name}` from {upg_sql.name}...")
            count = run_sql_file(conn, upg_sql)
            print(f"Executed {count} SQL statements cleanly.")

        conn.database = db_name
        cur = conn.cursor()
        tables = [
            "administrative_divisions",
            "agro_companies",
            "product_categories",
            "agricultural_products",
            "product_batches",
            "rbk_centres",
            "rbk_employees",
            "emp_password",
            "rbk_inventory",
            "cultivation_seasons",
            "warehouses",
            "crop_categories",
            "buyers",
            "farmers",
            "seasonal_cultivator_rights",
            "crop_batches",
        ]
        print("\nTable Row Counts:")
        for tbl in tables:
            cur.execute(f"SELECT COUNT(*) FROM `{tbl}`")
            cnt = cur.fetchone()[0]
            print(f"  - {tbl:<30} {cnt}")

        cur.execute(
            "SELECT TRIGGER_NAME FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = %s",
            (db_name,),
        )
        triggers = [r[0] for r in cur.fetchall()]
        print("\nActive Triggers:", triggers)
        cur.close()
    finally:
        conn.close()


if __name__ == "__main__":
    fresh = "--fresh" in sys.argv
    initialize_database(force_fresh=fresh)
