# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added
- Fix dashes in simple ranges like "10-20" in favor of broken minuses
in math. We aren't likely to face them.

### Changed
- Update TravisCI configuration.
- Add RSpec tests as default Rake task.
- Improved README content, fixed broken formating.
- Report CodeClimate for the coverage.
- Actualize RSpec config and fix failed tests.
- Add binaries for setup and console.

### Fixed
- Fix tests to run with current RSpec version.
- Changed Changelog format to respect https://keepachangelog.com/en/1.0.0/ recommendations.

## [3.0.2]
### Fixed
- Исправлен баг замены троеточия при последующем символе пунктуации

## [3.0.1]
### Fixed
- Испрвлен баг с необработкой кавычек процессором `quotes` используя метод `prepare`

## [3.0.0]
### Changed
- Gem был полностью переписан.
- Изменён метод доступа к отдельным процессорам. Теперь используется единый метод `processor`, вместо отдельных именованных методов. Например: `typograf.fractions` заменется на `typograf.processor(:fractions)`,  `typograf.quotes` заменется на `typograf.processor(:quotes)` и т.д.
- Процессор `signs` переименован на `mnemonics`
- Процессор `dots` переименован на `ellipsis`
- Процессор `nbspace` переименован на `nbspaces`
- Убраны инициализационные параметры типографа: `signs` и `quotes`

### Added
- Замена дробей изменена на html-code вместо utf-символа, что делает возможным замену любого дробного числового значения.
- Добавлен инициализационный параметр `mode`. Возмодные режимы: `:html` (подстановка html-кода символа), `:utf` (подстановка utf символа)

## [2.0.2]
