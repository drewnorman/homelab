#!/usr/bin/env python3

import argparse
import copy
import os
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT_ATTRIBUTES = {
    "xmlns:xsi": "http://www.w3.org/2001/XMLSchema-instance",
    "xmlns:xsd": "http://www.w3.org/2001/XMLSchema",
}


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Render Jellyfin LDAP configuration while preserving "
            "user mappings."
        )
    )
    parser.add_argument("--config-file", required=True, type=Path)
    parser.add_argument("--bind-password-file", required=True, type=Path)
    parser.add_argument("--base-dn", required=True)
    parser.add_argument("--password-reset-url", required=True)
    return parser.parse_args()


def load_ldap_users(config_file):
    if not config_file.exists():
        return ET.Element("LdapUsers")

    existing_root = ET.parse(config_file).getroot()
    if existing_root.tag != "PluginConfiguration":
        raise ValueError(
            f"unexpected root element in {config_file}: {existing_root.tag}"
        )

    ldap_users = existing_root.findall("LdapUsers")
    if len(ldap_users) > 1:
        raise ValueError(f"multiple LdapUsers elements found in {config_file}")
    if not ldap_users:
        return ET.Element("LdapUsers")
    return copy.deepcopy(ldap_users[0])


def build_tree(ldap_users, bind_password, base_dn, password_reset_url):
    values = {
        "LdapServer": "127.0.0.1",
        "LdapPort": "3890",
        "AllowPassChange": "false",
        "UseSsl": "false",
        "UseStartTls": "false",
        "SkipSslVerify": "false",
        "LdapBindUser": f"uid=admin,ou=people,{base_dn}",
        "LdapBindPassword": bind_password,
        "LdapBaseDn": base_dn,
        "LdapSearchFilter": (
            f"(&(objectClass=person)(memberOf=cn=media,ou=groups,{base_dn}))"
        ),
        "LdapAdminBaseDn": base_dn,
        "LdapAdminFilter": (
            "(&(objectClass=person)"
            f"(memberOf=cn=homelab_admins,ou=groups,{base_dn}))"
        ),
        "EnableLdapAdminFilterMemberUid": "false",
        "LdapSearchAttributes": "uid,mail,displayName,cn",
        "LdapClientCertPath": "",
        "LdapClientKeyPath": "",
        "LdapRootCaPath": "",
        "CreateUsersFromLdap": "true",
        "LdapUidAttribute": "uid",
        "LdapUsernameAttribute": "uid",
        "LdapPasswordAttribute": "userPassword",
        "EnableLdapProfileImageSync": "false",
        "RemoveImagesNotInLdap": "false",
        "LdapProfileImageAttribute": "jpegphoto",
        "LdapProfileImageFormat": "Default",
        "EnableAllFolders": "true",
        "PasswordResetUrl": password_reset_url,
    }

    root = ET.Element("PluginConfiguration", ROOT_ATTRIBUTES)
    root.append(ldap_users)
    for key, value in values.items():
        child = ET.SubElement(root, key)
        child.text = value
    ET.SubElement(root, "EnabledFolders")

    tree = ET.ElementTree(root)
    ET.indent(tree, space="  ")
    return tree


def atomic_write(tree, config_file):
    config_file.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=config_file.parent, prefix=f".{config_file.name}.", suffix=".tmp"
    )
    os.close(descriptor)
    temporary_path = Path(temporary_name)
    try:
        tree.write(temporary_path, encoding="utf-8", xml_declaration=True)
        os.chmod(temporary_path, 0o600)
        os.replace(temporary_path, config_file)
    finally:
        temporary_path.unlink(missing_ok=True)


def main():
    args = parse_args()
    try:
        ldap_users = load_ldap_users(args.config_file)
        bind_password = args.bind_password_file.read_text(
            encoding="utf-8"
        ).strip()
        tree = build_tree(
            ldap_users, bind_password, args.base_dn, args.password_reset_url
        )
        atomic_write(tree, args.config_file)
    except (OSError, ET.ParseError, ValueError) as error:
        print(f"jellyfin-ldap-config: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
