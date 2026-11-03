"""Кампания и AFK-награды.

Revision ID: 0004
Revises: 0003
"""
import sqlalchemy as sa
from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "campaign_progress",
        sa.Column("player_id", sa.Uuid(), sa.ForeignKey("players.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("cleared", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("gold", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("hero_xp", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("gold_fraction", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("xp_fraction", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("elapsed_us", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("quick_day", sa.String(10), nullable=False, server_default=""),
        sa.Column("quick_count", sa.Integer(), nullable=False, server_default="0"),
    )


def downgrade():
    op.drop_table("campaign_progress")
