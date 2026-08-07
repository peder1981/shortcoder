# Agnes Orchestrator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar um 5º agente `orchestrator` ao shortcoder onde Agnes 2.5
Flash decide qual modelo Ollama local responder, despacha essa chamada numa
goroutine assíncrona do AdvPP e refina o resultado antes de exibir.

**Architecture:** Duas mudanças em dois repositórios. AdvPP
(`/home/peder/Projetos/AdvPP`) ganha um par de natives novas,
`FWJOBSTART`/`FWJOBPOLL`, que dão retorno de valor a jobs assíncronos (hoje
`StartJob` é fire-and-forget). shortcoder (`/home/peder/Projetos/shortcoder`)
consome essas natives num novo agente que faz 2 chamadas HTTP síncronas a
Agnes (decide, refina) e 1 chamada assíncrona ao Ollama local no meio.

**Tech Stack:** Go 1.x (AdvPP — `pkg/vm`), AdvPL/TLPP (`shortcoder.prw`),
compilador `advplc` (binário próprio, precisa rebuild após mudar o AdvPP).

## Global Constraints

- `FWJOBSTART`/`FWJOBPOLL` são natives NOVAS — não alterar `StartJob`/`STARTJOB`
  existentes (zero regressão em uso já existente).
- `FWJOBPOLL` é destrutivo: uma vez lido o resultado pronto, a entrada é
  removida do map (evita vazamento de memória).
