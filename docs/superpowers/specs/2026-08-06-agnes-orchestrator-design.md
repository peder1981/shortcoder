# Agnes Orchestrator — Agnes roteando modelos Ollama locais via job assíncrono

Data: 2026-08-06
Status: aprovado para implementação

## Contexto

O shortcoder já tem 4 agentes (`ollama`, `mem0`, `ernesto`, `agnes`), todos síncronos —
cada um faz uma chamada HTTP bloqueante e espera a resposta antes de devolver o
prompt ao usuário.

Este design adiciona um 5º agente, `orchestrator`, onde o modelo remoto Agnes 2.5
Flash atua como **dispatcher**: decide qual modelo Ollama local é mais adequado
para a pergunta, dispara a chamada a esse modelo **em background** (thread
separada via goroutine do AdvPP), e ao final **refina** a resposta local antes de
exibi-la.

O objetivo duplo é (a) entregar a funcionalidade de orquestração e (b) validar
que o mecanismo de concorrência do AdvPP (`StartJob`/goroutines) funciona de
ponta a ponta com um caso de uso real — hoje ele é fire-and-forget, sem canal de
retorno de valor, o que é insuficiente para este fluxo.

## Fora de escopo

- Fan-out para múltiplos modelos em paralelo (decisão do brainstorming: é
  roteamento, não paralelismo de consulta).
- Substituir o agente `agnes` existente — ele continua intocado, chamada direta.
- Canal de erro estruturado no job assíncrono (ver limitação assumida abaixo).
- Cancelamento do job em andamento (Ctrl+C durante o spinner não aborta a
  goroutine, só a espera visual — comportamento aceito, ver Erros).

## Arquitetura

Dois repositórios mudam:

1. **AdvPP** (`/home/peder/Projetos/AdvPP`) — runtime ganha um par de natives
   novas para job assíncrono *com retorno de valor*. `StartJob`/`STARTJOB`
   existentes não são tocados (zero risco de regressão em uso já existente).
2. **shortcoder** (`/home/peder/Projetos/shortcoder`) — novo agente
   `orchestrator` que consome essas natives.

## 1. AdvPP — `FWJOBSTART` / `FWJOBPOLL`

Novo arquivo `pkg/vm/asyncjob_native.go`, registrado em `registerNatives` (ou
função equivalente já usada pelos outros arquivos `*_native.go`).

### `VM` struct (`pkg/vm/vm.go`)

```go
// jobResults guarda o retorno de jobs disparados via FWJOBSTART, indexados
// por job id, para coleta posterior via FWJOBPOLL.
jobResults sync.Map // map[string]*asyncJobResult

// jobIDSeq gera ids únicos para FWJOBSTART (atômico).
jobIDSeq int64
```

```go
type asyncJobResult struct {
    done  bool
    value advplrt.Value
}
```

### `FWJOBSTART(cFuncName, params...) -> cJobId`

- Sempre assíncrono (não tem parâmetro `lWait` — se quiser síncrono, o
  chamador já tem `StartJob(cFunc, cEnv, .T., ...)`).
- Reaproveita o mesmo caminho de `StartJob` com `wait=false`: cria `NewVM`
  isolado, respeita `MaxConcurrentJobs`/`activeJobsCount` (CWE-400), roda a
  função pelo nome (case-insensitive, mesma resolução de `RunFunction` —
  funciona com `Static Function` também, já que a tabela de funções do
  bytecode não distingue visibilidade em runtime).
- Gera `cJobId := fmt.Sprintf("job-%d", atomic.AddInt64(&v.jobIDSeq, 1))`.
- Ao terminar a goroutine, grava o resultado em `v.jobResults.Store(cJobId,
  &asyncJobResult{done: true, value: result})`. Erro da função vira
  `advplrt.NewCharacter("")` como valor (ver limitação abaixo) e é logado em
  `fmt.Printf` como já ocorre em `StartJob`.
