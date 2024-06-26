// linguify

#import "fluent.typ": get_message as __get_ftl_message, has_message as __has_ftl_message, ftl_data

#let __linguify_lang_preferred = state("linguify-preferred-lang", auto);  // auto means detect from context text.lang 

/// None or dictionary of the following structure:
/// default-lang: "en"
/// en: *en-data*
/// de: *de-data*
/// ...
/// where *en-data* and *de-data* are in the following structure:
/// __type: "typst-dict" | "ftl"
/// data: *typst-dict* | *ftl-str*
#let __linguify_lang_database = state("linguify-database", none);

/// Get a value from a L10n data dictionary.
#let get_text(src, key, default: none, args: none) = {
  assert.eq(type(src), dictionary, message: "expected src to be a dictionary, found " + type(src))
  if not "__type" in src {
    // Assume it's a typst-dict.
    src.at(key, default: default)
  }
  else if src.__type == "typst-dict" {
    src.data.at(key, default: default)
  } else if src.__type == "ftl" {
    let data = src.at("data", default: none)
    assert(data != none, message: "expected data to be present in ftl-string")
    assert.eq(type(data), str, message: "expected data to be a string, found " + type(data))
    if __has_ftl_message(data, key) {
      __get_ftl_message(data, key, args: args)
    } else {
      default
    }
  } else {
    panic("Invalid L10n data type: " + src.type)
  }
}

#let __linguify_lang_fallback = state("linguify-fallback-lang", auto); // auto means to look in database.

/// wrapper to get linguify database
/// ! needs context
#let linguify_get_database() = {
  __linguify_lang_database.get()
}

/// set a data dictionary for linguify database
#let linguify_set_database(data, languages: ()) = {
  if type(data) == str {
    // Interpret as FTL root
    data = ftl_data(data, languages) 
  }
  assert.eq(type(data), dictionary, message: "expected data to be a dictionary, found " + type(data))
  __linguify_lang_database.update(data);
}

/// check if database is not empty
/// ! needs context 
#let linguify_is_database_initialized() = {
  __linguify_lang_database.get() != none
}

/// add data to the current database
#let linguify_add_to_database(data) = {
  context {
    let database = __linguify_lang_database.get()
    for (key,value) in data.pairs() {
      // let lang_section = database.at(key, default: none)
      if key not in database.keys() {
        database.insert(key, value)
      } else {
        let new = database.at(key) + value
        database.insert(key, new)
      }
    }
    __linguify_lang_database.update(database);
  }
}

/// Update args
#let linguify_update_args(args) = {
  context {
    if linguify_is_database_initialized() {
      let database = __linguify_lang_database.get()
      let new-args = database.at("args", default: (:))
      for (key, value) in args.pairs() {
        new-args.insert(key, value)
      }
      linguify_add_to_database(("args": new-args))
    } else {
      panic("linguify database not initialized.")
    }
  }
}

/// set a fallback language
#let linguify_set_fallback_lang(lang) = {
  if lang != auto and lang != none {
    assert.eq(type(lang), str, message: "expected fallback lang to be a string, found " + type(lang))
  }
  __linguify_lang_fallback.update(lang)
}

/// set a preferred language.
///
/// ! warning: language from `set text(lang: "de")` is not detected if this is used.
/// you probably want this to stay auto
#let linguify_set_preferred_lang(lang) = {
  if lang != auto {
    assert.eq(type(lang), str, message: "expected overwrite lang to be a string, found " + type(lang))
  }
  __linguify_lang_preferred.update(lang);
}

/// update all settings at once
#let linguify_config(data: auto, lang: auto, fallback: auto) = {
  // set language data dictionary
  if data != auto {
    linguify_set_database(data)
  }

  // set fallback mode.
  linguify_set_fallback_lang(fallback)

  /// ! warning: language from `set text(lang: "de")` is not detected if this is used.
  /// you probably want this to stay auto
  linguify_set_preferred_lang(lang)
}

/// Helper function. 
/// if the value is auto "ret" is returned else the value self is returned
#let if-auto-then(val,ret) = {
  if (val == auto){
    ret
  } else { 
    val 
  }
}

/// fetch a string in the required lang.
///
/// - key (string): The key at which to retrieve the item.
/// - from (dictionary): database to fetch the item from. If auto linguify's global database will used.
/// - lang (string): the language to look for, if auto use `context text.lang` (default)
/// - default (any): A default value to return if the key is not part of the database.
#let linguify(key, from: auto, lang: auto, default: auto, args: auto) = {
  context {
    let database = if-auto-then(from,__linguify_lang_database.get())

    // check if database is not empty. Means no data dictionary was specified.
    assert(database != none, message: "linguify database is empty.")
    // get selected language.
    let selected_lang = if-auto-then(lang, if-auto-then(__linguify_lang_preferred.get(), text.lang))
    let lang_not_found = not selected_lang in database
    let fallback_lang = if-auto-then(__linguify_lang_fallback.get(), database.at("default-lang", default: none) )

    // get args
    let args = if-auto-then(args, database.at("args", default: (:)))

    // if available get the language section from the database if not try to get the fallback_lang entry.
    let lang_section = database.at(
      selected_lang,
      default: if (fallback_lang != none) { database.at(fallback_lang, default: none) } else { none }
    )

    // if lang_entry exists 
    if ( lang_section != none ) {
      // check if the value exits.
      let value = get_text(lang_section, key, default: none, args: args)
      if (value == none) {
        // info: fallback lang will not be used if given lang section exists but only a key is missing.
        // use this for a workaround: linguify("key", default: linguify("key", lang: "en", default: "key"));
        if (fallback_lang != none) {
          // check if fallback lang exists in database
          assert(database.at(fallback_lang, default: none) != none, message: "fallback lang (" + fallback_lang + ") does not exist in linguify database")

          let fallback_lang_section = database.at(fallback_lang)
          // check if key exists in fallback lang.
          let value = get_text(fallback_lang_section, key, default: none, args: args)
          assert(value != none, message: "key (" +  key + ") does not exist in fallback lang section.")
          return value
        }
        if (default != auto) {
          return default
        } else {
          if lang_not_found {
            panic("Could not find an entry for the key (" +  key + ") in the fallback section (" + fallback_lang + ") at the linguify database.")
          } else {
            panic("Could not find an entry for the key (" +  key + ") in the section (" + selected_lang + ") at the linguify database.")
          }
        }
      } else {
        return value
      }
    } else {
      if fallback_lang == none or selected_lang == fallback_lang {
        panic("Could not find a section for the language (" + selected_lang + ") in the linguify database.")
      } else {
        panic("Could not find a section for the language (" + selected_lang + ") or fallback language (" + fallback_lang + ") in the linguify database.")
      }
    }
  }
}
