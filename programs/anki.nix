{ pkgs, ... }:
{
  # Anki with add-ons from nixpkgs. The wrapper points ANKI_ADDONS at a
  # store directory, so the in-app add-on dialog is disabled and add-on
  # settings are set here with `<addon>.withConfig { config = …; }` rather
  # than in the app. Preferences, profiles and the sync login stay in
  # ~/.local/share/Anki2 as usual (programs.anki would make them read-only).
  # The German deck is built from ~/Documents/deutsch.
  home.packages = [
    (pkgs.anki.withAddons (
      with pkgs.ankiAddons;
      [
        # Two review buttons (Again / Good) instead of four.
        passfail2
        # Calendar of past and upcoming reviews on the deck overview.
        review-heatmap
        # Reschedule / postpone / advance with FSRS and keep sibling cards
        # (DE→RU and RU→DE of one note) apart. Needs FSRS on in deck options.
        fsrs4anki-helper
        # Local HTTP API (localhost:8765) so a script can import a deck and
        # trigger a sync in the running app.
        anki-connect
      ]
    ))
  ];
}
