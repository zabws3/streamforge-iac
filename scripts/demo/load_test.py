#!/usr/bin/env python3
"""Bounded HTTP load probe for the interactive StreamForge demo."""

import argparse
import concurrent.futures
import json
import math
import statistics
import sys
import time
import urllib.error
import urllib.request
from collections import Counter


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True)
    parser.add_argument("--requests", type=int, required=True)
    parser.add_argument("--concurrency", type=int, required=True)
    parser.add_argument("--duration", type=int, required=True)
    parser.add_argument("--timeout", type=float, default=5)
    args = parser.parse_args()
    if not 1 <= args.requests <= 500:
        parser.error("--requests must be between 1 and 500")
    if not 1 <= args.concurrency <= 20:
        parser.error("--concurrency must be between 1 and 20")
    if not 1 <= args.duration <= 60:
        parser.error("--duration must be between 1 and 60 seconds")
    if not 0.5 <= args.timeout <= 10:
        parser.error("--timeout must be between 0.5 and 10 seconds")
    return args


def request_once(url: str, deadline: float, timeout: float):
    if time.monotonic() >= deadline:
        return None
    started = time.monotonic()
    request = urllib.request.Request(url, headers={"User-Agent": "StreamForge-demo/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read(8192)
            instance = None
            try:
                instance = json.loads(body).get("instance")
            except (UnicodeDecodeError, json.JSONDecodeError, AttributeError):
                pass
            return response.status, time.monotonic() - started, instance
    except urllib.error.HTTPError as error:
        return error.code, time.monotonic() - started, None
    except (urllib.error.URLError, TimeoutError, OSError):
        return 0, time.monotonic() - started, None


def main() -> int:
    args = parse_args()
    deadline = time.monotonic() + args.duration
    started = time.monotonic()
    results = []
    skipped = 0
    executor = concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency)
    futures = [
        executor.submit(request_once, args.url, deadline, args.timeout)
        for _ in range(args.requests)
    ]
    try:
        for future in concurrent.futures.as_completed(futures, timeout=args.duration + args.timeout + 1):
            try:
                result = future.result()
            except Exception:
                result = (0, 0.0, None)
            if result is None:
                skipped += 1
            else:
                results.append(result)
    except concurrent.futures.TimeoutError:
        for future in futures:
            future.cancel()
    finally:
        executor.shutdown(wait=True, cancel_futures=True)

    elapsed = time.monotonic() - started
    statuses = Counter(status for status, _, _ in results)
    latencies = sorted(duration for _, duration, _ in results)
    instances = Counter(instance for _, _, instance in results if instance)
    completed = sum(1 for status, _, _ in results if 200 <= status < 400)
    failed = len(results) - completed

    print(f"URL: {args.url}")
    print(f"Solicitadas: {args.requests}; ejecutadas: {len(results)}; omitidas por deadline: {skipped}")
    print(f"Concurrencia máxima: {args.concurrency}; duración real: {elapsed:.2f}s (límite {args.duration}s + timeout)")
    print(f"Completadas 2xx/3xx: {completed}; fallidas: {failed}")
    print("Códigos HTTP:", ", ".join(f"{code or 'network-error'}={count}" for code, count in sorted(statuses.items())) or "ninguno")
    if latencies:
        p95 = latencies[max(0, math.ceil(len(latencies) * 0.95) - 1)]
        print(
            "Latencia (s): media={:.3f}; min={:.3f}; max={:.3f}; p95={:.3f}".format(
                statistics.mean(latencies), latencies[0], latencies[-1], p95
            )
        )
    print("Instancias observadas:")
    if instances:
        for instance, count in sorted(instances.items()):
            print(f"  {instance}: {count}")
    else:
        print("  (el endpoint no devolvió un campo JSON 'instance')")
    return 0 if completed and not failed and not skipped else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nCancelado por usuario.", file=sys.stderr)
        raise SystemExit(130)
