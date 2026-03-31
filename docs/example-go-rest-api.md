# Example: Go REST API for an Order Service

A Go backend project: HTTP handlers, service layer, repositories, DB migrations, background workers. Frontend kinds (Comp, View, Composable, ...) are not needed.

## Step 1: Choose your vocabulary

Kinds — entity types in the codebase:

```
Remove:  Comp, View, Layout, Composable, Prop, Emit, Hook, Provide, Style, Locale, Asset
Keep:    Fn, Util, Api, Dep, Typ, Service, Route, Const, E2e, Unit, Store
Add:     Pkg, Handler, Middleware, Repo, Migration, Job
```

Relations — keep the defaults, add one:

```
Keep: Belongs_to, Calls, Depends_on, Contains, Implements, References
Add:  Wraps (middleware wraps handler)
```

## Step 2: Edit `lid.ml` and `ref.ml`

In `lid.ml` — add 6 variants (`Pkg`, `Handler`, `Middleware`, `Repo`, `Migration`, `Job`), remove 11 frontend variants. In `ref.ml` — add `Wraps`.

See [customization guide](customization-guide.md) for step-by-step instructions.

## Step 3: Build

```bash
dune build && dune install
aimemory reset    # old database with old kinds is not valid anymore
```

## Step 4: Fill the graph

The order service looks like this:

```
internal/
  order/
    handler.go      — HTTP handlers (CreateOrder, GetOrder, CancelOrder)
    service.go      — business logic (Create, Cancel, FindByID)
    repo.go         — SQL queries (Insert, Update, FindByID)
    model.go        — types Order, OrderStatus
  auth/
    middleware.go   — AuthMiddleware (checks JWT)
  worker/
    notification.go — NotifyWorker (sends email after order)
  migration/
    003_orders.sql  — orders table
```

AI emits entities:

```bash
aimemory call emit '{
  "entities": [
    {"lid": "pkg:order",         "data": {"path": "internal/order"}},
    {"lid": "handler:order/create", "data": {"method": "POST", "path": "/api/orders", "file": "handler.go", "line": 15}},
    {"lid": "handler:order/get",    "data": {"method": "GET",  "path": "/api/orders/:id"}},
    {"lid": "handler:order/cancel", "data": {"method": "POST", "path": "/api/orders/:id/cancel"}},
    {"lid": "service:order",     "data": {"file": "service.go"}},
    {"lid": "fn:order/Create",   "data": {"file": "service.go", "line": 22, "receiver": "OrderService"}},
    {"lid": "fn:order/Cancel",   "data": {"file": "service.go", "line": 58}},
    {"lid": "fn:order/FindByID", "data": {"file": "service.go", "line": 89}},
    {"lid": "repo:order",        "data": {"file": "repo.go", "table": "orders"}},
    {"lid": "typ:Order",         "data": {"file": "model.go", "line": 5}},
    {"lid": "typ:OrderStatus",   "data": {"file": "model.go", "line": 20, "values": "pending,confirmed,cancelled"}},
    {"lid": "middleware:auth",   "data": {"file": "auth/middleware.go"}},
    {"lid": "job:notification",  "data": {"file": "worker/notification.go", "trigger": "order.created"}},
    {"lid": "migration:003_orders", "data": {"file": "migration/003_orders.sql"}},
    {"lid": "dep:pgx",           "data": {"version": "v5.5.0"}},
    {"lid": "dep:chi",           "data": {"version": "v5.0.11"}}
  ]
}'
```

AI emits relations:

```bash
aimemory call emit '{
  "entities": [
    {"lid": "handler:order/create", "refs": [
      {"target": "fn:order/Create",  "rel": "calls"},
      {"target": "pkg:order",        "rel": "belongs_to"}
    ]},
    {"lid": "fn:order/Create", "refs": [
      {"target": "repo:order",       "rel": "calls"},
      {"target": "typ:Order",        "rel": "references"},
      {"target": "service:order",    "rel": "belongs_to"}
    ]},
    {"lid": "repo:order", "refs": [
      {"target": "dep:pgx",          "rel": "depends_on"},
      {"target": "migration:003_orders", "rel": "references"}
    ]},
    {"lid": "middleware:auth", "refs": [
      {"target": "handler:order/create", "rel": "wraps"},
      {"target": "handler:order/cancel", "rel": "wraps"}
    ]},
    {"lid": "job:notification", "refs": [
      {"target": "fn:order/Create",  "rel": "references"}
    ]}
  ]
}'
```

## Step 5: Query the graph

Now AI can answer questions about code relations:

```bash
# What does the create handler call?
aimemory call query_refs '{"source": "handler:order/create", "rel": "calls"}'
# → fn:order/Create

# What is behind auth middleware?
aimemory call query_refs '{"source": "middleware:auth", "rel": "wraps"}'
# → handler:order/create, handler:order/cancel

# Who depends on pgx?
aimemory call query_refs '{"target": "dep:pgx", "rel": "depends_on"}'
# → repo:order

# All handlers
aimemory call query_entities '{"kind": "handler"}'
# → order/create, order/get, order/cancel

# What breaks if we change the Order type?
aimemory call query_refs '{"target": "typ:Order"}'
# → fn:order/Create (references)
```

The relation graph helps AI understand impact: "if we change `typ:Order`, it affects `fn:order/Create` → `handler:order/create` → `middleware:auth`".
