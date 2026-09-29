#!/usr/bin/env python3

import ipaddress
import json
import os
import ssl
import sys
import tempfile
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit

API_URL = "https://127.0.0.1:9443/api/open/records"
TOKEN_FILE = Path("/etc/safeline-wazuh/token")
STATE_DIR = Path("/var/lib/safeline-wazuh")
STATE_FILE = STATE_DIR / "state.json"
LOG_DIR = Path("/var/log/safeline")
LOG_FILE = LOG_DIR / "attacks.json"

PAGE_SIZE = 100
MAX_PAGES = 20
MAX_SEEN_IDS = 2000

ACTION_NAMES = {
    0: "continue",
    1: "deny",
}

ATTACK_TYPE_NAMES = {
    -4: "oversized_data",
    -3: "blacklist",
    -2: "whitelist",
    -1: "non_attack",
    0: "sql_injection",
    1: "xss",
    2: "csrf",
    3: "ssrf",
    4: "denial_of_service",
    5: "backdoor",
    6: "deserialization",
    7: "code_execution",
    8: "code_injection",
    9: "command_injection",
    10: "file_upload",
    11: "file_inclusion",
    12: "redirect",
    13: "improper_authorization",
    14: "information_disclosure",
    15: "unauthorized_access",
    16: "insecure_configuration",
    17: "xxe",
    18: "xpath_injection",
    19: "ldap_injection",
    20: "path_traversal",
    21: "scanner",
    22: "horizontal_authorization_bypass",
    23: "vertical_authorization_bypass",
    24: "file_modification",
    25: "file_read",
    26: "file_deletion",
    27: "logic_error",
    28: "crlf_injection",
    29: "template_injection",
    30: "clickjacking",
    31: "buffer_overflow",
    32: "integer_overflow",
    33: "format_string",
    34: "race_condition",
    35: "http_protocol_violation",
    61: "timeout",
    62: "unknown",
    63: "threat_intelligence",
    64: "cookie_tampering",
}

# Keep structured metadata useful for debugging and hunting, but do not copy
# raw HTTP headers, bodies, payloads, or query strings into Wazuh/Indexer.
SAFELINE_METADATA_FIELDS = (
    "site_uuid",
    "src_ip",
    "socket_ip",
    "protocol",
    "host",
    "url_path",
    "dst_port",
    "country",
    "province",
    "city",
    "lng",
    "lat",
    "risk_level",
    "action",
    "rule_id",
    "policy_name",
    "ja4_fingerprint",
    "created_at",
    "rule_id_list",
    "EventId",
    "src_port",
    "dst_ip",
    "method",
    "status_code",
    "location",
    "decode_path",
    "event_id",
    "attack_type",
    "module",
    "reason",
    "short_rule_id",
    "timestamp",
)

# SafeLine management endpoint is reached locally by IP and may not have
# a certificate that validates for 127.0.0.1.
SSL_CONTEXT = ssl._create_unverified_context()


def load_token():
    token = TOKEN_FILE.read_text(encoding="utf-8").strip()
    if not token:
        raise RuntimeError("SafeLine API token file is empty")
    return token


def load_state():
    if not STATE_FILE.exists():
        return {"seen_event_ids": []}

    try:
        with STATE_FILE.open("r", encoding="utf-8") as f:
            state = json.load(f)

        if not isinstance(state.get("seen_event_ids"), list):
            return {"seen_event_ids": []}

        return state
    except (json.JSONDecodeError, OSError):
        return {"seen_event_ids": []}


def save_state(state):
    STATE_DIR.mkdir(parents=True, exist_ok=True)

    fd, tmp_name = tempfile.mkstemp(
        prefix="state.",
        dir=str(STATE_DIR)
    )

    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(state, f)
            f.write("\n")

        os.chmod(tmp_name, 0o600)
        os.replace(tmp_name, STATE_FILE)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def fetch_page(token, page):
    url = f"{API_URL}?page={page}&page_size={PAGE_SIZE}"

    req = urllib.request.Request(
        url,
        headers={
            "X-SLCE-API-Token": token,
            "Accept": "application/json",
            "User-Agent": "safeline-wazuh-collector/1.0",
        },
        method="GET",
    )

    with urllib.request.urlopen(
        req,
        context=SSL_CONTEXT,
        timeout=10
    ) as response:
        if response.status != 200:
            raise RuntimeError(f"SafeLine API returned HTTP {response.status}")

        payload = json.loads(response.read().decode("utf-8"))

    if payload.get("err") is not None:
        raise RuntimeError(
            f"SafeLine API error: {payload.get('err')} "
            f"{payload.get('msg', '')}"
        )

    data = payload.get("data", {})
    records = data.get("data", [])

    if not isinstance(records, list):
        raise RuntimeError("Unexpected SafeLine API response")

    return records


