"""Tests for proxmox_discovery pure helper functions."""

import pytest
from proxmox_discovery import (
    _bytes_to_gb,
    _iface_type,
    _int,
    _mb_to_gb,
    _pick_primary_ipv4,
    _prefix_len,
    _sanitize_description,
    _should_skip_iface,
)


@pytest.mark.parametrize("val, default, expected", [
    (42, 0, 42),
    ("2048", 0, 2048),
    (None, 0, 0),
    ("", 0, 0),
    ("3.5", 0, 0),
    (None, 99, 99),
    (-5, 0, -5),
    (2147483648, 0, 2147483648),
    ("2147483648", 0, 2147483648),
])
def test_int(val, default, expected):
    assert _int(val, default) == expected


@pytest.mark.parametrize("mb, expected", [
    (1024, 1.0), (2048, 2.0), (0, 0.0), ("4096", 4.0),
])
def test_mb_to_gb(mb, expected):
    assert _mb_to_gb(mb) == expected


@pytest.mark.parametrize("b, expected", [
    (1073741824, 1.0), (2147483648, 2.0), (0, 0.0),
])
def test_bytes_to_gb(b, expected):
    assert _bytes_to_gb(b) == expected


@pytest.mark.parametrize("name, should_skip", [
    ("lo", True), ("fwbr100", True), ("tap100i0", True),
    ("veth100", True), ("fwln100", True), ("fwpr100", True),
    ("", True), (None, True),
    ("eth0", False), ("vmbr0", False), ("bond0", False), ("ens18", False),
])
def test_should_skip_iface(name, should_skip):
    assert _should_skip_iface(name) is should_skip


@pytest.mark.parametrize("name, expected_type", [
    ("vmbr0", "bridge"), ("bond0", "lag"),
    ("vlan100", "virtual"), (".100", "virtual"), ("wg0", "virtual"),
    ("eth0", "other"), ("ens18", "other"), ("xyz0", "other"),
])
def test_iface_type(name, expected_type):
    assert _iface_type(name) == expected_type


@pytest.mark.parametrize("cidr, expected", [
    ("10.0.0.1/24", 24), ("172.16.0.0/16", 16), ("10.0.0.1/32", 32),
    ("10.0.0.1", None), ("", None), (None, None),
    ("10.0.0.1/abc", None), ("/", None),
])
def test_prefix_len(cidr, expected):
    assert _prefix_len(cidr) == expected


class TestSanitizeDescription:
    @pytest.mark.parametrize("desc, expected_none", [
        ("", True), (None, True),
        ("password=abc\nsecret_key=xyz", True),
    ])
    def test_returns_none(self, desc, expected_none):
        assert _sanitize_description(desc) is None

    @pytest.mark.parametrize("sensitive_line", [
        "root password: abc",
        "API token: xyz",
        "secret: shhh",
        "PASSWORD: foo",
        "secret_key=abc",
        "api_token=xyz",
        "root_password=hunter2",
    ])
    def test_strips_sensitive_lines(self, sensitive_line):
        result = _sanitize_description(f"{sensitive_line}\nNormal line")
        assert "Normal line" in result
        keyword = sensitive_line.split("=")[0].split(":")[0].split()[-1].lower()
        assert keyword not in (result or "").lower()

    @pytest.mark.parametrize("safe_word", ["keyboard", "monkey", "turkey"])
    def test_preserves_words_containing_keywords(self, safe_word):
        result = _sanitize_description(f"{safe_word} layout: us")
        assert safe_word in result

    def test_clean_description_unchanged(self):
        desc = "Ubuntu server\nManaged by Ansible"
        assert _sanitize_description(desc) == desc


class TestPickPrimaryIpv4:
    @pytest.mark.parametrize("ips, expected", [
        ([{"address": "192.168.1.110", "prefix": 24}], ("192.168.1.110", 24)),
        ([], (None, None)),
        ([{"address": "127.0.0.1", "prefix": 8}], (None, None)),
        ([{"address": "", "prefix": 24}, {"address": "10.0.0.3", "prefix": 24}], ("10.0.0.3", 24)),
        ([{"address": "10.0.0.1", "prefix": None}, {"address": "10.0.0.2", "prefix": 24}], ("10.0.0.2", 24)),
    ])
    def test_selection(self, ips, expected):
        assert _pick_primary_ipv4(ips) == expected

    @pytest.mark.parametrize("skip_addr, valid_addr", [
        ("127.0.0.1", "192.168.1.50"),
        ("169.254.1.1", "10.0.0.5"),
        ("fe80::1", "192.168.1.200"),
    ])
    def test_skips_non_routable(self, skip_addr, valid_addr):
        ips = [{"address": skip_addr, "prefix": 24}, {"address": valid_addr, "prefix": 24}]
        assert _pick_primary_ipv4(ips)[0] == valid_addr
