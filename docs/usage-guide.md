# Руководство по использованию aimemory

## 1. Интеграция через MCP (Model Context Protocol)

MCP — протокол для подключения инструментов к AI-ассистентам. aimemory предоставляет tools через JSON API.

### 1.1 Настройка для Claude Desktop

Добавьте в `~/.config/claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "aimemory": {
      "command": "/path/to/aimemory",
      "args": ["--db", "/path/to/project/context.db", "mcp"],
      "env": {}
    }
  }
}
```

Возможные пути к `claude_desktop_config.json`:
- macOS: ~/Library/Application Support/Claude/claude_desktop_config.json
- Windows: %APPDATA%\Claude\claude_desktop_config.json
- Linux: ~/.config/Claude/claude_desktop_config.json

> Возможно вы никогда не делали локального подключения mcp. Вам могут помочь подсказки [отсюда](https://modelcontextprotocol.io/docs/develop/connect-local-servers#enoent-error-and-appdata-in-paths-on-windows)

### 1.2 Настройка для Claude Code

Добавьте в `.claude/settings.json` вашего проекта:

```json
{
  "mcpServers": {
    "aimemory": {
      "command": "aimemory",
      "args": ["--db", "./context.db", "mcp"]
    }
  }
}
```

### 1.3 Доступные MCP tools

После подключения AI получает доступ к инструментам:

| Tool | Описание |
|------|----------|
| `emit` | Сохранить сущности и связи |
| `query_entities` | Найти сущности по kind/pattern |
| `query_refs` | Найти связи между сущностями |
| `status` | Статистика: сколько entities, refs |

AI вызывает их автоматически когда нужно запомнить или вспомнить информацию о коде.


## 2. Интеграция через Bash + CLAUDE.md

Если MCP недоступен, можно использовать bash-команды напрямую.

### 2.1 Добавьте в CLAUDE.md проекта

```markdown
## Context Memory

Проект использует aimemory для хранения знаний о структуре кода.

### Команды

Сохранить информацию о коде:
\`\`\`bash
aimemory call emit '{"entities":[{"lid":"<kind>:<path>","data":{...},"refs":[...]}]}'
\`\`\`

Найти сущности:
\`\`\`bash
aimemory call query_entities '{"kind":"fn","pattern":"auth/*"}'
\`\`\`

Найти связи:
\`\`\`bash
aimemory call query_refs '{"source":"comp:LoginForm"}'
\`\`\`

Проверить статус:
\`\`\`bash
aimemory status
\`\`\`

### Правила использования

1. При анализе нового файла — сохраняй сущности через emit
2. Перед ответом на вопрос "кто использует X" — делай query_refs
3. Используй kind из списка: comp, fn, store, type, api, hook, composable
4. Связывай сущности через refs: calls, depends_on, contains, belongs_to

### Пример

Проанализировал `src/components/Button.vue`:
\`\`\`bash
aimemory call emit '{
  "entities": [
    {"lid": "comp:ui/Button", "data": {"file": "src/components/Button.vue", "props": ["variant", "disabled"]}},
    {"lid": "emit:ui/Button:click", "data": {}, "refs": [{"target": "comp:ui/Button", "rel": "belongs_to"}]}
  ]
}'
\`\`\`
```

### 2.2 Bash-обёртка для удобства

Создайте `scripts/ctx.sh`:

```bash
#!/bin/bash
DB="${CTX_DB:-./context.db}"

case "$1" in
  emit)
    aimemory --db "$DB" call emit "$2"
    ;;
  find)
    aimemory --db "$DB" call query_entities "{\"pattern\":\"$2\"}"
    ;;
  refs)
    aimemory --db "$DB" call query_refs "{\"source\":\"$2\"}"
    ;;
  status)
    aimemory --db "$DB" status
    ;;
  *)
    echo "Usage: ctx.sh {emit|find|refs|status} [args]"
    ;;
esac
```

В CLAUDE.md:
```markdown
Используй `./scripts/ctx.sh` для работы с контекстной памятью:
- `./scripts/ctx.sh find "auth/*"` — найти сущности
- `./scripts/ctx.sh refs "fn:login"` — найти связи
- `./scripts/ctx.sh status` — статистика
```


## 3. Расширение через npx AST-анализатор

aimemory хранит данные, но не анализирует код. Для автоматического анализа нужен отдельный инструмент.

### 3.1 Архитектура

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  AST Analyzer   │ --> │    aimemory     │ <-- │   AI Agent      │
│  (npx пакет)    │     │    (storage)    │     │  (Claude/GPT)   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
     парсит код          хранит сущности         запрашивает/
     извлекает           и связи                 дополняет
     структуру
```

### 3.2 Пример npx-пакета

Создайте пакет `aimemory-scanner`:

```json
// package.json
{
  "name": "aimemory-scanner",
  "bin": {
    "aimemory-analyze": "./bin/analyze.js"
  },
  "dependencies": {
    "@babel/parser": "^7.23.0",
    "@vue/compiler-sfc": "^3.4.0",
    "typescript": "^5.0.0"
  }
}
```

```javascript
// bin/analyze.js
#!/usr/bin/env node
const { parse } = require('@babel/parser');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const file = process.argv[2];
const db = process.env.CTX_DB || './context.db';

// Парсим файл
const code = fs.readFileSync(file, 'utf-8');
const ast = parse(code, { sourceType: 'module', plugins: ['typescript', 'jsx'] });

// Извлекаем сущности
const entities = [];
const baseName = path.basename(file, path.extname(file));

// Находим экспортированные функции
ast.program.body.forEach(node => {
  if (node.type === 'ExportNamedDeclaration' && node.declaration?.type === 'FunctionDeclaration') {
    const name = node.declaration.id.name;
    entities.push({
      lid: `fn:${baseName}/${name}`,
      data: {
        file,
        async: node.declaration.async,
        params: node.declaration.params.map(p => p.name || 'unknown')
      }
    });
  }
});

// Отправляем в aimemory
if (entities.length > 0) {
  const payload = JSON.stringify({ entities });
  execSync(`aimemory --db "${db}" call emit '${payload}'`);
  console.log(`Indexed ${entities.length} entities from ${file}`);
}
```

### 3.3 Использование

```bash
# Установка глобально
npm install -g aimemory-scanner

# Анализ файла
npx aimemory-analyze src/utils/auth.ts

# Анализ всего проекта
find src -name "*.ts" -exec npx aimemory-scanner {} \;
```

### 3.4 Интеграция с pre-commit

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: aimemory-index
        name: Index changed files
        entry: bash -c 'for f in "$@"; do npx aimemory-analyze "$f"; done' --
        language: system
        files: \.(ts|tsx|vue)$
```


## 4. Промпты для AI

### 4.1 Системный промпт для сбора информации

Добавьте в начало CLAUDE.md или system prompt:

```markdown
## Роль: Code Analyst

Ты анализируешь код и сохраняешь структурированную информацию в context memory.

### При анализе файла:

1. **Определи тип модуля** и создай главную сущность:
   - Vue компонент => `comp:<path>`
   - TypeScript модуль => по основной функции
   - Store => `store:<name>`

2. **Извлеки внутренние сущности**:
   - Функции => `fn:<module>/<name>`
   - Props => `prop:<component>/<name>`
   - Emits => `emit:<component>/<name>`
   - Computed => `computed:<module>/<name>`

3. **Установи связи**:
   - Импорт компонента => `contains`
   - Вызов функции => `calls`
   - Использование store => `depends_on`
   - Prop/emit => `belongs_to`

4. **Сохрани через emit** одним вызовом

### Формат данных:

```json
{
  "entities": [
    {
      "lid": "comp:auth/LoginForm",
      "data": {
        "file": "src/components/auth/LoginForm.vue",
        "description": "Форма входа с валидацией"
      },
      "refs": [
        {"target": "store:auth", "rel": "depends_on"},
        {"target": "comp:ui/Button", "rel": "contains"}
      ]
    }
  ]
}
```
```

### 4.2 Промпт для первичного анализа проекта

```
Проанализируй структуру проекта и создай карту сущностей.

Начни с:
1. Посмотри package.json — определи фреймворк и зависимости
2. Просмотри src/ — найди основные директории (components, stores, utils)
3. Для каждой ключевой директории:
   - Прочитай 2-3 файла
   - Сохрани сущности в context memory
   - Отметь связи между модулями

После анализа покажи:
- Сколько сущностей создано (aimemory status)
- Какие pending refs остались
- Что ещё стоит проанализировать
```

### 4.3 Промпт для анализа конкретного файла

```
Проанализируй файл {path} и сохрани в context memory:

1. Прочитай файл
2. Определи:
   - Какой это тип модуля (component/store/util/api)
   - Какие функции/методы экспортирует
   - Что импортирует (зависимости)
3. Создай сущности с правильными LID
4. Сохрани через emit
5. Покажи что сохранил
```

### 4.4 Промпт для ответа на вопросы о коде

```
Прежде чем ответить на вопрос о коде:

1. Сделай query_entities по релевантному pattern
2. Сделай query_refs чтобы найти связи
3. Если нужно — прочитай найденные файлы
4. Ответь на основе данных из memory + файлов

Если информации в memory нет — скажи что нужно сначала проанализировать.
```

### 4.5 Промпты для типичных задач

**Найти все использования функции:**
```
Найди все места где используется функция {name}:
1. query_refs с target="fn:{name}" чтобы найти кто вызывает
2. Покажи список вызывающих с указанием файлов
```

**Понять зависимости компонента:**
```
Покажи зависимости компонента {name}:
1. query_refs с source="comp:{name}" — что он использует
2. query_refs с target="comp:{name}" — кто его использует
3. Построй граф зависимостей
```

**Найти похожие компоненты:**
```
Найди компоненты похожие на {name}:
1. query_entities с pattern="{category}/*"
2. Сравни data полей (props, emits)
3. Покажи общие паттерны
```


## 5. Рекомендуемый workflow

### 5.1 Начало работы с проектом

```
1. Инициализируй базу:
   aimemory --db ./context.db status

2. Попроси AI проанализировать структуру:
   "Проанализируй проект, начни с package.json и src/"

3. AI создаст первичную карту сущностей

4. Проверь статус:
   aimemory status
```

### 5.2 Ежедневная работа

```
1. При работе с файлом — AI автоматически обновляет memory
2. При вопросах — AI сначала проверяет memory
3. При code review — AI показывает связи изменённых файлов
```

### 5.3 Поддержание актуальности

```
1. Настрой pre-commit hook для автоиндексации
2. Периодически запускай: aimemory status
3. Если много pending refs — попроси AI доанализировать
```
