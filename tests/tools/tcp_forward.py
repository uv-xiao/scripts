#!/usr/bin/env python3
import argparse
import asyncio
import signal
import sys


async def _pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while True:
            chunk = await reader.read(64 * 1024)
            if not chunk:
                break
            writer.write(chunk)
            await writer.drain()
    except (ConnectionError, asyncio.CancelledError):
        pass
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def _handle_client(
    client_reader: asyncio.StreamReader,
    client_writer: asyncio.StreamWriter,
    target_host: str,
    target_port: int,
) -> None:
    try:
        upstream_reader, upstream_writer = await asyncio.open_connection(
            target_host, target_port
        )
    except OSError:
        client_writer.close()
        return

    await asyncio.gather(
        _pipe(client_reader, upstream_writer),
        _pipe(upstream_reader, client_writer),
    )


async def _amain() -> int:
    ap = argparse.ArgumentParser(
        description="Simple TCP port forwarder (for container proxy bridging)."
    )
    ap.add_argument("--listen-host", default="0.0.0.0")
    ap.add_argument("--listen-port", type=int, default=0)
    ap.add_argument("--target-host", required=True)
    ap.add_argument("--target-port", type=int, required=True)
    args = ap.parse_args()

    server = await asyncio.start_server(
        lambda r, w: _handle_client(r, w, args.target_host, args.target_port),
        host=args.listen_host,
        port=args.listen_port,
    )
    sock = next(iter(server.sockets or []), None)
    if sock is None:
        print("error: failed to bind", file=sys.stderr)
        return 2

    port = sock.getsockname()[1]
    print(port, flush=True)

    stop_event = asyncio.Event()

    def _stop(*_a: object) -> None:
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _stop)
        except NotImplementedError:
            pass

    async with server:
        await stop_event.wait()
    return 0


def main() -> None:
    try:
        rc = asyncio.run(_amain())
    except KeyboardInterrupt:
        rc = 130
    raise SystemExit(rc)


if __name__ == "__main__":
    main()

