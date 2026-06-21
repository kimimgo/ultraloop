#!/usr/bin/env python3
"""gateway-bot.example.py — egress-only Discord 승인 데몬 (예시 자산)

이 파일은 ultraloop 스킬이 직접 실행하지 않는 '복붙용 예시'다. 승인 1건마다
프로세스를 띄우는 단발 방식(scripts/approve_bot.py) 대신, **길게 떠 있는 승인
데몬**을 선호할 때 이 골격을 그대로 가져다 쓰면 된다.

핵심 개념 (egress-only / DLP 호환)
----------------------------------
- Gateway = **바깥으로 나가는** WebSocket(WSS) 연결이다. 봇이 Discord 로
  먼저 연결을 맺고, 그 연결을 타고 버튼 클릭(INTERACTION_CREATE) 을 받는다.
  즉 **인그레스(열린 포트/웹훅) 가 전혀 필요 없다** — 송신만 허용되는
  방화벽에서도 버튼 승인이 동작한다.
- intents: 버튼 컴포넌트 인터랙션과 채널 접근에는 guilds 만 있으면 된다.
  message_content 같은 특권 intent 는 필요 없다(버튼은 컴포넌트 이벤트).
- 버튼 View: custom_id 를 `approve:<id>` / `reject:<id>` 로 인코딩해서
  어떤 승인 건인지 식별한다.
- approver 허용목록: 누른 사람이 APPROVER_IDS 에 있어야만 유효.
- 결과 기록: 결정을 RESULT_DIR/<id>.result 에 쓴다(큐가 폴링해서 소비).
- TTL: asyncio.wait_for 로 승인 만료를 건다.

실행
----
    export ULTRALOOP_DISCORD_BOT_TOKEN=...   # 토큰은 env 로만
    export ULTRALOOP_APPROVAL_CHANNEL_ID=123456789012345678
    export ULTRALOOP_APPROVER_IDS=111111111111111111,222222222222222222
    pip install discord.py
    python gateway-bot.example.py

데몬이 떠 있는 동안, 큐가 새 승인 건을 만들 때 request_approval() 를 호출하는
식으로 연동한다(아래 예시는 단독 데모로 한 건을 올린다).

R5(수명/재연결): 이 데몬 방식에서는 discord.py 의 내장 자동 reconnect 가
세션 만료/네트워크 끊김을 처리한다. 단발 방식과의 트레이드오프는 SPEC §13 참고.
"""
from __future__ import annotations

import os
import asyncio
from pathlib import Path

import discord  # pip install discord.py

# ── 설정 (env 로만, 하드코딩 금지) ──────────────────────────────────────────
TOKEN = os.environ.get("ULTRALOOP_DISCORD_BOT_TOKEN", "")
CHANNEL_ID = int(os.environ.get("ULTRALOOP_APPROVAL_CHANNEL_ID", "0"))
APPROVER_IDS = {
    s.strip() for s in os.environ.get("ULTRALOOP_APPROVER_IDS", "").split(",") if s.strip()
}
RESULT_DIR = Path(os.environ.get("TMPDIR", "/tmp")) / "ultraloop-approvals"
DEFAULT_TTL_SECONDS = 120 * 60  # 120분


def write_result(approval_id: str, decision: str, reason: str = "") -> None:
    """결정을 큐 디렉터리에 기록 — 큐가 이 파일을 폴링해 소비한다."""
    RESULT_DIR.mkdir(parents=True, exist_ok=True)
    (RESULT_DIR / f"{approval_id}.result").write_text(
        f"{decision}\n{reason}".rstrip() + "\n", encoding="utf-8"
    )


class ApprovalView(discord.ui.View):
    """[Y]/[N] 버튼 한 줄. 결정되면 done 퓨처를 채운다."""

    def __init__(self, approval_id: str, ttl_seconds: int) -> None:
        super().__init__(timeout=ttl_seconds)
        self.approval_id = approval_id
        self.done: asyncio.Future = asyncio.get_event_loop().create_future()

    def _ok(self, interaction: discord.Interaction) -> bool:
        # 허용목록이 비어 있으면 안전을 위해 아무도 통과시키지 않는다.
        return bool(APPROVER_IDS) and str(interaction.user.id) in APPROVER_IDS

    async def _finish(self, interaction, decision: str, label: str) -> None:
        if not self._ok(interaction):
            await interaction.response.send_message("승인 권한이 없습니다.", ephemeral=True)
            return
        reason = f"by {interaction.user} ({interaction.user.id})"
        write_result(self.approval_id, decision, reason)
        await interaction.response.send_message(f"{label} 처리되었습니다.", ephemeral=True)
        if not self.done.done():
            self.done.set_result(decision)
        self.stop()

    @discord.ui.button(label="[Y] 승인", style=discord.ButtonStyle.success, custom_id="approve")
    async def approve(self, interaction: discord.Interaction, button: discord.ui.Button) -> None:
        # custom_id 는 메시지 전송 시 approve:<id> 로 덮어쓴다(아래 request_approval 참고).
        await self._finish(interaction, "Y", "승인")

    @discord.ui.button(label="[N] 거부", style=discord.ButtonStyle.danger, custom_id="reject")
    async def reject(self, interaction: discord.Interaction, button: discord.ui.Button) -> None:
        await self._finish(interaction, "N", "거부")

    async def on_timeout(self) -> None:
        write_result(self.approval_id, "TIMEOUT", "no approver response within TTL")
        if not self.done.done():
            self.done.set_result("TIMEOUT")


async def request_approval(client: discord.Client, approval_id: str, question: str,
                           risk: str, ttl_seconds: int = DEFAULT_TTL_SECONDS) -> str:
    """승인 메시지를 올리고 결정(Y/N/TIMEOUT) 을 기다린다."""
    channel = client.get_channel(CHANNEL_ID) or await client.fetch_channel(CHANNEL_ID)
    view = ApprovalView(approval_id, ttl_seconds)
    # custom_id 에 approval_id 를 실어 식별 가능하게 한다.
    for child in view.children:
        if isinstance(child, discord.ui.Button):
            base = "approve" if child.style == discord.ButtonStyle.success else "reject"
            child.custom_id = f"{base}:{approval_id}"
    embed = discord.Embed(
        title=f"승인 요청 · {approval_id}",
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
        raise SystemExit("ULTRALOOP_DISCORD_BOT_TOKEN / ULTRALOOP_APPROVAL_CHANNEL_ID 필요")

    intents = discord.Intents.none()
    intents.guilds = True  # 채널 접근 + 컴포넌트 인터랙션 수신에 충분
    client = discord.Client(intents=intents)

    @client.event
    async def on_ready() -> None:
        print(f"[gateway-bot] 연결됨: {client.user}")
        # 데모: 한 건을 올려 본다. 실제로는 큐 이벤트마다 request_approval 을 호출.
        decision = await request_approval(
            client, approval_id="demo-001",
            question="프로덕션 DB 마이그레이션을 실행할까요?", risk="high",
        )
        print(f"[gateway-bot] demo 결정: {decision}")

    client.run(TOKEN)  # discord.py 가 자동 reconnect 를 처리(R5)


if __name__ == "__main__":
    main()
