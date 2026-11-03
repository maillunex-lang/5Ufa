"""Этап 1: релизы контента и каналы публикации

Revision ID: 0001
Revises:
Create Date: 2026-11-03
"""
import sqlalchemy as sa
from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "content_releases",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("source", sa.String(32), nullable=False),
        sa.Column("comment", sa.Text(), nullable=False, server_default=""),
        sa.Column("content_hash", sa.String(64), nullable=False),
        sa.Column("files_count", sa.Integer(), nullable=False),
        sa.Column("total_size", sa.BigInteger(), nullable=False),
        sa.Column("manifest", sa.JSON(), nullable=False),
    )
    op.create_index("ix_content_releases_content_hash", "content_releases", ["content_hash"])
    op.create_table(
        "content_channels",
        sa.Column("name", sa.String(32), primary_key=True),
        sa.Column("release_id", sa.Integer(), sa.ForeignKey("content_releases.id"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table("content_channels")
    op.drop_index("ix_content_releases_content_hash", table_name="content_releases")
    op.drop_table("content_releases")
