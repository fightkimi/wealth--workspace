#!/usr/bin/env python3
"""Read-only Futu OpenD bridge for Wealth Workbench.

This helper deliberately imports quote APIs only. It never authenticates a trade
account and never calls order, position, or cash-transfer endpoints.
"""

import argparse
from datetime import datetime
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


def clean_value(value):
    """Convert pandas/numpy values into strict JSON scalars."""
    if value is None:
        return None
    try:
        if value != value:
            return None
    except Exception:
        pass
    if isinstance(value, (str, bool, int)):
        return value
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    try:
        numeric = float(value)
        if math.isfinite(numeric):
            return numeric
    except (TypeError, ValueError):
        pass
    text = str(value).strip()
    return text or None


def clean_text(value):
    result = clean_value(value)
    if result is None:
        return None
    return str(result)


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


def calendar(host: str, port: int, begin_date: str, end_date: str, raw_codes: str) -> None:
    if not HOST_RE.fullmatch(host):
        fail("OpenD 地址格式无效")
    if port < 1 or port > 65535:
        fail("OpenD 端口无效")
    try:
        begin = datetime.strptime(begin_date, "%Y-%m-%d")
        end = datetime.strptime(end_date, "%Y-%m-%d")
    except ValueError:
        fail("日历日期格式无效")
    if end < begin or (end - begin).days > 6:
        fail("Futu 日历查询范围必须为 1 至 7 天")
    try:
        codes = json.loads(raw_codes)
    except json.JSONDecodeError:
        fail("持仓代码参数无效")
    if not isinstance(codes, list) or len(codes) > 400 or any(not isinstance(code, str) or not CODE_RE.fullmatch(code) for code in codes):
        fail("持仓代码不符合 Futu 格式")

    try:
        from futu import Market, OpenQuoteContext, RET_OK, SysConfig
    except Exception:
        fail("Futu SDK 未正确打包")

    signal.signal(signal.SIGALRM, timeout_handler)
    signal.alarm(18)
    context = None
    try:
        SysConfig.enable_console_log(False)
        context = OpenQuoteContext(host=host, port=port)
        events = []
        failures = []
        successful_calls = 0

        next_page = None
        for _ in range(5):
            ret, data, next_page, has_more = context.get_economic_calendar(
                begin_date=begin_date,
                end_date=end_date,
                count=100,
                next_page=next_page,
            )
            if ret != RET_OK:
                failures.append(f"经济日历：{data}")
                break
            successful_calls += 1
            for row in data.to_dict("records"):
                timestamp = clean_value(row.get("timestamp"))
                title = str(row.get("title", "")).strip()
                if not title:
                    continue
                events.append({
                    "id": f"economic:{timestamp}:{title}",
                    "type": "economic",
                    "title": title,
                    "timestamp": timestamp,
                    "date": None,
                    "country": clean_value(row.get("country")),
                    "market": None,
                    "symbol": None,
                    "importance": {"HIGH": 3, "MEDIUM": 2, "LOW": 1}.get(str(row.get("star", "")).upper()),
                    "previous": clean_text(row.get("previous")),
                    "consensus": clean_text(row.get("consensus")),
                    "actual": clean_text(row.get("actual")),
                    "detail": None,
                    "source": "Futu OpenD",
                })
            if not has_more or not next_page:
                break

        code_set = set(codes)
        market_map = {
            "US": Market.US,
            "HK": Market.HK,
            "SH": Market.SH,
            "SZ": Market.SZ,
        }
        for prefix in sorted({code.split(".", 1)[0] for code in codes}):
            market = market_map.get(prefix)
            if market is None:
                continue
            ret, data = context.get_earnings_calendar(
                market=market,
                begin_date=begin_date,
                end_date=end_date,
            )
            if ret != RET_OK:
                failures.append(f"{prefix} 财报日历：{data}")
                continue
            successful_calls += 1
            for row in data.to_dict("records"):
                security = str(row.get("security", "")).strip()
                if security not in code_set:
                    continue
                name = str(row.get("name", "")).strip() or security
                date_value = str(row.get("earnings_date", "")).strip()
                timestamp = clean_value(row.get("earnings_timestamp"))
                period = clean_value(row.get("period_text"))
                pub_type = clean_value(row.get("pub_type"))
                detail_parts = [str(value) for value in [period, pub_type] if value not in (None, "")]
                events.append({
                    "id": f"earnings:{security}:{date_value}:{timestamp}",
                    "type": "earnings",
                    "title": f"{name} 财报发布",
                    "timestamp": timestamp,
                    "date": date_value or None,
                    "country": None,
                    "market": prefix,
                    "symbol": security,
                    "importance": None,
                    "previous": None,
                    "consensus": clean_text(row.get("eps_predict")),
                    "actual": clean_text(row.get("eps_actual")),
                    "detail": " · ".join(detail_parts) or None,
                    "source": "Futu OpenD",
                })

        global_code, global_state = context.get_global_state()
        server_timestamp = time.time()
        if global_code == RET_OK and isinstance(global_state, dict):
            server_timestamp = safe_float(global_state.get("timestamp")) or server_timestamp
        if successful_calls == 0:
            fail("；".join(failures) or "Futu 日历接口不可用")
        print(json.dumps({
            "ok": True,
            "server_timestamp": server_timestamp,
            "events": events,
            "failures": failures,
        }, ensure_ascii=False, allow_nan=False))
        sys.stdout.flush()
        os._exit(0)
    except TimeoutError as exc:
        fail(str(exc))
    except SystemExit:
        raise
    except Exception as exc:
        fail(f"Futu 日历连接失败：{type(exc).__name__}")
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
    calendar_parser = subparsers.add_parser("calendar", add_help=False)
    calendar_parser.add_argument("--host", required=True)
    calendar_parser.add_argument("--port", type=int, required=True)
    calendar_parser.add_argument("--begin-date", required=True)
    calendar_parser.add_argument("--end-date", required=True)
    calendar_parser.add_argument("--codes", required=True)
    args = parser.parse_args()
    if args.command == "quote":
        quote(args.host, args.port, args.codes)
    elif args.command == "calendar":
        calendar(args.host, args.port, args.begin_date, args.end_date, args.codes)


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
