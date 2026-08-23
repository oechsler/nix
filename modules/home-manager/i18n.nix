# Home Manager Internationalization
#
# Provides the translation helper used by user-facing generated configuration.
# English is the fallback; German is selected for de_* locales.
{ locale, lib, ... }:

let
  isGerman = lib.hasPrefix "de" locale.language;
in
{
  _module.args.i18n = {
    language = if isGerman then "de" else "en";
    translate = english: german: if isGerman then german else english;
  };
}
