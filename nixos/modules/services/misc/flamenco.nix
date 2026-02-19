{
  lib,
  config,
  pkgs,
  ...
}:
let
  managerCfg = config.services.flamenco.manager;
  workerCfg = config.services.flamenco.worker;

  mkCommonOptions = name: {
    enable = lib.mkEnableOption "Flamenco, production render farm ${name}";
    package = lib.mkPackageOption pkgs "flamenco" { };

    user = lib.mkOption {
      type = lib.types.str;
      default = "flamenco";
      description = "The user to run the ${name} as.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "flamenco";
      description = "The group to run the ${name} under.";
    };
  };

  mkServiceConfig = cfg: {
    User = cfg.user;
    Group = cfg.group;
    StateDirectoryMode = "0750";
    Restart = "on-failure";
    RestartSec = 5;
    CapabilityBoundingSet = "";
    NoNewPrivileges = true;
    PrivateUsers = true;
    ProcSubset = "pid";
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHome = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectSystem = "strict";
    RestrictAddressFamilies = [
      "AF_NETLINK"
      "AF_INET"
      "AF_INET6"
    ];
    RestrictSUIDSGID = true;
    RestrictRealtime = true;
    RestrictNamespaces = true;
    LockPersonality = true;
    RemoveIPC = true;
  };

  configFormat = pkgs.formats.yaml { };
  filterNulls = lib.attrsets.filterAttrsRecursive (_: value: value != null);
  managerConfigFile = configFormat.generate "flamenco-manager.yaml" (filterNulls managerCfg.config);
  workerConfigFile = configFormat.generate "flamenco-worker.yaml" (filterNulls workerCfg.config);
in
{
  options.services.flamenco = {
    manager = mkCommonOptions "manager" // {
      config = lib.mkOption {
        type = lib.types.submodule {
          freeformType = configFormat.type;
        };
        default = { };
        example = lib.options.literalExpression ''
          {
            listen = "127.0.0.1:8080";
            shaman.enabled = true;
          }
        '';
        description = ''
          Attribute set of configuration options.
          View the available options over at <https://flamenco.blender.org/usage/manager-configuration/>.
        '';
      };
    };

    worker = mkCommonOptions "worker" // {
      name = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = "The name of the worker. If not specified, the hostname will be used.";
      };

      config = lib.mkOption {
        type = lib.types.submodule {
          freeformType = configFormat.type;
          options = {
            manager_url = lib.mkOption {
              type = with lib.types; nullOr str;
              default = null;
              example = "http://127.0.0.1:8080/";
              description = "The URL of the manager to connect to.";
            };

            task_types = lib.mkOption {
              type = with lib.types; nullOr (listOf str);
              default = null;
              example = [
                "blender"
                "ffmpeg"
                "file-management"
                "misc"
              ];
              description = "The types of tasks this worker is allowed to run.";
            };

            oom_score_adjust = lib.mkOption {
              type = with lib.types; nullOr (ints.between 0 1000);
              default = null;
              description = ''
                Configures the Out Of Memory behaviour of the Linux Kernel.
                This is the `oom_score_adj` value for all sub-processes started by the worker.
                Set this to a high value, so that when the machine runs out of memory when rendering,
                it is Blender that gets killed, and not the worker itself.
              '';
            };
          };
        };
        default = { };
        example = lib.options.literalExpression ''
          {
            manager_url = "http://127.0.0.1:8080/";
          }
        '';
        description = ''
          Attribute set of configuration options.
          View the available options over at <https://flamenco.blender.org/usage/worker-configuration/>.
        '';
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf managerCfg.enable {
      services.flamenco.manager.config = {
        _meta.version = 3;
      };

      users = {
        users."${managerCfg.user}" = {
          isNormalUser = true;
          inherit (managerCfg) group;
        };
        groups."${managerCfg.group}" = { };
      };

      systemd.tmpfiles.rules = [
        "L+ /var/lib/flamenco-manager/flamenco-manager.yaml - - - - ${managerConfigFile}"
      ];

      systemd.services.flamenco-manager = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        restartTriggers = [ managerConfigFile ];

        serviceConfig = mkServiceConfig managerCfg // {
          ExecStart = lib.getExe' managerCfg.package "flamenco-manager";
          WorkingDirectory = "/var/lib/flamenco-manager";
          StateDirectory = "flamenco-manager";
        };
      };
    })

    (lib.mkIf workerCfg.enable {
      users = {
        users."${workerCfg.user}" = {
          isNormalUser = true;
          inherit (workerCfg) group;
        };
        groups."${workerCfg.group}" = { };
      };

      systemd.tmpfiles.rules = [
        "L+ /var/lib/flamenco-worker/flamenco-worker.yaml - - - - ${workerConfigFile}"
      ];

      systemd.services.flamenco-worker = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        restartTriggers = [ workerConfigFile ];

        serviceConfig = mkServiceConfig workerCfg // {
          ExecStart = lib.getExe' workerCfg.package "flamenco-worker";
          RestartForceExitStatus = 47;
          WorkingDirectory = "/var/lib/flamenco-worker";
          StateDirectory = "flamenco-worker";
        };

        environment = {
          FLAMENCO_HOME = "/var/lib/flamenco-worker";
          FLAMENCO_WORKER_NAME = workerCfg.name;
        };
      };
    })
  ];
}
