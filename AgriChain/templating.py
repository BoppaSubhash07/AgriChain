"""Lightweight XSS-safe HTML template renderer using MarkupSafe."""

from pathlib import Path
import re
from markupsafe import Markup, escape
from config import BASE_DIR

TEMPLATES_DIR = BASE_DIR / "templates"
_PLACEHOLDER_RE = re.compile(r"\{\{\s*([a-zA-Z0-9_]+)\s*\}\}")


def h(value) -> Markup:
    """Escape untrusted strings into safe Markup."""
    if value is None:
        return Markup("")
    if isinstance(value, Markup):
        return value
    return escape(str(value))


def render_template(template_name: str, **context) -> str:
    """Render an HTML template file by replacing {{key}} placeholders safely."""
    path = TEMPLATES_DIR / template_name
    raw_html = path.read_text(encoding="utf-8")

    def _replace(match):
        key = match.group(1)
        if key not in context:
            return ""
        val = context[key]
        if isinstance(val, Markup):
            return str(val)
        return str(h(val))

    return _PLACEHOLDER_RE.sub(_replace, raw_html)


def render_page(template_name: str, layout_ctx: dict | None = None, **context) -> str:
    """Render an inner HTML template and wrap it inside layout.html."""
    inner_html = Markup(render_template(template_name, **context))
    ctx = dict(layout_ctx or {})
    ctx["content"] = inner_html
    return render_template("layout.html", **ctx)
