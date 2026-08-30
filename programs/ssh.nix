{
  programs.ssh = {
    enable = true;
    # Own the "Host *" defaults explicitly instead of inheriting home-manager's.
    enableDefaultConfig = false;
    settings."*" = {
      ForwardAgent = false;
      AddKeysToAgent = "no";
      Compression = false;
      ServerAliveInterval = 0;
      ServerAliveCountMax = 3;
      HashKnownHosts = false;
      UserKnownHostsFile = "~/.ssh/known_hosts";
      ControlMaster = "no";
      ControlPath = "~/.ssh/master-%r@%n:%p";
      ControlPersist = "no";
      SetEnv.TERM = "xterm-256color";
      StrictHostKeyChecking = "accept-new";
    };
  };
}
