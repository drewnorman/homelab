{ config, lib, pkgs, ... }:

let
  cfg  = config.services.lldap;
  prov = cfg.provision;

  # Strip passwordFile before baking into the closure — it's a runtime path,
  # not something we want embedded in a world-readable Nix store path.
  usersForJson = map (u: removeAttrs u [ "passwordFile" ]) prov.users;

  desiredStateFile = pkgs.writeText "lldap-desired-state.json" (builtins.toJSON {
    users  = usersForJson;
    groups = prov.groups;
  });

  # Each user that has a passwordFile gets an entry in this env-var map so the
  # script can read them at runtime without hardcoding paths in the store.
  # Format: LLDAP_PASS_<USERNAME_UPPERCASED>=<path>
  passwordEnv = lib.listToAttrs (lib.concatMap (u:
    lib.optional (u.passwordFile != null) {
      name  = "LLDAP_PASS_${lib.toUpper (builtins.replaceStrings ["-"] ["_"] u.username)}";
      value = u.passwordFile;
    }
  ) prov.users);

  provisionScript = pkgs.writeTextFile {
    name = "lldap-provision";
    executable = true;
    destination = "/bin/lldap-provision";
    text = ''
      #!${pkgs.python3}/bin/python3
      import json
      import os
      import subprocess
      import sys
      import time
      import urllib.error
      import urllib.request


      LLDAP_URL = "http://127.0.0.1:${toString cfg.settings.http_port}"
      DESIRED = "${desiredStateFile}"
      ADMIN_PASSWORD_FILE = "${prov.adminPasswordFile}"
      SET_PASSWORD = "${pkgs.lldap}/bin/lldap_set_password"


      def request(path, payload=None, token=None):
          data = None
          headers = {}
          if payload is not None:
              data = json.dumps(payload).encode()
              headers["Content-Type"] = "application/json"
          if token is not None:
              headers["Authorization"] = f"Bearer {token}"

          req = urllib.request.Request(f"{LLDAP_URL}{path}", data=data, headers=headers)
          try:
              with urllib.request.urlopen(req, timeout=10) as response:
                  body = response.read()
          except urllib.error.HTTPError as err:
              body = err.read().decode(errors="replace")
              raise RuntimeError(f"lldap-provision: HTTP {err.code} from {path}: {body}") from err
          return json.loads(body.decode()) if body else {}


      def wait_for_lldap():
          for attempt in range(30):
              try:
                  urllib.request.urlopen(f"{LLDAP_URL}/health", timeout=2).close()
                  return
              except (urllib.error.URLError, TimeoutError):
                  if attempt == 29:
                      raise RuntimeError("lldap-provision: LLDAP not ready after 30 s")
                  time.sleep(1)


      def gql(token, query):
          response = request("/api/graphql", {"query": query}, token=token)
          errors = response.get("errors")
          if errors:
              raise RuntimeError(f"lldap-provision: GraphQL error: {errors}")
          return response.get("data", {})


      def quote(value):
          return json.dumps(value)


      def password_env_name(username):
          return f"LLDAP_PASS_{username.upper().replace('-', '_')}"


      def main():
          with open(DESIRED) as desired_file:
              desired = json.load(desired_file)

          wait_for_lldap()

          with open(ADMIN_PASSWORD_FILE) as password_file:
              admin_password = password_file.read().rstrip("\n")

          login = request(
              "/auth/simple/login",
              {"username": "admin", "password": admin_password},
          )
          token = login.get("token")
          if not token:
              raise RuntimeError("lldap-provision: auth failed")

          groups = {
              group["displayName"]: group["id"]
              for group in gql(token, "{ groups { id displayName } }").get("groups", [])
          }

          for group in desired.get("groups", []):
              name = group["name"]
              if name not in groups:
                  print(f"lldap-provision: creating group {name}")
                  created = gql(
                      token,
                      f"mutation {{ createGroup(name: {quote(name)}) {{ id displayName }} }}",
                  )["createGroup"]
                  groups[created["displayName"]] = created["id"]

          users = {
              user["id"]
              for user in gql(token, "{ users { id } }").get("users", [])
          }

          for user in desired.get("users", []):
              uid = user["username"]
              if uid not in users:
                  email = user["email"]
                  display_name = user.get("displayName") or uid
                  print(f"lldap-provision: creating user {uid}")
                  gql(
                      token,
                      "mutation { "
                      "createUser(user: { "
                      f"id: {quote(uid)}, "
                      f"email: {quote(email)}, "
                      f"displayName: {quote(display_name)} "
                      "}) { id } "
                      "}",
                  )
                  users.add(uid)

              pass_file = os.environ.get(password_env_name(uid))
              if pass_file and os.path.isfile(pass_file):
                  with open(pass_file) as password_file:
                      user_password = password_file.read().rstrip("\n")
                  print(f"lldap-provision: setting password for {uid}")
                  subprocess.run(
                      [
                          SET_PASSWORD,
                          "--base-url",
                          LLDAP_URL,
                          "--token",
                          token,
                          "--username",
                          uid,
                          "--password",
                          user_password,
                      ],
                      check=True,
                      stdout=subprocess.DEVNULL,
                  )

              for group_name in user.get("groups", []):
                  group_id = groups.get(group_name)
                  if group_id is None:
                      print(f"lldap-provision: unknown group {group_name} for {uid}", file=sys.stderr)
                      continue
                  try:
                      gql(
                          token,
                          "mutation { "
                          f"addUserToGroup(userId: {quote(uid)}, groupId: {group_id}) "
                          "}",
                      )
                  except Exception as err:
                      print(err, file=sys.stderr)

          print("lldap-provision: done")


      if __name__ == "__main__":
          main()
    '';
  };

