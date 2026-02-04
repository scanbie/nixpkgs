{ lib, ... }:
{
  name = "flamenco-worker";
  meta.maintainers = with lib.maintainers; [ bddvlpr ];

  nodes = {
    manager =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.jq ];

        services.flamenco.manager = {
          enable = true;
          config.shared_storage_path = "/srv/flamenco";
        };

        networking.firewall.allowedTCPPorts = [ 8080 ];
      };

    worker = {
      services.flamenco.worker = {
        enable = true;
        config.manager_url = "http://manager:8080/";
      };
    };
  };

  testScript = ''
    manager.wait_for_unit("flamenco-manager.service")
    manager.wait_for_open_port(8080)

    worker.wait_for_unit("flamenco-worker.service")
    worker.wait_for_console_text("manager accepted sign-on")

    manager.succeed("curl --fail http://localhost:8080/api/v3/worker-mgt/workers | jq -e '.workers[] | select(.name == \"worker\")'")
  '';
}
