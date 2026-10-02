"""Check translation coverage, plural forms, and format argument safety.

Run on Windows, Linux, or in CI; Xcode compiles the catalog on macOS. This
focused source audit recognizes the app's SwiftUI and deferred-message APIs.
Dictionary content, SF Symbols, URLs, and preview fixture data are excluded.
"""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
FORMAT = re.compile(r"%(?:(\d+)\$)?(lld|ld|d|@)")


def string_end(source, start):
    i = start + 1
    while i < len(source):
        if source[i:i+2] == "\\(":
            i = expression_end(source, i + 1) + 1
        elif source[i] == "\\":
            i += 2
        elif source[i] == '"':
            return i + 1
        else:
            i += 1
    raise AssertionError("Unterminated Swift string")


def expression_end(source, start, first_argument=False):
    depth, i = 1, start + 1
    while i < len(source):
        if source[i] == '"':
            i = string_end(source, i)
            continue
        if source[i] == '(': depth += 1
        elif source[i] == ')':
            depth -= 1
            if depth == 0: return i
        elif first_argument and source[i] == ',' and depth == 1:
            return i
        i += 1
    raise AssertionError("Unterminated Swift call")


def localized_key(raw):
    result, i = '', 0
    while i < len(raw):
        if raw[i:i+2] == "\\(":
            end = expression_end(raw, i + 1)
            argument = raw[i+2:end]
            integer = re.search(r"\b(?:count|entryCount|resourceCount|repetitions|completed|total|method)\b", argument)
            result += '%lld' if integer else '%@'
            i = end + 1
        else:
            result += raw[i]
            i += 1
    return json.loads('"' + result + '"')


def literals(expression):
    i = 0
    while i < len(expression):
        if expression[i] == '"':
            end = string_end(expression, i)
            yield localized_key(expression[i+1:end-1])
            i = end
        else:
            i += 1


def source_keys(path):
    source = path.read_text(encoding='utf-8').split('#Preview')[0]
    calls = r'\b(?:Text|Label|Button|Picker|TextField|SecureField|ProgressView|ContentUnavailableView|LocalizedStringKey|FolioMessage|sectionLabel|accessibilityLabel|accessibilityValue|alert|confirmationDialog|navigationTitle)\s*\('
    for match in re.finditer(calls, source):
        start = source.index('(', match.start())
        end = expression_end(source, start, first_argument=True)
        expression = source[start+1:end].strip()
        if expression.startswith(('verbatim:', 'phonetic', 'value.translations', 'String(format:')):
            continue
        yield from literals(expression)
    for match in re.finditer(r'\bEditorialHeader\s*\(', source):
        start = source.index('(', match.start())
        yield from literals(source[start+1:expression_end(source, start)])
    for match in re.finditer(r'fallback:\s*("(?:[^"\\]|\\.)*")', source):
        yield json.loads(match[1])
    # Accent labels are runtime keys, passed into a reusable pronunciation row.
    for match in re.finditer(r'accent:\s*"(UK|US|EN)"', source):
        yield match[1]
    if 'Sources/FolioCore/Dictionary/' in path.as_posix():
        for match in re.finditer(r'MDictError\.(?:malformed|unsupported)\(', source):
            start = source.index('(', match.start())
            yield from literals(source[start+1:expression_end(source, start, first_argument=True)])


def units(value):
    if 'stringUnit' in value:
        yield value['stringUnit']
    for plural in value.get('variations', {}).values():
        for variation in plural.values():
            yield from units(variation)


def placeholders(value):
    # Match arguments by position so translators can reorder them safely.
    return sorted((int(position) if position else index, kind)
                  for index,(position,kind) in enumerate(FORMAT.findall(value), start=1))


def validate():
    catalog = json.loads((ROOT / 'Folio/Resources/Localizable.xcstrings').read_text(encoding='utf-8'))
    assert catalog['sourceLanguage'] == 'en'
    strings = catalog['strings']
    for key, entry in strings.items():
        for language in ['en', 'zh-Hans']:
            value = entry['localizations'][language]
            translated = list(units(value))
            assert translated, f'Empty translation: {key}, {language}'
            for unit in translated:
                assert unit['state'] == 'translated' and unit['value'], f'Untranslated: {key}, {language}'
                assert placeholders(unit['value']) == placeholders(key), f'Format mismatch: {key}, {language}'
            if 'variations' in value:
                forms = value['variations']['plural']
                assert 'other' in forms and (language != 'en' or 'one' in forms), f'Missing plural: {key}'
    missing = []
    paths = list((ROOT/'Folio').rglob('*.swift')) + list((ROOT/'Sources/FolioCore').rglob('*.swift'))
    for path in paths:
        for key in source_keys(path):
            if key and key not in strings:
                missing.append(f'{path.relative_to(ROOT)}: {key}')
    for path, boundary in [('Localization/AppLanguage.swift', 'public func resolvedIdentifier'),
                           ('Domain/VocabularyCard.swift', 'public enum LearningState'), ('Online/YoudaoConfiguration.swift', 'var endpoint:')]:
        source = (ROOT/'Sources/FolioCore'/path).read_text(encoding='utf-8')
        if 'var title:' in source:
            titles = source.split('var title:',1)[1]
            if boundary: titles = titles.split(boundary)[0]
            missing += [f'{path}: {key}' for key in literals(titles) if key not in strings]
    assert not missing, 'Missing catalog entries:\n' + '\n'.join(sorted(set(missing)))
    appearance = (ROOT/'Folio/Settings/AppAppearanceManager.swift').read_text(encoding='utf-8')
    for key in literals(appearance.split('var title:', 1)[1].split('var colorScheme:', 1)[0]):
        assert key in strings, f'Missing appearance localization: {key}'
    print(f'Validated {len(strings)} bilingual strings, plural forms, format arguments, and source coverage.')


if __name__ == '__main__':
    validate()
