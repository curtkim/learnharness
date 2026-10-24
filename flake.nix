{
  description = "learnharness — an agent harness for learning (standalone web server)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.buildNpmPackage {
          pname = "learnharness";
          version = (builtins.fromJSON (builtins.readFile ./package.json)).version;
          src = self;

          nodejs = pkgs.nodejs_24;
          npmDepsHash = "sha256-pziw5ud2QuqX3eMQKFNP5jG4xtNUl5jtiVeavlG1Cic=";

          # The build sandbox has no network: skip binary downloads in postinstall.
          env = {
            ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
            PUPPETEER_SKIP_DOWNLOAD = "1";
            NEXT_TELEMETRY_DISABLED = "1";
          };

          # next/font/google fetches at build time; swap in the same fonts from nixpkgs.
          postPatch = ''
            mkdir -p app/fonts
            cp "${pkgs.jetbrains-mono}/share/fonts/truetype/JetBrainsMono[wght].ttf" app/fonts/JetBrainsMono.ttf
            cp ${pkgs.source-sans}/share/fonts/truetype/SourceSans3VF-Upright.ttf app/fonts/SourceSans3.ttf
            substituteInPlace app/layout.tsx \
              --replace-fail 'import { JetBrains_Mono, Source_Sans_3 } from "next/font/google";' \
                             'import localFont from "next/font/local";' \
              --replace-fail 'JetBrains_Mono({ subsets: ["latin"], variable: "--font-jetbrains" })' \
                             'localFont({ src: "./fonts/JetBrainsMono.ttf", weight: "100 800", variable: "--font-jetbrains" })' \
              --replace-fail 'Source_Sans_3({ subsets: ["latin"], variable: "--font-sans3" })' \
                             'localFont({ src: "./fonts/SourceSans3.ttf", weight: "200 900", variable: "--font-sans3" })'
          '';

          buildPhase = ''
            runHook preBuild
            npx next build
            node scripts/build-server.mjs
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/lib $out/bin
            cp -r .next/standalone $out/lib/learnharness

            cat > $out/bin/learnharness <<EOF
            #!${pkgs.runtimeShell}
            state="\''${XDG_DATA_HOME:-\$HOME/.local/share}/learnharness"
            export LH_DATA_DIR="\''${LH_DATA_DIR:-\$state/data}"
            export LH_AUTH_FILE="\''${LH_AUTH_FILE:-\$state/auth.json}"
            export HOSTNAME="\''${LH_HOST:-127.0.0.1}"
            export PORT="\''${PORT:-3000}"
            export NEXT_TELEMETRY_DISABLED=1
            mkdir -p "\$LH_DATA_DIR" "\$(dirname "\$LH_AUTH_FILE")"
            echo "learnharness: http://\$HOSTNAME:\$PORT (data: \$LH_DATA_DIR)"
            exec ${pkgs.nodejs_24}/bin/node $out/lib/learnharness/server.js "\$@"
            EOF
            chmod +x $out/bin/learnharness
            runHook postInstall
          '';

          meta.mainProgram = "learnharness";
        };
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = nixpkgs.lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
      });
    };
}
