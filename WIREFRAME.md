# shortcoder-rag — Wireframe da TUI Melhorada

## Tela Inicial (Banner Expandido)

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                                                                               │
│    ▍ shortcoder-rag                                                           │
│                                                                               │
│    TUI de terminal para o little-coder + RAG Protheus                         │
│                                                                               │
│    modelo:    qwen2.5-coder:7b                                                 │
│    sessao:    shortcoder-20260802-143522                                       │
│    agente:    [LLM]  ←  (pressione /agent para trocar)                         │
│    colecao:   advpl_sources                                                    │
│    mem0:      default                                                          │
│                                                                               │
│    /agent troca agente · /model troca modelo · /rag advpl <pergunta>           │
│    /mem0 add <texto> · /history · /clear · /help · /exit                       │
│                                                                               │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Turno com Agente LLM (little-coder)

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                                                                               │
│  ╭─ você — 244 —────────────────────────────────────────────────────────╮     │
│  │ Como criar uma funcao que consulta a tabela SE1?                       │     │
│  ╰────────────────────────────────────────────────────────────────────────╯     │
│                                                                               │
│  ╭─ ollama/qwen2.5-coder:7b — 39 —──────────────────────────────────────╮    │
│  │ Para consultar a tabela **SE1** em AdvPL, use:                          │     │
│  │                                                                         │     │
│  │     DbQuery("SELECT * FROM SE1_" + xFilial('SE1') +                     │     │
│ |       " WHERE E1_FILIAL = '" + xFilial('SE1') + "'" +                   │     │
│  │       " AND D_E_L_E_T_ = ' '")                                          │     │
│  │                                                                         │     │
│  │ Lembre-se de sempre filtrar por **filial** e **D_E_L_E_T_**.            │     │
│  ╰────────────────────────────────────────────────────────────────────────╯    │
│                                                                               │
│  1,247 tok in · 89 tok out · 12.3s          [ollama/qwen2.5-coder:7b]         │
│                                                                               │
│  ╭─ você — 244 —────────────────────────────────────────────────────────╮     │
│  │ E se quiser usar FWExecStatement?                                      │     │
│  ╰────────────────────────────────────────────────────────────────────────╯     │
│                                                                               │
│  ╭─ ollama/qwen2.5-coder:7b — 39 —──────────────────────────────────────╮    │
│  │ Usando **FWExecStatement** (recomendado):                               │     │
│  │                                                                         │     │
│  │     Local cQuery := [SELECT * FROM SE1_%(E1_FILIAL)                    │     │
│  │                   WHERE E1_FILIAL = '%(E1_FILIAL)'                     │     │
│  │                   AND D_E_L_E_T_ = ' ']                                 │     │
│  │                                                                         │     │
│  │     FWExecStatement(cQuery)                                             │     │
│  ╰────────────────────────────────────────────────────────────────────────╯    │
│                                                                               │
│  1,340 tok in · 67 tok out · 8.7s           [ollama/qwen2.5-coder:7b]         │
│                                                                               │
│  ❯ _                                                                         │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Turno com Agente RAG (consulta direta)

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                                                                               │
│  ╭─ você — 244 —────────────────────────────────────────────────────────╮     │
│  │ O que e o campo A1_COD da tabela SA1?                                  │     │
│  ╰────────────────────────────────────────────────────────────────────────╯     │
│                                                                               │
│  ╭─ advpl_sources — 39 —────────────────────────────────────────────────╮    │
│  │ 5 resultados:                                                          │    │
│  │                                                                        │    │
│  │ [1] Fonte: MATA010.prw, linha 45                                       │    │
│  │  A1_COD é o código do cliente.                                        │    │
│  │  Utilizado para identificação única na tabela SA1.                    │    │
│  │                                                                        │    │
│  │ [2] Fonte: SX3_SA1.ch                                                  │    │
│  │  Campo: A1_COD                                                        │    │
│  │  Título: Código do Cliente                                             │    │
│  │  Tipo: Character, Tamanho: 6                                           │    │
│  │  Chave Primária: Sim                                                    │    │
│  │                                                                        │    │
│  │ [3] Fonte: A1 integral                                                 │    │
│  │  A1_COD CHARACTER(6) NOT NULL,  -- Código do cliente                  │    │
│  │  PRIMARY KEY (A1_FILIAL, A1_COD)                                       │    │
│  │                                                                        │    │
│  │ [4] Fonte: MATA010.prw, linha 120                                      │    │
│  │  Seek(A1_COD)                                                         │    │
│  │  // Busca por código do cliente na tabela SA1                          │    │
│  │                                                                        │    │
│  │ [5] Fonte: SGAX100.prw                                                │    │
│  │  // Validação de código do cliente antes de inclusao                   │    │
│  │  If A1_COD == ""                                                      │    │
│  │      MsgAlert("Codigo do cliente e obrigatoria!")                     │    │
│  │  EndIf                                                                 │    │
│  ╰────────────────────────────────────────────────────────────────────────╯    │
│                                                                               │
│  rag/advpl_sources · 0.4s · fast                                              │
│                                                                               │
│  ❯ _                                                                         │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Turno com Agente RAG — Dicionario Protheus

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                                                                               │
│  ╭─ você — 244 —────────────────────────────────────────────────────────╮     │
│  │ Indices da tabela SE1                                                  │     │
│  ╰────────────────────────────────────────────────────────────────────────╯     │
│                                                                               │
│  ╭─ dicionario_protheus — 46 —──────────────────────────────────────────╮    │
│  │ 3 indices encontrados:                                                 │    │
│  │                                                                        │    │
│  │ [1] SIX_ORDEM: 1                                                       │    │
│  │  Indice: SE1_X1_COD                                               │    │
│  │  Campos: E1_FILIAL, E1_COD                                          │    │
│  │  Tipo: Unique                                                        │    │
│  │                                                                        │    │
│  │ [2] SIX_ORDEM: 2                                                       │    │
│  │  Indice: SE1_X2_NOME                                              │    │
│  │  Campos: E1_FILIAL, E1_NOME                                         │    │
│  │  Tipo: Nao-unique                                                    │    │
│  │                                                                        │    │
│  │ [3] SIX_ORDEM: 3                                                       │    │
│  │  Indice: SE1_X3_DOC                                               │    │
│  │  Campos: E1_FILIAL, E1_DOC                                          │    │
│  │  Tipo: Nao-unique                                                    │    │
│  ╰────────────────────────────────────────────────────────────────────────╯    │
│                                                                               │
│  rag/dicionario_protheus · 0.3s · fast                                         │
│                                                                               │
│  ❯ _                                                                         │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Turno com Agente Mem0

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                                                                               │
│  ╭─ mem0/list — 148 —───────────────────────────────────────────────────╮    │
│  │ 4 memorias:                                                            │    │
│  │                                                                        │    │
│  │ [fact] conf:1.00                                                       │    │
│  │  O usuario prefere usar TLPP para codigos novos                        │    │
│  │                                                                        │    │
│  │ [fact] conf:0.95                                                       │    │
│  │  O compilador AdvPP esta em ~/Projetos/AdvPP                           │    │
│  │                                                                        │    │
│  │ [preference] conf:1.00                                                 │    │
│  │  O usuario prefere interacoes em portugues brasileiro                   │    │
│  │                                                                        │    │
│  │ [fact] conf:0.87                                                       │    │
│  │  O shortcoder opera sobre o little-coder como subprocesso                │    │
│  ╰────────────────────────────────────────────────────────────────────────╯    │
│                                                                               │
│  mem0/default · 0.2s · 4 memorias                                              │
│                                                                               │
│  ❯ _                                                                         │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Comando /history

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                                                                               │
│  ╭─ historico — 244 —────────────────────────────────────────────────────╮    │
│  │ 5 turnos:                                                               │    │
│  │                                                                         │    │
│  │ [1] agente=rag/advpl_sources | tempo=0.4s                               │    │
│  │     O que e o campo A1_COD da tabela SA1?                               │    │
│  │                                                                         │    │
│  │ [2] agente=llm                         | tempo=12.3s                    │    │
│  │     Como criar uma funcao que consulta a tabela SE1?                    │    │
│  │                                                                         │    │
│  │ [3] agente=mem0/add                    | tempo=0.2s                      │    │
│  │     O usuario prefere TLPP para codigos novos                           │    │
│  │                                                                         │    │
│  │ [4] agente=rag/dicionario_protheus  | tempo=0.3s                         │    │
│  │     Indices da tabela SE1                                               │    │
│  │                                                                         │    │
│  │ [5] agente=mem0/list                 | tempo=0.2s                        │    │
│  │     (sem pergunta)                                                       │    │
│  ╰─────────────────────────────────────────────────────────────────────────╯    │
│                                                                               │
│  ❯ _                                                                         │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Indicadores de Loading por Agente

