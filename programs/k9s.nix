{
  pkgs,
  pkgs-unstable,
  lib,
  ...
}:

{
  programs.k9s = {
    enable = true;
    package = pkgs-unstable.k9s;
    settings.k9s = {
      liveViewAutoRefresh = true;
      defaultView = "apps/v1/deployments";
      noExitOnCtrlC = true;
      skipLatestRevCheck = true;
      ui = {
        logoless = true;
        reactive = true;
        noIcons = false;
      };
      logger.textWrap = true;
    };
    plugins = {
      flux_toggle-helmrelease = {
        shortCut = "Shift-T";
        confirm = true;
        scopes = [ "helmreleases" ];
        description = "Toggle to suspend or resume a HelmRelease";
        command = "${lib.getExe pkgs.bash}";
        background = false;
        args = [
          "-c"
          ''suspended=$(${lib.getExe pkgs.kubectl} --context $CONTEXT get helmreleases -n $NAMESPACE $NAME -o=custom-columns=TYPE:.spec.suspend | tail -1); verb=$([ $suspended = "true" ] && echo "resume" || echo "suspend"); ${lib.getExe pkgs-unstable.fluxcd} $verb helmrelease --context $CONTEXT -n $NAMESPACE $NAME | ${lib.getExe pkgs.less} -K''
        ];
      };
      flux_toggle-kustomization = {
        shortCut = "Shift-T";
        confirm = true;
        scopes = [ "kustomizations" ];
        description = "Toggle to suspend or resume a Kustomization";
        command = "${lib.getExe pkgs.bash}";
        background = false;
        args = [
          "-c"
          ''suspended=$(${lib.getExe pkgs.kubectl} --context $CONTEXT get kustomizations -n $NAMESPACE $NAME -o=custom-columns=TYPE:.spec.suspend | tail -1); verb=$([ $suspended = "true" ] && echo "resume" || echo "suspend"); ${lib.getExe pkgs-unstable.fluxcd} $verb kustomization --context $CONTEXT -n $NAMESPACE $NAME | ${lib.getExe pkgs.less} -K''
        ];
      };
      flux_reconcile-git = {
        shortCut = "Shift-R";
        confirm = false;
        scopes = [ "gitrepositories" ];
        description = "Flux reconcile";
        command = "${lib.getExe pkgs.bash}";
        background = false;
        args = [
          "-c"
          "${lib.getExe pkgs-unstable.fluxcd} reconcile source git --context $CONTEXT -n $NAMESPACE $NAME | ${lib.getExe pkgs.less} -K"
        ];
      };
      flux_reconcile-hr = {
        shortCut = "Shift-R";
        confirm = false;
        scopes = [ "helmreleases" ];
        description = "Flux reconcile";
        command = "${lib.getExe pkgs.bash}";
        background = false;
        args = [
          "-c"
          "${lib.getExe pkgs-unstable.fluxcd} reconcile helmrelease --context $CONTEXT -n $NAMESPACE $NAME | ${lib.getExe pkgs.less} -K"
        ];
      };
      flux_reconcile-helm-repo = {
        shortCut = "Shift-Z";
        confirm = false;
        scopes = [ "helmrepositories" ];
        description = "Flux reconcile";
        command = "${lib.getExe pkgs.bash}";
        background = false;
        args = [
          "-c"
          "${lib.getExe pkgs-unstable.fluxcd} reconcile source helm --context $CONTEXT -n $NAMESPACE $NAME | ${lib.getExe pkgs.less} -K"
        ];
      };
      flux_reconcile-oci-repo = {
        shortCut = "Shift-Z";
        confirm = false;
        scopes = [ "ocirepositories" ];
        description = "Flux reconcile";
        command = "${lib.getExe pkgs.bash}";
        background = false;
        args = [
          "-c"
          "${lib.getExe pkgs-unstable.fluxcd} reconcile source oci --context $CONTEXT -n $NAMESPACE $NAME | ${lib.getExe pkgs.less} -K"
        ];
      };
      flux_reconcile-ks = {
        shortCut = "Shift-R";
        confirm = false;
        scopes = [ "kustomizations" ];
        description = "Flux reconcile";
        command = "${lib.getExe pkgs.bash}";
        background = false;
        args = [
          "-c"
          "${lib.getExe pkgs-unstable.fluxcd} reconcile kustomization --context $CONTEXT -n $NAMESPACE $NAME | ${lib.getExe pkgs.less} -K"
        ];
      };
      flux_reconcile-ir = {
        shortCut = "Shift-R";
        confirm = false;
        scopes = [ "imagerepositories" ];
        description = "Flux reconcile";
        command = "${lib.getExe' pkgs.bash "sh"}";
        background = false;
        args = [
          "-c"
          "${lib.getExe pkgs-unstable.fluxcd} reconcile image repository --context $CONTEXT -n $NAMESPACE $NAME | ${lib.getExe pkgs.less} -K"
        ];
      };
      flux_reconcile-iua = {
        shortCut = "Shift-R";
        confirm = false;
        scopes = [ "imageupdateautomations" ];
        description = "Flux reconcile";
        command = "${lib.getExe' pkgs.bash "sh"}";
        background = false;
        args = [
          "-c"
          "${lib.getExe pkgs-unstable.fluxcd} reconcile image update --context $CONTEXT -n $NAMESPACE $NAME | ${lib.getExe pkgs.less} -K"
        ];
      };
      flux_trace = {
        shortCut = "Shift-Q";
        confirm = false;
        scopes = [ "all" ];
        description = "Flux trace";
        command = "${lib.getExe pkgs.bash}";
        background = false;
        args = [
          "-c"
          ''if [ -n "$RESOURCE_GROUP" ]; then api_endpoint="/apis/$RESOURCE_GROUP/$RESOURCE_VERSION"; else api_endpoint="/api/$RESOURCE_VERSION"; fi; api_resource=$(${lib.getExe pkgs.kubectl} get --raw "''${api_endpoint}" | ${lib.getExe pkgs.jq} -r ".resources[] | select(.name==\"$RESOURCE_NAME\")"); kind=$(echo ''${api_resource} | ${lib.getExe pkgs.jq} -r '.kind'); namespace_arg=$(echo ''${api_resource} | ${lib.getExe pkgs.jq} -r "if .namespaced == true then \"--namespace $NAMESPACE\" else \"\" end"); [ -n "$RESOURCE_GROUP" ] && api_version=$RESOURCE_GROUP/; api_version=''${api_version}$RESOURCE_VERSION; ${lib.getExe pkgs-unstable.fluxcd} trace --context $CONTEXT --kind ''${kind} --api-version ''${api_version} ''${namespace_arg} $NAME |& ${lib.getExe pkgs.less} -K''
        ];
      };
      flux_get-suspended-helmreleases = {
        shortCut = "Shift-S";
        confirm = false;
        scopes = [ "helmrelease" ];
        description = "Suspended Helm Releases";
        command = "${lib.getExe' pkgs.bash "sh"}";
        background = false;
        args = [
          "-c"
          "${lib.getExe pkgs.kubectl} get --context $CONTEXT --all-namespaces helmreleases.helm.toolkit.fluxcd.io -o json | ${lib.getExe pkgs.jq} -r '.items[] | select(.spec.suspend==true) | [.metadata.namespace,.metadata.name,.spec.suspend] | @tsv' | ${lib.getExe pkgs.less} -K"
        ];
      };
      flux_get-suspended-kustomizations = {
        shortCut = "Shift-S";
        confirm = false;
        scopes = [ "kustomizations" ];
        description = "Suspended Kustomizations";
        command = "${lib.getExe' pkgs.bash "sh"}";
        background = false;
        args = [
          "-c"
          "${lib.getExe pkgs.kubectl} get --context $CONTEXT --all-namespaces kustomizations.kustomize.toolkit.fluxcd.io -o json | ${lib.getExe pkgs.jq} -r '.items[] | select(.spec.suspend==true) | [.metadata.name,.spec.suspend] | @tsv' | ${lib.getExe pkgs.less} -K"
        ];
      };
    };
  };
}
