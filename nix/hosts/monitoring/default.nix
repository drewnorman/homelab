{ config, lib, pkgs, allHosts, ... }:

let
  domain = "lab.adre.me";
  monitoredHosts = builtins.removeAttrs allHosts [ "arr" "qbittorrent" ];

  nodeStaticConfigs = lib.mapAttrsToList
    (name: host: {
      targets = [ "${host.ip}:9100" ];
      labels.host = name;
    })
    monitoredHosts;

  dashboardDir = pkgs.writeTextDir "homelab-node-overview.json" (builtins.toJSON {
    uid = "homelab-node-overview";
    title = "Homelab Node Overview";
    tags = [ "homelab" "nodes" ];
    timezone = "browser";
    refresh = "30s";
    schemaVersion = 39;
    version = 1;
    time = {
      from = "now-6h";
      to = "now";
    };
    templating.list = [
      {
        name = "instance";
        type = "query";
        datasource = { type = "prometheus"; uid = "prometheus"; };
        query = "label_values(up{job=\"node\"}, host)";
        refresh = 1;
        includeAll = true;
        current = {
          selected = true;
          text = "All";
          value = "$__all";
        };
      }
    ];
    panels = [
      {
        id = 1;
        type = "stat";
        title = "Hosts Up";
        datasource = { type = "prometheus"; uid = "prometheus"; };
        gridPos = { h = 4; w = 6; x = 0; y = 0; };
        targets = [{ expr = "sum(up{job=\"node\"})"; refId = "A"; }];
      }
      {
        id = 2;
        type = "stat";
        title = "Hosts Down";
        datasource = { type = "prometheus"; uid = "prometheus"; };
        gridPos = { h = 4; w = 6; x = 6; y = 0; };
        targets = [{ expr = "count(up{job=\"node\"}) - sum(up{job=\"node\"})"; refId = "A"; }];
      }
      {
        id = 3;
        type = "timeseries";
        title = "CPU Busy";
        datasource = { type = "prometheus"; uid = "prometheus"; };
        gridPos = { h = 8; w = 12; x = 0; y = 4; };
        targets = [{
          expr = "100 * (1 - avg by (host) (rate(node_cpu_seconds_total{job=\"node\",mode=\"idle\",host=~\"$instance\"}[5m])))";
          legendFormat = "{{host}}";
          refId = "A";
        }];
        fieldConfig.defaults.unit = "percent";
      }
      {
        id = 4;
        type = "timeseries";
        title = "Memory Used";
        datasource = { type = "prometheus"; uid = "prometheus"; };
        gridPos = { h = 8; w = 12; x = 12; y = 4; };
        targets = [{
          expr = "100 * (1 - (node_memory_MemAvailable_bytes{job=\"node\",host=~\"$instance\"} / node_memory_MemTotal_bytes{job=\"node\",host=~\"$instance\"}))";
          legendFormat = "{{host}}";
          refId = "A";
        }];
        fieldConfig.defaults.unit = "percent";
      }
      {
        id = 5;
        type = "timeseries";
        title = "Root Filesystem Used";
        datasource = { type = "prometheus"; uid = "prometheus"; };
        gridPos = { h = 8; w = 12; x = 0; y = 12; };
        targets = [{
          expr = "100 * (1 - (node_filesystem_avail_bytes{job=\"node\",mountpoint=\"/\",fstype!=\"rootfs\",host=~\"$instance\"} / node_filesystem_size_bytes{job=\"node\",mountpoint=\"/\",fstype!=\"rootfs\",host=~\"$instance\"}))";
          legendFormat = "{{host}}";
          refId = "A";
        }];
        fieldConfig.defaults.unit = "percent";
      }
      {
        id = 6;
        type = "timeseries";
        title = "Load Average";
        datasource = { type = "prometheus"; uid = "prometheus"; };
        gridPos = { h = 8; w = 12; x = 12; y = 12; };
        targets = [{
          expr = "node_load1{job=\"node\",host=~\"$instance\"}";
          legendFormat = "{{host}}";
          refId = "A";
        }];
      }
    ];
  });
in
{
  networking.firewall.allowedTCPPorts = [ 3000 9090 9093 ];

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 3000;
        domain = "grafana.${domain}";
        root_url = "https://grafana.${domain}";
      };
      users.allow_sign_up = false;
      analytics.reporting_enabled = false;
    };
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          uid = "prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://127.0.0.1:9090";
          isDefault = true;
        }
      ];
      dashboards.settings.providers = [
        {
          name = "Homelab";
          type = "file";
          disableDeletion = false;
          editable = true;
          options.path = dashboardDir;
        }
      ];
    };
  };

  services.prometheus = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 9090;
    globalConfig.scrape_interval = "30s";
    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [{ targets = [ "127.0.0.1:9090" ]; }];
      }
      {
        job_name = "node";
        static_configs = nodeStaticConfigs;
      }
    ];
    alertmanagers = [
      {
        scheme = "http";
        static_configs = [{ targets = [ "127.0.0.1:9093" ]; }];
      }
    ];
    rules = [
      ''
        groups:
          - name: homelab
            rules:
              - alert: NodeExporterDown
                expr: up{job="node"} == 0
                for: 5m
                labels:
                  severity: warning
                annotations:
                  summary: "Node exporter is down on {{ $labels.host }}"
              - alert: RootFilesystemNearlyFull
                expr: 100 * (1 - (node_filesystem_avail_bytes{job="node",mountpoint="/",fstype!="rootfs"} / node_filesystem_size_bytes{job="node",mountpoint="/",fstype!="rootfs"})) > 85
                for: 15m
                labels:
                  severity: warning
                annotations:
                  summary: "Root filesystem is over 85% used on {{ $labels.host }}"
              - alert: HighMemoryUsage
                expr: 100 * (1 - (node_memory_MemAvailable_bytes{job="node"} / node_memory_MemTotal_bytes{job="node"})) > 90
                for: 15m
                labels:
                  severity: warning
                annotations:
                  summary: "Memory usage is over 90% on {{ $labels.host }}"
      ''
    ];
    alertmanager = {
      enable = true;
      listenAddress = "0.0.0.0";
      port = 9093;
      configuration = {
        route = {
          receiver = "null";
          group_by = [ "alertname" "host" ];
        };
        receivers = [{ name = "null"; }];
      };
    };
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/grafana"
      "/var/lib/prometheus2"
      "/var/lib/prometheus-alertmanager"
    ];
  };
}
