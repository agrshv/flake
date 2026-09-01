# Plain attribute set (not a module): `import ../common/me.nix` where needed.
{
  # Login user on every host (uid 1000). Renaming it on a live host needs the
  # manual usermod step first — see INSTALL.md "Renaming the login user".
  user = "agrshv";
  # Personal ed25519 key — authorized on every host and in the installer ISO.
  sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFoJfwlfB0GAnaPFj2oLVK0HA9uGWPwoTfsfTrIPHpgb @personal_key";
}
