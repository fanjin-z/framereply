#!/usr/bin/env python3

import argparse
import copy
import json
import re
import sys
from pathlib import Path


PLACEHOLDER_PATTERN = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|f|@)|\$\{[^}]+\}")


class CatalogValidationError(Exception):
    pass


def string_units(value, path=()):
    if isinstance(value, dict):
        unit = value.get("stringUnit")
        if isinstance(unit, dict):
            yield path, unit
        for key, child in value.items():
            if key != "stringUnit":
                yield from string_units(child, path + (key,))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from string_units(child, path + (str(index),))


def placeholder_signature(value):
    return tuple(sorted(PLACEHOLDER_PATTERN.findall(value)))


def source_signatures(key, entry, source_language):
    source = entry.get("localizations", {}).get(source_language)
    if source is None:
        return {placeholder_signature(key)}
    units = list(string_units(source))
    if not units:
        raise CatalogValidationError(f"{key}: source localization has no string units")
    signatures = set()
    for _, unit in units:
        value = unit.get("value")
        if not isinstance(value, str) or not value:
            raise CatalogValidationError(f"{key}: source localization contains an empty value")
        signatures.add(placeholder_signature(value))
    return signatures


def validate_catalog(catalog, supported_languages):
    source_language = catalog.get("sourceLanguage")
    if not isinstance(source_language, str) or not source_language:
        raise CatalogValidationError("Catalog sourceLanguage is missing")
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        raise CatalogValidationError("Catalog strings object is missing")

    target_languages = [
        language for language in supported_languages if language != source_language
    ]
    for key, entry in strings.items():
        if entry.get("shouldTranslate", True) is False:
            continue
        signatures = source_signatures(key, entry, source_language)
        localizations = entry.get("localizations", {})
        for language in target_languages:
            localization = localizations.get(language)
            if localization is None:
                raise CatalogValidationError(f"{language}: missing translation for {key}")
            units = list(string_units(localization))
            if not units:
                raise CatalogValidationError(
                    f"{language}: {key} has no translated string or plural variants"
                )
            for path, unit in units:
                label = ".".join(path) or "stringUnit"
                value = unit.get("value")
                if not isinstance(value, str) or not value:
                    raise CatalogValidationError(
                        f"{language}: {key} ({label}) contains an empty translation"
                    )
                state = unit.get("state")
                if state != "translated":
                    raise CatalogValidationError(
                        f"{language}: {key} ({label}) has unapproved state {state!r}"
                    )
                signature = placeholder_signature(value)
                if signature not in signatures:
                    raise CatalogValidationError(
                        f"{language}: {key} ({label}) has placeholders {signature}, "
                        f"expected one of {sorted(signatures)}"
                    )


def translated_copy(value):
    result = copy.deepcopy(value)
    for _, unit in string_units(result):
        unit["state"] = "translated"
    return result


def add_complete_locale(catalog, language):
    source_language = catalog["sourceLanguage"]
    for key, entry in catalog["strings"].items():
        if entry.get("shouldTranslate", True) is False:
            continue
        localizations = entry.setdefault("localizations", {})
        source = localizations.get(source_language)
        if source is None:
            localizations[language] = {
                "stringUnit": {"state": "translated", "value": key}
            }
        else:
            localizations[language] = translated_copy(source)


def first_unit(catalog, key, language):
    localization = catalog["strings"][key]["localizations"][language]
    return next(string_units(localization))[1]


def expect_failure(name, catalog, languages):
    try:
        validate_catalog(catalog, languages)
    except CatalogValidationError:
        return
    raise CatalogValidationError(f"Self-test {name!r} unexpectedly passed")


def run_self_tests(base_catalog):
    complete = copy.deepcopy(base_catalog)
    add_complete_locale(complete, "es")
    validate_catalog(complete, [base_catalog["sourceLanguage"], "es"])

    key = "chat.fallback.title"
    missing = copy.deepcopy(complete)
    del missing["strings"][key]["localizations"]["es"]
    expect_failure("missing translation", missing, ["en", "es"])

    empty = copy.deepcopy(complete)
    first_unit(empty, key, "es")["value"] = ""
    expect_failure("empty translation", empty, ["en", "es"])

    unreviewed = copy.deepcopy(complete)
    first_unit(unreviewed, key, "es")["state"] = "needs_review"
    expect_failure("unreviewed translation", unreviewed, ["en", "es"])

    new_translation = copy.deepcopy(complete)
    first_unit(new_translation, key, "es")["state"] = "new"
    expect_failure("new translation", new_translation, ["en", "es"])

    stale = copy.deepcopy(complete)
    first_unit(stale, key, "es")["state"] = "stale"
    expect_failure("stale translation", stale, ["en", "es"])

    malformed_plural = copy.deepcopy(complete)
    malformed_plural["strings"]["import.added-messages"]["localizations"]["es"] = {
        "variations": {"plural": {"other": {}}}
    }
    expect_failure("malformed plural", malformed_plural, ["en", "es"])

    placeholder = copy.deepcopy(complete)
    first_unit(placeholder, "chat.merge.candidate.alias", "es")["value"] = "%1$@ only"
    expect_failure("placeholder mismatch", placeholder, ["en", "es"])

    print("Localization validator self-tests passed.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument("--languages", default="")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    try:
        with args.catalog.open(encoding="utf-8") as handle:
            catalog = json.load(handle)
        if args.self_test:
            run_self_tests(catalog)
        else:
            languages = [item for item in args.languages.split(",") if item]
            validate_catalog(catalog, languages)
    except (CatalogValidationError, json.JSONDecodeError, OSError) as error:
        print(f"Localization validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