in {
  options.services.lldap.provision = {
    enable = lib.mkEnableOption "declarative LLDAP user/group provisioning";

    adminPasswordFile = lib.mkOption {
      type        = lib.types.str;
      description = "Path to a file containing the LLDAP admin password.";
    };

    users = lib.mkOption {
      default     = [];
      description = ''
        Declarative LLDAP users. Users are created on first deploy; never
        deleted. Passwords are set/updated on every deploy when passwordFile
        is provided — the sops secret is always the source of truth.
      '';
      type = lib.types.listOf (lib.types.submodule {
        options = {
          username     = lib.mkOption { type = lib.types.str; };
          email        = lib.mkOption { type = lib.types.str; };
          displayName  = lib.mkOption { type = lib.types.str; default = ""; };
          groups       = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
          passwordFile = lib.mkOption {
            type        = lib.types.nullOr lib.types.str;
            default     = null;
            description = ''
              Path to a file containing this user's plaintext password
              (typically a sops secret). If set, the provisioner calls
              changeUserPassword on every run so the file is always authoritative.
              If null, the user is created without a password (login disabled
              until set manually in the LLDAP UI).
            '';
          };
        };
      });
    };

    groups = lib.mkOption {
      default     = [];
      description = "Declarative LLDAP groups. Groups are created; never deleted.";
      type        = lib.types.listOf (lib.types.submodule {
        options = {
          name        = lib.mkOption { type = lib.types.str; };
          displayName = lib.mkOption { type = lib.types.str; default = ""; };
        };
      });
    };
  };

  config = lib.mkIf (cfg.enable && prov.enable) {
    systemd.services.lldap-provision = {
      description = "Declarative LLDAP user/group provisioning";
      after       = [ "lldap.service" ];
      bindsTo     = [ "lldap.service" ];
      wantedBy    = [ "multi-user.target" ];
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
        ExecStart       = "${provisionScript}/bin/lldap-provision";
        # Inject password file paths as env vars so the script can read them
        # at runtime without any path appearing in the Nix store.
        Environment     = lib.mapAttrsToList (k: v: "${k}=${v}") passwordEnv;
      };
    };
  };
}
