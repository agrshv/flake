-- Option completion and docs from this machine's own config: the flake's
-- nixosConfigurations entry is named after the host.
local flake = '(builtins.getFlake "' .. vim.fn.expand('~/Documents/flake') .. '")'
local host = flake .. '.nixosConfigurations."' .. vim.fn.hostname() .. '"'

return {
  settings = {
    nixd = {
      nixpkgs = { expr = 'import ' .. flake .. '.inputs.nixpkgs { }' },
      options = {
        nixos = { expr = host .. '.options' },
        home_manager = {
          expr = host .. '.options.home-manager.users.type.getSubOptions [ ]',
        },
      },
    },
  },
}