### RAG (busca rapida)
```
╭─ advpl_sources — 39 —──────────────────────────────────────────────╮
│ Buscando na base Protheus... [████████████░░░░] 75%                 │
╰──────────────────────────────────────────────────────────────────────╯
```

### LLM (streaming)
```
╭─ ollama/qwen2.5 — 39 —───────────────────────────────────────────╮
│ Para consultar a tabela SE1, use DbQuery...                       │
│ [streaming ao vivo]                                                │
╰────────────────────────────────────────────────────────────────────╯
```

### Mem0 (operacao)
```
╭─ mem0/add — 148 —───────────────────────────────────────────────╮
│ Memorizando... ✓                                                │
╰───────────────────────────────────────────────────────────────────╯
```

## Esquema de Cores por Agente

| Agente | Cor ANSI | Uso |
|--------|----------|-----|
| `ollama/*` | `39` (cyan) | LLM local — padrao |
| `ernesto/*` | `212` (pink) | LLM + RAG composite |
| `rag/advpl_sources` | `39` (cyan) | RAG AdvPL |
| `rag/dicionario_protheus` | `46` (dark cyan) | RAG Dicionario |
| `rag/reversa_sources` | `141` (gold) | RAG Reversa |
| `rag/all` | `141` (gold) | RAG Multipla |
| `mem0/*` | `148` (green cyan) | Memoria persistente |

