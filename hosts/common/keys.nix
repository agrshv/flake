# Plain attribute set (not a module): `import ../common/keys.nix` where needed.
{
  # Personal ed25519 key — authorized on every host and in the installer ISO.
  personal = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFoJfwlfB0GAnaPFj2oLVK0HA9uGWPwoTfsfTrIPHpgb @personal_key";
}
