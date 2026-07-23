# Plymouth boot theme branded for the StagePlotiphar signage kiosks
# (hosts/stage-plotiphar). Colors, the badge mark, and the wordmark are
# pulled from the live plotiphar.com navbar (teal #0d9488 -> #2dd4bf badge
# gradient, near-black #07090f background, GeistSans wordmark — Inter is
# used here as the closest match available in nixpkgs) rather than
# checked-in binary assets: box.png is rendered from generate-box.py at
# build time so the theme stays reviewable as plain code.
{
  lib,
  stdenvNoCC,
  python3,
  inter,
}:

stdenvNoCC.mkDerivation {
  pname = "plymouth-theme-plotiphar";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ (python3.withPackages (ps: [ ps.pillow ])) ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    themeDir=$out/share/plymouth/themes/plotiphar
    mkdir -p "$themeDir"

    python3 generate-box.py "$themeDir/box.png" "${inter}/share/fonts/truetype/InterVariable.ttf"
    sed "s|@imageDir@|$themeDir|" plotiphar.plymouth.in > "$themeDir/plotiphar.plymouth"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Plymouth boot splash theme for the StagePlotiphar signage kiosk (plotiphar.com)";
    platforms = platforms.linux;
  };
}
