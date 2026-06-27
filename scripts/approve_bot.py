#!/usr/bin/env python3
"""ultraloop approve_bot.py — egress-only Discord Gateway approval bot.

SPEC v0.3 §13 (알림 & 승인 — 비동기 큐 + Discord 게이트웨이 봇).

왜 게이트웨이(Gateway)인가 — egress-only / DLP 호환
----------------------------------------------------
회사 DLP 환경은 inbound(인그레스) 웹훅을 열 수 없는 경우가 많다. Discord
Gateway 는 봇이 **바깥으로(outbound)** WebSocket(WSS) 연결을 맺고, 그 연결을
타고 버튼 클릭 같은 INTERACTION_CREATE 이벤트를 **수신**한다. 즉 우리 쪽에
열려 있는 포트가 전혀 필요 없다 — 송신만 하면 되는 방화벽에서도 동작한다.
discord.py(v2) 는 이 Gateway 연결 + 버튼 컴포넌트(View/Button) 를 내장한다.

동작
----
1) approval_channel_id 채널에 [Y]/[N] 버튼 메시지를 POST.
2) Gateway 로 들어오는 버튼 인터랙션을 기다린다.
3) 누른 사람이 approver_user_ids 허용목록에 있어야만 유효(아니면 거절 안내).
4) 선택(+선택적 사유)을 큐 디렉터리에 기록: <id>.result = "Y\n<reason>" / "N\n<reason>".
5) 종료코드: 0=Y(승인) / 1=N(거부) / 4=TTL 타임아웃(hold).

토큰
----
discord.token_env 가 가리키는 환경변수에서만 읽는다(기본
ULTRALOOP_DISCORD_BOT_TOKEN). 절대 하드코딩하지 않는다.

R5 — 봇 프로세스 수명/재연결
----------------------------
이 스크립트는 **승인 1건당 단기 실행(short-lived)** 으로 동작한다: 메시지 올리고,
결정 또는 TTL 까지만 살아 있다가 종료. 따라서 장수 데몬의 재연결/세션 만료
관리 부담이 없다(단발 연결이라 reconnect 가 사실상 불필요).
  대안: 길게 떠 있는 승인 데몬을 선호하면 assets/discord/gateway-bot.example.py
  를 참고(영구 연결 + discord.py 내장 재연결). 그 경우 R5 는 discord.py 의
  자동 reconnect 가 처리한다.

CLI
---
    approve_bot.py <approval_id> <question> <risk> [ttl_minutes]
"""
from __future__ import annotations

import os
import sys
import asyncio
from pathlib import Path

# ── config 로딩 (PyYAML 있으면 사용, 없으면 최소 파서) ──────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
# 기본 config = 대상 레포 cwd(loop가 대상 레포에서 호출). 플러그인 루트가 아니다.
CONFIG_PATH = Path(os.environ.get("ULTRALOOP_CONFIG") or (Path.cwd() / "ultraloop.config.yaml"))
RESULT_DIR = Path(os.environ.get("TMPDIR", "/tmp")) / "ultraloop-approvals"

DEFAULT_TOKEN_ENV = "ULTRALOOP_DISCORD_BOT_TOKEN"
DEFAULT_TTL_MIN = 120


def _load_discord_config() -> dict:
    """config 의 discord: 블록만 dict 로 반환. PyYAML 우선, 없으면 평면 파서."""
    if not CONFIG_PATH.exists():
        return {}
    text = CONFIG_PATH.read_text(encoding="utf-8")
    try:
        import yaml  # type: ignore
        data = yaml.safe_load(text) or {}
        return data.get("discord", {}) or {}
    except Exception:
        pass
    # 최소 폴백 파서: discord: 블록의 한 단계 들여쓴 key: value 만 읽는다.
    out: dict = {}
    in_block = False
    for raw in text.splitlines():
        if raw.startswith("discord:"):
            in_block = True
            continue
        if in_block:
            if raw and not raw[0].isspace():
                break  # 블록 종료
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
        print("discord.py 가 설치돼 있지 않습니다. 설치: pip install discord.py", file=sys.stderr)
        return 3

    cfg = _load_discord_config()
    token_env = cfg.get("token_env") or DEFAULT_TOKEN_ENV
    token = os.environ.get(token_env, "")
    channel_id = cfg.get("approval_channel_id")
    approvers = _coerce_ids(cfg.get("approver_user_ids", []))

    if not token:
        print(f"토큰 환경변수 {token_env} 가 비어 있습니다.", file=sys.stderr)
        return 3
    if not channel_id:
        print("discord.approval_channel_id 가 설정돼 있지 않습니다.", file=sys.stderr)
        return 3

    ttl_seconds = max(1, ttl_min) * 60
    loop = asyncio.get_running_loop()
    decision_future: asyncio.Future = loop.create_future()

    intents = discord.Intents.none()
    intents.guilds = True  # 채널 fetch + 컴포넌트 인터랙션 수신에 필요
    client = discord.Client(intents=intents)

    class ApprovalView(discord.ui.View):
        """[Y]/[N] 버튼 한 줄. custom_id 에 approval_id 를 담아 식별한다."""

        def __init__(self) -> None:
            super().__init__(timeout=ttl_seconds)

        async def _authorized(self, interaction: "discord.Interaction") -> bool:
            # approver_user_ids 가 비어 있으면(미설정) 누구도 승인 못 한다 — fail-closed 안전 기본값.
            if (not approvers) or (str(interaction.user.id) not in approvers):
                await interaction.response.send_message(
                    "승인 권한이 없는 사용자입니다.", ephemeral=True
                )
                return False
            return True

        async def _resolve(self, interaction, decision: str, label: str) -> None:
            reason = f"by {interaction.user} ({interaction.user.id})"
            await interaction.response.send_message(f"{label} 처리되었습니다.", ephemeral=True)
            if not decision_future.done():
                decision_future.set_result((decision, reason))
            self.stop()

        @discord.ui.button(label="[Y] 승인", style=discord.ButtonStyle.success,
                           custom_id=f"approve:{approval_id}")
        async def approve(self, interaction, button):  # noqa: ANN001
            if await self._authorized(interaction):
                await self._resolve(interaction, "Y", "승인")

        @discord.ui.button(label="[N] 거부", style=discord.ButtonStyle.danger,
                           custom_id=f"reject:{approval_id}")
        async def reject(self, interaction, button):  # noqa: ANN001
            if await self._authorized(interaction):
                await self._resolve(interaction, "N", "거부")

    @client.event
    async def on_ready() -> None:  # noqa: ANN202
        try:
            channel = client.get_channel(int(channel_id)) or await client.fetch_channel(int(channel_id))
            embed = discord.Embed(
                title=f"승인 요청 · {approval_id}",
                description=f"{question}\n\n**risk:** `{risk}`\n**TTL:** {ttl_min}분",
                color=0x3498DB,
            )
            await channel.send(embed=embed, view=ApprovalView())
        except Exception as exc:  # noqa: BLE001
            if not decision_future.done():
                decision_future.set_exception(exc)

    async def driver() -> int:
        # client.start 를 백그라운드로 돌리고, 결정/타임아웃을 경쟁시킨다.
        start_task = asyncio.create_task(client.start(token))
        try:
            try:
                decision, reason = await asyncio.wait_for(decision_future, timeout=ttl_seconds)
            except asyncio.TimeoutError:
                write_result(approval_id, "TIMEOUT", "no approver response within TTL")
                print(f"[approve_bot] TTL({ttl_min}m) 초과 → hold", file=sys.stderr)
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
