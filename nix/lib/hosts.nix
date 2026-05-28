# Central host registry. IPs must match terraform/variables.tf service_ips defaults.
{
  core = {
    hostname         = "lab-core";
    ip               = "192.168.1.210";
    networkInterface = "ens18";
    bootDevice       = "/dev/vda";
    rootDevice       = "/dev/disk/by-label/nixos";
    rootFsType       = "ext4";
  };
  adguard = {
    hostname = "lab-adguard";
    ip       = "192.168.1.210";
  };
  edge = {
    hostname = "lab-edge";
    ip       = "192.168.1.211";
  };
  monitoring = {
    hostname = "lab-monitoring";
    ip       = "192.168.1.212";
  };
  authelia = {
    hostname = "lab-authelia";
    ip       = "192.168.1.213";
  };
  lldap = {
    hostname = "lab-lldap";
    ip       = "192.168.1.214";
  };
  jellyfin = {
    hostname = "lab-jellyfin";
    ip       = "192.168.1.230";
  };
  arr = {
    hostname = "lab-arr";
    ip       = "192.168.1.232";
  };
  qbittorrent = {
    hostname = "lab-qbittorrent";
    ip       = "192.168.1.233";
  };
}
