#!/usr/bin/env python3
"""gateway-bot.example.py — egress-only Discord approval daemon (example asset)

This file is a copy-paste example that the ultraloop skill never runs directly.
Use this skeleton as-is when you prefer a **long-running approval daemon** over
the one-shot mode that spawns a process per approval (scripts/approve_bot.py).

Core concepts (egress-only / DLP compatible)
----------------------------------
- Gateway = an **outbound** WebSocket (WSS) connection. The bot connects to
  Discord first, and button clicks (INTERACTION_CREATE) arrive over that connection.
  That means **no ingress (open port/webhook) is needed at all** — button
  approvals work even behind a firewall that only allows outbound traffic.
- intents: button component interactions and channel access only need guilds.
  No privileged intent like message_content is required (buttons are component events).
- Button View: encode custom_id as `approve:<id>` / `reject:<id>` to
  identify which approval it belongs to.
- approver allowlist: the clicker is valid only if listed in APPROVER_IDS.
- Result recording: write the decision to RESULT_DIR/<id>.result (the queue polls and consumes it).
- TTL: approval expiry is enforced with asyncio.wait_for.

Run
----
    export ULTRALOOP_DISCORD_BOT_TOKEN=...   # token via env only
    export ULTRALOOP_APPROVAL_CHANNEL_ID=123456789012345678
    export ULTRALOOP_APPROVER_IDS=111111111111111111,222222222222222222
    pip install discord.py
    python gateway-bot.example.py

While the daemon is up, integrate by calling request_approval() whenever the
queue creates a new approval item (the example below posts one item as a standalone demo).

R5 (lifetime/reconnect): in this daemon mode, discord.py's built-in automatic
reconnect handles session expiry/network drops. See SPEC §13 for the trade-offs
against the one-shot mode.
"""
from __future__ import annotations

import os
import asyncio
from pathlib import Path

import discord  # pip install discord.py

# ── Settings (env only, no hardcoding) ─────────────────────────────────────
TOKEN = os.environ.get("ULTRALOOP_DISCORD_BOT_TOKEN", "")
CHANNEL_ID = int(os.environ.get("ULTRALOOP_APPROVAL_CHANNEL_ID", "0"))
APPROVER_IDS = {
    s.strip() for s in os.environ.get("ULTRALOOP_APPROVER_IDS", "").split(",") if s.strip()
}
RESULT_DIR = Path(os.environ.get("TMPDIR", "/tmp")) / "ultraloop-approvals"
DEFAULT_TTL_SECONDS = 120 * 60  # 120 minutes


def write_result(approval_id: str, decision: str, reason: str = "") -> None:
    """Record the decision in the queue directory — the queue polls and consumes this file."""
    RESULT_DIR.mkdir(parents=True, exist_ok=True)
    (RESULT_DIR / f"{approval_id}.result").write_text(
        f"{decision}\n{reason}".rstrip() + "\n", encoding="utf-8"
    )


class ApprovalView(discord.ui.View):
    """One row of [Y]/[N] buttons. Fills the done future once decided."""

    def __init__(self, approval_id: str, ttl_seconds: int) -> None:
        super().__init__(timeout=ttl_seconds)
        self.approval_id = approval_id
        self.done: asyncio.Future = asyncio.get_event_loop().create_future()

    def _ok(self, interaction: discord.Interaction) -> bool:
        # If the allowlist is empty, let nobody through, for safety.
        return bool(APPROVER_IDS) and str(interaction.user.id) in APPROVER_IDS

    async def _finish(self, interaction, decision: str, label: str) -> None:
        if not self._ok(interaction):
            await interaction.response.send_message("You are not authorized to approve.", ephemeral=True)
            return
        reason = f"by {interaction.user} ({interaction.user.id})"
        write_result(self.approval_id, decision, reason)
        await interaction.response.send_message(f"{label} processed.", ephemeral=True)
        if not self.done.done():
            self.done.set_result(decision)
        self.stop()

    @discord.ui.button(label="[Y] Approve", style=discord.ButtonStyle.success, custom_id="approve")
    async def approve(self, interaction: discord.Interaction, button: discord.ui.Button) -> None:
        # custom_id is overwritten to approve:<id> when the message is sent (see request_approval below).
        await self._finish(interaction, "Y", "Approval")

    @discord.ui.button(label="[N] Reject", style=discord.ButtonStyle.danger, custom_id="reject")
    async def reject(self, interaction: discord.Interaction, button: discord.ui.Button) -> None:
        await self._finish(interaction, "N", "Rejection")

    async def on_timeout(self) -> None:
        write_result(self.approval_id, "TIMEOUT", "no approver response within TTL")
        if not self.done.done():
            self.done.set_result("TIMEOUT")


async def request_approval(client: discord.Client, approval_id: str, question: str,
                           risk: str, ttl_seconds: int = DEFAULT_TTL_SECONDS) -> str:
    """Post the approval message and wait for the decision (Y/N/TIMEOUT)."""
    channel = client.get_channel(CHANNEL_ID) or await client.fetch_channel(CHANNEL_ID)
    view = ApprovalView(approval_id, ttl_seconds)
    # Carry approval_id in custom_id so the item is identifiable.
    for child in view.children:
        if isinstance(child, discord.ui.Button):
            base = "approve" if child.style == discord.ButtonStyle.success else "reject"
            child.custom_id = f"{base}:{approval_id}"
    embed = discord.Embed(
        title=f"Approval request · {approval_id}",
        description=f"{question}\n\n**risk:** `{risk}`",
        color=0x3498DB,
    )
    await channel.send(embed=embed, view=view)
    try:
        return await asyncio.wait_for(view.done, timeout=ttl_seconds)
    except asyncio.TimeoutError:
        return "TIMEOUT"


def main() -> None:
    if not TOKEN or not CHANNEL_ID:
        raise SystemExit("ULTRALOOP_DISCORD_BOT_TOKEN / ULTRALOOP_APPROVAL_CHANNEL_ID required")

    intents = discord.Intents.none()
    intents.guilds = True  # sufficient for channel access + receiving component interactions
    client = discord.Client(intents=intents)

    @client.event
    async def on_ready() -> None:
        print(f"[gateway-bot] connected: {client.user}")
        # Demo: post one item. In real use, call request_approval per queue event.
        decision = await request_approval(
            client, approval_id="demo-001",
            question="Run the production DB migration?", risk="high",
        )
        print(f"[gateway-bot] demo decision: {decision}")

    client.run(TOKEN)  # discord.py handles automatic reconnect (R5)


if __name__ == "__main__":
    main()
