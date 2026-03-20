{ lib }:

{
  # "companion"  -> "companion"
  # "Baby Buddy" -> "babybuddy"
  # "Open WebUI" -> "openwebui"
  toSlug = s: lib.toLower (lib.replaceStrings [ " " ] [ "" ] s);

  # "companion"  -> "companion"
  # "Baby Buddy" -> "babyBuddy"
  # "Open WebUI" -> "openWebUI"
  toCamelCase = s:
    let
      words = lib.splitString " " (lib.toLower s);
    in
    lib.concatStrings (lib.imap0 (i: w:
      if i == 0 then w
      else (lib.toUpper (lib.substring 0 1 w)) + (lib.substring 1 (-1) w)
    ) words);
}
