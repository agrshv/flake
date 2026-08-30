# Plain attribute set (not a module): `import ../common/me.nix` where needed.
{
  # Login user on the workstations (uid 1000). home-server still uses the old
  # name `d3spair` — see INSTALL.md "Renaming the login user" before changing it.
  user = "agrshv";
  # Personal ed25519 key — authorized on every host and in the installer ISO.
  sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFoJfwlfB0GAnaPFj2oLVK0HA9uGWPwoTfsfTrIPHpgb @personal_key";
}
