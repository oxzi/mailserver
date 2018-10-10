#  nixos-mailserver: a simple mail server
#  Copyright (C) 2016-2018  Robin Raymond
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program. If not, see <http://www.gnu.org/licenses/>

{ config, pkgs, lib, ... }:

let
  cfg = config.mailserver;

  postfixCfg  = config.services.postfix;
  dovecot2Cfg = config.services.dovecot2;
  rspamdCfg   = config.services.rspamd;
in
{
  config = with cfg; lib.mkIf enable {
    # rmilter is enabled if rspamd is enabled. However, rmilter is deprecated
    # https://github.com/NixOS/nixpkgs/issues/48011
    services.rmilter.enable = false;

    services.rspamd = {
      enable = true;
      extraConfig = ''
        extended_spam_headers = yes;
      '';

      workers.rspamd_proxy = {
        # The pipe_bin-scripts are not executed as the vmailUser and I havn't
        # figured out how to change this. That's why the mode is 666.
        bindSockets = [{
          socket = "/run/rspamd.sock";
          mode = "0666";
          group = rspamdCfg.group;
        }];

        type = "proxy";
        count = 4;  # Spawn more processes in self-scan mode
        extraConfig = ''
          milter = yes; # Enable milter mode
          timeout = 120s; # Needed for Milter usually

          upstream "local" {
            default = yes; # Self-scan upstreams are always default
            self_scan = yes; # Enable self-scan
          }

          max_retries = 5; # How many times master is queried in case of failure
          discard_on_reject = false; # Discard message instead of rejection
          quarantine_on_reject = false; # Tell MTA to quarantine rejected messages
          spam_header = "X-Spam"; # Use the specific spam header
        '';
      };
    };

    systemd.services.postfix = {
      after    = [ "rspamd.service" ];
      requires = [ "rspamd.service" ];
    };

    users.extraUsers.${postfixCfg.user}.extraGroups = [ rspamdCfg.group ];
    users.extraUsers.${dovecot2Cfg.mailUser}.extraGroups = [ rspamdCfg.group ];
  };
}
