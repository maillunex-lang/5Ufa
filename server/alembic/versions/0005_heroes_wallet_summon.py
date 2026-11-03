"""Этап 5а: герои игрока, кошелёк валют, призыв

- player_heroes   — экземпляры героев (копии) с редкостью, уровнем и слотом Кристалла резонанса
- player_wallet   — все валюты игрока (золото, опыт героев, кристаллы, эссенция, свитки ...)
- summon_state    — счётчики гаранта по баннерам
- player_state    — служебные флаги (выдан ли стартовый набор)
- campaign_progress: добавлены доли кристаллов и эссенции для AFK-сундука

Золото и опыт переносятся из campaign_progress в player_wallet (при откате — обратно).

Revision ID: 0005
Revises: 0004
"""
import sqlalchemy as sa
from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "player_heroes",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("player_id", sa.Uuid(), sa.ForeignKey("players.id", ondelete="CASCADE"), nullable=False),
        sa.Column("hero_id", sa.String(64), nullable=False),
        sa.Column("tier", sa.String(32), nullable=False),
        sa.Column("level", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("crystal_slot", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_player_heroes_player_id", "player_heroes", ["player_id"])
    op.create_table(
        "player_wallet",
        sa.Column("player_id", sa.Uuid(), sa.ForeignKey("players.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("code", sa.String(48), primary_key=True),
        sa.Column("amount", sa.BigInteger(), nullable=False, server_default="0"),
    )
    op.create_table(
        "summon_state",
        sa.Column("player_id", sa.Uuid(), sa.ForeignKey("players.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("banner_id", sa.String(64), primary_key=True),
        sa.Column("pity", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("total", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_table(
        "player_state",
        sa.Column("player_id", sa.Uuid(), sa.ForeignKey("players.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("starter_granted", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.add_column("campaign_progress", sa.Column("crystal_fraction", sa.BigInteger(), nullable=False, server_default="0"))
    op.add_column("campaign_progress", sa.Column("essence_fraction", sa.BigInteger(), nullable=False, server_default="0"))
    # Перенос накопленного золота и опыта в кошелёк
    op.execute("INSERT INTO player_wallet (player_id, code, amount) "
               "SELECT player_id, 'gold', gold FROM campaign_progress WHERE gold > 0")
    op.execute("INSERT INTO player_wallet (player_id, code, amount) "
               "SELECT player_id, 'hero_xp', hero_xp FROM campaign_progress WHERE hero_xp > 0")
    op.execute("UPDATE campaign_progress SET gold = 0, hero_xp = 0")


def downgrade():
    op.execute("UPDATE campaign_progress SET gold = COALESCE((SELECT amount FROM player_wallet w "
               "WHERE w.player_id = campaign_progress.player_id AND w.code = 'gold'), 0)")
    op.execute("UPDATE campaign_progress SET hero_xp = COALESCE((SELECT amount FROM player_wallet w "
               "WHERE w.player_id = campaign_progress.player_id AND w.code = 'hero_xp'), 0)")
    op.drop_column("campaign_progress", "essence_fraction")
    op.drop_column("campaign_progress", "crystal_fraction")
    op.drop_table("player_state")
    op.drop_table("summon_state")
    op.drop_table("player_wallet")
    op.drop_index("ix_player_heroes_player_id", table_name="player_heroes")
    op.drop_table("player_heroes")