def as_integer(value):
    if isinstance(value, bool):
        return None

    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def valid_ip(value):
    if not isinstance(value, str) or not value:
        return None

    try:
        ipaddress.ip_address(value)
        return value
    except ValueError:
        return None


def valid_port(value):
    port = as_integer(value)
    if port is None or not 0 <= port <= 65535:
        return None
    return port


def path_without_query(value):
    if not isinstance(value, str):
        return None
    return urlsplit(value).path


def safe_safeline_metadata(record):
    return {
        field: record[field]
        for field in SAFELINE_METADATA_FIELDS
        if field in record
    }


def normalize(record):
    source_ip = record.get("src_ip")
    source_port = record.get("src_port")
    destination_ip = record.get("dst_ip")
    destination_port = record.get("dst_port")
    action = as_integer(record.get("action"))
    attack_type = as_integer(record.get("attack_type"))

    event = {
        "schema_version": 1,
        "integration": "safeline",
        "event_type": "waf_attack",

        "event_id": record.get("event_id"),
        "timestamp": record.get("timestamp"),
        "created_at": record.get("created_at"),

        "source_ip": source_ip,
        "socket_ip": record.get("socket_ip"),
        "source_port": source_port,

        "destination_ip": destination_ip,
        "destination_port": destination_port,

        "host": record.get("host"),
        "url_path": record.get("url_path"),
        "path_only": path_without_query(record.get("url_path")),
        "method": record.get("method"),

        "risk_level": record.get("risk_level"),
        "action": action,
        "action_name": ACTION_NAMES.get(action, "unknown"),

        "attack_type": attack_type,
        "attack_type_name": ATTACK_TYPE_NAMES.get(attack_type, "unknown"),
        "module": record.get("module"),
        "rule_id": record.get("rule_id"),
        "policy_name": record.get("policy_name"),

        "ja4_fingerprint": record.get("ja4_fingerprint"),

        "country": record.get("country"),
        "province": record.get("province"),
        "city": record.get("city"),

        "reason": record.get("reason"),

        "status_code": record.get("status_code"),

        "safeline": safe_safeline_metadata(record),
    }

    srcip = valid_ip(source_ip)
    if srcip is not None:
        event["srcip"] = srcip

    srcport = valid_port(source_port)
    if srcport is not None:
        event["srcport"] = srcport

    dstip = valid_ip(destination_ip)
    if dstip is not None:
        event["dstip"] = dstip

    dstport = valid_port(destination_port)
    if dstport is not None:
        event["dstport"] = dstport

    return event


def append_records(records):
    if not records:
        return

    LOG_DIR.mkdir(parents=True, exist_ok=True)

    with LOG_FILE.open("a", encoding="utf-8") as f:
        for record in records:
            json.dump(
                normalize(record),
                f,
                ensure_ascii=False,
                separators=(",", ":"),
            )
            f.write("\n")

        f.flush()
        os.fsync(f.fileno())

    os.chmod(LOG_FILE, 0o640)


def main():
    token = load_token()
    state = load_state()

    seen_list = state.get("seen_event_ids", [])
    seen = set(seen_list)

    new_records = []
    stop = False

    for page in range(1, MAX_PAGES + 1):
        records = fetch_page(token, page)

        if not records:
            break

        for record in records:
            event_id = record.get("event_id")

            if not event_id:
                continue

            if event_id in seen:
                stop = True
                break

            new_records.append(record)

        if stop or len(records) < PAGE_SIZE:
            break

    # API returns newest first; log oldest first for chronological ordering.
    new_records.reverse()

    append_records(new_records)

    for record in new_records:
        event_id = record.get("event_id")
        if event_id:
            seen_list.append(event_id)

    # Keep bounded state.
    seen_list = seen_list[-MAX_SEEN_IDS:]

    save_state({
        "seen_event_ids": seen_list
    })

    print(f"SafeLine collector: wrote {len(new_records)} new event(s)")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"SafeLine collector error: {exc}", file=sys.stderr)
        sys.exit(1)
