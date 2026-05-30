# Central host registry. IPs must match the OpenTofu lab-core VM settings.
{
  core = {
    hostname         = "lab-core";
    ip               = "192.168.1.210";
    tailscaleIp      = "100.78.23.58";
    networkInterface = "ens18";
    bootDevice       = "/dev/vda";
    rootDevice       = "/dev/disk/by-label/nixos";
    rootFsType       = "ext4";
  };
}