## Estados de Erro

### Servico indisponivel
```
╭─ rag/advpl_sources — 196 —──────────────────────────────────────────╮
│ Erro: ernesto-rag-proxy nao respondendo em 127.0.0.1:9080           │
│ Verifique se o servico esta rodando:                                 │
│   systemctl --user status ernesto-rag-proxy                          │
╰───────────────────────────────────────────────────────────────────────╯
```

### Timeout
```
╭─ ollama/qwen2.5 — 196 —────────────────────────────────────────────╮
│ Timeout após 30s — o modelo pode estar occupado ou lento            │
│ Tente novamente ou troque o modelo com /model                       │
╰──────────────────────────────────────────────────────────────────────╯
```

### Nenhum resultado
```
╭─ advpl_sources — 244 —─────────────────────────────────────────────╮
│ Nenhum resultado encontrado para: "pergunta feita"                  │
│ Tente:                                                               │
│   - /rag dicionario <pergunta>                                       │
│   - /rag reversa <pergunta>                                          │
│   - /rag all <pergunta>                                              │
╰──────────────────────────────────────────────────────────────────────╯
```

## Resumo Visual

A TUI melhorada oferece:

1. **Separação visual clara** por agente (cores diferentes)
2. **Indicadores de performance** (tempo, tokens, tipo de fonte)
3. **Historico navegavel** com `/history`
4. **Persistencia de contexto** via Mem0
5. **Respostas ultra-rapidas** para perguntas de dominio (RAG direto)
6. **Capacidade generativa** para tarefas criativas (LLM)
7. **Banner informativo** com estado atual do sistema
