#!/usr/bin/env python3
"""ultraloop approve_bot.py — egress-only Discord Gateway approval bot.

SPEC v0.3 §13 (notification & approval — async queue + Discord gateway bot).

Why the Gateway — egress-only / DLP compatible
----------------------------------------------------
Corporate DLP environments often cannot open inbound (ingress) webhooks. With
the Discord Gateway, the bot opens an **outbound** WebSocket (WSS) connection
and **receives** INTERACTION_CREATE events such as button clicks over that
connection. In other words, no open port is needed on our side at all — it
works even behind a send-only firewall.
discord.py (v2) ships this Gateway connection + button components (View/Button) built in.

Behavior
----
1) POST a [Y]/[N] button message to the approval_channel_id channel.
2) Wait for button interactions arriving over the Gateway.
3) The clicking user must be in the approver_user_ids allowlist to count
   (otherwise a rejection notice is shown).
4) Record the decision (+ optional reason) in the queue directory: <id>.result = "Y\n<reason>" / "N\n<reason>".
5) Exit codes: 0=Y (approved) / 1=N (rejected) / 4=TTL timeout (hold).

Token
----
Read only from the environment variable that discord.token_env points to
(default ULTRALOOP_DISCORD_BOT_TOKEN). Never hardcode it.

R5 — bot process lifetime/reconnection
----------------------------
This script runs **short-lived, one execution per approval**: it posts the
message, stays alive until a decision or the TTL, then exits. So there is no
long-lived-daemon burden of reconnects/session expiry (a one-shot connection
makes reconnect practically unnecessary).
  Alternative: if you prefer a long-running approval daemon, see
  assets/discord/gateway-bot.example.py (permanent connection + discord.py
  built-in reconnect). In that case R5 is handled by discord.py auto
  reconnect.

CLI
---
    approve_bot.py <approval_id> <question> <risk> [ttl_minutes]
"""
from __future__ import annotations

import os
import sys
import asyncio
from pathlib import Path

# ── config loading (use PyYAML if present, else a minimal parser) ──────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
# default config = target repo cwd (loop invokes from the target repo). Not the plugin root.
CONFIG_PATH = Path(os.environ.get("ULTRALOOP_CONFIG") or (Path.cwd() / "ultraloop.config.yaml"))
RESULT_DIR = Path(os.environ.get("TMPDIR", "/tmp")) / "ultraloop-approvals"

DEFAULT_TOKEN_ENV = "ULTRALOOP_DISCORD_BOT_TOKEN"
DEFAULT_TTL_MIN = 120


def _load_discord_config() -> dict:
    """Return only the discord: block of the config as a dict. PyYAML first, else a flat parser."""
    if not CONFIG_PATH.exists():
        return {}
    text = CONFIG_PATH.read_text(encoding="utf-8")
    try:
        import yaml  # type: ignore
        data = yaml.safe_load(text) or {}
        return data.get("discord", {}) or {}
    except Exception:
        pass
    # minimal fallback parser: reads only one-level-indented key: value lines in the discord: block.
    out: dict = {}
    in_block = False
    for raw in text.splitlines():
        if raw.startswith("discord:"):
            in_block = True
            continue
        if in_block:
            if raw and not raw[0].isspace():
                break  # end of block
            line = raw.strip()
            if not line or line.startswith("#") or ":" not in line:
                continue
            key, _, val = line.partition(":")
            val = val.strip().strip('"').strip("'")
            if val.startswith("[") and val.endswith("]"):
                items = [v.strip().strip('"').strip("'") for v in val[1:-1].split(",")]
                out[key.strip()] = [v for v in items if v]
            else:
                out[key.strip()] = val
    return out


def write_result(approval_id: str, decision: str, reason: str = "") -> None:
    RESULT_DIR.mkdir(parents=True, exist_ok=True)
    path = RESULT_DIR / f"{approval_id}.result"
    path.write_text(f"{decision}\n{reason}".rstrip() + "\n", encoding="utf-8")


def _coerce_ids(raw) -> set[str]:
    if isinstance(raw, list):
        return {str(x).strip() for x in raw if str(x).strip()}
    if isinstance(raw, str):
        return {x.strip() for x in raw.strip("[]").split(",") if x.strip()}
    return set()


