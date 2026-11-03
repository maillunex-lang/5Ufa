"""Этап 5б: снаряжение и уникальный предмет героя

- player_items — предметы снаряжения (слот, тип, редкость, фракция, уровень улучшения, на ком надет)
- player_heroes.signature_level — уровень уникального предмета героя
- player_state.equipment_starter_granted — выдан ли стартовый набор снаряжения
- campaign_progress: доли руды и предметов для AFK-сундука

Revision ID: 0006
Revises: 0005
"""
import sqlalchemy as sa
from alembic import op

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "player_items",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("player_id", sa.Uuid(), sa.ForeignKey("players.id", ondelete="CASCADE"), nullable=False),
        sa.Column("slot", sa.String(32), nullable=False),
        sa.Column("kind", sa.String(32), nullable=False),
        sa.Column("quality", sa.String(32), nullable=False),
        sa.Column("faction", sa.String(64), nullable=True),
        sa.Column("level", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("ore_spent", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("hero_instance_id", sa.Integer(), sa.ForeignKey("player_heroes.id", ondelete="SET NULL"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_player_items_player_id", "player_items", ["player_id"])
    op.create_index("ix_player_items_hero_instance_id", "player_items", ["hero_instance_id"])
    op.add_column("player_heroes", sa.Column("signature_level", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("player_state", sa.Column("equipment_starter_granted", sa.Boolean(), nullable=False,
                                            server_default=sa.false()))
    op.add_column("campaign_progress", sa.Column("ore_fraction", sa.BigInteger(), nullable=False, server_default="0"))
    op.add_column("campaign_progress", sa.Column("equipment_fraction", sa.BigInteger(), nullable=False, server_default="0"))


def downgrade():
    op.drop_column("campaign_progress", "equipment_fraction")
    op.drop_column("campaign_progress", "ore_fraction")
    op.drop_column("player_state", "equipment_starter_granted")
    op.drop_column("player_heroes", "signature_level")
    op.drop_index("ix_player_items_hero_instance_id", table_name="player_items")
    op.drop_index("ix_player_items_player_id", table_name="player_items")
    op.drop_table("player_items")
