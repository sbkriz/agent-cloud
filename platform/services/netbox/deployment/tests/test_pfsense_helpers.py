"""Tests for pfsense_sync pure helper functions."""

import pytest

from pfsense_sync import _is_valid_ip


class TestIsValidIp:
    def test_valid_ipv4(self):
        assert _is_valid_ip("192.168.1.100") is True

    def test_valid_ipv6(self):
        assert _is_valid_ip("2001:db8::1") is True

    def test_rejects_unspecified(self):
        assert _is_valid_ip("0.0.0.0") is False

    def test_rejects_loopback(self):
        assert _is_valid_ip("127.0.0.1") is False

    def test_rejects_link_local(self):
        assert _is_valid_ip("169.254.1.1") is False

    def test_rejects_ipv6_loopback(self):
        assert _is_valid_ip("::1") is False

    def test_rejects_ipv6_link_local(self):
        assert _is_valid_ip("fe80::1") is False

    def test_rejects_garbage(self):
        assert _is_valid_ip("not-an-ip") is False

    def test_rejects_none(self):
        assert _is_valid_ip(None) is False

    def test_rejects_empty(self):
        assert _is_valid_ip("") is False

    def test_private_class_a(self):
        assert _is_valid_ip("10.0.0.1") is True

    def test_private_class_b(self):
        assert _is_valid_ip("172.16.0.1") is True

    def test_public_ip(self):
        assert _is_valid_ip("8.8.8.8") is True
