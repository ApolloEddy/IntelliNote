from unittest.mock import MagicMock

from app.services.smart_embedding import SmartEmbeddingManager


def test_iter_batches_splits_correctly():
    manager = SmartEmbeddingManager(MagicMock())
    items = [str(i) for i in range(12)]
    batches = list(manager._iter_batches(items, 5))
    assert [len(b) for b in batches] == [5, 5, 2]


def test_iter_batches_guard_zero_batch_size():
    manager = SmartEmbeddingManager(MagicMock())
    items = ["a", "b", "c"]
    batches = list(manager._iter_batches(items, 0))
    assert [len(b) for b in batches] == [1, 1, 1]
