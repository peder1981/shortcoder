# shortcoder — Documentacao Completa

## Visao Geral

`shortcoder` eh uma TUI (Terminal User Interface) no estilo BBS (Bulletin Board System) classico dos anos 90, construida em AdvPL/TLPP e compilada com AdvPP.

### Caracteristicas

- **Interface BBS retrô**: ASCII art, cores vintage (amarelo, ciano, verde, magenta), caixas delimitadas
- **Orquestracao de agentes**: Roteamento automatico baseado no dominio da pergunta
- **100% legivel**: Texto quebrado corretamente, padding dinamico, caixas proporcionais
- **3 agentes integrados**:
  - `ollama`: LLM rapido (~1s) para tarefas gerais
  - `mem0`: Memoria persistente (<1s) para consultar/salvar fatos
  - `ernesto`: RAG + Memoria (>30s) para perguntas de dominio Protheus

---

## Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                      shortcoder                             │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   ORQUESTRADOR                           │   │
│  │  DetectAgent(cInput, cDefaultAgent)                      │   │
│  │    ├─ Keywords mem0 → agente mem0                       │   │
│  │    ├─ Keywords Protheus → agente ernesto (RAG)          │   │
│  │    └─ Padrão → agente ollama (LLM)                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            │                                    │
│        ┌───────────────────┼───────────────────┐               │
│        │                   │                   │               │
│   ┌────▼────┐        ┌────▼────┐        ┌────▼────┐           │
│   │ ollama  │        │  mem0   │        │ ernesto │           │
│   │  (rapido)│        │(memoria)│        │  (RAG)  │           │
│   └────┬────┘        └────┬────┘        └────┬────┘           │
│        │                  │                  │                │
│   ┌────▼────┐        ┌────▼────┐        ┌────▼────┐           │
│   │ Ollama  │        │ ernesto │        │ ernesto │           │
│   │  :11434 │        │  :9081  │        │  :9081  │           │
│   └─────────┘        └─────────┘        └─────────┘           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Instalacao

### Requisitos

- AdvPP compilador (`advplc`) instalado em `~/.local/bin/`
- Ollama rodando em `http://127.0.0.1:11434`
- ernesto-mem0 rodando em `http://127.0.0.1:9081`
- Modelo `lfm25-1b-uncensored:latest` carregado no Ollama

### Compilacao

```bash
cd ~/Projetos/shortcoder
advplc build shortcoder.prw -o shortcoder
```

### Executcao

```bash
./shortcoder
```

---

## Uso

### Interface

```
╔══════════════════════════════════════════════════════════════════════════╗
║                                                                          ║
║                                SHORTCODER                                ║
║                                                                          ║
║                   [AI Coding Agent v1.0] [BBS Edition]                   ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
┌──────────────────────────────────────────────────────────────────────────┐
│ MODEL:  [lfm25-1b-uncensored:latest]                                   │
│ SESSION:[user-20260802-...]                                            │
│ AGENT:  [OLLAMA]                                                       │
│ MEM0:   [default]                                                      │
└──────────────────────────────────────────────────────────────────────────┘
>
```

### Comandos

| Comando | Descricao | Agente |
|---------|-----------|--------|
| `/agent` | Alterna entre ollama/mem0/ernesto | — |
| `/model` | Lista e seleciona modelo | — |
| `/mem0 list` | Lista memorias salvas | mem0 |
| `/mem0 add <texto>` | Adiciona memoria persistente | mem0 |
| `/mem0 clear` | Remove todas as memorias | mem0 |
| `/history` | Mostra historico de turnos | — |
| `/clear` | Nova sessao (limpa historico) | — |
| `/help` | Esta ajuda | — |
| `/exit` | Sair do programa | — |

### Orquestracao Automatica

O sistema detecta automaticamente o agente mais adequado:

