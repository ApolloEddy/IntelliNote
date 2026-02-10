"""Harden document and chunk cache constraints

Revision ID: 7c2c5e9f1d4a
Revises: 015ec0f3c03d
Create Date: 2026-02-10 10:55:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "7c2c5e9f1d4a"
down_revision: Union[str, Sequence[str], None] = "015ec0f3c03d"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _upgrade_sqlite() -> None:
    op.create_table(
        "documents_new",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("notebook_id", sa.String(), nullable=False),
        sa.Column("filename", sa.String(), nullable=False),
        sa.Column("file_hash", sa.String(length=64), nullable=False),
        sa.Column("emoji", sa.String(), nullable=True),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("error_msg", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("(CURRENT_TIMESTAMP)"), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "status IN ('pending','processing','ready','failed')",
            name="ck_documents_status_valid",
        ),
        sa.ForeignKeyConstraint(["file_hash"], ["artifacts.hash"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("notebook_id", "file_hash", name="uq_documents_notebook_file_hash"),
    )
    op.execute(
        """
        INSERT INTO documents_new (id, notebook_id, filename, file_hash, emoji, status, error_msg, created_at, updated_at)
        SELECT
            id,
            notebook_id,
            filename,
            file_hash,
            emoji,
            CASE
                WHEN status IN ('pending','processing','ready','failed') THEN status
                ELSE 'pending'
            END AS status,
            error_msg,
            created_at,
            updated_at
        FROM documents
        """
    )
    op.drop_table("documents")
    op.rename_table("documents_new", "documents")
    op.create_index(op.f("ix_documents_notebook_id"), "documents", ["notebook_id"], unique=False)

    op.create_table(
        "chunk_cache_new",
        sa.Column("text_hash", sa.String(length=64), nullable=False),
        sa.Column("model_name", sa.String(), nullable=False, server_default=sa.text("'default'")),
        sa.Column("embedding", sa.LargeBinary(), nullable=False),
        sa.PrimaryKeyConstraint("text_hash", "model_name", name="pk_chunk_cache_text_model"),
    )
    op.execute(
        """
        INSERT INTO chunk_cache_new (text_hash, model_name, embedding)
        SELECT text_hash, COALESCE(model_name, 'default'), embedding
        FROM chunk_cache
        """
    )
    op.drop_table("chunk_cache")
    op.rename_table("chunk_cache_new", "chunk_cache")
    op.create_index(op.f("ix_chunk_cache_text_hash"), "chunk_cache", ["text_hash"], unique=False)


def _downgrade_sqlite() -> None:
    op.create_table(
        "documents_old",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("notebook_id", sa.String(), nullable=False),
        sa.Column("filename", sa.String(), nullable=False),
        sa.Column("file_hash", sa.String(length=64), nullable=False),
        sa.Column("emoji", sa.String(), nullable=True),
        sa.Column("status", sa.String(), nullable=True),
        sa.Column("error_msg", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("(CURRENT_TIMESTAMP)"), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["file_hash"], ["artifacts.hash"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.execute(
        """
        INSERT INTO documents_old (id, notebook_id, filename, file_hash, emoji, status, error_msg, created_at, updated_at)
        SELECT id, notebook_id, filename, file_hash, emoji, status, error_msg, created_at, updated_at
        FROM documents
        """
    )
    op.drop_table("documents")
    op.rename_table("documents_old", "documents")
    op.create_index(op.f("ix_documents_notebook_id"), "documents", ["notebook_id"], unique=False)

    op.create_table(
        "chunk_cache_old",
        sa.Column("text_hash", sa.String(length=64), nullable=False),
        sa.Column("embedding", sa.LargeBinary(), nullable=False),
        sa.Column("model_name", sa.String(), nullable=True),
        sa.PrimaryKeyConstraint("text_hash"),
    )
    op.execute(
        """
        INSERT INTO chunk_cache_old (text_hash, embedding, model_name)
        SELECT text_hash, embedding, model_name
        FROM chunk_cache
        """
    )
    op.drop_table("chunk_cache")
    op.rename_table("chunk_cache_old", "chunk_cache")
    op.create_index(op.f("ix_chunk_cache_text_hash"), "chunk_cache", ["text_hash"], unique=False)


def upgrade() -> None:
    """Upgrade schema."""
    bind = op.get_bind()
    if bind.dialect.name == "sqlite":
        _upgrade_sqlite()
        return

    with op.batch_alter_table("documents", schema=None) as batch_op:
        batch_op.alter_column("status", existing_type=sa.String(), nullable=False)
        batch_op.create_check_constraint(
            "ck_documents_status_valid",
            "status IN ('pending','processing','ready','failed')",
        )
        batch_op.create_unique_constraint(
            "uq_documents_notebook_file_hash",
            ["notebook_id", "file_hash"],
        )

    with op.batch_alter_table("chunk_cache", schema=None) as batch_op:
        batch_op.alter_column("model_name", existing_type=sa.String(), nullable=False)


def downgrade() -> None:
    """Downgrade schema."""
    bind = op.get_bind()
    if bind.dialect.name == "sqlite":
        _downgrade_sqlite()
        return

    with op.batch_alter_table("documents", schema=None) as batch_op:
        batch_op.drop_constraint("uq_documents_notebook_file_hash", type_="unique")
        batch_op.drop_constraint("ck_documents_status_valid", type_="check")
        batch_op.alter_column("status", existing_type=sa.String(), nullable=True)

    with op.batch_alter_table("chunk_cache", schema=None) as batch_op:
        batch_op.alter_column("model_name", existing_type=sa.String(), nullable=True)
