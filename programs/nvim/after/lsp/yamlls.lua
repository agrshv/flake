-- Same schema setup as Zed's yaml-language-server (programs/zed.nix).
local kubernetes = {}
for _, dir in ipairs({ 'k8s', 'manifests', 'deploy', 'kube' }) do
  for _, ext in ipairs({ 'yaml', 'yml' }) do
    -- The server hides the bogus "Matches multiple schemas" k8s error using a
    -- naive matcher: no {a,b} braces, and "dir/**/" needs a subdirectory.
    -- "dir/*.ext" covers any depth there, "dir/**/*.ext" covers it for the
    -- real schema association.
    table.insert(kubernetes, dir .. '/*.' .. ext)
    table.insert(kubernetes, dir .. '/**/*.' .. ext)
  end
end

return {
  settings = {
    yaml = {
      -- Auto-associate well-known files (kustomization.yaml, Helm Chart.yaml,
      -- GitHub Actions, compose, ...) with schemas from the JSON Schema Store.
      schemaStore = {
        enable = true,
        url = 'https://www.schemastore.org/api/json/catalog.json',
      },
      schemas = { kubernetes = kubernetes },
    },
  },
}
