{
  config,
  lib,
  pkgs,
  ...
}:
let
  library = "/var/lib/kavita/library";

  # Files whatever lands in inbox/ under books/<Author>/<Series or Title>/,
  # named from the book's own metadata (read with calibre's ebook-meta) or an
  # Anna's Archive file name — the
  # folder-per-series layout Kavita's scanner wants. Only EPUB and PDF, the
  # book formats Kavita reads; anything else, anything without a title and
  # author, or anything already in the library goes to inbox-failed/ instead.
  kavita-inbox = pkgs.writeShellApplication {
    name = "kavita-inbox";
    runtimeInputs = [ pkgs.calibre ];
    text = ''
      inbox=${library}/inbox
      failed=${library}/inbox-failed
      books=${library}/books
      annas_archive="^(.+) -- [0-9a-f]{32} -- Anna(’|')s Archive\.[^.]+$"

      # dufs writes uploads in place, so wait until nothing has changed for
      # 30s rather than filing (or failing) a half-uploaded book.
      while [[ -n $(find "$inbox" -mindepth 1 -mmin -0.5 -print -quit) ]]; do
        sleep 10
      done

      reject() {
        echo "kavita-inbox: ''${1#"$inbox"/}: $2" >&2
        mv --backup=numbered "$1" "$failed/"
      }

      # One path component: no slashes, no leading dots or spaces, and short
      # enough that a non-Latin title stays under the 255-byte name limit.
      safe() {
        local s=''${1//\//-}
        s=''${s#"''${s%%[![:space:].]*}"}
        s=''${s%"''${s##*[![:space:]]}"}
        printf '%s' "''${s:0:80}"
      }

      file_book() {
        local f=$1 ext meta title author series index dir name fields
        ext=''${f##*.}
        ext=''${ext,,}
        if [[ $ext != epub && $ext != pdf ]]; then
          reject "$f" "not an EPUB or PDF"
          return
        fi

        meta=$(ebook-meta "$f" 2>/dev/null) || {
          reject "$f" "ebook-meta failed"
          return
        }
        title=$(sed -n 's/^Title *: //p' <<<"$meta")
        # "A & B [B, A & C, B]": the first author, without the sort form.
        author=$(sed -n 's/^Author(s) *: //p' <<<"$meta")
        author=''${author%% [[]*}
        author=''${author%% & *}
        series=$(sed -n 's/^Series *: //p' <<<"$meta")

        # Anna's Archive names files "Title -- Author;Author -- … -- <md5> --
        # Anna’s Archive.pdf", which beats the metadata inside (for PDFs often
        # a publisher or nothing), so take the title and first author from
        # there. The series, if any, still comes from the metadata.
        if [[ ''${f##*/} =~ $annas_archive ]] && [[ ''${BASH_REMATCH[1]} == *" -- "* ]]; then
          fields=''${BASH_REMATCH[1]}
          title=''${fields%% -- *}
          fields=''${fields#* -- }
          author=''${fields%% -- *}
          author=''${author%%;*}
        fi

        # ebook-meta falls back to the file name and "Unknown" for files it
        # can't read, so an unknown author is how a broken file shows up.
        title=$(safe "$title")
        author=$(safe "$author")
        if [[ -z $title || -z $author || $author == Unknown ]]; then
          reject "$f" "no title or author in its metadata"
          return
        fi

        if [[ -n $series ]]; then
          # "Discworld #2.5" -> Discworld/02.5 - Title.epub
          index=''${series##* #}
          series=$(safe "''${series% #*}")
          printf -v index '%02d%s' "$((10#''${index%%.*}))" "''${index#"''${index%%.*}"}"
          dir=$books/$author/$series
          name="$index - $title.$ext"
        else
          dir=$books/$author/$title
          name="$title.$ext"
        fi

        if [[ -e $dir/$name ]]; then
          reject "$f" "$dir/$name already exists"
          return
        fi
        mkdir -p "$dir"
        mv "$f" "$dir/$name"
        echo "kavita-inbox: filed ''${f#"$inbox"/} as ''${dir#"$books"/}/$name"
      }

      while IFS= read -r -d "" f; do
        file_book "$f"
      done < <(find "$inbox" -mindepth 1 ! -type d -print0)

      # Folder uploads leave their directories behind; an inbox that isn't
      # empty would re-trigger the path unit forever.
      find "$inbox" -mindepth 1 -type d -empty -delete
    '';
  };
in
{
  # Signs Kavita's login JWTs; rotating it logs every client out. The file is
  # the bare key (no KEY= prefix), e.g. `head -c 64 /dev/urandom | base64 -w0`.
  sops.secrets."kavita/token-key".restartUnits = [ "kavita.service" ];

  # Kavita — ebook / comic / manga library with a web reader, OPDS feed and
  # KOReader progress sync. Deliberately NOT behind Authelia forward-auth: OPDS
  # readers and KOReader talk to the API directly and can't follow a login
  # redirect, so Kavita's own accounts are the gate (as with vaultwarden). The
  # country gate in ./nginx.nix still applies.
  #
  # Books go in /var/lib/kavita/library (owned by kavita; uploaded through
  # ./dufs.nix); add its subfolders as libraries in the web UI. Each book or
  # series needs a folder of its own — files loose in a library's top level
  # are skipped by the scanner. Books dropped in inbox/ are filed into books/
  # automatically (kavita-inbox above); comics and manga still go in by hand.
  # Don't add the library root itself, or inbox/ gets scanned too.
  services.kavita = {
    enable = true;
    tokenKeyFile = config.sops.secrets."kavita/token-key".path;
    settings = {
      IpAddresses = "127.0.0.1";
      Port = 5000;
    };
  };

  systemd.tmpfiles.settings."10-kavita" =
    lib.genAttrs
      [
        library
        "${library}/books"
        "${library}/inbox"
        "${library}/inbox-failed"
      ]
      (_: {
        d = {
          mode = "0750";
          user = "kavita";
          group = "kavita";
        };
      });

  # Runs kavita-inbox whenever something is in inbox/; it re-triggers if more
  # arrived while it ran. Runs as kavita, so filed books already have the
  # owner Kavita needs and its library watcher picks them up.
  systemd.paths.kavita-inbox = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.DirectoryNotEmpty = "${library}/inbox";
  };
  systemd.services.kavita-inbox = {
    description = "File books from the Kavita inbox";
    environment = {
      # ebook-meta's labels and "Unknown" are translated otherwise.
      LC_ALL = "C.UTF-8";
      # calibre wants a writable config and cache dir; $HOME is read-only here.
      CALIBRE_CONFIG_DIRECTORY = "/tmp/calibre/config";
      CALIBRE_CACHE_DIRECTORY = "/tmp/calibre/cache";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe kavita-inbox;
      User = "kavita";
      Group = "kavita";
      UMask = "0027";

      ProtectSystem = "strict";
      ReadWritePaths = [ library ];
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      PrivateNetwork = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      LockPersonality = true;
    };
  };

  services.nginx.virtualHosts."books.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.kavita.settings.Port}";
      # The web reader and live library updates use a SignalR websocket.
      proxyWebsockets = true;
    };
  };
}
