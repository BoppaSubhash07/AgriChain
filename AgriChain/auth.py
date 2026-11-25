"""Authentication, password verification, biometric check, and signed cookie sessions."""

import base64
import hashlib
import hmac
import json
import time
from werkzeug.security import check_password_hash, generate_password_hash
from config import APP_SECRET
from db import query_one

SESSION_COOKIE = "agrichain_session"
FLASH_COOKIE = "agrichain_flash"
SESSION_TTL_SECONDS = 8 * 3600


def hash_password(plain_password: str) -> str:
    """Hash a password using Werkzeug PBKDF2-SHA256."""
    return generate_password_hash(plain_password, method="pbkdf2:sha256")


def verify_password(plain_password: str, stored_hash: str | None) -> bool:
    """Verify password against either PBKDF2/scrypt hash or legacy 64-hex SHA-256."""
    if not plain_password or not stored_hash:
        return False
    if stored_hash.startswith(("pbkdf2:", "scrypt:")):
        return check_password_hash(stored_hash, plain_password)
    if len(stored_hash) == 64:
        candidate = hashlib.sha256(plain_password.encode("utf-8")).hexdigest()
        return hmac.compare_digest(candidate.lower(), stored_hash.lower())
    return hmac.compare_digest(plain_password, stored_hash)


def _sign(payload_b64: str) -> str:
    return hmac.new(
        APP_SECRET.encode("utf-8"), payload_b64.encode("utf-8"), hashlib.sha256
    ).hexdigest()


def encode_signed_data(data: dict) -> str:
    """Serialize and HMAC-sign a JSON payload."""
    raw = json.dumps(data, separators=(",", ":"), default=str).encode("utf-8")
    payload_b64 = base64.urlsafe_b64encode(raw).decode("ascii")
    return f"{payload_b64}.{_sign(payload_b64)}"


def decode_signed_data(token: str | None) -> dict | None:
    """Verify HMAC signature and decode JSON payload."""
    if not token or "." not in token:
        return None
    payload_b64, sig = token.rsplit(".", 1)
    if not hmac.compare_digest(_sign(payload_b64), sig):
        return None
    try:
        raw = base64.urlsafe_b64decode(payload_b64.encode("ascii"))
        return json.loads(raw.decode("utf-8"))
    except Exception:
        return None


def get_session(request) -> dict | None:
    """Return active session dict if cookie is valid and unexpired."""
    data = decode_signed_data(request.cookies.get(SESSION_COOKIE))
    if not data:
        return None
    if data.get("exp", 0) < time.time():
        return None
    return data


def set_session_cookie(response, session_data: dict):
    """Attach signed session cookie to response."""
    payload = dict(session_data)
    payload["exp"] = int(time.time()) + SESSION_TTL_SECONDS
    response.set_cookie(
        SESSION_COOKIE,
        encode_signed_data(payload),
        httponly=True,
        samesite="Lax",
        max_age=SESSION_TTL_SECONDS,
        path="/",
    )


def clear_session_cookie(response):
    """Delete session cookie."""
    response.delete_cookie(SESSION_COOKIE, path="/")


def set_flash_cookie(response, category: str, message: str):
    """Store one-time flash notification in a signed cookie."""
    response.set_cookie(
        FLASH_COOKIE,
        encode_signed_data({"category": category, "message": message}),
        httponly=True,
        samesite="Lax",
        max_age=120,
        path="/",
    )


def pop_flash(request) -> dict | None:
    """Read flash cookie if present."""
    return decode_signed_data(request.cookies.get(FLASH_COOKIE))


