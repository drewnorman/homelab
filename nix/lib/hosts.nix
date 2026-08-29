# Central host registry.
{
  core = {
    hostname         = "lab-core";
    ip               = "192.168.1.210";
    sshHost          = "192.168.1.210";
    tailscaleSshHost = "lab-core-ts";
    networkInterface = "ens18";
    bootDevice       = "/dev/vda";
    rootDevice       = "/dev/disk/by-label/nixos";
    rootFsType       = "ext4";
  };
}