- Erro dentro do job assíncrono vira string vazia `""` como valor de retorno
  (sem canal de erro dedicado neste escopo — ver spec, seção "Limitação
  assumida").
- Paleta de cores dos agentes no shortcoder (não colidir): ollama=`1;36`,
  mem0=`1;32`, ernesto=`1;35`, agnes=`1;33`, **orchestrator=`1;31`**.
- Depois de editar `pkg/vm/*.go` no AdvPP, o binário `advplc` (que embute a
  VM) precisa ser recompilado (`go build -o advplc ./cmd/advplc`) e copiado
  para `~/.local/bin/advplc` — senão `advplc build shortcoder.prw` usa a VM
  antiga sem as natives novas (mesmo bug de binário desatualizado já visto
  nesta sessão).
- Ao final, o binário `shortcoder` recompilado deve ser copiado para
  `~/.local/bin/shortcoder` (prática já estabelecida neste projeto).
- Spec de referência:
  `docs/superpowers/specs/2026-08-06-agnes-orchestrator-design.md`.

---

## Task 1: AdvPP — natives `FWJOBSTART` / `FWJOBPOLL`

**Files:**
- Modify: `/home/peder/Projetos/AdvPP/pkg/vm/vm.go` (struct `VM`, campos novos)
- Create: `/home/peder/Projetos/AdvPP/pkg/vm/asyncjob_native.go`
- Modify: `/home/peder/Projetos/AdvPP/pkg/vm/natives.go:1936` (registro da nova função, logo após `registerP2PNatives(natives)`)
- Test: script `.prw` manual em
  `/tmp/claude-1000/-home-peder-Projetos-shortcoder/a02b8716-d139-44fd-a3fe-8bf5763caf1a/scratchpad/test_asyncjob.prw`
  (scratchpad da sessão — não faz parte de nenhum dos dois repositórios)

**Interfaces:**
- Produces: native `FWJOBSTART(cFuncName, params...) -> cJobId` (Character).
  Sempre assíncrono. `cFuncName` é resolvido na tabela de funções do
  bytecode (case-insensitive, aceita prefixo `U_`), igual `RunFunction` já
  faz para `StartJob`.
- Produces: native `FWJOBPOLL(cJobId) -> uResultado`. Retorna `Nil` (tipo
  `U`) enquanto pendente ou se `cJobId` não existir; retorna o valor
  (Character, tipicamente) assim que pronto, e **remove a entrada** do
  armazenamento interno (leitura única).

### Passo 1.1: Adicionar campos ao struct `VM`

Editar `pkg/vm/vm.go`, dentro do bloco de campos do `type VM struct` (perto
de `httpHeaders`/`inputHistory`, linhas ~115-117):

```go
	jobResults     sync.Map                 // map[string]*asyncJobResult — resultados de FWJOBSTART pendentes/prontos, indexados por job id (FWJOBPOLL)
	jobIDSeq       int64                    // contador atômico p/ gerar job ids únicos (FWJOBSTART)
```

Confirmar que `sync` já está importado em `vm.go` (já é usado por
`jobs sync.WaitGroup` na linha ~104) — não precisa adicionar import novo.

`sync.Map` e `int64` não precisam de inicialização em `NewVM` (zero-value
funciona: `sync.Map{}` vazio é válido, `jobIDSeq` começa em 0).

### Passo 1.2: Criar `pkg/vm/asyncjob_native.go`

```go
package vm

import (
	"fmt"
	"sync/atomic"

	advplrt "github.com/advpl/compiler/pkg/runtime"
)

// asyncJobResult guarda o resultado de um job disparado via FWJOBSTART,
// consumido (uma única vez) por FWJOBPOLL.
type asyncJobResult struct {
	done  bool
	value advplrt.Value
}

// registerAsyncJobNatives registers FWJOBSTART/FWJOBPOLL: um mecanismo de
// job assíncrono COM retorno de valor, complementar ao StartJob/STARTJOB
// existente (que é fire-and-forget e não é alterado por este arquivo).
func (v *VM) registerAsyncJobNatives(natives map[string]func(args []advplrt.Value) (advplrt.Value, error)) {
	// FWJOBSTART(cFuncName, params...) -> cJobId
	// Dispara cFuncName numa goroutine com VM isolado (mesmo mecanismo e
	// limite de concorrência de StartJob com wait=false). Retorna
	// imediatamente um id opaco para coleta posterior via FWJOBPOLL.
	natives["FWJOBSTART"] = func(args []advplrt.Value) (advplrt.Value, error) {
		funcName := advplrt.ToString(getArg(args, 0))
		if funcName == "" {
			return advplrt.Nil, fmt.Errorf("FWJOBSTART: missing function name")
		}
		var params []advplrt.Value
		if len(args) > 1 {
			params = args[1:]
		}

		jobID := fmt.Sprintf("job-%d", atomic.AddInt64(&v.jobIDSeq, 1))

		currentCount := atomic.LoadInt32(&activeJobsCount)
		if currentCount >= int32(MaxConcurrentJobs) {
			return advplrt.Nil, fmt.Errorf("max concurrent jobs exceeded (%d)", MaxConcurrentJobs)
		}
		newCount := atomic.AddInt32(&activeJobsCount, 1)
		if newCount > int32(MaxConcurrentJobs) {
			atomic.AddInt32(&activeJobsCount, -1)
			return advplrt.Nil, fmt.Errorf("max concurrent jobs exceeded (%d)", MaxConcurrentJobs)
		}

		job := NewVM(v.bc, false)
		job.dbFactory = v.dbFactory
		if v.dbFactory != nil {
			job.dbEngine = v.dbFactory()
		}

		v.jobs.Add(1)
		go func() {
			defer v.jobs.Done()
			defer atomic.AddInt32(&activeJobsCount, -1)
			result, err := job.RunFunction(funcName, params)
			if err != nil {
				fmt.Printf("FWJOBSTART(%s) error: %v\n", funcName, err)
				result = advplrt.NewString("")
			}
			v.jobResults.Store(jobID, &asyncJobResult{done: true, value: result})
		}()

		return advplrt.NewString(jobID), nil
	}

	// FWJOBPOLL(cJobId) -> uResultado
	// Nil enquanto pendente/desconhecido. Valor pronto (uma única vez —
	// remove a entrada ao ler) assim que o job termina.
	natives["FWJOBPOLL"] = func(args []advplrt.Value) (advplrt.Value, error) {
		jobID := advplrt.ToString(getArg(args, 0))
		raw, ok := v.jobResults.Load(jobID)
		if !ok {
			return advplrt.Nil, nil
		}
		r := raw.(*asyncJobResult)
		if !r.done {
			return advplrt.Nil, nil
		}
		v.jobResults.Delete(jobID)
		return r.value, nil
	}
}
```

### Passo 1.3: Registrar em `natives.go`

Editar `pkg/vm/natives.go`, logo após a linha `v.registerP2PNatives(natives)`
(~linha 1936):

```go
	v.registerAsyncJobNatives(natives)
```

### Passo 1.4: Build do AdvPP

```bash
cd /home/peder/Projetos/AdvPP
go build ./... 2>&1 | tail -30
go vet ./pkg/vm/... 2>&1 | tail -30
gofmt -l pkg/vm/asyncjob_native.go pkg/vm/vm.go pkg/vm/natives.go
```

Expected: sem erros de build/vet; `gofmt -l` sem saída (nenhum arquivo
precisa reformatação). Se `gofmt -l` listar algo, rodar
`gofmt -w pkg/vm/asyncjob_native.go` (só nos arquivos tocados nesta task —
não mexer em arquivos com débito de formatação pré-existente, como já
documentado nesta sessão para `debug.go`/`httpclient_native.go`).

### Passo 1.5: Rebuild do `advplc` e instalação local

```bash
cd /home/peder/Projetos/AdvPP
go build -o advplc ./cmd/advplc
cp advplc ~/.local/bin/advplc
~/.local/bin/advplc --help >/dev/null 2>&1 && echo "advplc OK"
```

Expected: `advplc OK` (binário roda sem crash).

### Passo 1.6: Smoke test manual das natives novas

Criar
`/tmp/claude-1000/-home-peder-Projetos-shortcoder/a02b8716-d139-44fd-a3fe-8bf5763caf1a/scratchpad/test_asyncjob.prw`:

```advpl
#include "protheus.ch"

User Function Main()
    Local cJobId
    Local uResult
    Local nTries := 0

    cJobId := FWJOBSTART("SlowEcho", "hello-async")
    ConOut("job id: " + cJobId)

    uResult := FWJOBPOLL(cJobId)
    If ValType(uResult) == "U"
        ConOut("poll imediato: pendente (esperado)")
    Else
        ConOut("ERRO: job nao deveria estar pronto ainda")
    EndIf

    Do While ValType(uResult) == "U" .And. nTries < 40
        Sleep(100)
        uResult := FWJOBPOLL(cJobId)
        nTries++
    EndDo

    If ValType(uResult) == "U"
        ConOut("ERRO: timeout esperando job")
    Else
        ConOut("resultado final: [" + uResult + "]")
    EndIf
Return Nil

Static Function SlowEcho(cMsg)
    Sleep(500)
Return "echo:" + cMsg
```

Compilar e rodar:

```bash
cd /tmp/claude-1000/-home-peder-Projetos-shortcoder/a02b8716-d139-44fd-a3fe-8bf5763caf1a/scratchpad
ADVPP_SRC=/home/peder/Projetos/AdvPP advplc build test_asyncjob.prw -o test_asyncjob
./test_asyncjob
```

Expected (nesta ordem):
```
job id: job-1
poll imediato: pendente (esperado)
resultado final: [echo:hello-async]
```

Se `poll imediato` não vier como "pendente" (ou seja, o job terminou antes
de 100ms mesmo com `Sleep(500)` dentro dele), revisar se `FWJOBSTART` está
mesmo despachando em goroutine e não bloqueando.

### Passo 1.7: Commit no repositório AdvPP

```bash
cd /home/peder/Projetos/AdvPP
git add pkg/vm/vm.go pkg/vm/natives.go pkg/vm/asyncjob_native.go
git commit -m "$(cat <<'EOF'
Adiciona FWJOBSTART/FWJOBPOLL: job assincrono com retorno de valor

StartJob/STARTJOB continua fire-and-forget (nao alterado). As natives
novas complementam com um job id + polling para casos que precisam
recuperar o resultado da goroutine depois, como o agente orchestrator
do shortcoder.
EOF
)"
```

---

## Task 2: shortcoder — agente `orchestrator`

**Files:**
- Modify: `/home/peder/Projetos/shortcoder/shortcoder.prw`
  - `PickAgent` (linha ~680-709): nova opção `[5] orchestrator`
  - `AgentColor` (linha ~595-606): novo `Case`
  - `Main` (dispatch, linha ~94-98): novo `ElseIf`
  - Nova `Static Function OrchestratorOllamaJob(cModel, cPrompt)`
  - Nova `Static Function RunOrchestratorAgent(cEsc, cPrompt, aModels, nWidth, aHistory)`

**Interfaces:**
- Consumes (de Task 1): `FWJOBSTART(cFuncName, params...) -> cJobId`
  (Character), `FWJOBPOLL(cJobId) -> uResultado` (Nil ou Character).
- Consumes (já existentes no shortcoder.prw): `FWHTTPHEADER`,
  `FWHTTPCLEARHEADERS`, `FWHTTPPOST`, `FWHTTPBODY`, `FWHTTPERROR`,
  `JsonEscape`, `JsonObject():New()`, `FormatMarkdownForBox`,
  `BoxLineAuto`, `BoxTop`/`BoxDiv`/`BoxBottom`, `BoxAgentTitle`.
- Produces: agente selecionável `"orchestrator"` via `/agent` opção `5`,
  cor `1;31`, histórico marcado com tag `"orchestrator"` em `aHistory`.

### Passo 2.1: `PickAgent` — nova opção `[5]`

Em `shortcoder.prw`, dentro de `Static Function PickAgent`, mudar:

```advpl
    ConOut(BoxOptionLine(cEsc, "4", "1;33", "agnes",   "Agnes 2.5 Flash (remote, cloud)", nInner, "1;33"))
    ConOut(BoxBottomD(cEsc, nInner, "1;33"))
    ConOut("")

    cChoice := AllTrim(ConIn("Select agent [1-4] (Enter=" + cCurrent + "): "))
    ConOut("")

    If cChoice == "1"
        Return "ollama"
    ElseIf cChoice == "2"
        Return "mem0"
    ElseIf cChoice == "3"
        Return "ernesto"
    ElseIf cChoice == "4"
        Return "agnes"
    EndIf
Return cCurrent
```

Para:

```advpl
    ConOut(BoxOptionLine(cEsc, "4", "1;33", "agnes",   "Agnes 2.5 Flash (remote, cloud)", nInner, "1;33"))
    ConOut(BoxOptionLine(cEsc, "5", "1;31", "orchestrator", "Agnes roteia + Ollama local (async)", nInner, "1;33"))
    ConOut(BoxBottomD(cEsc, nInner, "1;33"))
    ConOut("")

    cChoice := AllTrim(ConIn("Select agent [1-5] (Enter=" + cCurrent + "): "))
    ConOut("")

    If cChoice == "1"
        Return "ollama"
    ElseIf cChoice == "2"
        Return "mem0"
    ElseIf cChoice == "3"
        Return "ernesto"
    ElseIf cChoice == "4"
        Return "agnes"
    ElseIf cChoice == "5"
        Return "orchestrator"
    EndIf
Return cCurrent
```

### Passo 2.2: `AgentColor` — novo case

Mudar:

```advpl
    Case Lower(cAgent) == "agnes"
        Return "1;33"
    EndCase
Return "1;37"
```

Para:

```advpl
    Case Lower(cAgent) == "agnes"
        Return "1;33"
    Case Lower(cAgent) == "orchestrator"
        Return "1;31"
    EndCase
Return "1;37"
```

### Passo 2.3: Dispatch em `Main`

Mudar (linha ~94-96):

```advpl
            ElseIf cSelectedAgent == "agnes"
                RunAgnesAgent(cEsc, cInput, nWidth, @aHistory)
            Else
```

Para:

```advpl
            ElseIf cSelectedAgent == "agnes"
                RunAgnesAgent(cEsc, cInput, nWidth, @aHistory)
            ElseIf cSelectedAgent == "orchestrator"
                RunOrchestratorAgent(cEsc, cInput, aModels, nWidth, @aHistory)
            Else
```

`aModels` já está no escopo local de `Main` (carregado por `LoadModels` na
linha 30) — passagem por valor (array é referência em AdvPL, não precisa
`@`).

### Passo 2.4: `OrchestratorOllamaJob` — função-alvo do job assíncrono

Adicionar depois de `RunOllamaAgent` (depois da linha 819):

```advpl
/*/{Protheus.doc} OrchestratorOllamaJob
    Funcao-alvo de FWJOBSTART: roda isolada num VM proprio (sem acesso a
    variaveis do VM principal), faz a chamada HTTP ao Ollama local e
    retorna a string da resposta. Sem UI (ConOut/Box) aqui — quem exibe
    e RunOrchestratorAgent, depois de FWJOBPOLL trazer o resultado.
    Retorna "" em qualquer erro (status != 200, parse falho, sem conteudo).
@type function
/*/
Static Function OrchestratorOllamaJob(cModel, cPrompt)
    Local nStatus
    Local cBody, oJ, oChoice
    Local cContent := ""

    cBody := '{"model":"' + cModel + '","messages":[{"role":"user","content":"' + JsonEscape(cPrompt) + '"}],"stream":false,"max_tokens":500}'
    nStatus := FWHTTPPOST("http://127.0.0.1:11434/v1/chat/completions", cBody, "application/json")

    If nStatus == 200
        cBody := FWHTTPBODY()
        oJ := JsonObject():New()
        If oJ:FromJson(cBody)
            oChoice := oJ["choices"][1]
            If ValType(oChoice) == "O"
                cContent := AllTrim(oChoice["message"]["content"])
                If Empty(cContent)
                    cContent := AllTrim(oChoice["message"]["reasoning"])
                EndIf
            EndIf
        EndIf
    EndIf
Return cContent
```

### Passo 2.5: `RunOrchestratorAgent` — decide, despacha, espera, refina, exibe

Adicionar logo depois de `OrchestratorOllamaJob`:

```advpl
/*/{Protheus.doc} RunOrchestratorAgent
    Agente orchestrator: Agnes decide qual modelo Ollama local responder
    (DECIDE), despacha essa chamada numa goroutine assincrona via
    FWJOBSTART (DESPACHA), anima um spinner enquanto FWJOBPOLL nao traz
    resultado (ESPERA), e manda a resposta local de volta pra Agnes
    revisar antes de exibir (REFINA).
@type function
/*/
Static Function RunOrchestratorAgent(cEsc, cPrompt, aModels, nWidth, aHistory)
    Local nInner := nWidth - 2
    Local cApiKey := GetEnv("AGNES_API_KEY", "")
    Local nStart := Seconds()
    Local cResponse
    Local cModeloEscolhido
    Local cJobId
    Local uLocalResult
    Local cLocalAnswer
    Local nStatus
    Local cBody, oJ, oChoice
    Local cErr
    Local aSpin := {"|", "/", "-", "\"}
    Local nSpin := 1

    If Empty(cApiKey)
        cResponse := BoxLineAuto(cEsc, cEsc + "[1;31m[ERROR] AGNES_API_KEY nao configurada" + cEsc + "[0m", nInner, "1;33")
        ShowOrchestratorBox(cEsc, "-", cResponse, nInner, Seconds() - nStart)
        aAdd(aHistory, {"orchestrator", cPrompt, Seconds() - nStart})
        Return Nil
    EndIf

    If Len(aModels) == 0
        cResponse := BoxLineAuto(cEsc, cEsc + "[1;31m[ERROR] nenhum modelo local disponivel" + cEsc + "[0m", nInner, "1;33")
        ShowOrchestratorBox(cEsc, "-", cResponse, nInner, Seconds() - nStart)
        aAdd(aHistory, {"orchestrator", cPrompt, Seconds() - nStart})
        Return Nil
    EndIf

    // ---- 1) DECIDE: Agnes escolhe o modelo local ----
    // DecideOrchestratorModel retorna "" especificamente quando a chamada
    // HTTP a Agnes falhou (status != 200) — nesse caso abortamos, sem
    // despachar job. Se a chamada teve sucesso mas Agnes respondeu um id
    // que nao bate com nenhum aModels[i][1], a funcao ja faz fallback
    // silencioso internamente e devolve um id valido (nunca "").
    cModeloEscolhido := DecideOrchestratorModel(cApiKey, aModels, cPrompt)
    If Empty(cModeloEscolhido)
        cErr := FWHTTPERROR()
        If !Empty(cErr) .And. At("timeout", Lower(cErr)) > 0
            cResponse := BoxLineAuto(cEsc, cEsc + "[1;33m[TIMEOUT] Agnes API too slow (decide)" + cEsc + "[0m", nInner, "1;33")
        Else
            cResponse := BoxLineAuto(cEsc, cEsc + "[1;31m[ERROR] Agnes (decide) falhou — " + Left(cErr, 40) + cEsc + "[0m", nInner, "1;33")
        EndIf
        ShowOrchestratorBox(cEsc, "-", cResponse, nInner, Seconds() - nStart)
        aAdd(aHistory, {"orchestrator", cPrompt, Seconds() - nStart})
        Return Nil
    EndIf

    // ---- 2) DESPACHA: chamada assincrona ao Ollama local ----
    cJobId := FWJOBSTART("OrchestratorOllamaJob", cModeloEscolhido, cPrompt)

    // ---- 3) ESPERA com spinner ----
    uLocalResult := FWJOBPOLL(cJobId)
    Do While ValType(uLocalResult) == "U"
        ConOutRaw(cEsc + "[2m  aguardando " + cModeloEscolhido + "... " + aSpin[nSpin] + cEsc + "[0m" + cEsc + "[K" + Chr(13))
        nSpin++
        If nSpin > Len(aSpin)
            nSpin := 1
        EndIf
        Sleep(150)
        uLocalResult := FWJOBPOLL(cJobId)
    EndDo
    ConOutRaw(cEsc + "[K" + Chr(13))
    cLocalAnswer := uLocalResult

    If Empty(cLocalAnswer)
        cResponse := BoxLineAuto(cEsc, cEsc + "[1;31m[ERROR] " + cModeloEscolhido + " nao respondeu" + cEsc + "[0m", nInner, "1;33")
        ShowOrchestratorBox(cEsc, cModeloEscolhido, cResponse, nInner, Seconds() - nStart)
        aAdd(aHistory, {"orchestrator", cPrompt, Seconds() - nStart})
        Return Nil
    EndIf

    // ---- 4) REFINA: Agnes revisa a resposta local ----
    FWHTTPHEADER("Authorization", "Bearer " + cApiKey)
    cBody := '{"model":"agnes-2.5-flash","messages":[{"role":"user","content":"' + ;
        JsonEscape("Pergunta original: " + cPrompt + Chr(10) + ;
        "Resposta do modelo local (" + cModeloEscolhido + "): " + cLocalAnswer + Chr(10) + ;
        "Revise essa resposta mantendo o mesmo idioma e conteudo, melhorando clareza e correcao. Responda apenas com a versao final.") + ;
        '"}],"stream":false,"max_tokens":500}'
    nStatus := FWHTTPPOST("https://apihub.agnes-ai.com/v1/chat/completions", cBody, "application/json")
    FWHTTPCLEARHEADERS()

    If nStatus != 200
        cResponse := FormatMarkdownForBox(cEsc, cLocalAnswer, nInner, "1;33")
        ConOut(cEsc + "[2m  [AGNES REFINE FALHOU - exibindo resposta local]" + cEsc + "[0m")
    Else
        cBody := FWHTTPBODY()
        oJ := JsonObject():New()
        If oJ:FromJson(cBody)
            oChoice := oJ["choices"][1]
            If ValType(oChoice) == "O" .And. !Empty(AllTrim(oChoice["message"]["content"]))
                cResponse := FormatMarkdownForBox(cEsc, AllTrim(oChoice["message"]["content"]), nInner, "1;33")
            Else
                cResponse := FormatMarkdownForBox(cEsc, cLocalAnswer, nInner, "1;33")
                ConOut(cEsc + "[2m  [AGNES SEM CONTEUDO - exibindo resposta local]" + cEsc + "[0m")
            EndIf
        Else
            cResponse := FormatMarkdownForBox(cEsc, cLocalAnswer, nInner, "1;33")
            ConOut(cEsc + "[2m  [AGNES PARSE ERR - exibindo resposta local]" + cEsc + "[0m")
        EndIf
    EndIf

    ShowOrchestratorBox(cEsc, cModeloEscolhido, cResponse, nInner, Seconds() - nStart)
    aAdd(aHistory, {"orchestrator", cPrompt, Seconds() - nStart})
Return Nil

/*/{Protheus.doc} DecideOrchestratorModel
    Chama Agnes pedindo APENAS o id do modelo Ollama local mais adequado
    pra pergunta. Retorna "" especificamente quando a chamada HTTP falhou
    (status != 200) — sinal para o chamador abortar (RunOrchestratorAgent
    le FWHTTPERROR() logo em seguida, ainda valido pois nenhuma outra
    chamada HTTP acontece entre esta funcao e a leitura do erro).
    Se a chamada teve sucesso mas a resposta nao bate com nenhum
    aModels[i][1] conhecido (texto livre, modelo inventado), cai no
    fallback silencioso aModels[1][1] — este caso NUNCA retorna "".
@type function
/*/
Static Function DecideOrchestratorModel(cApiKey, aModels, cPrompt)
    Local cModelsList := ""
    Local i
    Local cBody, oJ, oChoice, cEscolhido
    Local nStatus

    For i := 1 To Len(aModels)
        If i > 1
            cModelsList += ", "
        EndIf
        cModelsList += aModels[i][1]
    Next i

    FWHTTPHEADER("Authorization", "Bearer " + cApiKey)
    cBody := '{"model":"agnes-2.5-flash","messages":[{"role":"user","content":"' + ;
        JsonEscape("Voce e um roteador. Escolha o modelo mais adequado da lista abaixo para responder a pergunta do usuario. Responda APENAS com o id exato do modelo, sem explicacoes." + Chr(10) + ;
        "Modelos disponiveis: " + cModelsList + Chr(10) + ;
        "Pergunta: " + cPrompt) + ;
        '"}],"stream":false,"max_tokens":50}'
    nStatus := FWHTTPPOST("https://apihub.agnes-ai.com/v1/chat/completions", cBody, "application/json")
    FWHTTPCLEARHEADERS()

    If nStatus != 200
        Return ""
    EndIf

    oJ := JsonObject():New()
    If oJ:FromJson(FWHTTPBODY())
        oChoice := oJ["choices"][1]
        If ValType(oChoice) == "O"
            cEscolhido := AllTrim(oChoice["message"]["content"])
            For i := 1 To Len(aModels)
                If Lower(aModels[i][1]) == Lower(cEscolhido) .Or. Lower(aModels[i][1]) $ Lower(cEscolhido)
                    Return aModels[i][1]
                EndIf
            Next i
        EndIf
    EndIf

Return aModels[1][1]

/*/{Protheus.doc} ShowOrchestratorBox
    Caixa de exibicao padrao do agente orchestrator (mesmo padrao visual
    dos outros agentes), mostrando qual modelo local foi escolhido no
    subtitulo.
@type function
/*/
Static Function ShowOrchestratorBox(cEsc, cModeloEscolhido, cResponse, nInner, nElapsed)
    ConOut("")
    ConOut(BoxTop(cEsc, nInner, "1;31"))
    ConOut(BoxAgentTitle(cEsc, "AGENT:ORCHESTRATOR", cModeloEscolhido, nInner, "1;31"))
    ConOut(BoxDiv(cEsc, nInner, "1;31"))
    ConOut(cResponse)
    ConOut(BoxBottom(cEsc, nInner, "1;31"))
    ConOut(cEsc + "[2m  " + AllTrim(Str(nElapsed, 10, 1)) + "s response time" + cEsc + "[0m")
    ConOut("")
Return Nil
```

Observação de tipo: `aModels[i]` é um array `{cId, cDisplayName}` (ver
`LoadModels`, linha ~152-162) — `aModels[i][1]` é sempre o id usado nas
chamadas de API, igual já é usado em `PickModel`/`Main`.

### Passo 2.6: Build local do shortcoder e teste manual (sem key/Ollama)

```bash
cd /home/peder/Projetos/shortcoder
ADVPP_SRC=/home/peder/Projetos/AdvPP advplc build shortcoder.prw -o shortcoder 2>&1 | tail -40
```

Expected: `Standalone executable built: shortcoder` (sem erros de
compilação — isso já valida sintaxe e resolução de símbolos das funções
novas).

```bash
printf '/agent\n5\n/exit\n' | ./shortcoder 2>&1 | grep -i "orchestrator"
```

Expected: linha da opção `[5] orchestrator` no menu e `AGENT: [ORCHESTRATOR]`
na status bar atualizada.

### Passo 2.7: Teste ponta a ponta (requer `AGNES_API_KEY` e Ollama local)

Só rodar se `AGNES_API_KEY` estiver setada no ambiente e `ollama serve`
estiver ativo em `127.0.0.1:11434`:

```bash
cd /home/peder/Projetos/shortcoder
printf '/agent\n5\nolá, tudo bem?\n/history\n/exit\n' | ./shortcoder 2>&1 | tail -60
```

Expected: caixa `AGENT:ORCHESTRATOR` com o nome do modelo local escolhido
no subtítulo, resposta formatada, e `/history` listando a entrada com tag
`orchestrator`. Se `AGNES_API_KEY` não estiver disponível neste ambiente,
pular este passo e registrar isso ao reportar a task (não é um teste que
pode ser simulado sem a chave real).

### Passo 2.8: Commit no shortcoder

```bash
cd /home/peder/Projetos/shortcoder
git add shortcoder.prw
git commit -m "$(cat <<'EOF'
Adiciona agente orchestrator: Agnes roteia Ollama local via job assincrono

Novo agente [5] no /agent. Agnes decide qual modelo Ollama local
responder (DecideOrchestratorModel), a chamada roda em background via
FWJOBSTART/FWJOBPOLL (AdvPP) enquanto um spinner anima o prompt, e
Agnes revisa a resposta local antes de exibir (RunOrchestratorAgent).
EOF
)"
```

---

## Task 3: Documentação (`/help` e README.md)

**Files:**
- Modify: `/home/peder/Projetos/shortcoder/shortcoder.prw` (`ShowBBSHelp`,
  linha ~650)
- Modify: `/home/peder/Projetos/shortcoder/README.md` (comandos, tabela de
  agentes)

**Interfaces:**
- Consumes: nada novo — só texto.
- Produces: nada consumido por outra task.

### Passo 3.1: `ShowBBSHelp`

Mudar:

```advpl
    ConOut(BoxCmdLine(cEsc, "/agent", "Switch agent (ollama/mem0/ernesto/agnes)", nInner, "1;33"))
```

Para:

```advpl
    ConOut(BoxCmdLine(cEsc, "/agent", "Switch agent (ollama/mem0/ernesto/agnes/orchestrator)", nInner, "1;33"))
```

### Passo 3.2: README.md — comandos

Em `README.md`, na seção `## Comandos`, mudar:

```
/agent     — Troca entre ollama (rapido), mem0 (memoria), ernesto (RAG), agnes (remoto)
```

Para:

```
/agent     — Troca entre ollama (rapido), mem0 (memoria), ernesto (RAG), agnes (remoto), orchestrator (agnes roteia ollama local)
```

### Passo 3.3: README.md — tabela de Agentes

Na seção `## Agentes`, adicionar linha depois da linha do `agnes`:

```
| orchestrator | Agnes decide + `:11434` local + Agnes revisa | ~2 chamadas remotas + 1 local (async) | Agnes 2.5 Flash roteia a pergunta para o melhor modelo Ollama local (via job assíncrono do AdvPP) e revisa a resposta antes de exibir. Requer `AGNES_API_KEY` e Ollama local rodando. |
```

### Passo 3.4: Rebuild + verificação visual do `/help`

```bash
cd /home/peder/Projetos/shortcoder
ADVPP_SRC=/home/peder/Projetos/AdvPP advplc build shortcoder.prw -o shortcoder
printf '/help\n/exit\n' | ./shortcoder 2>&1 | grep -i "orchestrator"
```

Expected: linha do `/agent` no help mostrando `orchestrator` na lista.

### Passo 3.5: Commit

```bash
cd /home/peder/Projetos/shortcoder
git add shortcoder.prw README.md
git commit -m "$(cat <<'EOF'
Documenta agente orchestrator no /help e no README
EOF
)"
```

---

## Task 4: Instalação final

**Files:** nenhum arquivo de repositório — só binários instalados.

**Interfaces:** consumes o binário `shortcoder` já buildado nas tasks
anteriores.

### Passo 4.1: Confirmar binário atualizado e instalar

```bash
cd /home/peder/Projetos/shortcoder
ADVPP_SRC=/home/peder/Projetos/AdvPP advplc build shortcoder.prw -o shortcoder
cp shortcoder ~/.local/bin/shortcoder
printf '/agent\n5\n/exit\n' | ~/.local/bin/shortcoder 2>&1 | grep -i "orchestrator"
```

Expected: `~/.local/bin/shortcoder` mostra a opção `orchestrator` no menu
`/agent` — confirma que o binário instalado é o novo, não um stale (mesmo
cuidado já validado no início desta sessão).

### Passo 4.2: Relatar ao usuário

Resumir: o que foi testado com sucesso, e se o passo 2.7 (teste ponta a
ponta com Agnes real + Ollama real) rodou ou foi pulado por falta de
`AGNES_API_KEY`/Ollama ativo no ambiente — nesse caso, pedir para o usuário
rodar `/agent` → `5` manualmente e confirmar.
