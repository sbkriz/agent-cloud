"""Tests for pfsense_sync pure helper functions."""

import pytest

from pfsense_sync import _is_valid_ip


@pytest.mark.parametrize("addr, expected", [
    ("192.168.1.100", True),
    ("10.0.0.1", True),
    ("172.16.0.1", True),
    ("8.8.8.8", True),
    ("2001:db8::1", True),
    ("0.0.0.0", False),
    ("127.0.0.1", False),
    ("169.254.1.1", False),
    ("::1", False),
    ("fe80::1", False),
    ("not-an-ip", False),
    (None, False),
    ("", False),
])
def test_is_valid_ip(addr, expected):
    assert _is_valid_ip(addr) is expected