- Retorna `cJobId` (Character) imediatamente, sem bloquear.

### `FWJOBPOLL(cJobId) -> uResult`

- `v.jobResults.Load(cJobId)`:
  - Não encontrado ou `done == false` → retorna `advplrt.Nil` (tipo `U`).
  - `done == true` → retorna o `value` guardado (tipicamente Character) e
    **remove a entrada do map** (`Delete`) para não vazar memória em jobs de
    vida longa — poll é destrutivo, só pode ser lido uma vez.

### Limitação assumida (documentada, não corrigida neste design)

`FWJOBPOLL` não distingue "job terminou com erro" de "job terminou e
retornou string vazia". Aceitável porque a única função despachada por este
fluxo (`OrchestratorOllamaJob`) só retorna string vazia em caso de erro HTTP
— o chamador (`RunOrchestratorAgent`) trata string vazia como falha. Se no
futuro outro job precisar diferenciar isso, adicionar um segundo valor de
retorno ou um native `FWJOBERROR(cJobId)` fica para depois
(`ponytail: sem canal de erro dedicado; adicionar FWJOBERROR se surgir um
job que precise diferenciar erro de resultado vazio`).

## 2. shortcoder — agente `orchestrator`

### `PickAgent` (shortcoder.prw)

Adiciona opção `[5] orchestrator` na caixa de seleção, cor `1;31` (vermelho —
livre na paleta atual: ollama=`1;36`, mem0=`1;32`, ernesto=`1;35`,
agnes=`1;33`).

### `AgentColor`

`Case Lower(cAgent) == "orchestrator" \n Return "1;31"`.

### Dispatch em `Main`

```
ElseIf cSelectedAgent == "orchestrator"
    RunOrchestratorAgent(cEsc, cInput, aModels, nWidth, @aHistory)
```

`aModels` já está disponível no escopo de `Main` (carregado por `LoadModels`
no início) — passado por referência/valor para a nova função, igual padrão
de `cModel` etc.

### `Static Function OrchestratorOllamaJob(cModel, cPrompt)`

Função-alvo do `FWJOBSTART`. Roda em VM isolado, não tem acesso a variáveis
do VM principal — recebe tudo por parâmetro. Faz exatamente o que
`RunOllamaAgent` já faz (POST em `http://127.0.0.1:11434/v1/chat/completions`,
parse do JSON, extrai `choices[1].message.content`), mas **retorna a string**
em vez de imprimir — sem chamadas a `ConOut`/`BoxXxx` (essa função não tem UI,
só rede + parse). Em qualquer erro (status != 200, parse falho, conteúdo
vazio) retorna `""`.

### `Static Function RunOrchestratorAgent(cEsc, cPrompt, aModels, nWidth, aHistory)`

Sequência:

1. **Guarda de API key**: `AGNES_API_KEY` vazia → mesma caixa de erro que
   `RunAgnesAgent` já usa, retorna sem gastar rede.
2. **Passo DECIDE (síncrono)**: monta prompt de roteamento para Agnes —
   lista os `aModels[i][1]` (ids) e a pergunta do usuário, pede resposta
   *apenas* com o id do modelo escolhido. Chama Agnes
   (`FWHTTPHEADER`/`FWHTTPPOST`/`FWHTTPCLEARHEADERS`, mesmo padrão de
   `RunAgnesAgent`). Erro de rede aqui aborta com a mesma caixa de
   erro/timeout já usada em `RunAgnesAgent`.
   - Parse da resposta: `AllTrim` do conteúdo, valida contra
     `aModels[i][1]` (case-insensitive). Se não bater com nenhum, usa
     `aModels[1][1]` como fallback silencioso (loga em `ConOut` modo `2m`
     dim: "roteamento inválido, usando <modelo> como fallback").
3. **Passo DESPACHA (assíncrono)**:
   `cJobId := FWJOBSTART("OrchestratorOllamaJob", cModeloEscolhido, cPrompt)`.