def authenticate_rbk_employee(identifier: str, password: str) -> dict | None:
    """Authenticate an RBK employee by email, employee_id, phone, or system username."""
    ident = (identifier or "").strip()
    if not ident or not password:
        return None

    row = query_one(
        """
        SELECT e.employee_id, e.rbk_id, e.employee_name, e.designation,
               e.email, e.phone, e.employment_status,
               r.rbk_name, r.district, r.location,
               p.password_hash
          FROM rbk_employees e
          JOIN rbk_centres r ON r.rbk_id = e.rbk_id
          LEFT JOIN emp_password p ON p.employee_id = e.employee_id
         WHERE (e.email = %s OR e.employee_id = %s OR e.phone = %s)
           AND e.employment_status = 'Active'
         LIMIT 1
        """,
        (ident, ident, ident),
    )

    if not row:
        # Fallback check: system_users username (e.g., 'rbk_officer') mapped by email
        sys_user = query_one(
            """
            SELECT email, password_hash
              FROM system_users
             WHERE (username = %s OR email = %s) AND status = 'Active'
             LIMIT 1
            """,
            (ident, ident),
        )
        if sys_user:
            row = query_one(
                """
                SELECT e.employee_id, e.rbk_id, e.employee_name, e.designation,
                       e.email, e.phone, e.employment_status,
                       r.rbk_name, r.district, r.location,
                       COALESCE(p.password_hash, %s) AS password_hash
                  FROM rbk_employees e
                  JOIN rbk_centres r ON r.rbk_id = e.rbk_id
                  LEFT JOIN emp_password p ON p.employee_id = e.employee_id
                 WHERE e.email = %s AND e.employment_status = 'Active'
                 LIMIT 1
                """,
                (sys_user["password_hash"], sys_user["email"]),
            )

    if not row or not verify_password(password, row["password_hash"]):
        return None

    return {
        "role": "rbk",
        "user_id": row["employee_id"],
        "name": row["employee_name"],
        "designation": row["designation"],
        "email": row["email"],
        "rbk_id": row["rbk_id"],
        "rbk_name": row["rbk_name"],
        "district": row["district"],
    }


def authenticate_farmer_password(identifier: str, password: str) -> dict | None:
    """Authenticate a farmer by farmer_id, phone, or email + password."""
    ident = (identifier or "").strip()
    if not ident or not password:
        return None
    row = query_one(
        """
        SELECT f.farmer_id, f.farmer_name, f.phone, f.email, f.password_hash,
               b.status AS biometric_status
          FROM farmers f
          LEFT JOIN biometric_authentication b ON b.farmer_id = f.farmer_id
         WHERE f.farmer_id = %s OR f.phone = %s OR f.email = %s
         LIMIT 1
        """,
        (ident, ident, ident),
    )
    if not row or not verify_password(password, row["password_hash"]):
        return None
    return {
        "role": "farmer",
        "user_id": row["farmer_id"],
        "name": row["farmer_name"],
        "phone": row["phone"],
        "email": row["email"],
        "biometric_status": row["biometric_status"] or "Pending",
    }


def authenticate_farmer_biometric(identifier: str, aadhaar_last4: str) -> tuple[dict | None, str]:
    """Authenticate a farmer using verified Aadhaar biometric record."""
    ident = (identifier or "").strip()
    last4 = (aadhaar_last4 or "").strip()
    if not ident or len(last4) != 4:
        return None, "Enter your Farmer ID or Phone and the 4-digit Aadhaar biometric PIN/suffix."

    row = query_one(
        """
        SELECT f.farmer_id, f.farmer_name, f.phone, f.email,
               b.aadhaar_number, b.biometric_type, b.status AS biometric_status
          FROM farmers f
          JOIN biometric_authentication b ON b.farmer_id = f.farmer_id
         WHERE f.farmer_id = %s OR f.phone = %s
         LIMIT 1
        """,
        (ident, ident),
    )
    if not row:
        return None, "No farmer found with a linked biometric profile for that Farmer ID or Phone."
    if row["biometric_status"] != "Verified":
        return None, f"Biometric authentication status is '{row['biometric_status']}'. Please verify at your RBK kiosk."
    if not str(row["aadhaar_number"]).lower().endswith(last4.lower()):
        return None, "Biometric Aadhaar verification failed: last 4 digits do not match registered record."

    return {
        "role": "farmer",
        "user_id": row["farmer_id"],
        "name": row["farmer_name"],
        "phone": row["phone"],
        "email": row["email"],
        "biometric_status": row["biometric_status"],
        "auth_method": f"Biometric ({row['biometric_type']})",
    }, ""


def authenticate_buyer(identifier: str, password: str) -> dict | None:
    """Authenticate an institutional buyer by buyer_id, email, or registration_number."""
    ident = (identifier or "").strip()
    if not ident or not password:
        return None
    row = query_one(
        """
        SELECT buyer_id, buyer_name, buyer_type, phone, email,
               registration_number, buyer_password_hash
          FROM buyers
         WHERE buyer_id = %s OR email = %s OR registration_number = %s
         LIMIT 1
        """,
        (ident, ident, ident),
    )
    if not row or not verify_password(password, row["buyer_password_hash"]):
        return None
    return {
        "role": "buyer",
        "user_id": row["buyer_id"],
        "name": row["buyer_name"],
        "buyer_type": row["buyer_type"],
        "email": row["email"],
        "registration_number": row["registration_number"],
    }
