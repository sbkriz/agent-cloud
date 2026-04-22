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


class TestInt:
    def test_int_passthrough(self):
        assert _int(42) == 42

    def test_string_to_int(self):
        assert _int("2048") == 2048

    def test_none_returns_default(self):
        assert _int(None) == 0

    def test_empty_string_returns_default(self):
        assert _int("") == 0

    def test_float_string_returns_default(self):
        assert _int("3.5") == 0

    def test_custom_default(self):
        assert _int(None, 99) == 99

    def test_negative(self):
        assert _int(-5) == -5

    def test_large_int(self):
        assert _int(2147483648) == 2147483648

    def test_string_large_int(self):
        assert _int("2147483648") == 2147483648


class TestMbToGb:
    def test_1024_mb(self):
        assert _mb_to_gb(1024) == 1.0

    def test_2048_mb(self):
        assert _mb_to_gb(2048) == 2.0

    def test_zero(self):
        assert _mb_to_gb(0) == 0.0

    def test_string_input(self):
        assert _mb_to_gb("4096") == 4.0


class TestBytesToGb:
    def test_1gb(self):
        assert _bytes_to_gb(1073741824) == 1.0

    def test_2gb(self):
        assert _bytes_to_gb(2147483648) == 2.0

    def test_zero(self):
        assert _bytes_to_gb(0) == 0.0


class TestShouldSkipIface:
    def test_loopback(self):
        assert _should_skip_iface("lo") is True

    def test_firewall_bridge(self):
        assert _should_skip_iface("fwbr100") is True

    def test_tap_device(self):
        assert _should_skip_iface("tap100i0") is True

    def test_veth(self):
        assert _should_skip_iface("veth100") is True

    def test_fwln(self):
        assert _should_skip_iface("fwln100") is True

    def test_fwpr(self):
        assert _should_skip_iface("fwpr100") is True

    def test_empty(self):
        assert _should_skip_iface("") is True

    def test_none(self):
        assert _should_skip_iface(None) is True

    def test_eth0(self):
        assert _should_skip_iface("eth0") is False

    def test_vmbr0(self):
        assert _should_skip_iface("vmbr0") is False

    def test_bond0(self):
        assert _should_skip_iface("bond0") is False

    def test_ens18(self):
        assert _should_skip_iface("ens18") is False


class TestIfaceType:
    def test_bridge(self):
        assert _iface_type("vmbr0") == "bridge"

    def test_bond(self):
        assert _iface_type("bond0") == "lag"

    def test_vlan(self):
        assert _iface_type("vlan100") == "virtual"

    def test_dot_vlan(self):
        assert _iface_type(".100") == "virtual"

    def test_wireguard(self):
        assert _iface_type("wg0") == "virtual"

    def test_eth(self):
        assert _iface_type("eth0") == "other"

    def test_ens(self):
        assert _iface_type("ens18") == "other"

    def test_unknown(self):
        assert _iface_type("xyz0") == "other"


class TestPrefixLen:
    def test_cidr24(self):
        assert _prefix_len("10.0.0.1/24") == 24

    def test_cidr16(self):
        assert _prefix_len("172.16.0.0/16") == 16

    def test_cidr32(self):
        assert _prefix_len("10.0.0.1/32") == 32

    def test_no_slash(self):
        assert _prefix_len("10.0.0.1") is None

    def test_empty(self):
        assert _prefix_len("") is None

    def test_none(self):
        assert _prefix_len(None) is None

    def test_invalid_prefix(self):
        assert _prefix_len("10.0.0.1/abc") is None

    def test_just_slash(self):
        assert _prefix_len("/") is None


class TestSanitizeDescription:
    def test_clean_description(self):
        desc = "Ubuntu server\nManaged by Ansible"
        assert _sanitize_description(desc) == desc

    def test_strips_password_line(self):
        result = _sanitize_description("root password: abc\nNormal line")
        assert "password" not in (result or "").lower()
        assert "Normal line" in result

    def test_strips_token_line(self):
        result = _sanitize_description("API token: xyz\nNormal line")
        assert "token" not in (result or "").lower()

    def test_strips_secret_line(self):
        result = _sanitize_description("secret: shhh\nNormal line")
        assert "secret" not in (result or "").lower()

    def test_fully_redacted_returns_none(self):
        assert _sanitize_description("password=abc\nsecret_key=xyz") is None

    def test_empty_string_returns_none(self):
        assert _sanitize_description("") is None

    def test_none_returns_none(self):
        assert _sanitize_description(None) is None

    def test_case_insensitive(self):
        result = _sanitize_description("PASSWORD: foo\nNormal")
        assert result == "Normal"

    def test_keyboard_survives(self):
        result = _sanitize_description("keyboard layout: us")
        assert "keyboard" in result

    def test_monkey_survives(self):
        result = _sanitize_description("monkey business")
        assert "monkey" in result

    def test_turkey_survives(self):
        result = _sanitize_description("turkey sandwich")
        assert "turkey" in result

    def test_compound_secret_key(self):
        result = _sanitize_description("secret_key=abc\nNormal")
        assert result == "Normal"

    def test_compound_api_token(self):
        result = _sanitize_description("api_token=xyz\nNormal")
        assert result == "Normal"

    def test_compound_root_password(self):
        result = _sanitize_description("root_password=hunter2\nNormal")
        assert result == "Normal"


class TestPickPrimaryIpv4:
    def test_basic_selection(self):
        ips = [{"address": "192.168.1.110", "prefix": 24}]
        assert _pick_primary_ipv4(ips) == ("192.168.1.110", 24)

    def test_skips_loopback(self):
        ips = [
            {"address": "127.0.0.1", "prefix": 8},
            {"address": "192.168.1.50", "prefix": 24},
        ]
        assert _pick_primary_ipv4(ips) == ("192.168.1.50", 24)

    def test_skips_link_local(self):
        ips = [
            {"address": "169.254.1.1", "prefix": 16},
            {"address": "10.0.0.5", "prefix": 24},
        ]
        assert _pick_primary_ipv4(ips) == ("10.0.0.5", 24)

    def test_skips_ipv6(self):
        ips = [
            {"address": "fe80::1", "prefix": 64},
            {"address": "192.168.1.200", "prefix": 24},
        ]
        assert _pick_primary_ipv4(ips) == ("192.168.1.200", 24)

    def test_empty_list(self):
        assert _pick_primary_ipv4([]) == (None, None)

    def test_only_loopback(self):
        assert _pick_primary_ipv4([{"address": "127.0.0.1", "prefix": 8}]) == (None, None)

    def test_missing_prefix(self):
        ips = [
            {"address": "10.0.0.1", "prefix": None},
            {"address": "10.0.0.2", "prefix": 24},
        ]
        assert _pick_primary_ipv4(ips) == ("10.0.0.2", 24)

    def test_missing_address(self):
        ips = [{"address": "", "prefix": 24}, {"address": "10.0.0.3", "prefix": 24}]
        assert _pick_primary_ipv4(ips) == ("10.0.0.3", 24)
