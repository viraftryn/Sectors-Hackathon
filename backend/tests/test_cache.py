"""Tests for the two-layer cache (L1 in-memory only — no DB needed)."""

import time

from app.cache import _MemoryStore


def test_memory_store_set_and_get() -> None:
    store = _MemoryStore()
    store.set("key1", {"price": 9800}, ttl=300)
    assert store.get("key1") == {"price": 9800}


def test_memory_store_miss() -> None:
    store = _MemoryStore()
    assert store.get("nonexistent") is None


def test_memory_store_expiry() -> None:
    store = _MemoryStore()
    store.set("key1", {"price": 9800}, ttl=0)
    time.sleep(0.01)
    assert store.get("key1") is None


def test_memory_store_invalidate() -> None:
    store = _MemoryStore()
    store.set("key1", {"price": 9800}, ttl=300)
    store.invalidate("key1")
    assert store.get("key1") is None


def test_memory_store_clear() -> None:
    store = _MemoryStore()
    store.set("a", 1, ttl=300)
    store.set("b", 2, ttl=300)
    assert store.size == 2
    store.clear()
    assert store.size == 0


def test_memory_store_overwrite() -> None:
    store = _MemoryStore()
    store.set("key1", {"v": 1}, ttl=300)
    store.set("key1", {"v": 2}, ttl=300)
    assert store.get("key1") == {"v": 2}


def test_memory_store_different_ttls() -> None:
    store = _MemoryStore()
    store.set("short", "data", ttl=0)
    store.set("long", "data", ttl=9999)
    time.sleep(0.01)
    assert store.get("short") is None
    assert store.get("long") == "data"