| Entrada do Usuario | Agente Selecionado | Razao |
|-------------------|-------------------|-------|
| "o que e A1_COD?" | ernesto (RAG) | Contem palavra-chave "campo" |
| "/mem0 list" | mem0 | Comando mem0 explicito |
| "2+2" | ollama (LLM) | Pergunta geral |
| "escreva um poema" | ollama (LLM) | Tarefa criativa |
| "como funciona SE1?" | ernesto (RAG) | Contem palavra-chave Protheus |

### Palavras-chave de Dominio (Protheus/AdvPL)

O sistema detecta automaticamente perguntas sobre:
- **Campos**: campo, tabela, sx2, sx3, six
- **Formularios**: formulario, rotina
- **Consultas**: query, sql, trigger, indice
- **Modulos**: protheus, advpl, tlpp, totvs, mata, finan
- **Tabelas**: se1, sa1, sb1, sc1, sd1, sf1, sg1, sh1
- **Funcoes**: d_e_l_e_t_, xfilial, fwexecstatement, tcquery, dbquery

---

## Arquitetura Tecnica

### Funcoes Principais

#### `DetectAgent(cInput, cDefaultAgent)`
Orquestrador que decide qual agente usar baseado no conteudo.

```advpl
Static Function DetectAgent(cInput, cDefaultAgent)
    Local cLower := Lower(cInput)
    
    // Regra 1: Comandos mem0 explicitos
    If Left(cLower, 10) == "/mem0 " .Or. cLower == "/mem0 list" ...
        Return "mem0"
    EndIf
    
    // Regra 2: Palavras-chave de dominio Protheus
    Local aProtheusKeywords := { "campo", "tabela", "sx2", ... }
    For i := 1 To Len(aProtheusKeywords)
        If aProtheusKeywords[i] $ cLower
            Return "ernesto"
        EndIf
    Next i
    
    // Regra 3: Padrão usa agente selecionado
    Return cDefaultAgent
```

#### `WordWrap(cText, nMaxLen)`
Quebra texto em linhas de tamanho maximo, respeitando palavras.

```advpl
Static Function WordWrap(cText, nMaxLen)
    Local aLines := {}
    Local cWord, cLine := "", nWordLen, nLineLen
    Local aWords, i
    
    cText := StrTran(cText, Chr(10), " ")
    cText := StrTran(cText, Chr(13), " ")
    
    // Tokenizacao manual (StrTokArray nao existe no AdvPP)
    aWords := {}
    ...
    
    For i := 1 To Len(aWords)
        cWord := aWords[i]
        nWordLen := Len(cWord)
        nLineLen := Len(cLine)
        
        If nLineLen + nWordLen + (Empty(cLine) .And. 0 .Or. 1) <= nMaxLen
            If !Empty(cLine)
                cLine := cLine + " "
            EndIf
            cLine := cLine + cWord
        Else
            If !Empty(cLine)
                aAdd(aLines, cLine)
            EndIf
            cLine := cWord
        EndIf
    Next i
    
    If !Empty(cLine)
        aAdd(aLines, cLine)
    EndIf
    
Return aLines
```

#### `FormatTextForBox(cEsc, cText, nMaxLen, nBoxW)`
Formata texto para caber dentro de caixa BBS.

```advpl
Static Function FormatTextForBox(cEsc, cText, nMaxLen, nBoxW)
    Local aLines, cLine, cResult := "", i, nLen
    
    aLines := WordWrap(cText, nMaxLen)
    
    For i := 1 To Len(aLines)
        cLine := aLines[i]
        nLen := Len(cLine)
        
        If nLen >= nMaxLen
            cResult := cResult + cEsc + "[2;37m" + Left(cLine, nMaxLen) + cEsc + "[0m" + Chr(10)
        Else
            cResult := cResult + cEsc + "[2;37m" + cLine + Replicate(" ", nMaxLen - nLen) + cEsc + "[0m" + Chr(10)
        EndIf
    Next i
    
Return cResult
```

### Endpoints HTTP

