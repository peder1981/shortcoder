# shortcoder-rag — Arquitetura de Orquestração com protheus-rag

## Visão Geral

O shortcoder-rag é uma extensão do shortcoder que adiciona providers nativos de RAG
e Mem0, permitindo ao usuário consultar a base Protheus diretamente da TUI sem
dependência do little-coder para perguntas de domínio AdvPL/Protheus.

```
┌─────────────────────────────────────────────────────────────────┐
│                         shortcoder.prw                          │
│  ┌─────────────┐  ┌─────────────┐  ┌────────────────────────┐  │
│  │  Agent:      │  │  Agent:     │  │  Agent: RAG Direct     │  │
│  │  LLM (via    │  │  little-    │  │  (HTTP nativo,         │  │
│  │  ProcRun)    │  │  coder)     │  │   sem little-coder)    │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬─────────────┘  │
│         │                │                     │                │
│         └────────────────┴─────────────────────┘                │
│                              │                                  │
│                      ┌───────▼───────┐                          │
│                      │  Router /     │                          │
│                      │  Dispatcher   │                          │
│                      └───────┬───────┘                          │
│                              │                                  │
│         ┌────────────────────┼────────────────────┐             │
│         │                    │                    │             │
│  ┌──────▼──────┐      ┌──────▼──────┐     ┌──────▼──────┐      │
│  │ ollama/     │      │ ernesto/    │     │ protheus-   │      │
│  │ qwen        │      │ ernesto     │     │ rag/        │      │
│  │             │      │ (RAG+mem0)  │     │ ask         │      │
│  └─────────────┘      └─────────────┘     └─────────────┘      │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Backend HTTP (via FWHTTP* — já existe no AdvPP)      │    │
│  │  http://127.0.0.1:9080   — ernesto-rag-proxy          │    │
│  │  http://127.0.0.1:9081   — ernesto-mem0               │    │
│  │  http://127.0.0.1:11434  — ollama                       │    │
│  └──────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

## Endpoints Disponíveis

### ernesto-rag-proxy (porta 9080)

| Rota | Método | Payload | Resposta |
|------|--------|---------|----------|
| `/v1/chat/completions` | POST | OpenAI chat format | NDJSON stream |
| `/admin/config` | GET | — | Configuracao atual |
| `/admin/collections` | GET | — | Lista de colecoes |
| `/admin/search` | POST | `{"collection":"advpl_sources","question":"..."}` | JSON com chunks |

O `/admin/search` é o mais útil para integracao direta — retorna os chunks brutos
sem passar pelo LLM.

### ernesto-mem0 (porta 9081)

| Rota | Metodo | Payload | Resposta |
|------|--------|---------|----------|
| `/memories/{user_id}` | POST | `{"content":"..."}` | memoria criada |
| `/memories/{user_id}` | GET | — | Lista de memorias |
| `/v1/chat/completions` | POST | OpenAI chat format | NDJSON stream (com mem0 injetado) |

### ollama (porta 11434)

| Rota | Metodo | Uso |
|------|--------|-----|
| `/v1/models` | GET | Listar modelos |
| `/v1/chat/completions` | POST | Completions (streaming/nao-streaming) |

## Agentes

### Agente 1: `ollama/{model}`
- Rotas pelo ProcRun (como o shortcoder atual)
- little-coder como wrapper
- Adequado para: codigo geral, tarefas criativas, raciocinio livre

### Agente 2: `rag/advpl` (protheus-rag direto)
- HTTP POST para `/admin/search` no proxy (9080)
- Resposta: chunks brutos formatados como texto
- Adequado para: "o que e o campo A1_COD?", "como consulta a SE1?"
- Mais rapido que ernesto porque pula o LLM

### Agente 3: `rag/reversa`
- HTTP POST para `/admin/search` com `collection=reversa_sources`
- Adequado para: perguntas sobre o framework Reversa, comandos, skills

### Agente 4: `mem0/{user_id}`
- HTTP GET `/memories/{user_id}` no proxy (9081)
- HTTP POST `/memories/{user_id}` no proxy (9081)
- Adequado para: consulta e adicao de memorias persistentes

### Agente 5: `ernesto/{model}`
- Rotas pelo ProcRun (little-coder)
- Pula pelo proxy RAG+mem0
- Adequado para: perguntas complexas que precisam de raciocinio + RAG

## Modelo de Decisao

```
Input do usuario
    │
    ├─ comando / (slash command)?  →  Agente: RAG Direct (admin/search)
    │
    ├─ contem palavra-chave de    →  Agente: RAG Direct
    │  dominio Protheus?            (consultar campos, tabelas, functions)
    │
    ├─ contem /reversa-*?         →  Agente: RAG Direct (colecao reversa)
    │
    └─ outro                      →  Agente: LLM (ProcRun via little-coder)
