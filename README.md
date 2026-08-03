# shortcoder — Interface BBS Retrô

Versao do shortcoder com estetica BBS (Bulletin Board System) classica dos anos 90.

## Visual

- **ASCII Art** no header com o nome "SHORTCODER"
- **Cores vintage**: amarelo (#FFFF00), ciano, verde, magenta
- **Caixas delimitadas** com `+──+|` estilo BBS
- **Status bar** comModel/Session/Agent/Mem0
- **Mensagens formatadas** em blocos com bordas

## Comandos

```
/agent     — Troca entre ollama (rapido), mem0 (memoria), ernesto (RAG)
/model     — Lista e seleciona modelo
/mem0 list — Visualiza memorias salvas
/mem0 add  — Salva memoria persistente
/mem0 clear— Remove todas as memorias
/history   — Mostra historico de conversas
/clear     — Nova sessao (limpa historico)
/help      — Esta ajuda
/exit      — Sair
```

## Agentes

| Agente | Backend | Velocidade | Uso |
|--------|---------|------------|-----|
| ollama | `:11434/v1/chat` | ~1-3s | Conversas rapidas |
| mem0 | `:9081/memories/` | <1s | Memoria persistente |
| ernesto | `:9081/v1/chat` | >30s (timeout) | RAG + contexto |

## Como Compilar

```bash
cd ~/Projetos/shortcoder
advplc build shortcoder.prw -o shortcoder
./shortcoder
```

## Testes

```bash
# Testar ajuda
printf '/help\n/exit\n' | ./shortcoder

# Testar resposta LLM
printf '2+2\n/exit\n' | ./shortcoder

# Testar memoria
printf '/mem0 add "teste BBS"\n/mem0 list\n/exit\n' | ./shortcoder

# Testar historico
printf 'ola\n/history\n/exit\n' | ./shortcoder
```

## Comparacao com Versoes Anteriores

| Versao | Estilo | Funcionalidades |
|--------|--------|-----------------|
| shortcoder | Minimalista | LLM via ProcRun |
| shortcoder-rag | Cards modernos | LLM + Mem0 HTTP |
| **shortcoder** | **BBS retrô** | **LLM + Mem0 + visual** |
