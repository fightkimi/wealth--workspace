#!/usr/bin/env python3
"""Read-only Futu OpenD bridge for Wealth Workbench.

This helper deliberately imports quote APIs only. It never authenticates a trade
account and never calls order, position, or cash-transfer endpoints.
"""

import argparse
import json
import math
import os
import re
import signal
import sys
import time


CODE_RE = re.compile(r"^(US|HK|SH|SZ)\.[A-Z0-9._-]{1,32}$")
HOST_RE = re.compile(r"^[A-Za-z0-9.:-]{1,255}$")


def fail(message: str, exit_code: int = 1) -> None:
    print(json.dumps({"ok": False, "message": message}, ensure_ascii=False))
    sys.stdout.flush()
    sys.stderr.flush()
    # The frozen Futu runtime can keep helper threads alive during normal
    # interpreter teardown. This is a one-shot subprocess, so let the OS close
    # its read-only socket after the JSON response has been written.
    os._exit(exit_code)


def safe_float(value):
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) and result > 0 else None


def timeout_handler(_signum, _frame):
    raise TimeoutError("连接 Futu OpenD 超时")


def quote(host: str, port: int, raw_codes: str) -> None:
    if not HOST_RE.fullmatch(host):
        fail("OpenD 地址格式无效")
    if port < 1 or port > 65535:
        fail("OpenD 端口无效")
    try:
        codes = json.loads(raw_codes)
    except json.JSONDecodeError:
        fail("标的代码参数无效")
    if not isinstance(codes, list) or len(codes) > 400 or any(not isinstance(code, str) or not CODE_RE.fullmatch(code) for code in codes):
        fail("标的代码不符合 Futu 格式")
    if not codes:
        print(json.dumps({"ok": True, "server_timestamp": time.time(), "quotes": []}, ensure_ascii=False))
        sys.stdout.flush()
        os._exit(0)

    try:
        from futu import OpenQuoteContext, RET_OK, SysConfig
    except Exception:
        fail("Futu SDK 未正确打包")

    signal.signal(signal.SIGALRM, timeout_handler)
    signal.alarm(10)
    context = None
    try:
        SysConfig.enable_console_log(False)
        context = OpenQuoteContext(host=host, port=port)
        snapshot_code, snapshot = context.get_market_snapshot(codes)
        if snapshot_code != RET_OK:
            fail(f"Futu 快照失败：{snapshot}")
        state_code, states = context.get_market_state(codes)
        if state_code != RET_OK:
            fail(f"Futu 市场状态失败：{states}")
        global_code, global_state = context.get_global_state()
        server_timestamp = time.time()
        if global_code == RET_OK and isinstance(global_state, dict):
            server_timestamp = safe_float(global_state.get("timestamp")) or server_timestamp

        state_lookup = {}
        for row in states.to_dict("records"):
            state_lookup[str(row.get("code", ""))] = str(row.get("market_state", ""))

        output = []
        for row in snapshot.to_dict("records"):
            code = str(row.get("code", ""))
            output.append(
                {
                    "code": code,
                    "name": str(row.get("name", "")),
                    "market_state": state_lookup.get(code, ""),
                    "update_time": str(row.get("update_time", "")),
                    "last_price": safe_float(row.get("last_price")),
                    "prev_close_price": safe_float(row.get("prev_close_price")),
                    "pre_price": safe_float(row.get("pre_price")),
                    "after_price": safe_float(row.get("after_price")),
                    "overnight_price": safe_float(row.get("overnight_price")),
                }
            )
        print(json.dumps({"ok": True, "server_timestamp": server_timestamp, "quotes": output}, ensure_ascii=False, allow_nan=False))
        sys.stdout.flush()
        os._exit(0)
    except TimeoutError as exc:
        fail(str(exc))
    except SystemExit:
        raise
    except Exception as exc:
        fail(f"Futu OpenD 连接失败：{type(exc).__name__}")
    finally:
        signal.alarm(0)
        if context is not None:
            try:
                context.close()
            except Exception:
                pass


def main() -> None:
    parser = argparse.ArgumentParser(add_help=False)
    subparsers = parser.add_subparsers(dest="command", required=True)
    quote_parser = subparsers.add_parser("quote", add_help=False)
    quote_parser.add_argument("--host", required=True)
    quote_parser.add_argument("--port", type=int, required=True)
    quote_parser.add_argument("--codes", required=True)
    args = parser.parse_args()
    if args.command == "quote":
        quote(args.host, args.port, args.codes)


if __name__ == "__main__":
    exit_code = 0
    try:
        main()
    except SystemExit as exc:
        exit_code = exc.code if isinstance(exc.code, int) else 1
    finally:
        # The packaged Futu SDK can leave helper threads alive after the quote
        # context closes. This bridge is a one-shot, read-only subprocess, so
        # flush the JSON result and terminate deterministically for the host app.
        sys.stdout.flush()
        sys.stderr.flush()
    os._exit(exit_code)
