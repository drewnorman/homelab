# Caddy built with the caddy-dns/cloudflare plugin for DNS-01 ACME challenges.
# Required by the edge host to issue wildcard certs via Cloudflare's API.
#
# If the hash needs to be updated after a nixpkgs bump:
#   nix build .#packages.x86_64-linux.caddy-cloudflare 2>&1 | grep "got:"
# then replace the hash below with the output value.
final: prev: {
  caddy-cloudflare = prev.caddy.withPlugins {
    plugins = [ "github.com/caddy-dns/cloudflare@v0.2.1" ];
    hash    = "sha256-48Xq2tb8ruAl87IJNWlIQa6bLISmNic0LuMNAJO7/n0=";
  };
}
