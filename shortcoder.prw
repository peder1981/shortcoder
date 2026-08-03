#include "protheus.ch"

/*/{Protheus.doc} Main
    shortcoder — TUI estilo BBS classico com estetica retrô.
    Interface 100% legivel com caixas delimitadas e texto quebrado corretamente.
    ORQUESTRACAO ENTRE AGENTES:
      - Detecta dominio da pergunta (Protheus, Mem0, geral)
      - Roteia automaticamente para o agente mais adequado
      - Suporta multi-agente (agente primario + sec undario)
@type function
@author shortcoder
@since 02/08/2026
/*/
User Function Main()
    Local cEsc      := Chr(27)
    Local cHome     := GetEnv("HOME", "")
    Local cModelsJs := cHome + "/.config/little-coder/models.json"
    Local aModels   := {}
    Local cDefModel := "lfm25-1b-uncensored:latest"
    Local cModel
    Local cSession  := NewSessionId()
    Local nWidth    := Min(UiTermWidth(80) - 4, 96)
    Local cInput
    Local cAgent    := "ollama"
    Local cMemUser  := "default"
    Local aHistory  := {}
    Local cSelectedAgent

    LoadModels(cModelsJs, @aModels, @cDefModel)
    cModel := cDefModel

    UiAltScreenEnter()
    ShowBBSHeader(cEsc, nWidth)
    ShowStatus(cEsc, cModel, cSession, cAgent, cMemUser, nWidth)

    While .T.
        cInput := ConIn(cEsc + "[1;33m>" + cEsc + "[0m ")

        If ValType(cInput) == "U"
            Exit
        EndIf
        cInput := AllTrim(cInput)

        If Empty(cInput)
            Loop
        ElseIf Lower(cInput) == "/exit" .Or. Lower(cInput) == "/quit"
            Exit
        ElseIf Lower(cInput) == "/help"
            ShowBBSHelp(cEsc, nWidth)
            Loop
        ElseIf Lower(cInput) == "/clear"
            cSession := NewSessionId()
            aHistory := {}
            ConOutRaw(cEsc + "[2J" + cEsc + "[H")
            ShowBBSHeader(cEsc, nWidth)
            ShowStatus(cEsc, cModel, cSession, cAgent, cMemUser, nWidth)
            Loop
        ElseIf Lower(cInput) == "/model"
            cModel := PickModel(cEsc, aModels, cModel, nWidth)
            Loop
        ElseIf Lower(cInput) == "/agent"
            cAgent := PickAgent(cEsc, cAgent)
            ShowStatus(cEsc, cModel, cSession, cAgent, cMemUser, nWidth)
            Loop
        ElseIf Lower(cInput) == "/mem0 list"
            RunMem0Agent(cEsc, cMemUser, nWidth, @aHistory)
            Loop
        ElseIf Lower(Left(cInput, 10)) == "/mem0 add "
            cInput := SubStr(cInput, 11)
            RunMem0Add(cEsc, cMemUser, cInput, nWidth, @aHistory)
            Loop
        ElseIf Lower(cInput) == "/mem0 clear"
            RunMem0Clear(cEsc, cMemUser, nWidth, @aHistory)
            Loop
        ElseIf Lower(cInput) == "/history"
            ShowHistory(cEsc, aHistory, nWidth)
            Loop
        Else
            ShowUserMessage(cEsc, cInput, nWidth)
            
            // ORQUESTRACAO: Decide qual agente usar baseado no conteudo
            cSelectedAgent := DetectAgent(cInput, cAgent)
            
            If cSelectedAgent == "mem0"
                RunMem0Agent(cEsc, cMemUser, nWidth, @aHistory)
            ElseIf cSelectedAgent == "ernesto"
                RunErnestoAgent(cEsc, cInput, cModel, nWidth, @aHistory)
            Else
                RunOllamaAgent(cEsc, cInput, cModel, nWidth, @aHistory)
            EndIf
        EndIf
    End

    UiAltScreenExit()
    ConOut(cEsc + "[2m[EOF] Conectado por " + cSession + cEsc + "[0m")
Return

