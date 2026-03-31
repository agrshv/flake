{ ... }:

{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 30;
        modules-left = [ "sway/workspaces" "sway/mode" ];
        modules-center = [ "sway/window" ];
        modules-right = [ "pulseaudio" "cpu" "memory" "battery" "clock" "tray" ];

        "sway/workspaces" = {
          disable-scroll = true;
          all-outputs = true;
        };

        clock = {
          format = "{:%H:%M}";
          format-alt = "{:%Y-%m-%d}";
          tooltip-format = "{:%Y-%m-%d | %H:%M}";
        };

        cpu = {
          format = "{usage}% 󰻠";
          tooltip = false;
        };

        memory = {
          format = "{}% 󰍛";
        };

        battery = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{capacity}% {icon}";
          format-full = "";
          format-icons = {
            default = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
            charging = [ "󰢜" "󰂆" "󰂇" "󰂈" "󰢝" "󰂉" "󰢞" "󰂊" "󰂋" "󰂅" ];
          };
        };

        pulseaudio = {
          format = "{volume}% {icon}";
          format-muted = "󰝟";
          format-icons = {
            default = [ "󰖁" "󰕿" "󰖀" "󰕾" ];
          };
          on-click = "pavucontrol";
        };

        tray = {
          spacing = 10;
        };
      };
    };
    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font", "Font Awesome 6 Free";
        font-size: 13px;
        min-height: 0;
      }

      window#waybar {
        background: @base;
        color: @text;
        border-bottom: 2px solid @surface0;
      }

      #workspaces button {
        padding: 0 8px;
        color: @text;
        background: transparent;
        border-radius: 0;
      }

      #workspaces button:hover {
        background: @surface0;
      }

      #workspaces button.focused {
        background: @mauve;
        color: @crust;
      }

      #workspaces button.urgent {
        background: @red;
        color: @crust;
      }

      #clock,
      #battery,
      #cpu,
      #memory,
      #network,
      #pulseaudio,
      #tray,
      #mode {
        padding: 0 10px;
        margin: 4px 2px;
        background: @surface0;
        border-radius: 4px;
      }

      #battery.charging {
        color: @green;
      }

      #battery.warning:not(.charging) {
        color: @yellow;
      }

      #battery.critical:not(.charging) {
        background: @red;
        color: @crust;
      }

      #network.disconnected {
        color: @red;
      }

      #pulseaudio.muted {
        color: @overlay0;
      }
    '';
  };
}