async def run_approval(approval_id: str, question: str, risk: str, ttl_min: int) -> int:
    try:
        import discord  # type: ignore
    except ImportError:
        print("discord.py is not installed. Install it: pip install discord.py", file=sys.stderr)
        return 3

    cfg = _load_discord_config()
    token_env = cfg.get("token_env") or DEFAULT_TOKEN_ENV
    token = os.environ.get(token_env, "")
    channel_id = cfg.get("approval_channel_id")
    approvers = _coerce_ids(cfg.get("approver_user_ids", []))

    if not token:
        print(f"Token environment variable {token_env} is empty.", file=sys.stderr)
        return 3
    if not channel_id:
        print("discord.approval_channel_id is not configured.", file=sys.stderr)
        return 3

    ttl_seconds = max(1, ttl_min) * 60
    loop = asyncio.get_running_loop()
    decision_future: asyncio.Future = loop.create_future()

    intents = discord.Intents.none()
    intents.guilds = True  # needed to fetch the channel + receive component interactions
    client = discord.Client(intents=intents)

    class ApprovalView(discord.ui.View):
        """One row of [Y]/[N] buttons. custom_id carries the approval_id for identification."""

        def __init__(self) -> None:
            super().__init__(timeout=ttl_seconds)

        async def _authorized(self, interaction: "discord.Interaction") -> bool:
            # if approver_user_ids is empty (unset), nobody can approve — fail-closed safe default.
            if (not approvers) or (str(interaction.user.id) not in approvers):
                await interaction.response.send_message(
                    "You are not authorized to approve.", ephemeral=True
                )
                return False
            return True

        async def _resolve(self, interaction, decision: str, label: str) -> None:
            reason = f"by {interaction.user} ({interaction.user.id})"
            await interaction.response.send_message(f"{label} processed.", ephemeral=True)
            if not decision_future.done():
                decision_future.set_result((decision, reason))
            self.stop()

        @discord.ui.button(label="[Y] Approve", style=discord.ButtonStyle.success,
                           custom_id=f"approve:{approval_id}")
        async def approve(self, interaction, button):  # noqa: ANN001
            if await self._authorized(interaction):
                await self._resolve(interaction, "Y", "Approval")

        @discord.ui.button(label="[N] Reject", style=discord.ButtonStyle.danger,
                           custom_id=f"reject:{approval_id}")
        async def reject(self, interaction, button):  # noqa: ANN001
            if await self._authorized(interaction):
                await self._resolve(interaction, "N", "Rejection")

    @client.event
    async def on_ready() -> None:  # noqa: ANN202
        try:
            channel = client.get_channel(int(channel_id)) or await client.fetch_channel(int(channel_id))
            embed = discord.Embed(
                title=f"Approval request · {approval_id}",
                description=f"{question}\n\n**risk:** `{risk}`\n**TTL:** {ttl_min} min",
                color=0x3498DB,
            )
            await channel.send(embed=embed, view=ApprovalView())
        except Exception as exc:  # noqa: BLE001
            if not decision_future.done():
                decision_future.set_exception(exc)

    async def driver() -> int:
        # run client.start in the background and race the decision against the timeout.
        start_task = asyncio.create_task(client.start(token))
        try:
            try:
                decision, reason = await asyncio.wait_for(decision_future, timeout=ttl_seconds)
            except asyncio.TimeoutError:
                write_result(approval_id, "TIMEOUT", "no approver response within TTL")
                print(f"[approve_bot] TTL({ttl_min}m) exceeded → hold", file=sys.stderr)
                return 4
            write_result(approval_id, decision, reason)
            print(f"[approve_bot] decision={decision} ({reason})", file=sys.stderr)
            return 0 if decision == "Y" else 1
        finally:
            await client.close()
            start_task.cancel()
            try:
                await start_task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass

    return await driver()


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print(__doc__)
        print("\nusage: approve_bot.py <approval_id> <question> <risk> [ttl_minutes]", file=sys.stderr)
        return 2
    approval_id, question, risk = argv[1], argv[2], argv[3]
    ttl_min = int(argv[4]) if len(argv) > 4 else DEFAULT_TTL_MIN
    try:
        return asyncio.run(run_approval(approval_id, question, risk, ttl_min))
    except KeyboardInterrupt:
        return 4


if __name__ == "__main__":
    sys.exit(main(sys.argv))