```

Palavras-chave de dominio Protheus (heurstica simples):
- "campo", "tabela", "SX2", "SX3", "formulario", "Rotina", "Rotina MATA",
  "como funciona", "ondeesta", "o que e", "query", "SQL", "trigger", "indice"

## TUI Melhorada

### Split View

```
┌────────────────────────────────────────────────────────────────────┐
│ ▍ shortcoder-rag                    modelo: rag/advpl  sessao: abc │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ╭─ voce — 244 ─────────────────────────────────────────────╮     │
│  │ O que e o campo A1_COD da tabela SA1?                     │     │
│  ╰────────────────────────────────────────────────────────────╯     │
│                                                                    │
│  ╭─ rag/advpl — 39 ──────────────────────────────────────────╮    │
│  │ **A1_COD** (Campo de identificacao do cliente)             │    │
│  │                                                            │    │
│  │ Fonte: SX3 SA1, campo A1_COD                               │    │
│  │ Tipo: Character, tamanho 6                                   │    │
│  │ Chave primaria da tabela SA1                                 │    │
│  │                                                              │    │
│  │ [contexto RAG — 3 chunks relevantes]                         │    │
│  │   - SA1: A1_COD = codigo do cliente                        │    │
│  │   -SX3: A1_COD, C8_titulo="Codigo do Cliente"               │    │
│  │   -Fonte: MATA010.prw, linha 45                              │    │
│  ╰────────────────────────────────────────────────────────────╯    │
│                                                                    │
│  2 tok in · 45 tok out · 0.3s  [rag/advpl — fast]                  │
│                                                                    │
│  ╭─ voce — 244 ─────────────────────────────────────────────╮     │
│  │ Mostra como consultar a SE1 com filtro D_E_L_E_T_          │     │
│  ╰────────────────────────────────────────────────────────────╯     │
│                                                                    │
│  ╭─ ollama/qwen2.5 — 39 ────────────────────────────────────╮     │
│  │ Aqui esta um exemplo de consulta SE1 com filtro...         │     │
│  │                                                            │     │
│  │ ```advpl                                                    │     │
│  │  DBQuery("SELECT * FROM SE1_%s WHERE E1_FILIAL = '%s'..."  │     │
│  │ ```                                                          │     │
│  ╰────────────────────────────────────────────────────────────╯     │
│                                                                    │
│  ❯ _                                                              │
└────────────────────────────────────────────────────────────────────┘
```

### Novos Comandos

| Comando | Descricao |
|---------|-----------|
| `/rag <coletao> <pergunta>` | Consulta direta ao RAG (sem LLM) |
| `/rag advpl <pergunta>` | Atalho para colecao `advpl_sources` |
| `/rag dicionario <pergunta>` | Atalho para colecao `dicionario_protheus` |
| `/rag reversa <pergunta>` | Atalho para colecao `reversa_sources` |
| `/mem0 add <texto>` | Adiciona memoria persistente |
| `/mem0 list` | Lista memorias do usuario |
| `/mem0 clear` | Limpa memorias do usuario |
| `/agent` | Mostra agente ativo e troca |
| `/history` | Mostra historico de turnos |

### Indicadores Visuais

- Badge de agente no canto superior direito da caixa: `[rag]` / `[llm]` / `[mem0]`
- Rodape diferenciado por agente:
  - `rag/advpl`: "fast · RAG direto" (sem tokens, velocidade alta)
  - `ollama/*`: "N tok in · M tok out · X.Xs" (padrao)
  - `mem0/*`: "N memorias · conf media: X.X"

### Estados de Loading

```
╭─ rag/advpl — 39 ─────────────────────────────╮
│ Buscando na base Protheus... [||||||    ] 70% │
╰───────────────────────────────────────────────╯
```

### Cores por Agente

| Agente | Cor ANSI |
|--------|----------|
| `ollama/*` | 39 (ciano) — padrao atual |
| `rag/advpl` | 46 (ciano escuro/teal) — RAG AdvPL |
| `rag/reversa` | 141 (amarelo-ouro) — Reversa |
| `mem0/*` | 148 (verde-azulado) — Memoria |
| `ernesto/*` | 212 (rosa) — RAG+LLM composite |

## Implementacao

### Alteracoes no shortcoder.prw (sem mexer no AdvPP)

1. Adicionar funcao `CallRagSearch(cCollection, cQuestion)` que:
   - Faz HTTP POST para `http://127.0.0.1:9080/admin/search`
   - Parse do JSON de resposta com JsonObject
   - Retorna string formatada com os chunks

2. Adicionar funcao `CallMem0List(cUserId)` que:
   - Faz HTTP GET para `http://127.0.0.1:9081/memories/{cUserId}`
   - Parse e retorna string formatada

3. Adicionar funcao `CallMem0Add(cUserId, cContent)` que:
   - Faz HTTP POST para `http://127.0.0.1:9081/memories/{cUserId}`
   - Retorna sucesso/erro

4. Modificar o loop principal para:
   - Detectar `/rag`, `/mem0` e outros comandos
   - Rotear para o agente correto
   - Detectar heuristicamente perguntas de dominio Protheus

5. Adicionar novo banner com selecao de agente

### Dependencias

Nenhuma nova dependencia no AdvPP. Tudo usa:
- `FWHTTPPOST` / `FWHTTPGET` — ja existe
- `JsonObject()` — ja existe (implementado por voce)
- `UiBox` / `UiStreamBox` — ja existe
- `ConOutRaw` — ja existe

## Roadmap

### Fase 1 — RAG direto
- [ ] Implementar `CallRagSearch`
- [ ] Adicionar comandos `/rag advpl`, `/rag dicionario`, `/rag reversa`
- [ ] Testar com perguntas reais

### Fase 2 — Mem0
- [ ] Implementar `CallMem0List` e `CallMem0Add`
- [ ] Adicionar comandos `/mem0 add`, `/mem0 list`, `/mem0 clear`

### Fase 3 — Deteccao automatica
- [ ] Heuristica de palavras-chave para rotear perguntas Protheus
- [ ] Configuracao de palavras-chave via arquivo de config

### Fase 4 — TUI melhorada
- [ ] Badge de agente nas caixas
- [ ] Rodape diferenciado por agente
- [ ] Comandos de navegacao (/history, /agent)
- [ ] Indicador de loading por agente

### Fase 5 — Agentes multiplas
- [ ] Sistema de configuracao de agentes (JSON local)
- [ ] Agente customizado para cada skill do Reversa
- [ ] Pipeline /reversa-* integrado via HTTP
