{ pkgs, ... }:
{
  # Use Valkey (the BSD-licensed Redis fork) for every Redis instance on this
  # host. The NixOS redis module has a single, shared `services.redis.package`
  # that all `services.redis.servers.*` launch from — so this one line switches
  # the authelia (sessions), immich, and paperless instances at once.
  #
  # Valkey is a drop-in: its package ships `redis-server`/`redis-cli` and is
  # RDB/AOF and protocol compatible, so the existing /var/lib/redis-* data dirs
  # load unchanged.
  services.redis.package = pkgs.valkey;
}
