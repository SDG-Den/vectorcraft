# `programs.vectorcraft` for NixOS and home-manager.
#
# The option set is shared; `kind` selects only the behaviour the target module system can express:
# home-manager writes the settings overlay and the palette variable per user, NixOS installs the
# package and the MIME defaults for the whole system. NixOS cannot write per-user files, so it never
# writes `settings` or the palette variable.
#
# The overlay is `settings.override.json` beside `ui.json` (`apps/vectorcraft/src/prefs.rs`), merged
# over the saved preferences at start-up. VectorCraft never writes it, so the declarative values
# survive a normal save. `ui.json` also holds window and docking state, which the overlay changes
# only when it names those keys.
{ kind }:
{
  config,
  lib,
  pkgs,
  # The package of this flake; `flake.nix` passes it through `_module.args`, so importing the
  # module directly needs no overlay.
  vectorcraftPackage ? pkgs.vectorcraft,
  # `flake.nix` passes the source build and the pre-built release binary separately. Importing the
  # module directly falls back to `vectorcraftPackage` and no binary.
  vectorcraftSourcePackage ? vectorcraftPackage,
  vectorcraftBinaryPackage ? null,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.programs.vectorcraft;

  jsonFormat = pkgs.formats.json { };

  # The same list as `packaging/linux/ai.storyteller.vectorcraft.desktop` (`MimeType=`).
  mimeTypes = [
    "image/svg+xml"
    "application/pdf"
    "application/x-vectorcraft"
    "image/svg+xml-compressed"
    "application/illustrator"
    "application/x-ai-template"
    "image/png"
    "image/jpeg"
    "image/gif"
    "image/webp"
    "image/tiff"
    "image/bmp"
    "application/x-vectorcraft-template"
    "image/vnd.dxf"
    "image/emf"
    "image/wmf"
    "image/x-eps"
    "application/x-affinity"
  ];

  desktopFile = "ai.storyteller.vectorcraft.desktop";

  # The per-user settings directory: `$XDG_CONFIG_HOME/vectorcraft` on Linux.
  settingsDir = "${config.xdg.configHome}/vectorcraft";

  associations = lib.genAttrs mimeTypes (_: [ desktopFile ]);
in
{
  options.programs.vectorcraft = {
    enable = mkEnableOption "VectorCraft";

    useBinary = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Install the pre-built Linux binary from `binary-url.json` when this system has one,
        instead of building from source. Falls back to the source build when the file is missing
        or the system is unsupported.
      '';
    };

    package = mkOption {
      type = types.package;
      default =
        if cfg.useBinary && vectorcraftBinaryPackage != null then
          vectorcraftBinaryPackage
        else
          vectorcraftSourcePackage;
      defaultText = lib.literalMD "the pre-built binary from `binary-url.json`, or the source build";
      description = "The VectorCraft package to install.";
    };

    setAsDefault = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open SVG, PDF, VectorCraft documents and the other formats VectorCraft reads with it by
        default (the MIME types of `packaging/linux/ai.storyteller.vectorcraft.desktop`).
      '';
    };

    settings = mkOption {
      type = jsonFormat.type;
      default = { };
      description = ''
        Free-form preferences merged over the app's settings. Home-manager writes them to
        `settings.override.json`; NixOS ignores them, because it cannot write per-user files.
      '';
    };

    paletteFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional shared palette file, exported as `CRAFT_PALETTE_FILE` by home-manager. Inert until
        theming support lands; NixOS ignores it because the variable would be system-wide.
      '';
    };
  };

  config = lib.mkMerge [
    (mkIf cfg.enable (
      if kind == "nixos" then
        {
          environment.systemPackages = [ cfg.package ];
          xdg.mime.defaultApplications = mkIf cfg.setAsDefault associations;
        }
      else
        {
          home.packages = [ cfg.package ];
          home.sessionVariables = mkIf (cfg.paletteFile != null) {
            CRAFT_PALETTE_FILE = toString cfg.paletteFile;
          };
          home.file."${settingsDir}/settings.override.json" = mkIf (cfg.settings != { }) {
            source = jsonFormat.generate "vectorcraft-settings.override.json" cfg.settings;
          };
          xdg.mimeApps = mkIf cfg.setAsDefault {
            enable = true;
            defaultApplications = associations;
            # Associated even when another application stays the default.
            associations.added = associations;
          };
        }
    ))
  ];
}