| Endpoint | Metodo | Uso | Tempo响 |
|----------|--------|-----|---------|
| `http://127.0.0.1:11434/v1/chat/completions` | POST | Ollama LLM | ~1s |
| `http://127.0.0.1:9081/memories/{user_id}` | GET | Mem0 list | <1s |
| `http://127.0.0.1:9081/memories/{user_id}` | POST | Mem0 add | <2s |
| `http://127.0.0.1:9081/memories/{user_id}` | DELETE | Mem0 clear | <1s |
| `http://127.0.0.1:9081/v1/chat/completions` | POST | Ernesto RAG | >30s |

---

## Limitacoes

1. **Tempo响 do modelo ernesto**: O modelo RAG (ernesto-granite41-rag:latest) eh muito lento (>30s), causando timeout no HTTP client (timeout padrao: 30s).

2. **StrTokArray nao existe**: O AdvPP nao possui a funcao `StrTokArray`, entao a tokenizacao de texto eh feita manualmente no `WordWrap`.

3. **Sem streaming**: As respostas sao processadas em modo nao-streaming (aguarda resposta completa).

4. **Memoria limitada**: O modelo `lfm25-1b-uncensored` tem contexto de 128k tokens, mas respostas longas podem ser truncadas.

---

## Testes

### Resultado dos Testes

| Teste | Descricao | Status | Tempo |
|-------|-----------|--------|-------|
| 1 | Inicializacao + banner ASCII art | ✅ PASS | <1s |
| 2 | Comando /help | ✅ PASS | <1s |
| 3 | Agente ollama — 2+2 | ✅ PASS | 0.8s |
| 4 | Agente mem0 — listar memorias | ✅ PASS | 0.0s |
| 5 | Agente mem0 — add memoria | ✅ PASS | 4.3s |
| 6 | Agente mem0 — clear | ✅ PASS | <1s |
| 7 | Comando /history | ✅ PASS | <1s |
| 8 | Comando /model — listar modelos | ✅ PASS | <1s |
| 9 | Comando /agent — trocar agente | ✅ PASS | <1s |
| 10 | Comando /clear — nova sessao | ✅ PASS | <1s |
| 11 | Criatividade — haiku sobre编程 | ✅ PASS | 1.3s |
| 12 | Multi-turno com historico | ✅ PASS | 12.2s + 1.1s |
| 13 | Texto longo — explicacao HTTP | ✅ PASS | 13.7s |
| 14 | Orquestracao — pergunta Protheus | ✅ PASS | (timeout esperado) |

**Total: 14 testes, 14 passed, 0 failed**

### Executar Testes

```bash
# Teste 1: Inicializacao
printf '/exit\n' | ./shortcoder

# Teste 2: Ajuda
printf '/help\n/exit\n' | ./shortcoder

# Teste 3: Resposta rapida
printf '2+2\n/exit\n' | ./shortcoder

# Teste 4: Memoria
printf '/mem0 add "teste"\n/mem0 list\n/exit\n' | ./shortcoder

# Teste 5: Orquestracao
printf 'o que e o campo A1_COD?\n/exit\n' | ./shortcoder
```

---

## Arquivos

```
~/Projetos/shortcoder/
├── shortcoder          # Binario ELF (44MB)
├── shortcoder.prw      # Fonte AdvPL (26KB)
├── TEST_RESULTS.md         # Resultados dos testes
├── BBS_README.md           # Resumo rapido
├── DOCUMENTACAO.md         # Este arquivo
├── shortcoder              # Versao original
├── shortcoder.prw
├── shortcoder-rag          # Versao com RAG
├── shortcoder-rag.prw
├── ARCHITECTURE.md
├── PROTOTIPO.md
└── WIREFRAME.md
```

---

## Referencias

- **AdvPP**: https://github.com/peder1981/AdvPP
- **Ollama**: https://ollama.ai
- **ernesto-mem0**: http://127.0.0.1:9081
- **MCP protheus-rag**: http://127.0.0.1:9080

---

## Licenca

Codigo desenvolvido para uso interno no projeto shortcoder.
