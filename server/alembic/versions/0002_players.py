"""Этап 2: игроки и сессии

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-03
"""
import sqlalchemy as sa
from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "players",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("number", sa.Integer(), nullable=False, unique=True),
        sa.Column("display_name", sa.String(32), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("email", sa.String(254), nullable=True, unique=True),
        sa.Column("password_hash", sa.String(255), nullable=True),
        sa.Column("is_test", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("banned_until", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ban_reason", sa.Text(), nullable=False, server_default=""),
    )
    op.create_table(
        "player_sessions",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("player_id", sa.Uuid(), sa.ForeignKey("players.id", ondelete="CASCADE"), nullable=False),
        sa.Column("device_id", sa.String(64), nullable=False),
        sa.Column("refresh_hash", sa.String(64), nullable=False, unique=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("client_version", sa.String(32), nullable=False, server_default=""),
        sa.Column("ip", sa.String(64), nullable=False, server_default=""),
    )
    op.create_index("ix_player_sessions_player_id", "player_sessions", ["player_id"])
    op.create_index("ix_player_sessions_device_id", "player_sessions", ["device_id"])


def downgrade() -> None:
    op.drop_table("player_sessions")
    op.drop_table("players")
