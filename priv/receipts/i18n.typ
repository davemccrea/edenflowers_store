// Mirrors laskutys' translation pattern. Single lookup function over a
// TOML keyed by language; fallback to English if a key is missing.

#let _translations = toml("translations.toml")

#let translate(key, lang) = {
  let table = _translations.at(lang, default: _translations.en)
  table.at(key, default: _translations.en.at(key))
}
