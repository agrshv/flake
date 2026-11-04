-- nvim-lspconfig leaves out terraform-vars, so .tfvars/.tofuvars files would
-- get no server.
return {
  filetypes = { 'opentofu', 'opentofu-vars', 'terraform', 'terraform-vars' },
}
