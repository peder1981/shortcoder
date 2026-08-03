# shortcoder-rag — Prototipo Funcional

Prototipo do shortcoder estendido com agentes Mem0 e LLM rapido, usando
somente endpoints HTTP ja existentes (sem modificar o AdvPP).

## Endpoints Usados

| Endpoint | Status | Tempo响 | Uso |
|----------|--------|---------|-----|
| `http://127.0.0.1:11434/v1/chat/completions` | ✅ OK | ~1s | LLM rapido (lfm25) |
| `http://127.0.0.1:9081/memories/{user_id}` | ✅ OK | <1s | Operacoes de memoria |
| `http://127.0.0.1:9081/v1/chat/completions` | ⚠️ Lento | >30s | LLM + RAG integrado (timeout) |
| `http://127.0.0.1:9080/v1/chat/completions` | ❌ Muito lento | >2min | NAO usar |

## Agentes Disponiveis

### 1. ollama (rapido) — padrao
- Backend: `http://127.0.0.1:11434/v1/chat/completions`
- Modelo padrao: `lfm25-1b-uncensored:latest` (1.2B params, ultra-rapido)
- Tempo响: 1-2 segundos
- Uso: Conversas gerais, codigos, perguntas rapidas

### 2. mem0 (memoria persistente)
- Backend: `http://127.0.0.1:9081/memories/{user_id}`
- Operacoes: list, add, clear
- Tempo响: <1 segundo
- Uso: Consultar e gerenciar memorias persistentes

### 3. ernesto (RAG + Mem0) — experimental
- Backend: `http://127.0.0.1:9081/v1/chat/completions`
- Modelo: `ernesto-granite41-rag:latest` (8.8B)
- Tempo响: >30s (timeout do HTTP client)
- Uso: Perguntas que precisam de contexto RAG (limitado pelo timeout)

## Comandos da TUI

### Agentes
```
/agent
  → Menu: 1=ollama (rapido), 2=mem0 (memoria), 3=ernesto (RAG)
  → Alterna agente padrao para turnos livres

/model
  → Lista modelos disponiveis em ~/.config/little-coder/models.json
  → Troca modelo ativo
```

### Mem0 (operacoes diretas)
```
/mem0 list
  → Lista todas as memorias do usuario default

/mem0 add <texto>
  → Adiciona memoria persistente
  → Ex: /mem0 add "O usuario prefere TLPP para codigos novos"

/mem0 clear
  → Remove todas as memorias do usuario
```

### Navegacao
```
/history
  → Mostra historico de turnos com agente, tempo响 e preview

/clear
  → Nova sessao, zera historico

/help
  → Esta ajuda
```

## Como Compilar

```bash
cd ~/Projetos/shortcoder
advplc build shortcoder-rag.prw -o shortcoder-rag
./shortcoder-rag
```

## Testes de Validacao

### Teste 1: Agente Ollama (rapido)
```
$ ./shortcoder-rag
❯ 2+2
╭─ ollama ──────────────────────────────────────────────╮
│ The result of 2 + 2 is 4.                            │
╰───────────────────────────────────────────────────────╯
  ollama · 1.1s · fast
```

### Teste 2: Memoria Persistente
```
❯ /mem0 add "teste: prefiro portugues"
╭─ mem0/add ────────────────────────────────────────────╮
│ Memoria adicionada com sucesso!                       │
╰───────────────────────────────────────────────────────╯
  mem0/add · 0.5s

❯ /mem0 list
╭─ mem0/list ───────────────────────────────────────────╮
│ 847 memorias:                                         │
│ [fact] conf:1.00 teste: prefiro portugues             │
│ ...                                                   │
╰───────────────────────────────────────────────────────╯
  mem0 · 1.3s · 847 memorias
```

### Teste 3: Historico
```
❯ /history
╭─ historico ───────────────────────────────────────────╮
│ 2 turnos:                                             │
│ [1] agente=ollama | tempo=1.1s                        │
│     2+2                                               │
│ [2] agente=mem0/add   | tempo=0.5s                    │
│     teste: prefiro portugues                          │
╰───────────────────────────────────────────────────────╯
```

## Limitacoes

1. **Timeout HTTP (30s)**: O modelo ernesto (RAG) e muito lento para responder
   dentro do timeout. Para RAG rapido, usar o little-coder existente ou
   chamar o Python diretamente via ProcRun.

2. **Colecao advpl_sources**: Nao existe no ChromaDB local (FAISS indisponivel).
   Colecoes disponiveis: `dicionario_protheus` (268k), `reversa_sources` (2.8k).

3. **Sem streaming RAG**: O endpoint `/v1/chat/completions` retorna JSON completo;
   nao ha streaming de chunks como no little-coder.

## Endpoints Verificados

```bash
# Ollama
curl http://127.0.0.1:11434/v1/models        # ✅ lista modelos
curl -X POST http://127.0.0.1:11434/v1/chat/completions  # ✅ funciona

# Mem0
curl http://127.0.0.1:9081/health            # ✅ ok
curl http://127.0.0.1:9081/memories/default  # ✅ lista memorias
curl -X POST http://127.0.0.1:9081/memories/default  # ✅ adiciona

# Ernesto RAG Proxy (9080)
curl http://127.0.0.1:9080/health            # ✅ ok (mas respostas lentas)
curl -X POST http://127.0.0.1:9080/v1/chat/completions  # ❌ >2min por request
```

## Próximos Passos

1. **RAG direto via Python**: Usar ProcRun para chamar `python3 -c "from rag.chroma import..."`
   e fazer buscas ultrarrápidas sem depender do proxy HTTP lento.

2. **Streaming**: Implementar parse de SSE (Server-Sent Events) para respostas
   em streaming (como o shortcoder original faz com NDJSON).

3. **Cache local**: Armazenar respostas frequentes em arquivo JSON para
   reduzir tempo响 para perguntas repetidas.
