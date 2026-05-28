# Minimal NixOS image used only as the Proxmox clone template.
#
# The real homelab configuration is deployed afterward with deploy-rs. Keep
# this image boring: boot, cloud-init, SSH, and QEMU guest agent.
{ lib, modulesPath, ... }:
{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
  ];

  services.cloud-init = {
    enable = true;
    network.enable = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  services.qemuGuest.enable = true;

  users.users.root.openssh.authorizedKeys.keys = lib.mkDefault [];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.05";
}
