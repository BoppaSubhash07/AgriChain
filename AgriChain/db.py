"""MySQL database connection pool and transaction helpers for AgriChain."""

from contextlib import contextmanager
import uuid
import mysql.connector
from mysql.connector import pooling
from config import DB_CONFIG

_pool = None


def get_pool():
    """Lazily initialize and return the MySQL connection pool."""
    global _pool
    if _pool is None:
        _pool = pooling.MySQLConnectionPool(
            pool_name="agrichain_pool",
            pool_size=8,
            pool_reset_session=True,
            autocommit=False,
            **DB_CONFIG,
        )
    return _pool


def reset_pool():
    """Reset connection pool (useful after config changes or DB re-init)."""
    global _pool
    _pool = None


def get_connection():
    """Acquire a connection from the pool."""
    return get_pool().get_connection()


def query_all(sql: str, params=None) -> list[dict]:
    """Execute a SELECT query and return all rows as dicts."""
    conn = get_connection()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute(sql, params or ())
        rows = cur.fetchall()
        cur.close()
        return rows
    finally:
        conn.close()


def query_one(sql: str, params=None) -> dict | None:
    """Execute a SELECT query and return the first row as a dict, or None."""
    conn = get_connection()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute(sql, params or ())
        row = cur.fetchone()
        cur.close()
        return row
    finally:
        conn.close()


def execute(sql: str, params=None) -> int:
    """Execute a write statement in its own transaction and return affected row count."""
    with transaction() as cur:
        cur.execute(sql, params or ())
        return cur.rowcount


@contextmanager
def transaction():
    """Transactional context manager yielding a dictionary cursor."""
    conn = get_connection()
    cur = conn.cursor(dictionary=True)
    try:
        conn.start_transaction()
        yield cur
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()


def gen_id(prefix: str, hex_len: int = 6) -> str:
    """Generate a compact readable unique ID fitting CHAR(36), e.g. PUR-A1B2C3."""
    return f"{prefix}-{uuid.uuid4().hex[:hex_len].upper()}"


def check_db_health() -> tuple[bool, str]:
    """Verify MySQL connectivity and presence of agri_management_database."""
    try:
        row = query_one("SELECT DATABASE() AS db_name, VERSION() AS version")
        return True, f"Connected to {row['db_name']} (MySQL {row['version']})"
    except Exception as exc:
        return False, str(exc)
