
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

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.mailserver;
in
{
  options.mailserver = {
    enable = mkEnableOption "nixos-mailserver";

    fqdn = mkOption {
      type = types.str;
      example = "mx.example.com";
      description = "The fully qualified domain name of the mail server.";
    };

    domains = mkOption {
      type = types.listOf types.str;
      example = [ "example.com" ];
      default = [];
      description = "The domains that this mail server serves.";
    };

    messageSizeLimit = mkOption {
      type = types.int;
      example = 52428800;
      default = 20971520;
      description = "Message size limit enforced by Postfix.";
    };

    loginAccounts = mkOption {
      type = types.loaOf (types.submodule ({ name, ... }: {
        options = {
          name = mkOption {
            type = types.str;
            example = "user1@example.com";
            description = "Username";
          };

          hashedPassword = mkOption {
            type = types.str;
            example = "$6$evQJs5CFQyPAW09S$Cn99Y8.QjZ2IBnSu4qf1vBxDRWkaIZWOtmu1Ddsm3.H3CFpeVc0JU4llIq8HQXgeatvYhh5O33eWG3TSpjzu6/";
            description = ''
              Hashed password. Use `mkpasswd` as follows

              ```
              mkpasswd -m sha-512 "super secret password"
              ```
            '';
          };

          aliases = mkOption {
            type = with types; listOf types.str;
            example = ["abuse@example.com" "postmaster@example.com"];
            default = [];
            description = ''
              A list of aliases of this login account.
              Note: Use list entries like "@example.com" to create a catchAll
              that allows sending from all email addresses in these domain.
            '';
          };

          catchAll = mkOption {
            type = with types; listOf (enum cfg.domains);
            example = ["example.com" "example2.com"];
            default = [];
            description = ''
              For which domains should this account act as a catch all?
              Note: Does not allow sending from all addresses of these domains.
            '';
          };

          quota = mkOption {
            type = with types; nullOr types.str;
            default = null;
            example = "2G";
            description = ''
              Per user quota rules. Accepted sizes are `xx k/M/G/T` with the
              obvious meaning. Leave blank for the standard quota `100G`.
            '';
          };

          sieveScript = mkOption {
            type = with types; nullOr lines;
            default = null;
            example = ''
              require ["fileinto", "mailbox"];

              if address :is "from" "gitlab@mg.gitlab.com" {
                fileinto :create "GitLab";
                stop;
              }

              # This must be the last rule, it will check if list-id is set, and
              # file the message into the Lists folder for further investigation
              elsif header :matches "list-id" "<?*>" {
                fileinto :create "Lists";
                stop;
              }
            '';
            description = ''
              Per-user sieve script.
            '';
          };
        };

        config.name = mkDefault name;
      }));
      example = {
        user1 = {
          hashedPassword = "$6$evQJs5CFQyPAW09S$Cn99Y8.QjZ2IBnSu4qf1vBxDRWkaIZWOtmu1Ddsm3.H3CFpeVc0JU4llIq8HQXgeatvYhh5O33eWG3TSpjzu6/";
        };
        user2 = {
          hashedPassword = "$6$oE0ZNv2n7Vk9gOf$9xcZWCCLGdMflIfuA0vR1Q1Xblw6RZqPrP94mEit2/81/7AKj2bqUai5yPyWE.QYPyv6wLMHZvjw3Rlg7yTCD/";
        };
      };
      description = ''
        The login account of the domain. Every account is mapped to a unix user,
        e.g. `user1@example.com`. To generate the passwords use `mkpasswd` as
        follows

        ```
        mkpasswd -m sha-512 "super secret password"
        ```
      '';
      default = {};
    };

    extraVirtualAliases = mkOption {
      type = types.loaOf (mkOptionType {
        name = "Login Account";
        check = (ele:
          let accounts = builtins.attrNames cfg.loginAccounts;
          in if (builtins.isList ele)
            then (builtins.all (x: builtins.elem x accounts) ele) && (builtins.length ele > 0)
            else (builtins.elem ele accounts));
      });
      example = {
        "info@example.com" = "user1@example.com";
        "postmaster@example.com" = "user1@example.com";
        "abuse@example.com" = "user1@example.com";
        "multi@example.com" = [ "user1@example.com" "user2@example.com" ];
      };
      description = ''
        Virtual Aliases. A virtual alias `"info@example.com" = "user1@example.com"` means that
        all mail to `info@example.com` is forwarded to `user1@example.com`. Note
        that it is expected that `postmaster@example.com` and `abuse@example.com` is
        forwarded to some valid email address. (Alternatively you can create login
        accounts for `postmaster` and (or) `abuse`). Furthermore, it also allows
        the user `user1@example.com` to send emails as `info@example.com`.
        It's also possible to create an alias for multiple accounts. In this
        example all mails for `multi@example.com` will be forwarded to both
        `user1@example.com` and `user2@example.com`.
      '';
      default = {};
    };

    rejectSender = mkOption {
      type = types.listOf types.str;
      example = [ "@example.com" "spammer@example.net" ];
      description = ''
        Reject emails from these addresses from unauthorized senders.
        Use if a spammer is using the same domain or the same sender over and over.
      '';
      default = [];
    };

    rejectRecipients = mkOption {
      type = types.listOf types.str;
      example = [ "sales@example.com" "info@example.com" ];
      description = ''
        Reject emails addressed to these local addresses from unauthorized senders.
        Use if a spammer has found email addresses in a catchall domain but you do
        not want to disable the catchall.
      '';
      default = [];
    };

    vmailUID = mkOption {
      type = types.int;
      default = 5000;
      description = ''
        The unix UID of the virtual mail user.  Be mindful that if this is
        changed, you will need to manually adjust the permissions of
        mailDirectory.
      '';
    };

    vmailUserName = mkOption {
      type = types.str;
      default = "virtualMail";
      description = ''
        The user name and group name of the user that owns the directory where all
        the mail is stored.
      '';
    };

    vmailGroupName = mkOption {
      type = types.str;
      default = "virtualMail";
      description = ''
        The user name and group name of the user that owns the directory where all
        the mail is stored.
      '';
    };

    mailDirectory = mkOption {
      type = types.path;
      default = "/var/vmail";
      description = ''
        Where to store the mail.
      '';
    };

    useFsLayout = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Sets whether dovecot should organize mail in subdirectories:

        - /var/vmail/example.com/user/.folder.subfolder/ (default layout)
        - /var/vmail/example.com/user/folder/subfolder/  (FS layout)

        See https://wiki2.dovecot.org/MailboxFormat/Maildir for details.
      '';
    };

    hierarchySeparator = mkOption {
      type = types.string;
      default = ".";
      description = ''
        The hierarchy separator for mailboxes used by dovecot for the namespace 'inbox'.
        Dovecot defaults to "." but recommends "/".
        This affects how mailboxes appear to mail clients and sieve scripts.
        For instance when using "." then in a sieve script "example.com" would refer to the mailbox "com" in the parent mailbox "example".
        This does not determine the way your mails are stored on disk.
        See https://wiki.dovecot.org/Namespaces for details.
      '';
    };

    mailboxes = mkOption {
      description = ''
        The mailboxes for dovecot.
        Depending on the mail client used it might be necessary to change some mailbox's name.
      '';
      default = [
        {
          name = "Trash";
          auto = "no";
          specialUse = "Trash";
        }

        {
          name = "Junk";
          auto = "subscribe";
          specialUse = "Junk";
        }

        {
          name = "Drafts";
          auto = "subscribe";
          specialUse = "Drafts";
        }

        {
          name = "Sent";
          auto = "subscribe";
          specialUse = "Sent";
        }
      ];
    };

    certificateScheme = mkOption {
      type = types.enum [ 1 2 3 ];
      default = 2;
      description = ''
        Certificate Files. There are three options for these.

        1) You specify locations and manually copy certificates there.
        2) You let the server create new (self signed) certificates on the fly.
        3) You let the server create a certificate via `Let's Encrypt`. Note that
           this implies that a stripped down webserver has to be started. This also
           implies that the FQDN must be set as an `A` record to point to the IP of
           the server. In particular port 80 on the server will be opened. For details
           on how to set up the domain records, see the guide in the readme.
      '';
    };

    certificateFile = mkOption {
      type = types.path;
      example = "/root/mail-server.crt";
      description = ''
        Scheme 1)
        Location of the certificate
      '';
    };

    keyFile = mkOption {
      type = types.path;
      example = "/root/mail-server.key";
      description = ''
        Scheme 1)
        Location of the key file
      '';
    };

    certificateDirectory = mkOption {
      type = types.path;
      default = "/var/certs";
      description = ''
        Sceme 2)
        This is the folder where the certificate will be created. The name is
        hardcoded to "cert-<domain>.pem" and "key-<domain>.pem" and the
        certificate is valid for 10 years.
      '';
    };

    dkimSigning = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to activate dkim signing.
      '';
    };

    dkimSelector = mkOption {
      type = types.str;
      default = "mail";
      description = ''

      '';
    };

    dkimKeyDirectory = mkOption {
      type = types.path;
      default = "/var/dkim";
      description = ''

      '';
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable verbose logging for mailserver related services. This
        intended be used for development purposes only, you probably don't want
        to enable this unless you're hacking on nixos-mailserver.
      '';
    };

    maxConnectionsPerUser = mkOption {
      type = types.int;
      default = 100;
      description = ''
        Maximum number of IMAP/POP3 connections allowed for a user from each IP address.
        E.g. a value of 50 allows for 50 IMAP and 50 POP3 connections at the same
        time for a single user.
      '';
    };

    localDnsResolverPort = mkOption {
      type = types.int;
      default = 5300;
      description = ''
        The port which kresd will be bound to.
        A local DNS resolver (kresd) will be bound to this port and used by
        rspamd as recommended.
      '';
    };

    policydSPFExtraConfig = mkOption {
      type = types.lines;
      default = "";
      example = ''
        skip_addresses = 127.0.0.0/8,::ffff:127.0.0.0/104,::1
      '';
      description = ''
        Extra configuration options for policyd-spf. This can be use to among
        other things skip spf checking for some IP addresses.
      '';
    };
  };

  imports = [
    ./mail-server/dovecot.nix
    ./mail-server/environment.nix
    ./mail-server/kresd.nix
    ./mail-server/networking.nix
    ./mail-server/nginx.nix
    ./mail-server/opendkim.nix
    ./mail-server/postfix.nix
    ./mail-server/rspamd.nix
    ./mail-server/systemd.nix
    ./mail-server/users.nix
  ];
}
