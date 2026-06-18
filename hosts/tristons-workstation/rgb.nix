{ pkgs, ... }:

let
  og = "${pkgs.openrgb}/bin/openrgb";

  offScript = pkgs.writeShellScript "rgb-off" ''
    ${og} --mode static --color 000000 || true
    ${og} --device "Corsair MM700" --mode direct --color 000000 || true
    ${og} --device "ASUS TUF GAMING B650E-E WIFI" --zone 0 --size 9 --mode direct --color 000000,000000,000000,000000,000000,000000,000000,000000,000000 || true
    ${og} --device "ASUS TUF GAMING B650E-E WIFI" --zone 1 --size 9 --mode direct --color 000000,000000,000000,000000,000000,000000,000000,000000,000000 || true
  '';

  vibesScript = pkgs.writeShellScript "rgb-vibes" ''
    # Interpolate two hex colors — returns N comma-separated hex values
    hex2rgb() {
      printf '%d %d %d' \
        "$(( 16#$(printf '%s' "$1" | cut -c1-2) ))" \
        "$(( 16#$(printf '%s' "$1" | cut -c3-4) ))" \
        "$(( 16#$(printf '%s' "$1" | cut -c5-6) ))"
    }

    gradient() {
      local c1="$1" c2="$2" n="$3"
      [ -z "$n" ] && n=9
      local r1 g1 b1 r2 g2 b2
      read -r r1 g1 b1 <<< "$(hex2rgb "$c1")"
      read -r r2 g2 b2 <<< "$(hex2rgb "$c2")"
      local result="" i
      for i in $(seq 0 $((n-1))); do
        local r g b hex
        r=$(( r1 + (r2 - r1) * i / (n - 1) ))
        g=$(( g1 + (g2 - g1) * i / (n - 1) ))
        b=$(( b1 + (b2 - b1) * i / (n - 1) ))
        hex=$(printf '%02X%02X%02X' "$r" "$g" "$b")
        [ -n "$result" ] && result="$result,$hex" || result="$hex"
      done
      printf '%s' "$result"
    }

    apply() {
      local static_c="$1" mm700_c="$2" fan0="$3" fan1="$4"
      ${og} --mode static --color "$static_c" || true
      ${og} --device "Corsair MM700" --mode direct --color "$mm700_c" || true
      ${og} --device "ASUS TUF GAMING B650E-E WIFI" --zone 0 --size 9 --mode direct --color "$fan0" || true
      ${og} --device "ASUS TUF GAMING B650E-E WIFI" --zone 1 --size 9 --mode direct --color "$fan1" || true
    }

    DOY=$(date +%j)
    THEME=$(( 10#$DOY % 30 ))

    case $THEME in
      0)  apply "FF1493" "00FFFF" "$(gradient FF1493 9400D3)" "$(gradient 00FFFF FF1493)" ;;  # Synthwave
      1)  apply "228B22" "00FF7F" "$(gradient 006400 00FF00)" "$(gradient 00FF00 006400)" ;;  # Deep Forest
      2)  apply "FF6600" "FF4500" "$(gradient FF8C00 FF0000)" "$(gradient FF0000 FFD700)" ;;  # Ember
      3)  apply "ADD8E6" "E0FFFF" "$(gradient 87CEEB FFFFFF)" "$(gradient FFFFFF 00BFFF)" ;;  # Arctic
      4)  apply "FFFF00" "00FFFF" "$(gradient 00FF41 FFFF00)" "$(gradient FFFF00 FF00FF)" ;;  # Cyberpunk
      5)  apply "FF4500" "FF6600" "$(gradient FF0000 FF8C00)" "$(gradient FF8C00 FF0000)" ;;  # Lava
      6)  apply "4B0082" "9400D3" "$(gradient 1A0066 FF1493)" "$(gradient FF1493 0000FF)" ;;  # Galaxy
      7)  apply "00CED1" "FF8C00" "$(gradient 00CED1 FF8C00)" "$(gradient FF8C00 00CED1)" ;;  # Tropical
      8)  apply "EE82EE" "FFB6C1" "$(gradient FFB6C1 9370DB)" "$(gradient 9370DB FFB6C1)" ;;  # Vaporwave
      9)  apply "00FF41" "00FF41" "$(gradient 003300 00FF41)" "$(gradient 00FF41 003300)" ;;  # Matrix
      10) apply "FF4500" "FF8C00" "$(gradient FFFFFF FF4500)" "$(gradient FF4500 FFFFFF)" ;;  # Inferno
      11) apply "006994" "00FFFF" "$(gradient 00008B 00FFFF)" "$(gradient 00FFFF 006994)" ;;  # Oceanic
      12) apply "FF00FF" "FF4500" "$(gradient FF4500 8B008B)" "$(gradient 8B008B FF4500)" ;;  # Dusk
      13) apply "00FFFF" "FF00FF" "$(gradient 00FFFF FF00FF)" "$(gradient FF00FF 00FFFF)" ;;  # Neon City
      14) apply "FF69B4" "FFB6C1" "$(gradient FF69B4 FFFFFF)" "$(gradient FFFFFF FF1493)" ;;  # Sakura
      15) apply "7FFF00" "ADFF2F" "$(gradient 00FF00 FFFF00)" "$(gradient FFFF00 00FF00)" ;;  # Toxic
      16) apply "191970" "4169E1" "$(gradient 000033 4169E1)" "$(gradient 4169E1 000033)" ;;  # Midnight
      17) apply "DC143C" "FF4500" "$(gradient DC143C FF8C00)" "$(gradient FF8C00 DC143C)" ;;  # Volcano
      18) apply "FFFFFF" "FF0000" "$(gradient FF0000 8B00FF)" "$(gradient 8B00FF FF0000)" ;;  # Prism
      19) apply "FF9ECD" "B0E0E6" "$(gradient FFB6C1 E6E6FA)" "$(gradient E6E6FA B0E0E6)" ;;  # Cotton Candy
      20) apply "D2691E" "FF8C00" "$(gradient F4A460 CC4400)" "$(gradient CC4400 F4A460)" ;;  # Desert Heat
      21) apply "00FA9A" "9400D3" "$(gradient 00FF7F 9400D3)" "$(gradient 9400D3 00FF7F)" ;;  # Northern Lights
      22) apply "8B0000" "DC143C" "$(gradient 330000 DC143C)" "$(gradient DC143C 330000)" ;;  # Blood Moon
      23) apply "0080FF" "00BFFF" "$(gradient 003399 00BFFF)" "$(gradient 00BFFF 003399)" ;;  # Electric
      24) apply "FF79C6" "BD93F9" "$(gradient BD93F9 FF79C6)" "$(gradient 50FA7B BD93F9)" ;;  # Dracula
      25) apply "B58900" "268BD2" "$(gradient B58900 268BD2)" "$(gradient 268BD2 B58900)" ;;  # Solarized
      26) apply "CC5500" "DAA520" "$(gradient CC0000 DAA520)" "$(gradient DAA520 CC0000)" ;;  # Autumn
      27) apply "FFFFFF" "FFFFFF" "$(gradient CCCCCC FFFFFF)" "$(gradient FFFFFF CCCCCC)" ;;  # Monochrome
      28) apply "E8A09A" "FFD700" "$(gradient E8A09A FFD700)" "$(gradient FFD700 E8A09A)" ;;  # Rose Gold
      29) apply "003366" "00FFCC" "$(gradient 001A33 00FFCC)" "$(gradient 00FFCC 001A33)" ;;  # Deep Sea
    esac
  '';
in {
  systemd.services.rgb-off = {
    description = "Turn off all RGB";
    serviceConfig = { Type = "oneshot"; ExecStart = "${offScript}"; };
  };
  systemd.timers.rgb-off = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "*-*-* 20:00:00 America/Indiana/Indianapolis";
  };

  systemd.services.rgb-vibes = {
    description = "Director of Vibes - morning RGB theme";
    serviceConfig = { Type = "oneshot"; ExecStart = "${vibesScript}"; };
  };
  systemd.timers.rgb-vibes = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 08:00:00 America/Indiana/Indianapolis";
      Persistent = true;
    };
  };
}
