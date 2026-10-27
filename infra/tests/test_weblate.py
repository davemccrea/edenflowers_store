"""Validate Weblate's rendered network configuration without production secrets."""

import ipaddress
import json
from pathlib import Path
import unittest

from jinja2 import Environment, StrictUndefined
import yaml


INFRA = Path(__file__).parents[1]


class WeblateNetworkTest(unittest.TestCase):
    def test_dynamic_addresses_cannot_claim_the_tunnel_address(self):
        variables = yaml.safe_load((INFRA / "group_vars/all/vars.yml").read_text())
        variables.update(
            weblate_db_password="dummy-database-password",
            weblate_smtp_user="dummy-smtp-user",
            weblate_smtp_password="dummy-smtp-password",
            weblate_cloudflare_tunnel_token="dummy-tunnel-token",
            weblate_admin_email="admin@example.com",
        )
        environment = Environment(undefined=StrictUndefined)
        environment.filters["to_json"] = json.dumps
        template = INFRA / "roles/common/templates/weblate-compose.yml.j2"
        compose = yaml.safe_load(environment.from_string(template.read_text()).render(variables))
        services = compose["services"]
        network = compose["networks"]["default"]["ipam"]["config"][0]
        subnet = ipaddress.ip_network(network["subnet"])
        dynamic_range = ipaddress.ip_network(network.get("ip_range", network["subnet"]))
        tunnel = ipaddress.ip_address(
            services["cloudflared"]["networks"]["default"]["ipv4_address"]
        )
        self.assertTrue(dynamic_range.subnet_of(subnet))
        self.assertIn(tunnel, subnet)
        self.assertNotIn(tunnel, dynamic_range)
        self.assertEqual(
            services["weblate"]["environment"]["WEBLATE_TRUSTED_PROXY_ADDRESSES"], str(tunnel)
        )
        self.assertTrue(all(not service.get("ports") for service in services.values()))