4. **Espera com spinner**: loop `Do While .T.` — `FWJOBPOLL(cJobId)`; se
   `ValType(...) == "U"`, imprime frame do spinner (`\r` + caractere
   giratório de um array `{"|", "/", "-", "\"}`) e `Sleep(150)`; senão sai do
   loop com o resultado. Sem timeout de segurança adicional além do timeout
   HTTP já embutido em `OrchestratorOllamaJob` (herdado do default do
   `FWHTTPPOST`, já que a VM isolada não herda `FWHTTPTIMEOUT` do VM
   principal).
   - Resultado vazio (`""`) → caixa de erro "modelo local falhou", encerra
     sem chamar Agnes de novo.
5. **Passo REFINA (síncrono)**: segunda chamada a Agnes — prompt com a
   pergunta original + a resposta do modelo local, pedindo a versão final
   revisada. Mesmo tratamento de erro/timeout do passo DECIDE; se falhar
   aqui, cai para mostrar a resposta local crua (`[AGNES REFINE FALHOU —
   exibindo resposta local]`) em vez de perder o trabalho já feito.
6. **Exibição**: caixa `AGENT:ORCHESTRATOR` mostrando também qual modelo
   local foi escolhido no título/subtítulo (ex.
   `BoxAgentTitle(cEsc, "AGENT:ORCHESTRATOR", cModeloEscolhido, nInner,
   "<cor>")`), tempo total decorrido, `FormatMarkdownForBox` no conteúdo —
   mesmo padrão visual dos outros agentes.
7. `aAdd(aHistory, {"orchestrator", cPrompt, Seconds() - nStart})`.

### `ShowBBSHelp` e `README.md`

- `/agent` descrição passa a `"Switch agent
  (ollama/mem0/ernesto/agnes/orchestrator)"`.
- Nova linha na tabela de Agentes do README explicando o fluxo
  decide→despacha→refina.
- Seção "Atalhos de teclado" não muda (não relacionado).

## Erros e casos-limite

| Cenário | Comportamento |
|---|---|
| `AGNES_API_KEY` ausente | Caixa de erro antes de qualquer rede, igual `agnes` |
| Agnes (decide) falha/timeout | Caixa de erro, aborta, não despacha job |
| Agnes escolhe modelo inexistente/texto livre | Fallback silencioso pro primeiro da lista (log dim) |
| Job Ollama local retorna erro (`""`) | Caixa de erro "modelo local falhou", sem chamar Agnes de novo |
| Agnes (refina) falha/timeout | Mostra resposta local crua com aviso, não perde o resultado do passo 2 |
| Usuário aperta Ctrl+C durante o spinner | Cancela a *linha de input* (comportamento padrão do `ConIn`); a goroutine do job continua rodando em background até terminar (é descartada, sem crash — mesmo comportamento que `StartJob` já tem hoje para jobs órfãos) |

## Testes

1. **AdvPP isolado** (Go, fora do shortcoder): programa `.prw` de teste que
   chama `FWJOBSTART` numa função que faz `Sleep(500)` e retorna uma string
   fixa; confere que `FWJOBPOLL` retorna `Nil` numa primeira checada
   imediata e o valor certo numa checada após o sleep. Cobre também
   `MaxConcurrentJobs` não sendo violado (reaproveita o limite já existente
   de `StartJob`).
2. **shortcoder ponta a ponta** (requer `AGNES_API_KEY` e Ollama local
   rodando):
   ```bash
   printf '/agent\n5\nolá, tudo bem?\n/exit\n' | ./shortcoder
   ```
   Confere que a saída mostra o spinner (ou ao menos não trava), a caixa
   `AGENT:ORCHESTRATOR` final, e que `/history` lista a entrada com tag
   `orchestrator`.
3. Rebuild + `cp` para `~/.local/bin/shortcoder` ao final, como já é prática
   estabelecida neste projeto.