/*/{Protheus.doc} NewSessionId
@type function
/*/
Static Function NewSessionId()
Return "user-" + DToS(Date()) + "-" + StrTran(Str(Seconds(), 12, 3), ".", "")

/*/{Protheus.doc} JsonEscape
    Escapa uma string para uso segura dentro de um valor JSON
@type function
/*/
Static Function JsonEscape(cText)
    Local cResult := cText
    cResult := StrTran(cResult, "\", "\\")
    cResult := StrTran(cResult, Chr(34), '\"')
    cResult := StrTran(cResult, Chr(10), "\n")
    cResult := StrTran(cResult, Chr(13), "")
Return cResult

/*/{Protheus.doc} LoadModels
@type function
/*/
Static Function LoadModels(cPath, aModels, cDefModel)
    Local cJson := MemoRead(cPath)
    Local oRoot := JsonObject():New()
    Local aProvNames, cProv, oProv, aProvModels, oModel
    Local i, j, nIdx, cId

    If Empty(cJson) .Or. !oRoot:FromJson(cJson)
        Return Nil
    EndIf

    If ValType(oRoot["default"]) == "C" .And. !Empty(oRoot["default"])
        cDefModel := oRoot["default"]
        nIdx := At("/", cDefModel)
        If nIdx > 0
            cDefModel := SubStr(cDefModel, nIdx + 1)
        EndIf
    EndIf

    If ValType(oRoot["providers"]) != "O"
        Return Nil
    EndIf

    aProvNames := oRoot["providers"]:GetNames()
    For i := 1 To Len(aProvNames)
        cProv := aProvNames[i]
        oProv := oRoot["providers"][cProv]
        If ValType(oProv["models"]) != "A"
            Loop
        EndIf
        aProvModels := oProv["models"]
        For j := 1 To Len(aProvModels)
            oModel := aProvModels[j]
            If ValType(oModel["id"]) == "C"
                cId := oModel["id"]
                If At("/", cId) > 0
                    cId := SubStr(cId, At("/", cId) + 1)
                EndIf
                If ValType(oModel["name"]) == "C"
                    aAdd(aModels, {cId, oModel["name"]})
                Else
                    aAdd(aModels, {cId, cId})
                EndIf
            EndIf
        Next j
    Next i

    ASort(aModels, , , {|x, y| x[1] < y[1]})
Return Nil

/*/{Protheus.doc} StripANSI
    Remove sequencias ANSI de uma string e devolve o texto puro
@type function
/*/
Static Function StripANSI(cEsc, cText)
    Local cResult := cText
    Local nIdx

    // Remove codes como [1;33m, [0m, etc
    Do While At(cEsc + "[", cResult) > 0
        nIdx := At(cEsc + "[", cResult)
        cResult := SubStr(cResult, 1, nIdx - 1) + SubStr(cResult, nIdx + 2)
        // Pula ate encontrar 'm'
        nIdx := At("m", cResult)
        If nIdx > 0
            cResult := SubStr(cResult, 1, nIdx) + SubStr(cResult, nIdx + 1)
        EndIf
    Loop
    
Return cResult

/*/{Protheus.doc} WordWrap
    Quebra texto em linhas de tamanho maximo, respeitando palavras
@type function
/*/
Static Function WordWrap(cText, nMaxLen)
    Local aLines := {}
    Local aWords := {}
    Local cWord := ""
    Local cLine := ""
    Local cChar
    Local nWordLen, nLineLen, nSep
    Local nLen, i

    cText := StrTran(cText, Chr(10), " ")
    cText := StrTran(cText, Chr(13), " ")
    // Manual tokenization since StrTokArray doesn't exist
    nLen := Len(cText)

    For i := 1 To nLen
        cChar := SubStr(cText, i, 1)
        If cChar == " " .And. !Empty(cWord)
            aAdd(aWords, cWord)
            cWord := ""
        Else
            cWord := cWord + cChar
        EndIf
    Next i

    If !Empty(cWord)
        aAdd(aWords, cWord)
    EndIf

    For i := 1 To Len(aWords)
        cWord := aWords[i]
        nWordLen := Len(cWord)
        nLineLen := Len(cLine)

        nSep := 0
        If !Empty(cLine)
            nSep := 1
        EndIf

        If nLineLen + nWordLen + nSep <= nMaxLen
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

/*/{Protheus.doc} ShowBBSHeader
@type function
/*/
Static Function ShowBBSHeader(cEsc, nWidth)
    Local cArt := cEsc + "[1;33m" + ;
        " ╔" + Replicate("�?", nWidth - 2) + "╗" + Chr(10) + ;
        " ║" + Replicate(" ", nWidth - 2) + "║" + Chr(10) + ;
        " ║" + PadCenter("SHORTCODER", nWidth - 2) + "║" + Chr(10) + ;
        " ║" + Replicate(" ", nWidth - 2) + "║" + Chr(10) + ;
        " ║" + PadCenter("[AI Coding Agent v1.0] [BBS Edition]", nWidth - 2) + "║" + Chr(10) + ;
        " ║" + Replicate(" ", nWidth - 2) + "║" + Chr(10) + ;
        " ╚" + Replicate("�?", nWidth - 2) + "�?" + cEsc + "[0m"
    
    ConOut(cArt)
Return Nil

/*/{Protheus.doc} PadCenter
    Centraliza texto em espaco dado
@type function
/*/
Static Function PadCenter(cText, nWidth)
    Local nTextLen := Len(cText)
    Local nPad := nWidth - nTextLen
    Local nLeft := Int(nPad / 2)
    
    If nPad <= 0
        Return Left(cText, nWidth)
    EndIf
    
Return Replicate(" ", nLeft) + cText + Replicate(" ", nPad - nLeft)

/*/{Protheus.doc} ShowStatus
@type function
/*/
Static Function ShowStatus(cEsc, cModel, cSession, cAgent, cMemUser, nWidth)
    Local cLine1, cLine2, cLine3, cLine4
    
    cLine1 := " │ MODEL:  [" + cEsc + "[1;33m" + Left(cModel, 30) + cEsc + "[36m" + "]                   │"
    cLine2 := " │ SESSION:[0m" + cEsc + "[1;33m" + Left(cSession, 30) + cEsc + "[36m" + "]                   │"
    cLine3 := " │ AGENT:  [" + cEsc + "[1;33m" + Upper(cAgent) + cEsc + "[36m" + "]                          │"
    cLine4 := " │ MEM0:   [" + cEsc + "[1;33m" + cMemUser + cEsc + "[36m" + "]                            │"
    
    ConOut(cEsc + "[2;36m" + ;
        " ┌" + Replicate("─", nWidth - 2) + "�?" + Chr(10) + ;
        cLine1 + Chr(10) + ;
        cLine2 + Chr(10) + ;
        cLine3 + Chr(10) + ;
        cLine4 + Chr(10) + ;
        " └" + Replicate("─", nWidth - 2) + "┘" + cEsc + "[0m")
Return Nil

Static Function ShowBBSHelp(cEsc, nWidth)
    Local nBoxW := nWidth - 2
    
    ConOut("")
    ConOut(cEsc + "[1;33m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut(cEsc + "[1;33m|" + PadCenter("[ COMMAND LIST ]", nBoxW) + "|" + cEsc + "[0m")
    ConOut(cEsc + "[1;33m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut(cEsc + "[2;37m|" + cEsc + "[0m " + cEsc + "[1mAGENTES:" + cEsc + "[0m" + Replicate(" ", nBoxW - 12) + cEsc + "[2m|" + cEsc + "[0m")
    ConOut(cEsc + "[2;37m|" + cEsc + "[0m   /agent          - Switch agent (ollama/mem0/ernesto)" + Replicate(" ", Max(0, nBoxW - 58)) + cEsc + "[2m|" + cEsc + "[0m")
    ConOut(cEsc + "[2;37m|" + cEsc + "[0m   /model          - List & select model" + Replicate(" ", Max(0, nBoxW - 48)) + cEsc + "[2m|" + cEsc + "[0m")
    ConOut(cEsc + "[2;37m|" + cEsc + "[0m " + Replicate(" ", nBoxW) + cEsc + "[2m|" + cEsc + "[0m")
    ConOut(cEsc + "[2;37m|" + cEsc + "[0m " + cEsc + "[1mMEMORIA PERSISTENTE:" + cEsc + "[0m" + Replicate(" ", Max(0, nBoxW - 32)) + cEsc + "[2m|" + cEsc + "[0m")
    ConOut(cEsc + "[2;37m|" + cEsc + "[0m   /mem0 list      - View saved memories" + Replicate(" ", Max(0, nBoxW - 48)) + cEsc + "[2m|" + cEsc + "[0m")
    ConOut(cEsc + "[2;37m|" + cEsc + "[0m   /mem0 add <txt> - Save a memory" + Replicate(" ", Max(0, nBoxW - 40)) + cEsc + "[2m|" + cEsc + "[0m")
    ConOut(cEsc + "[2;37m|" + cEsc + "[0m   /mem0 clear     - Remove all memories" + Replicate(" ", Max(0, nBoxW - 48)) + cEsc + "[2m|" + cEsc + "[0m")
    ConOut(cEsc + "[2;37m|" + cEsc + "[0m " + Replicate(" ", nBoxW) + cEsc + "[2m|" + cEsc + "[0m")
    ConOut(cEsc + "[2;37m|" + cEsc + "[0m " + cEsc + "[1mOUTROS:" + cEsc + "[0m" + Replicate(" ", nBoxW - 9) + cEsc + "[2m|" + cEsc + "[0m")
    ConOut(cEsc + "[2;37m|" + cEsc + "[0m   /clear   - New session (clear history)" + Replicate(" ", Max(0, nBoxW - 50)) + cEsc + "[2m|" + cEsc + "[0m")
    ConOut(cEsc + "[2;37m|" + cEsc + "[0m   /history - View conversation history" + Replicate(" ", Max(0, nBoxW - 48)) + cEsc + "[2m|" + cEsc + "[0m")
    ConOut(cEsc + "[2;37m|" + cEsc + "[0m   /help    - This help screen" + Replicate(" ", Max(0, nBoxW - 38)) + cEsc + "[2m|" + cEsc + "[0m")
    ConOut(cEsc + "[2;37m|" + cEsc + "[0m   /exit    - Disconnect" + Replicate(" ", Max(0, nBoxW - 30)) + cEsc + "[2m|" + cEsc + "[0m")
    ConOut(cEsc + "[1;33m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut("")
Return Nil

/*/{Protheus.doc} PickAgent
@type function
/*/
Static Function PickAgent(cEsc, cCurrent)
    Local cChoice
    
    ConOut("")
    ConOut(cEsc + "[1;33m+" + Replicate("─", 40) + "+" + cEsc + "[0m")
    ConOut(cEsc + "[1;33m|" + PadCenter("[ SELECT AGENT ]", 40) + "|" + cEsc + "[0m")
    ConOut(cEsc + "[1;33m+" + Replicate("─", 40) + "+" + cEsc + "[0m")
    ConOut(cEsc + "[2m  [1]" + cEsc + "[0m ollama  — Fast LLM (lfm25, ~1s response)")
    ConOut(cEsc + "[2m  [2]" + cEsc + "[0m mem0    — Persistent memory queries")
    ConOut(cEsc + "[2m  [3]" + cEsc + "[0m ernesto — RAG + Memory (slow, >30s)")
    ConOut(cEsc + "[1;33m+" + Replicate("─", 40) + "+" + cEsc + "[0m")
    ConOut("")
    
    cChoice := AllTrim(ConIn("Select agent [1-3] (Enter=" + cCurrent + "): "))
    ConOut("")
    
    If cChoice == "1"
        Return "ollama"
    ElseIf cChoice == "2"
        Return "mem0"
    ElseIf cChoice == "3"
        Return "ernesto"
    EndIf
Return cCurrent

/*/{Protheus.doc} PickModel
@type function
/*/
Static Function PickModel(cEsc, aModels, cCurrent, nWidth)
    Local i, cChoice, nIdx, nBoxW := 50
    
    If Len(aModels) == 0
        ConOut(cEsc + "[33m[WARN] No models found — keeping " + cCurrent + cEsc + "[0m")
        Return cCurrent
    EndIf
    
    ConOut("")
    ConOut(cEsc + "[1;33m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut(cEsc + "[1;33m|" + PadCenter("[ MODEL SELECT ]", nBoxW) + "|" + cEsc + "[0m")
    ConOut(cEsc + "[1;33m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    
    For i := 1 To Min(Len(aModels), 20)
        ConOut(cEsc + "[2m  [" + StrZero(i, 2) + "]" + cEsc + "[0m " + Left(aModels[i][1], nBoxW - 8))
    Next i
    
    ConOut(cEsc + "[1;33m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut("")
    
    cChoice := AllTrim(ConIn("Select model [1-" + Str(Len(aModels)) + "] or type name: "))
    ConOut("")
    
    If Empty(cChoice)
        Return cCurrent
    EndIf
    
    nIdx := Val(cChoice)
    If nIdx >= 1 .And. nIdx <= Len(aModels)
        Return aModels[nIdx][1]
    EndIf
Return cChoice

/*/{Protheus.doc} RunOllamaAgent
@type function
/*/
Static Function RunOllamaAgent(cEsc, cPrompt, cModel, nWidth, aHistory)
    Local cResponse
    Local nStart
    Local nStatus
    Local cBody, oJ, oChoice
    Local nBoxW := nWidth - 2

    nStart := Seconds()
    cBody := '{"model":"' + cModel + '","messages":[{"role":"user","content":"' + JsonEscape(cPrompt) + '"}],"stream":false,"max_tokens":500}'

    nStatus := FWHTTPPOST("http://127.0.0.1:11434/v1/chat/completions", cBody, "application/json")

    If nStatus != 200
        Local cErr := FWHTTPERROR()
        If !Empty(cErr) .And. At("timeout", Lower(cErr)) > 0
            cResponse := cEsc + "[1;33m[TIMEOUT] Model too slow (load >30s) — try /agent 1 for fast LLM" + cEsc + "[0m"
        Else
            cResponse := cEsc + "[1;31m[ERROR] HTTP " + AllTrim(Str(nStatus)) + " — " + Left(cErr, 40) + cEsc + "[0m"
        EndIf
    Else
        cBody := FWHTTPBODY()
        oJ := JsonObject():New()
        If oJ:FromJson(cBody)
            oChoice := oJ["choices"][1]
            If ValType(oChoice) == "O"
                Local cContent := AllTrim(oChoice["message"]["content"])
                Local cReasoning := AllTrim(oChoice["message"]["reasoning"])
                If !Empty(cContent)
                    cResponse := FormatTextForBox(cEsc, cContent, nWidth - 4, nWidth - 2)
                ElseIf !Empty(cReasoning)
                    cResponse := FormatTextForBox(cEsc, cReasoning, nWidth - 4, nWidth - 2)
                Else
                    cResponse := cEsc + "[2m[NO CONTENT]" + cEsc + "[0m"
                EndIf
            Else
                cResponse := cEsc + "[2m[NO RESPONSE]" + cEsc + "[0m"
            EndIf
        Else
            cResponse := cEsc + "[1;33m[PARSE ERR]" + cEsc + "[0m"
        EndIf
    EndIf

    ConOut("")
    ConOut(cEsc + "[1;36m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut(cEsc + "[1;36m|" + cEsc + "[1;33m AGENT:OLLAMA " + cEsc + "[36m" + cEsc + "[2m" + cModel + Replicate(" ", Max(0, nBoxW - 22 - Len(cModel))) + " " + cEsc + "[1;36m|" + cEsc + "[0m")
    ConOut(cEsc + "[1;36m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut(cResponse)
    ConOut(cEsc + "[1;36m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut(cEsc + "[2m  " + AllTrim(Str(Seconds() - nStart, 10, 1)) + "s response time" + cEsc + "[0m")
    ConOut("")

    aAdd(aHistory, {"ollama", cPrompt, Seconds() - nStart})
Return Nil

/*/{Protheus.doc} FormatTextForBox
    Formata texto para caber dentro de caixa BBS
@type function
/*/
Static Function FormatTextForBox(cEsc, cText, nMaxLen, nBoxW)
    Local aLines, cLine, cResult := "", i, nLen, cStripped
    
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

/*/{Protheus.doc} RunMem0Agent
@type function
/*/
Static Function RunMem0Agent(cEsc, cUserId, nWidth, aHistory)
    Local cResponse
    Local nStart
    Local nStatus
    Local cBody
    Local oJ, aMemories, oMem
    Local i, cContent, cCat, cConf
    Local nCount := 0
    Local nBoxW := nWidth - 2

    nStart := Seconds()
    nStatus := FWHTTPGET("http://127.0.0.1:9081/memories/" + cUserId)

    If nStatus != 200
        cResponse := cEsc + "[1;31m[ERROR] HTTP " + AllTrim(Str(nStatus)) + " — mem0 unavailable" + cEsc + "[0m"
    Else
        cBody := FWHTTPBODY()
        oJ := JsonObject():New()
        If oJ:FromJson(cBody)
            aMemories := oJ["memories"]
            If ValType(aMemories) == "A" .And. Len(aMemories) > 0
                cResponse := ""
                For i := 1 To Min(Len(aMemories), 10)
                    oMem := aMemories[i]
                    If ValType(oMem) == "O"
                        cContent := AllTrim(oMem["content"])
                        cCat := oMem["metadata"]["category"]
                        cConf := AllTrim(Str(oMem["metadata"]["confidence"], 5, 2))
                        If !Empty(cContent)
                            nCount++
                            cResponse := cResponse + cEsc + "[2m[" + cCat + "] conf:" + cConf + cEsc + "[0m "
                            cResponse := cResponse + Left(cContent, 100)
                            If Len(cContent) > 100
                                cResponse := cResponse + "..."
                            EndIf
                            cResponse := cResponse + Chr(10)
                        EndIf
                    EndIf
                Next i
                If nCount == 0
                    cResponse := cEsc + "[2m[NO MEMORIES]" + cEsc + "[0m"
                Else
                    cResponse := cEsc + "[2m--- " + AllTrim(Str(nCount)) + " of " + AllTrim(Str(Len(aMemories))) + " memories shown ---" + cEsc + "[0m" + Chr(10) + cResponse
                EndIf
            Else
                cResponse := cEsc + "[2m[NO MEMORIES]" + cEsc + "[0m"
            EndIf
        Else
            cResponse := cEsc + "[1;33m[PARSE ERR]" + cEsc + "[0m"
        EndIf
    EndIf

    ConOut("")
    ConOut(cEsc + "[1;32m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut(cEsc + "[1;32m|" + cEsc + "[1;33m AGENT:MEM0   " + cEsc + "[32m" + cEsc + "[2mPersistent Memory Store" + Replicate(" ", Max(0, nBoxW - 35)) + " " + cEsc + "[1;32m|" + cEsc + "[0m")
    ConOut(cEsc + "[1;32m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut(cResponse)
    ConOut(cEsc + "[1;32m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut(cEsc + "[2m  " + AllTrim(Str(Seconds() - nStart, 10, 1)) + "s · " + AllTrim(Str(nCount)) + " results" + cEsc + "[0m")
    ConOut("")

    aAdd(aHistory, {"mem0", "", Seconds() - nStart})
Return Nil

/*/{Protheus.doc} RunErnestoAgent
@type function
/*/
Static Function RunErnestoAgent(cEsc, cPrompt, cModel, nWidth, aHistory)
    Local cResponse
    Local nStart
    Local nStatus
    Local cBody, oJ, oChoice
    Local nBoxW := nWidth - 2

    nStart := Seconds()
    cBody := '{"model":"' + cModel + '","messages":[{"role":"user","content":"' + JsonEscape(cPrompt) + '"}],"stream":false,"max_tokens":500}'

    nStatus := FWHTTPPOST("http://127.0.0.1:9081/v1/chat/completions", cBody, "application/json")

    If nStatus != 200
        Local cErr := FWHTTPERROR()
        If !Empty(cErr) .And. At("timeout", Lower(cErr)) > 0
            cResponse := cEsc + "[1;33m[TIMEOUT] RAG pipeline slow (>30s) — use ollama agent for fast responses" + cEsc + "[0m"
        Else
            cResponse := cEsc + "[1;31m[ERROR] HTTP " + AllTrim(Str(nStatus)) + " — " + Left(cErr, 40) + cEsc + "[0m"
        EndIf
    Else
        cBody := FWHTTPBODY()
        oJ := JsonObject():New()
        If oJ:FromJson(cBody)
            oChoice := oJ["choices"][1]
            If ValType(oChoice) == "O"
                cResponse := FormatTextForBox(cEsc, AllTrim(oChoice["message"]["content"]), nWidth - 4, nBoxW)
            Else
                cResponse := cEsc + "[2m[NO RESPONSE]" + cEsc + "[0m"
            EndIf
        Else
            cResponse := cEsc + "[1;33m[PARSE ERR]" + cEsc + "[0m"
        EndIf
    EndIf

    ConOut("")
    ConOut(cEsc + "[1;35m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut(cEsc + "[1;35m|" + cEsc + "[1;33m AGENT:ERNESO " + cEsc + "[35m" + cEsc + "[2mRAG + Memory Integrated" + Replicate(" ", Max(0, nBoxW - 35)) + " " + cEsc + "[1;35m|" + cEsc + "[0m")
    ConOut(cEsc + "[1;35m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut(cResponse)
    ConOut(cEsc + "[1;35m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut(cEsc + "[2m  " + AllTrim(Str(Seconds() - nStart, 10, 1)) + "s response time" + cEsc + "[0m")
    ConOut("")

    aAdd(aHistory, {"ernesto", cPrompt, Seconds() - nStart})
Return Nil

/*/{Protheus.doc} RunMem0Add
@type function
/*/
Static Function RunMem0Add(cEsc, cUserId, cContent, nWidth, aHistory)
    Local nStatus
    Local nStart := Seconds()
    Local nBoxW := nWidth - 2

    nStatus := FWHTTPPOST("http://127.0.0.1:9081/memories/" + cUserId, ;
        '{"content":"' + JsonEscape(cContent) + '"}', ;
        "application/json")

    ConOut("")
    ConOut(cEsc + "[1;32m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    If nStatus == 200
        ConOut(cEsc + "[1;32m|" + cEsc + "[32m[OK]      " + cEsc + "[37mMemory saved successfully" + Replicate(" ", Max(0, nBoxW - 35)) + " " + cEsc + "[1;32m|" + cEsc + "[0m")
    Else
        ConOut(cEsc + "[1;32m|" + cEsc + "[31m[ERROR]   " + cEsc + "[37mHTTP " + AllTrim(Str(nStatus)) + " — could not save memory" + Replicate(" ", Max(0, nBoxW - 45)) + " " + cEsc + "[1;32m|" + cEsc + "[0m")
    EndIf
    ConOut(cEsc + "[1;32m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut(cEsc + "[2m  " + AllTrim(Str(Seconds() - nStart, 10, 1)) + "s" + cEsc + "[0m")
    ConOut("")

    aAdd(aHistory, {"mem0/add", cContent, Seconds() - nStart})
Return Nil

/*/{Protheus.doc} RunMem0List
@type function
/*/
Static Function RunMem0List(cEsc, cUserId, nWidth, aHistory)
    RunMem0Agent(cEsc, cUserId, nWidth, aHistory)
Return Nil

/*/{Protheus.doc} RunMem0Clear
@type function
/*/
Static Function RunMem0Clear(cEsc, cUserId, nWidth, aHistory)
    Local nStatus
    Local nStart := Seconds()
    Local nBoxW := nWidth - 2

    nStatus := FWHTTPDELETE("http://127.0.0.1:9081/memories/" + cUserId)

    ConOut("")
    ConOut(cEsc + "[1;32m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    If nStatus == 200
        ConOut(cEsc + "[1;32m|" + cEsc + "[32m[OK]      " + cEsc + "[37mAll memories cleared" + Replicate(" ", Max(0, nBoxW - 30)) + " " + cEsc + "[1;32m|" + cEsc + "[0m")
    Else
        ConOut(cEsc + "[1;32m|" + cEsc + "[31m[ERROR]   " + cEsc + "[37mHTTP " + AllTrim(Str(nStatus)) + " — could not clear" + Replicate(" ", Max(0, nBoxW - 38)) + " " + cEsc + "[1;32m|" + cEsc + "[0m")
    EndIf
    ConOut(cEsc + "[1;32m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut(cEsc + "[2m  " + AllTrim(Str(Seconds() - nStart, 10, 1)) + "s" + cEsc + "[0m")
    ConOut("")

    aAdd(aHistory, {"mem0/clear", "", Seconds() - nStart})
Return Nil

/*/{Protheus.doc} DetectAgent
    ORQUESTRACAO: Detecta qual agente usar baseado no conteudo da mensagem.
    Regras de classificacao:
      - Palavras-chave de memoria → mem0
      - Palavras-chave de dominio Protheus → ernesto (RAG)
      - Padrão → ollama (LLM geral)
@type function
/*/
Static Function DetectAgent(cInput, cDefaultAgent)
    Local cLower := Lower(cInput)
    
    // Regra 1: Comandos mem0 explicitos
    If Left(cLower, 10) == "/mem0 " .Or. cLower == "/mem0 list" .Or. cLower == "/mem0 add" .Or. cLower == "/mem0 clear"
        Return "mem0"
    EndIf
    
    // Regra 2: Palavras-chave de dominio Protheus/AdvPL
    Local aProtheusKeywords := { ;
        "campo", "tabela", "sx2", "sx3", "six", "formulario", "rotina", ;
        "como funciona", "onde esta", "o que e", "query", "sql", "trigger", ;
        "indice", "protheus", "advpl", "tlpp", "totvs", "mata", "finan", ;
        "se1", "sa1", "sb1", "sc1", "sd1", "sf1", "sg1", "sh1", ;
        "d_e_l_e_t_", "xfilial", "fwexecstatement", "tcquery", "dbquery", ;
        "entrada", "rotina m", "user function", "usf_", "paramixb" ;
    }
    Local i
    For i := 1 To Len(aProtheusKeywords)
        If aProtheusKeywords[i] $ cLower
            Return "ernesto"
        EndIf
    Next i
    
    // Regra 3: Padrão usa agente selecionado
Return cDefaultAgent

/*/{Protheus.doc} ShowUserMessage
@type function
/*/
Static Function ShowUserMessage(cEsc, cMsg, nWidth)
    Local nBoxW := nWidth - 2
    Local aLines, cLine, i
    
    ConOut("")
    ConOut(cEsc + "[1;33m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut(cEsc + "[1;33m|" + cEsc + "[1;37m USER     " + cEsc + "[33m" + cEsc + "[2m" + Left(cMsg, nBoxW - 14) + Replicate(" ", Max(0, nBoxW - 14 - Len(cMsg))) + " " + cEsc + "[1;33m|" + cEsc + "[0m")
    ConOut(cEsc + "[1;33m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
Return Nil

/*/{Protheus.doc} ShowHistory
@type function
/*/
Static Function ShowHistory(cEsc, aHistory, nWidth)
    Local nBoxW := nWidth - 2
    Local i, cLine
    
    ConOut("")
    ConOut(cEsc + "[1;33m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut(cEsc + "[1;33m|" + cEsc + "[1;37m HISTORY   " + Replicate(" ", Max(0, nBoxW - 14)) + " " + cEsc + "[1;33m|" + cEsc + "[0m")
    ConOut(cEsc + "[1;33m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")

    If Len(aHistory) == 0
        ConOut(cEsc + "[2m  [EMPTY] No conversation history" + cEsc + "[0m")
    Else
        For i := 1 To Len(aHistory)
            cLine := cEsc + "[2m  [" + StrZero(i, 3) + "]" + cEsc + "[0m "
            cLine := cLine + cEsc + "[1m" + aHistory[i][1] + cEsc + "[0m "
            cLine := cLine + cEsc + "[2m(" + AllTrim(Str(aHistory[i][3], 5, 1)) + "s)" + cEsc + "[0m"
            cLine := cLine + " " + Left(aHistory[i][2], nBoxW - 25)
            ConOut(cLine)
        Next i
    EndIf

    ConOut(cEsc + "[1;33m+" + Replicate("─", nBoxW) + "+" + cEsc + "[0m")
    ConOut("")
Return Nil
