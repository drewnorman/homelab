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

  provisionScript = pkgs.writeShellApplication {
    name = "lldap-provision";
    runtimeInputs = [ pkgs.curl pkgs.jq ];
    text = ''
      LLDAP_URL="http://127.0.0.1:${toString cfg.settings.http_port}"
      DESIRED=${desiredStateFile}

      # Wait up to 30 s for LLDAP to become ready
      for i in $(seq 1 30); do
        curl -sf "$LLDAP_URL/health" > /dev/null 2>&1 && break
        [ "$i" -eq 30 ] && { echo "lldap-provision: LLDAP not ready after 30 s"; exit 1; }
        sleep 1
      done

      ADMIN_PASS=$(cat "${prov.adminPasswordFile}")

      TOKEN=$(curl -sf -X POST "$LLDAP_URL/auth/simple/login" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASS\"}" \
        | jq -r '.token')
      [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ] && { echo "lldap-provision: auth failed"; exit 1; }

      gql() {
        curl -sf -X POST "$LLDAP_URL/api/graphql" \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -d "{\"query\": $(printf '%s' "$1" | jq -Rs .)}"
      }

      # ---- groups -------------------------------------------------------
      declare -A GROUP_IDS
      while IFS=$'\t' read -r gid gname; do
        GROUP_IDS["$gname"]="$gid"
      done < <(gql "{ listGroups { id displayName } }" \
        | jq -r '.data.listGroups[] | [(.id | tostring), .displayName] | @tsv')

      while IFS= read -r grp; do
        name=$(printf '%s' "$grp" | jq -r '.name')
        if [ -z "''${GROUP_IDS[$name]:-}" ]; then
          echo "lldap-provision: creating group $name"
          result=$(gql "mutation { createGroup(name: $(printf '%s' "$name" | jq -Rs .)) { id displayName } }" \
            | jq -r '.data.createGroup | [(.id | tostring), .displayName] | @tsv')
          IFS=$'\t' read -r gid _ <<< "$result"
          GROUP_IDS["$name"]="$gid"
        fi
      done < <(jq -c '.groups[]' "$DESIRED")

      # ---- users --------------------------------------------------------
      declare -A EXISTING_USERS
      while IFS= read -r uid; do
        EXISTING_USERS["$uid"]=1
      done < <(gql "{ listUsers { id } }" | jq -r '.data.listUsers[].id')

      while IFS= read -r usr; do
        uid=$(printf '%s' "$usr" | jq -r '.username')
        email=$(printf '%s' "$usr" | jq -r '.email')
        dn=$(printf '%s' "$usr" | jq -r '.displayName // .username')

        if [ -z "''${EXISTING_USERS[$uid]:-}" ]; then
          echo "lldap-provision: creating user $uid"
          gql "mutation {
            createUser(user: {
              id:          $(printf '%s' "$uid"   | jq -Rs .),
              email:       $(printf '%s' "$email" | jq -Rs .),
              displayName: $(printf '%s' "$dn"    | jq -Rs .)
            }) { id }
          }" > /dev/null
          EXISTING_USERS["$uid"]=1
        fi

        # Set/update password if a password file env var is present for this user.
        # The env var name is LLDAP_PASS_<USERNAME_UPPERCASED> and is injected by
        # the systemd service's EnvironmentFiles — the value is the file path.
        pass_var="LLDAP_PASS_''${uid^^}"
        pass_var="''${pass_var//-/_}"          # replace hyphens with underscores
        pass_file="''${!pass_var:-}"
        if [ -n "$pass_file" ] && [ -f "$pass_file" ]; then
          user_pass=$(cat "$pass_file")
          echo "lldap-provision: setting password for $uid"
          gql "mutation {
            changeUserPassword(
              userId:   $(printf '%s' "$uid"       | jq -Rs .),
              password: $(printf '%s' "$user_pass" | jq -Rs .)
            )
          }" > /dev/null
        fi

        # Reconcile group memberships (add only — removal is manual)
        while IFS= read -r grp; do
          gid="''${GROUP_IDS[$grp]:-}"
          [ -z "$gid" ] && { echo "lldap-provision: unknown group $grp for $uid"; continue; }
          gql "mutation {
            addUserToGroup(userId: $(printf '%s' "$uid" | jq -Rs .), groupId: $gid)
          }" > /dev/null || true
        done < <(printf '%s' "$usr" | jq -r '.groups[]')

      done < <(jq -c '.users[]' "$DESIRED")

      echo "lldap-provision: done"
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
        User            = "lldap";
        Group           = "lldap";
        # Inject password file paths as env vars so the script can read them
        # at runtime without any path appearing in the Nix store.
        Environment     = lib.mapAttrsToList (k: v: "${k}=${v}") passwordEnv;
      };
    };
  };
}
