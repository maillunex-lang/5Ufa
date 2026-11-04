"""Этап 6в-2: скины героев — полученные игроком и выбранные

Revision ID: 0008
Revises: 0007
"""
import sqlalchemy as sa
from alembic import op

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "player_skins",
        sa.Column("player_id", sa.Uuid(), sa.ForeignKey("players.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("hero_id", sa.String(64), primary_key=True),
        sa.Column("skin_id", sa.String(32), primary_key=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_table(
        "player_skin_choice",
        sa.Column("player_id", sa.Uuid(), sa.ForeignKey("players.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("hero_id", sa.String(64), primary_key=True),
        sa.Column("skin_id", sa.String(32), nullable=False),
    )


def downgrade():
    op.drop_table("player_skin_choice")
    op.drop_table("player_skins")
