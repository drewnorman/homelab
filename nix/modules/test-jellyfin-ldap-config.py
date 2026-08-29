#!/usr/bin/env python3

import importlib.util
import os
import stat
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


MODULE_PATH = Path(
    os.environ.get(
        "JELLYFIN_LDAP_CONFIG_MODULE",
        Path(__file__).with_name("jellyfin-ldap-config.py"),
    )
)
SPEC = importlib.util.spec_from_file_location("jellyfin_ldap_config", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class JellyfinLdapConfigTests(unittest.TestCase):
    def run_cli(self, directory):
        password_file = directory / "bind-password"
        password_file.write_text("new-secret\n", encoding="utf-8")
        return subprocess.run(
            [
                sys.executable,
                MODULE_PATH,
                "--config-file",
                directory / "LDAP-Auth.xml",
                "--bind-password-file",
                password_file,
                "--base-dn",
                "dc=lab,dc=adre,dc=me",
                "--password-reset-url",
                "https://users.lab.adre.me",
            ],
            check=False,
            capture_output=True,
            text=True,
        )

    def render(self, directory, existing=None, password="new-secret"):
        config_file = directory / "LDAP-Auth.xml"
        if existing is not None:
            config_file.write_text(existing, encoding="utf-8")
        password_file = directory / "bind-password"
        password_file.write_text(password + "\n", encoding="utf-8")

        ldap_users = MODULE.load_ldap_users(config_file)
        tree = MODULE.build_tree(
            ldap_users,
            password_file.read_text(encoding="utf-8").strip(),
            "dc=lab,dc=adre,dc=me",
            "https://users.lab.adre.me",
        )
        MODULE.atomic_write(tree, config_file)
        return config_file

    def test_preserves_mappings_and_replaces_managed_values(self):
        existing = """<?xml version="1.0"?>
<PluginConfiguration>
  <LdapUsers>
    <LdapUser><LinkedJellyfinUserId>drew-id</LinkedJellyfinUserId><LdapUid>drew</LdapUid><ProfileImageHash>hash</ProfileImageHash><FutureField>kept</FutureField></LdapUser>
    <LdapUser><LinkedJellyfinUserId>angela-id</LinkedJellyfinUserId><LdapUid>angela</LdapUid><ProfileImageHash /></LdapUser>
  </LdapUsers>
  <LdapServer>stale.example</LdapServer>
  <LdapBindPassword>old-secret</LdapBindPassword>
  <UnmanagedRootField>discarded</UnmanagedRootField>
</PluginConfiguration>
"""
        with tempfile.TemporaryDirectory() as temporary_directory:
            config_file = self.render(Path(temporary_directory), existing)
            root = ET.parse(config_file).getroot()

            self.assertEqual(
                [
                    user.findtext("LdapUid")
                    for user in root.findall("LdapUsers/LdapUser")
                ],
                ["drew", "angela"],
            )
            self.assertEqual(
                root.findtext("LdapUsers/LdapUser/FutureField"), "kept"
            )
            self.assertEqual(root.findtext("LdapServer"), "127.0.0.1")
            self.assertEqual(root.findtext("LdapBindPassword"), "new-secret")
            self.assertIsNone(root.find("UnmanagedRootField"))
            self.assertIsNotNone(root.find("EnabledFolders"))
            self.assertEqual(stat.S_IMODE(config_file.stat().st_mode), 0o600)

    def test_first_boot_and_repeated_execution_are_idempotent(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            config_file = self.render(directory)
            first_render = config_file.read_bytes()
            self.assertEqual(
                len(ET.parse(config_file).getroot().findall("LdapUsers")), 1
            )
            self.assertEqual(
                len(ET.parse(config_file).getroot().findall("LdapUsers/LdapUser")), 0
            )

            self.render(directory)
            self.assertEqual(config_file.read_bytes(), first_render)

    def test_malformed_xml_is_rejected_without_modification(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            config_file = Path(temporary_directory) / "LDAP-Auth.xml"
            malformed = b"<PluginConfiguration><LdapUsers>"
            config_file.write_bytes(malformed)

            result = self.run_cli(Path(temporary_directory))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("jellyfin-ldap-config:", result.stderr)
            self.assertEqual(config_file.read_bytes(), malformed)

    def test_duplicate_ldap_users_are_rejected_without_modification(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            config_file = Path(temporary_directory) / "LDAP-Auth.xml"
            duplicate = (
                b"<PluginConfiguration><LdapUsers/><LdapUsers/>"
                b"</PluginConfiguration>"
            )
            config_file.write_bytes(duplicate)

            result = self.run_cli(Path(temporary_directory))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("multiple LdapUsers", result.stderr)
            self.assertEqual(config_file.read_bytes(), duplicate)


if __name__ == "__main__":
    unittest.main()
