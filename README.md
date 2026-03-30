# aimemory

Контекстная память для AI-агентов. SQLite-хранилище сущностей кода и связей между ними.

**Версия:** 0.1.0

## Недавние изменения

### Логирование (`lib/support/`)
- Новый модуль `Log` на базе `logs` + `fmt`
- Логи пишутся в файл `<db_name>.log` (например, `context.log` для `context.db`)
- CLI флаги: `--verbose` (debug), `--quiet` (только stderr ошибки)

### Property-based тесты
- Добавлены `qcheck-core` и `qcheck-ounit`
- Новые тесты: `test/test_prop.ml`, `test/test_log.ml`

### CLI улучшения
```bash
aimemory --verbose call emit '...'  # debug logging
aimemory --quiet status             # без логов
aimemory --db custom.db status      # кастомный путь
```

### Улучшенные tool descriptions
- Расширенные enum-описания для AI в `query_entities` и `query_refs`
- Более детальные описания relationship types

### Рефакторинг
- JSON конвертеры (`value_to_json`/`json_to_value`) перенесены в `Repo`
- `glob_matches` убран из Resolver — используется SQL LIKE
- Сокращены комментарии в domain layer (убраны verbose примеры)

## Зачем это нужно

AI-агент анализирует код и сохраняет информацию о структуре проекта: компоненты, функции, хуки, сторы. Когда агент видит новый файл, он может спросить: "кто использует эту функцию?" или "какие компоненты зависят от этого стора?".

Сейчас система заточена под **фронтенд-проекты** (Vue/React). Kind-типы отражают типичную архитектуру: `comp`, `view`, `store`, `composable`, `hook` и т.д. При необходимости можно расширить набор kind под свой стек.

## Архитектурные решения (ADR)

Ключевые решения задокументированы в [docs/adr/](docs/adr/):

| ADR | Решение |
|-----|---------|
| [001](docs/adr/001-lid-format.md) | Формат LID (`kind:path`) вместо UUID |
| [002](docs/adr/002-pending-refs.md) | Pending refs как нормальное состояние |
| [003](docs/adr/003-flat-entity-data.md) | Плоская структура entity.data |
| [004](docs/adr/004-type-contracts.md) | Type contracts (raw vs processed) |
| [005](docs/adr/005-layered-architecture.md) | Слоистая архитектура |
| [006](docs/adr/006-typed-errors.md) | Типизированные ошибки |
| [007](docs/adr/007-pagination.md) | Пагинация запросов |

## Руководство по интеграции

Подробное руководство по использованию: **[docs/usage-guide.md](docs/usage-guide.md)**

- MCP интеграция с Claude Desktop / Claude Code
- Bash-скрипты и CLAUDE.md
- Расширение через npx AST-анализатор
- Промпты для AI-агентов

## Архитектура

```
┌─────────────────────────────────────────────────────────┐
│                      API Layer                          │
│  Tools.dispatch: JSON => Protocol.command => JSON result  │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                    Engine Layer                         │
│  Ingest: обрабатывает команды, оркестрирует pipeline    │
│  Resolver: резолвит pending refs, glob-запросы          │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                   Storage Layer                         │
│  Repo: SQLite CRUD, транзакции, миграции                │
│  Schema: DDL таблиц entities, refs, meta                │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                    Domain Layer                         │
│  Lid: kind:path идентификаторы (comp:ui/Button)         │
│  Entity: raw => processed с timestamps                   │
│  Ref: pending => resolved связи между сущностями         │
│  Protocol: command/response типы для AI                 │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                   Support Layer                         │
│  Log: структурированное логирование в файл              │
└─────────────────────────────────────────────────────────┘
```

## Почему OCaml

**Не Go:** Задача — классифицировать сущности (`comp`, `store`, `fn`...) и связи (`calls`, `depends_on`...). В Go это строки — опечатался и узнал в runtime. В OCaml это варианты — добавил новый kind, компилятор показал все места где забыл обработать.

**Не Rust:** Та же type safety, но без борьбы с borrow checker. Здесь нет сложного управления памятью — данные пришли, сохранились в SQLite, ушли. Lifetime annotations были бы чистым оверхедом.

**Итог:** Exhaustive pattern matching + ADT = компилятор ловит забытые случаи. Для domain-heavy кода с фиксированным набором категорий — то что нужно.

## Ключевые концепции

### LID (Logical ID)

Уникальный идентификатор сущности: `kind:path`

```
comp:ui/Button        — компонент
fn:useAuth:login      — функция внутри composable
store:cart            — Pinia store
type:UserDto          — TypeScript тип
dep:lodash            — внешняя зависимость
```

### Kind (тип сущности)

Текущий набор оптимизирован под Vue/фронтенд:

**Уровень модуля:**
- `comp` — компонент
- `view` — страница роутера
- `layout` — layout-обёртка
- `store` — Pinia/Vuex store
- `composable` — Vue composable
- `service` — сервисный слой
- `util` — утилиты
- `api` — API endpoint
- `dep` — npm-пакет

**Уровень внутри модуля:**
- `fn` — функция/метод
- `state` — реактивное состояние
- `computed` — вычисляемое свойство
- `action` — action в сторе
- `prop` — входной пропс
- `emit` — событие компонента
- `hook` — lifecycle hook
- `type` — TypeScript тип/интерфейс

### Ref (связь)

Направленная связь между двумя сущностями:

```
Button -[calls]-> fetchUsers
useAuth -[depends_on]-> authStore
Modal -[contains]-> CloseButton
```

Типы связей: `belongs_to`, `calls`, `depends_on`, `contains`, `implements`, `references`

### Pending vs Resolved

AI может описывать код в любом порядке. Если связь ссылается на несуществующую сущность — она сохраняется как `pending`. Когда целевая сущность появится — связь автоматически станет `resolved`.

## Использование

### CLI

```bash
# Сохранить сущность
aimemory call emit '{"entities":[{"lid":"fn:auth/login","data":{"async":true}}]}'

# Запросить все функции
aimemory call query_entities '{"kind":"fn"}'

# Найти связи от сущности
aimemory call query_refs '{"source":"fn:auth/login"}'

# Статус базы
aimemory status

# Сбросить базу
aimemory reset

# С логированием
aimemory --verbose call emit '...'
aimemory --quiet status
```

### MCP Tools

Система предоставляет tool-схемы для интеграции с AI:

```bash
aimemory schemas
```

Tools:
- `emit` — upsert сущностей со связями
- `query_entities` — поиск по kind/pattern
- `query_refs` — поиск связей
- `status` — диагностика (сколько entities, resolved/pending refs)

## Расширение под свой стек

Kind-типы определены в `lib/domain/lid.ml`. Для адаптации под другой стек (например, backend на Go):

1. Замените kind-варианты на свои: `Handler`, `Repository`, `Service`, `Model`, etc.
2. Обновите `prefix_of_kind` и `kind_of_prefix`
3. AI-агент будет ориентироваться на эти типы при анализе кода

## Сборка и тесты

```bash
# Сборка
dune build

# Тесты
dune runtest

# Запуск
dune exec aimemory -- status
```

## Лицензия

MIT
