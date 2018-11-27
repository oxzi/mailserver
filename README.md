# Mailserver

*Very simple NixOS-based mailserver*

This repository contains a hard fork of the [Simple Nixos Mailserver][snm]
initially created to maintain my private mailserver. Some *non
mailserver-related* options were removed and other options may differ.

Most of the work was done by Robin Raymond and the
[Simple Nixos Mailserver's][snm] contributors - thanks a million!

Use this fork at your own risk!


## Usage

```nix
# Example NixOS configuration

{ config, pkgs, ... }:
{
  imports = [
    # Assume that this repository is cloned to mailserver
    ./mailserver
  ];

  mailserver = {
    enable = true;
    fqdn = "mail.example.com";
    domains = [ "example.com" "example2.com" ];

    # Generate password: mkpasswd -m sha-512
    loginAccounts = {
      "user@example.com" = {
        hashedPassword = "…";

        aliases = [ "postmaster@example.com" ];
        catchAll = [ "example2.com" ];
      };
      "user2@example.com" = {
        hashedPassword = "…";

        sieveScript = ''
           require ["fileinto"];

           # Discourse killed the mailing list
           if header :contains "List-Id" "<nix-devel.googlegroups.com>" {
             fileinto "INBOX.nix-devel";
           }
        '';
      };
    };

    extraVirtualAliases = {
      "single-alias@example.com" = "user1@example.com";
      "multi-alias@example.com" = [
        "user1@example.com" "user2@example.com" ];
    };

    rejectSender = [ "rejected-sender@spammer.com" ];
    rejectRecipients = [ "rejected-recipient@example.com" ];
  };
}
```


[snm]: https://gitlab.com/simple-nixos-mailserver/nixos-mailserver
