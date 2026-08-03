#include "protheus.ch"

/*/{Protheus.doc} Main
    shortcoder — TUI estilo BBS classico com estetica retrô.
    Interface 100% legivel com caixas delimitadas e texto quebrado corretamente.
    ORQUESTRACAO ENTRE AGENTES:
      - Detecta dominio da pergunta (Protheus, Mem0, geral)
      - Roteia automaticamente para o agente mais adequado
      - Suporta multi-agente (agente primario + sec undario)
@type function
@author Peder Munksgaard
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
            cAgent := PickAgent(cEsc, cAgent, nWidth)
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

/*/{Protheus.doc} LoadModels
@type function
/*/
Static Function LoadModels(cPath, aModels, cDefModel)
    Local cJson := MemoRead(cPath)
    Local oRoot := JsonObject():New()
    Local aProvNames, cProv, oProv, aProvModels, oModel
    Local i, j, nIdx, cId, lFound

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
                lFound := .F.
                For nIdx := 1 To Len(aModels)
                    If aModels[nIdx][1] == cId
                        lFound := .T.
                        Exit
                    EndIf
                Next nIdx
                If !lFound
                    If ValType(oModel["name"]) == "C"
                        aAdd(aModels, {cId, oModel["name"]})
                    Else
                        aAdd(aModels, {cId, cId})
                    EndIf
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
    Local cResult := ""
    Local nLen := Len(cText)
    Local i := 1
    Local nRel

    While i <= nLen
        If SubStr(cText, i, 1) == cEsc .And. SubStr(cText, i + 1, 1) == "["
            // Sequencia so tem digitos/';' antes do 'm' terminador, entao o
            // primeiro 'm' a partir DAQUI (nao da string toda) e sempre o dela.
            // Bug anterior buscava o 'm' na string toda ja processada e podia
            // cortar em um 'm' de texto plano (ex.: "Memory"), quebrando a conta.
            nRel := At("m", SubStr(cText, i))
            If nRel > 0
                i := i + nRel
            Else
                i := i + 2
            EndIf
        Else
            cResult := cResult + SubStr(cText, i, 1)
            i++
        EndIf
    End

Return cResult

/*/{Protheus.doc} Utf8Len
    Numero de colunas visiveis de uma string UTF-8. Len()/SubStr() nesta
    runtime operam sobre bytes (confirmado no fonte do compilador), entao
    qualquer acento (á, ç, ã...) inflava a contagem e furava o padding das
    caixas. Conta 1 por sequencia UTF-8 (byte que nao e continuation byte
    10xxxxxx), o que cobre letras latinas acentuadas.
    ponytail: emoji/CJK largos contam como 1 coluna aqui (ceiling); tratar
    largura dupla se a UI passar a exibir esse tipo de conteudo.
@type function
/*/
Static Function Utf8Len(cText)
    Local nBytes := Len(cText)
    Local nChars := 0
    Local i := 1
    Local nByte

    While i <= nBytes
        nByte := Asc(SubStr(cText, i, 1))
        If nByte >= 240
            i += 4
        ElseIf nByte >= 224
            i += 3
        ElseIf nByte >= 192
            i += 2
        Else
            i += 1
        EndIf
        nChars++
    End
Return nChars

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
    Local nInner   := nWidth - 2
    Local cWord    := "SHORTCODER"
    Local nLogoW   := Len(cWord) * 6 - 1
    Local nPad     := 0
    Local aLetters := {}
    Local aGlyph
    Local cRow
    Local i, r

    ConOut(cEsc + "[1;33m ╔" + Replicate("═", nInner) + "╗" + cEsc + "[0m")
    ConOut(cEsc + "[1;33m ║" + cEsc + "[0;34m" + Replicate("░", nInner) + cEsc + "[1;33m" + "║" + cEsc + "[0m")
    ConOut(cEsc + "[1;33m ║" + cEsc + "[1;34m" + Replicate("▒", nInner) + cEsc + "[1;33m" + "║" + cEsc + "[0m")

    If nInner >= nLogoW
        For i := 1 To Len(cWord)
            aAdd(aLetters, BigFont(SubStr(cWord, i, 1)))
        Next i
        nPad := Int((nInner - nLogoW) / 2)
        For r := 1 To 5
            cRow := ""
            For i := 1 To Len(aLetters)
                aGlyph := aLetters[i]
                cRow += StrTran(StrTran(aGlyph[r], "#", "█"), ".", " ")
                If i < Len(aLetters)
                    cRow += " "
                EndIf
            Next i
            ConOut(cEsc + "[1;33m ║" + Replicate(" ", nPad) + cEsc + "[1;36m" + cRow + cEsc + "[1;33m" + Replicate(" ", nInner - nPad - nLogoW) + "║" + cEsc + "[0m")
        Next r
    Else
        ConOut(cEsc + "[1;33m ║" + cEsc + "[1;36m" + PadCenter("SHORTCODER", nInner) + cEsc + "[1;33m" + "║" + cEsc + "[0m")
    EndIf

    ConOut(cEsc + "[1;33m ║" + cEsc + "[1;34m" + Replicate("▒", nInner) + cEsc + "[1;33m" + "║" + cEsc + "[0m")
    ConOut(cEsc + "[1;33m ║" + cEsc + "[0;34m" + Replicate("░", nInner) + cEsc + "[1;33m" + "║" + cEsc + "[0m")
    ConOut(cEsc + "[1;33m ║" + PadCenter("[AI Coding Agent v1.0]", nInner) + "║" + cEsc + "[0m")
    ConOut(cEsc + "[1;33m ╚" + Replicate("═", nInner) + "╝" + cEsc + "[0m")
Return Nil

/*/{Protheus.doc} BigFont
    Retorna a matriz 5x5 (linhas de '#'/'.') do glifo em bloco de uma letra,
    no estilo logo ANSI-art classico (TheDraw / figlet block font).
@type function
/*/
Static Function BigFont(cChar)
    Local aRows := {}

    Do Case
    Case cChar == "S"
        aRows := {"#####", "#....", "#####", "....#", "#####"}
    Case cChar == "H"
        aRows := {"#...#", "#...#", "#####", "#...#", "#...#"}
    Case cChar == "O"
        aRows := {"#####", "#...#", "#...#", "#...#", "#####"}
    Case cChar == "R"
        aRows := {"#####", "#...#", "#####", "#..#.", "#...#"}
    Case cChar == "T"
        aRows := {"#####", "..#..", "..#..", "..#..", "..#.."}
    Case cChar == "C"
        aRows := {"#####", "#....", "#....", "#....", "#####"}
    Case cChar == "D"
        aRows := {"####.", "#...#", "#...#", "#...#", "####."}
    Case cChar == "E"
        aRows := {"#####", "#....", "#####", "#....", "#####"}
    OtherWise
        aRows := {".....", ".....", ".....", ".....", "....."}
    EndCase
Return aRows

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
    Local nInner := nWidth - 2
    Local cLine1 := StatusLine(cEsc, "MODEL",   cModel,        nInner, "1;33")
    Local cLine2 := StatusLine(cEsc, "SESSION", cSession,      nInner, "1;32")
    Local cLine3 := StatusLine(cEsc, "AGENT",   Upper(cAgent), nInner, "1;35")
    Local cLine4 := StatusLine(cEsc, "MEM0",    cMemUser,      nInner, "1;33")

    ConOut(cEsc + "[2;36m" + ;
        " ┌" + Replicate("─", nInner) + "┐" + Chr(10) + ;
        cLine1 + Chr(10) + ;
        cLine2 + Chr(10) + ;
        cLine3 + Chr(10) + ;
        cLine4 + Chr(10) + ;
        " └" + Replicate("─", nInner) + "┘" + cEsc + "[0m")
Return Nil

/*/{Protheus.doc} StatusLine
    Monta uma linha do painel de status com largura fixa em nInner,
    para a borda direita alinhar independente do tamanho do valor.
@type function
/*/
Static Function StatusLine(cEsc, cLabel, cValue, nInner, cColor)
    Local cHead  := " " + PadR(cLabel + ":", 9) + " ["
    Local nAvail := Max(0, nInner - Len(cHead) - 1)
    Local cVal   := Left(cValue, nAvail)
    Local nPad   := nAvail - Len(cVal)

Return " │" + cHead + cEsc + "[" + cColor + "m" + cVal + cEsc + "[36m" + "]" + Replicate(" ", nPad) + "│"

/*/{Protheus.doc} BoxTop / BoxDiv / BoxBottom
    Bordas de caixa em box-drawing Unicode (estilo ANSI art classico),
    substituindo o antigo "+---+" ASCII usado nas telas legadas.
@type function
/*/
Static Function BoxTop(cEsc, nInner, cColor)
Return cEsc + "[" + cColor + "m ┌" + Replicate("─", nInner) + "┐" + cEsc + "[0m"

Static Function BoxDiv(cEsc, nInner, cColor)
Return cEsc + "[" + cColor + "m ├" + Replicate("─", nInner) + "┤" + cEsc + "[0m"

Static Function BoxBottom(cEsc, nInner, cColor)
Return cEsc + "[" + cColor + "m └" + Replicate("─", nInner) + "┘" + cEsc + "[0m"

/*/{Protheus.doc} BoxTopD / BoxDivD / BoxBottomD / BoxShadeD
    Variante de moldura dupla (╔═╗║╚═╝), a mesma usada no header do
    SHORTCODER — reservada para telas de menu/painel (Help, selecao de
    agente/modelo, historico), que ganham tambem uma faixa de shading
    (▒/░) como nas dele, em vez da caixa simples usada nas respostas
    dinamicas dos agentes.
@type function
/*/
Static Function BoxTopD(cEsc, nInner, cColor)
Return cEsc + "[" + cColor + "m ╔" + Replicate("═", nInner) + "╗" + cEsc + "[0m"

Static Function BoxDivD(cEsc, nInner, cColor)
Return cEsc + "[" + cColor + "m ╠" + Replicate("═", nInner) + "╣" + cEsc + "[0m"

Static Function BoxBottomD(cEsc, nInner, cColor)
Return cEsc + "[" + cColor + "m ╚" + Replicate("═", nInner) + "╝" + cEsc + "[0m"

Static Function BoxShadeD(cEsc, nInner, cBorderColor, cShadeColor, cChar)
Return cEsc + "[" + cBorderColor + "m ║" + cEsc + "[" + cShadeColor + "m" + Replicate(cChar, nInner) + cEsc + "[" + cBorderColor + "m║" + cEsc + "[0m"

/*/{Protheus.doc} BoxLineD
    Como BoxLine, mas com borda vertical dupla (║) para casar com
    BoxTopD/BoxBottomD.
@type function
/*/
Static Function BoxLineD(cEsc, cContent, nVisLen, nInner, cColor)
    Local nPad := Max(0, nInner - nVisLen)
Return cEsc + "[" + cColor + "m ║" + cEsc + "[0m" + cContent + Replicate(" ", nPad) + cEsc + "[" + cColor + "m║" + cEsc + "[0m"

/*/{Protheus.doc} BoxTitleD
    Titulo centralizado dentro de moldura dupla.
@type function
/*/
Static Function BoxTitleD(cEsc, cText, nInner, cBorderColor, cTextColor)
Return cEsc + "[" + cBorderColor + "m ║" + cEsc + "[" + cTextColor + "m" + PadCenter(cText, nInner) + cEsc + "[" + cBorderColor + "m║" + cEsc + "[0m"

/*/{Protheus.doc} BoxLine
    Monta uma linha de conteudo com largura fixa em nInner, calculada a
    partir do comprimento VISIVEL (nVisLen), para a borda direita alinhar
    sempre, independente de quanto texto/cor o chamador colocou dentro.
@type function
/*/
Static Function BoxLine(cEsc, cContent, nVisLen, nInner, cColor)
    Local nPad := Max(0, nInner - nVisLen)
Return cEsc + "[" + cColor + "m │" + cEsc + "[0m" + cContent + Replicate(" ", nPad) + cEsc + "[" + cColor + "m│" + cEsc + "[0m"

/*/{Protheus.doc} BoxLineAuto
    Como BoxLine, mas calcula o comprimento visivel automaticamente via
    StripANSI. Uso restrito a mensagens curtas de status/erro, cujo
    tamanho o chamador ja garante caber em nInner (nao ha truncagem segura
    de texto colorido).
@type function
/*/
Static Function BoxLineAuto(cEsc, cColoredText, nInner, cColor)
    Local nVis := Utf8Len(StripANSI(cEsc, cColoredText)) + 1
Return BoxLine(cEsc, " " + cColoredText, nVis, nInner, cColor)

Static Function BoxLineAutoD(cEsc, cColoredText, nInner, cColor)
    Local nVis := Utf8Len(StripANSI(cEsc, cColoredText)) + 1
Return BoxLineD(cEsc, " " + cColoredText, nVis, nInner, cColor)

/*/{Protheus.doc} AgentColor
    Cor associada a cada agente (mesma paleta usada em PickAgent), para
    manter a identidade visual consistente onde o nome do agente aparece.
@type function
/*/
Static Function AgentColor(cAgent)
    Do Case
    Case Lower(cAgent) == "ollama"
        Return "1;36"
    Case Lower(cAgent) == "mem0" .Or. Lower(cAgent) == "mem0/add" .Or. Lower(cAgent) == "mem0/clear"
        Return "1;32"
    Case Lower(cAgent) == "ernesto"
        Return "1;35"
    EndCase
Return "1;37"

/*/{Protheus.doc} BoxTitle
    Linha de titulo centralizada dentro da caixa.
@type function
/*/
Static Function BoxTitle(cEsc, cText, nInner, cBorderColor, cTextColor)
Return cEsc + "[" + cBorderColor + "m │" + cEsc + "[" + cTextColor + "m" + PadCenter(cText, nInner) + cEsc + "[" + cBorderColor + "m│" + cEsc + "[0m"

/*/{Protheus.doc} BoxBlank
    Linha em branco dentro da caixa (preenche com espacos ate a borda).
@type function
/*/
Static Function BoxBlank(cEsc, nInner, cColor)
Return BoxLineD(cEsc, "", 0, nInner, cColor)

/*/{Protheus.doc} BoxSection
    Linha de cabecalho de secao (texto em negrito) dentro da caixa.
@type function
/*/
Static Function BoxSection(cEsc, cText, nInner, cColor)
    Local cPlain := " " + cText
Return BoxLineD(cEsc, " " + cEsc + "[1m" + cText + cEsc + "[0m", Len(cPlain), nInner, cColor)

/*/{Protheus.doc} BoxCmdLine
    Linha "  /comando   - descricao" dentro da caixa, com o comando
    alinhado em coluna fixa (PadR) independente do tamanho da descricao.
@type function
/*/
Static Function BoxCmdLine(cEsc, cCmd, cDesc, nInner, cColor)
    Local cPlain   := "   " + PadR(cCmd, 16) + "- " + cDesc
    Local cContent := "   " + cEsc + "[1;36m" + PadR(cCmd, 16) + cEsc + "[0m" + cEsc + "[2;37m" + "- " + cDesc + cEsc + "[0m"
Return BoxLineD(cEsc, cContent, Len(cPlain), nInner, cColor)

Static Function ShowBBSHelp(cEsc, nWidth)
    Local nInner := nWidth - 2

    ConOut("")
    ConOut(BoxTopD(cEsc, nInner, "1;33"))
    ConOut(BoxShadeD(cEsc, nInner, "1;33", "0;33", "░"))
    ConOut(BoxTitleD(cEsc, "[ COMMAND LIST ]", nInner, "1;33", "1;36"))
    ConOut(BoxShadeD(cEsc, nInner, "1;33", "0;33", "░"))
    ConOut(BoxDivD(cEsc, nInner, "1;33"))
    ConOut(BoxSection(cEsc, "AGENTES:", nInner, "1;33"))
    ConOut(BoxCmdLine(cEsc, "/agent", "Switch agent (ollama/mem0/ernesto)", nInner, "1;33"))
    ConOut(BoxCmdLine(cEsc, "/model", "List & select model", nInner, "1;33"))
    ConOut(BoxBlank(cEsc, nInner, "1;33"))
    ConOut(BoxSection(cEsc, "MEMORIA PERSISTENTE:", nInner, "1;33"))
    ConOut(BoxCmdLine(cEsc, "/mem0 list", "View saved memories", nInner, "1;33"))
    ConOut(BoxCmdLine(cEsc, "/mem0 add <txt>", "Save a memory", nInner, "1;33"))
    ConOut(BoxCmdLine(cEsc, "/mem0 clear", "Remove all memories", nInner, "1;33"))
    ConOut(BoxBlank(cEsc, nInner, "1;33"))
    ConOut(BoxSection(cEsc, "OUTROS:", nInner, "1;33"))
    ConOut(BoxCmdLine(cEsc, "/clear", "New session (clear history)", nInner, "1;33"))
    ConOut(BoxCmdLine(cEsc, "/history", "View conversation history", nInner, "1;33"))
    ConOut(BoxCmdLine(cEsc, "/help", "This help screen", nInner, "1;33"))
    ConOut(BoxCmdLine(cEsc, "/exit", "Disconnect", nInner, "1;33"))
    ConOut(BoxBottomD(cEsc, nInner, "1;33"))
    ConOut("")
Return Nil

/*/{Protheus.doc} PickAgent
@type function
/*/
Static Function PickAgent(cEsc, cCurrent, nWidth)
    Local nInner := Min(nWidth - 2, 58)
    Local cChoice

    ConOut("")
    ConOut(BoxTopD(cEsc, nInner, "1;33"))
    ConOut(BoxShadeD(cEsc, nInner, "1;33", "0;33", "░"))
    ConOut(BoxTitleD(cEsc, "[ SELECT AGENT ]", nInner, "1;33", "1;36"))
    ConOut(BoxShadeD(cEsc, nInner, "1;33", "0;33", "░"))
    ConOut(BoxDivD(cEsc, nInner, "1;33"))
    ConOut(BoxOptionLine(cEsc, "1", "1;36", "ollama",  "Fast LLM (lfm25, ~1s response)",  nInner, "1;33"))
    ConOut(BoxOptionLine(cEsc, "2", "1;32", "mem0",    "Persistent memory queries",       nInner, "1;33"))
    ConOut(BoxOptionLine(cEsc, "3", "1;35", "ernesto", "RAG + Memory (slow, >30s)",       nInner, "1;33"))
    ConOut(BoxBottomD(cEsc, nInner, "1;33"))
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

/*/{Protheus.doc} BoxOptionLine
    Linha "  [n] nome  - descricao" usada nos menus de selecao (agente,
    modelo), com o nome colorido e alinhado em coluna fixa.
@type function
/*/
Static Function BoxOptionLine(cEsc, cNum, cNameColor, cName, cDesc, nInner, cBorderColor)
    Local cPlain   := "  [" + cNum + "] " + PadR(cName, 9) + "- " + cDesc
    Local cContent := "  " + cEsc + "[2m[" + cNum + "]" + cEsc + "[0m " + cEsc + "[" + cNameColor + "m" + PadR(cName, 9) + cEsc + "[0m" + cEsc + "[2m- " + cDesc + cEsc + "[0m"
Return BoxLineD(cEsc, cContent, Len(cPlain), nInner, cBorderColor)

/*/{Protheus.doc} PickModel
@type function
/*/
Static Function PickModel(cEsc, aModels, cCurrent, nWidth)
    Local i, cChoice, nIdx
    Local nInner := Min(nWidth - 2, 70)
    Local cName, cPlain, cContent

    If Len(aModels) == 0
        ConOut(cEsc + "[33m[WARN] No models found — keeping " + cCurrent + cEsc + "[0m")
        Return cCurrent
    EndIf

    ConOut("")
    ConOut(BoxTopD(cEsc, nInner, "1;33"))
    ConOut(BoxShadeD(cEsc, nInner, "1;33", "0;33", "░"))
    ConOut(BoxTitleD(cEsc, "[ MODEL SELECT ]", nInner, "1;33", "1;36"))
    ConOut(BoxShadeD(cEsc, nInner, "1;33", "0;33", "░"))
    ConOut(BoxDivD(cEsc, nInner, "1;33"))

    For i := 1 To Min(Len(aModels), 20)
        cName    := Left(aModels[i][1], Max(0, nInner - 8))
        cPlain   := "  [" + StrZero(i, 2) + "] " + cName
        cContent := "  " + cEsc + "[2m[" + StrZero(i, 2) + "]" + cEsc + "[0m " + cEsc + "[1;36m" + cName + cEsc + "[0m"
        ConOut(BoxLineD(cEsc, cContent, Utf8Len(cPlain), nInner, "1;33"))
    Next i

    ConOut(BoxBottomD(cEsc, nInner, "1;33"))
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
    Local nInner := nWidth - 2

    nStart := Seconds()
    cBody := '{"model":"' + cModel + '","messages":[{"role":"user","content":"' + JsonEscape(cPrompt) + '"}],"stream":false,"max_tokens":500}'

    nStatus := FWHTTPPOST("http://127.0.0.1:11434/v1/chat/completions", cBody, "application/json")

    If nStatus != 200
        Local cErr := FWHTTPERROR()
        If !Empty(cErr) .And. At("timeout", Lower(cErr)) > 0
            cResponse := BoxLineAuto(cEsc, cEsc + "[1;33m[TIMEOUT] Model too slow (load >30s) — try /agent 1 for fast LLM" + cEsc + "[0m", nInner, "1;36")
        Else
            cResponse := BoxLineAuto(cEsc, cEsc + "[1;31m[ERROR] HTTP " + AllTrim(Str(nStatus)) + " — " + Left(cErr, 40) + cEsc + "[0m", nInner, "1;36")
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
                    cResponse := FormatTextForBox(cEsc, cContent, nInner, "1;36")
                ElseIf !Empty(cReasoning)
                    cResponse := FormatTextForBox(cEsc, cReasoning, nInner, "1;36")
                Else
                    cResponse := BoxLineAuto(cEsc, cEsc + "[2m[NO CONTENT]" + cEsc + "[0m", nInner, "1;36")
                EndIf
            Else
                cResponse := BoxLineAuto(cEsc, cEsc + "[2m[NO RESPONSE]" + cEsc + "[0m", nInner, "1;36")
            EndIf
        Else
            cResponse := BoxLineAuto(cEsc, cEsc + "[1;33m[PARSE ERR]" + cEsc + "[0m", nInner, "1;36")
        EndIf
    EndIf

    ConOut("")
    ConOut(BoxTop(cEsc, nInner, "1;36"))
    ConOut(BoxAgentTitle(cEsc, "AGENT:OLLAMA", cModel, nInner, "1;36"))
    ConOut(BoxDiv(cEsc, nInner, "1;36"))
    ConOut(cResponse)
    ConOut(BoxBottom(cEsc, nInner, "1;36"))
    ConOut(cEsc + "[2m  " + AllTrim(Str(Seconds() - nStart, 10, 1)) + "s response time" + cEsc + "[0m")
    ConOut("")

    aAdd(aHistory, {"ollama", cPrompt, Seconds() - nStart})
Return Nil

/*/{Protheus.doc} BoxAgentTitle
    Linha de titulo das caixas de resposta de agente: " AGENT:X  subtitulo".
@type function
/*/
Static Function BoxAgentTitle(cEsc, cLabel, cSub, nInner, cColor)
    Local cPlain   := " " + cLabel + " " + cSub
    Local cContent := " " + cEsc + "[1;33m" + cLabel + cEsc + "[0m" + " " + cEsc + "[2m" + cSub + cEsc + "[0m"
Return BoxLine(cEsc, cContent, Len(cPlain), nInner, cColor)

/*/{Protheus.doc} FormatTextForBox
    Formata texto em linhas com borda │...│ dentro de nInner, quebrando
    palavras (WordWrap) — mesma tecnica das demais caixas do app.
@type function
/*/
Static Function FormatTextForBox(cEsc, cText, nInner, cColor)
    Local aLines, cLine, cResult := "", i
    Local nMaxLen := Max(1, nInner - 2)

    aLines := WordWrap(cText, nMaxLen)

    For i := 1 To Len(aLines)
        cLine := " " + aLines[i]
        cResult := cResult + BoxLine(cEsc, cEsc + "[2;37m" + cLine + cEsc + "[0m", Utf8Len(cLine), nInner, cColor) + Chr(10)
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
    Local i, cContent, cCat, cConf, cItem
    Local nCount := 0
    Local nInner := nWidth - 2

    nStart := Seconds()
    nStatus := FWHTTPGET("http://127.0.0.1:9081/memories/" + cUserId)

    If nStatus != 200
        cResponse := BoxLineAuto(cEsc, cEsc + "[1;31m[ERROR] HTTP " + AllTrim(Str(nStatus)) + " — mem0 unavailable" + cEsc + "[0m", nInner, "1;32")
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
                            Local cPrefix := "[" + cCat + "] conf:" + cConf + " "
                            Local nAvail  := Max(1, nInner - Utf8Len(cPrefix) - 1)
                            nCount++
                            cItem := Left(cContent, nAvail)
                            If Len(cContent) > Len(cItem)
                                cItem := Left(cItem, Max(0, Len(cItem) - 3)) + "..."
                            EndIf
                            cResponse := cResponse + BoxLineAuto(cEsc, cEsc + "[2m" + cPrefix + cEsc + "[0m" + cItem, nInner, "1;32") + Chr(10)
                        EndIf
                    EndIf
                Next i
                If nCount == 0
                    cResponse := BoxLineAuto(cEsc, cEsc + "[2m[NO MEMORIES]" + cEsc + "[0m", nInner, "1;32")
                Else
                    cResponse := BoxLineAuto(cEsc, cEsc + "[2m--- " + AllTrim(Str(nCount)) + " of " + AllTrim(Str(Len(aMemories))) + " memories shown ---" + cEsc + "[0m", nInner, "1;32") + Chr(10) + cResponse
                EndIf
            Else
                cResponse := BoxLineAuto(cEsc, cEsc + "[2m[NO MEMORIES]" + cEsc + "[0m", nInner, "1;32")
            EndIf
        Else
            cResponse := BoxLineAuto(cEsc, cEsc + "[1;33m[PARSE ERR]" + cEsc + "[0m", nInner, "1;32")
        EndIf
    EndIf

    ConOut("")
    ConOut(BoxTop(cEsc, nInner, "1;32"))
    ConOut(BoxAgentTitle(cEsc, "AGENT:MEM0", "Persistent Memory Store", nInner, "1;32"))
    ConOut(BoxDiv(cEsc, nInner, "1;32"))
    ConOut(cResponse)
    ConOut(BoxBottom(cEsc, nInner, "1;32"))
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
    Local nInner := nWidth - 2

    nStart := Seconds()
    cBody := '{"model":"' + cModel + '","messages":[{"role":"user","content":"' + JsonEscape(cPrompt) + '"}],"stream":false,"max_tokens":500}'

    nStatus := FWHTTPPOST("http://127.0.0.1:9081/v1/chat/completions", cBody, "application/json")

    If nStatus != 200
        Local cErr := FWHTTPERROR()
        If !Empty(cErr) .And. At("timeout", Lower(cErr)) > 0
            cResponse := BoxLineAuto(cEsc, cEsc + "[1;33m[TIMEOUT] RAG pipeline slow (>30s) — use ollama agent for fast responses" + cEsc + "[0m", nInner, "1;35")
        Else
            cResponse := BoxLineAuto(cEsc, cEsc + "[1;31m[ERROR] HTTP " + AllTrim(Str(nStatus)) + " — " + Left(cErr, 40) + cEsc + "[0m", nInner, "1;35")
        EndIf
    Else
        cBody := FWHTTPBODY()
        oJ := JsonObject():New()
        If oJ:FromJson(cBody)
            oChoice := oJ["choices"][1]
            If ValType(oChoice) == "O"
                cResponse := FormatTextForBox(cEsc, AllTrim(oChoice["message"]["content"]), nInner, "1;35")
            Else
                cResponse := BoxLineAuto(cEsc, cEsc + "[2m[NO RESPONSE]" + cEsc + "[0m", nInner, "1;35")
            EndIf
        Else
            cResponse := BoxLineAuto(cEsc, cEsc + "[1;33m[PARSE ERR]" + cEsc + "[0m", nInner, "1;35")
        EndIf
    EndIf

    ConOut("")
    ConOut(BoxTop(cEsc, nInner, "1;35"))
    ConOut(BoxAgentTitle(cEsc, "AGENT:ERNESTO", "RAG + Memory Integrated", nInner, "1;35"))
    ConOut(BoxDiv(cEsc, nInner, "1;35"))
    ConOut(cResponse)
    ConOut(BoxBottom(cEsc, nInner, "1;35"))
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
    Local nInner := nWidth - 2

    nStatus := FWHTTPPOST("http://127.0.0.1:9081/memories/" + cUserId, ;
        '{"content":"' + JsonEscape(cContent) + '"}', ;
        "application/json")

    ConOut("")
    ConOut(BoxTop(cEsc, nInner, "1;32"))
    If nStatus == 200
        ConOut(BoxLineAuto(cEsc, cEsc + "[32m[OK]" + cEsc + "[0m " + cEsc + "[37mMemory saved successfully" + cEsc + "[0m", nInner, "1;32"))
    Else
        ConOut(BoxLineAuto(cEsc, cEsc + "[31m[ERROR]" + cEsc + "[0m " + cEsc + "[37mHTTP " + AllTrim(Str(nStatus)) + " — could not save memory" + cEsc + "[0m", nInner, "1;32"))
    EndIf
    ConOut(BoxBottom(cEsc, nInner, "1;32"))
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
    Local nInner := nWidth - 2

    nStatus := FWHTTPDELETE("http://127.0.0.1:9081/memories/" + cUserId)

    ConOut("")
    ConOut(BoxTop(cEsc, nInner, "1;32"))
    If nStatus == 200
        ConOut(BoxLineAuto(cEsc, cEsc + "[32m[OK]" + cEsc + "[0m " + cEsc + "[37mAll memories cleared" + cEsc + "[0m", nInner, "1;32"))
    Else
        ConOut(BoxLineAuto(cEsc, cEsc + "[31m[ERROR]" + cEsc + "[0m " + cEsc + "[37mHTTP " + AllTrim(Str(nStatus)) + " — could not clear" + cEsc + "[0m", nInner, "1;32"))
    EndIf
    ConOut(BoxBottom(cEsc, nInner, "1;32"))
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
    Local nInner := nWidth - 2
    Local cText, cPlain, cContent

    ConOut("")
    ConOut(BoxTop(cEsc, nInner, "1;33"))
    cText    := Left(cMsg, Max(0, nInner - 8))
    cPlain   := " USER  " + cText
    cContent := " " + cEsc + "[1;37mUSER " + cEsc + "[0m " + cEsc + "[2;33m" + cText + cEsc + "[0m"
    ConOut(BoxLine(cEsc, cContent, Utf8Len(cPlain), nInner, "1;33"))
    ConOut(BoxBottom(cEsc, nInner, "1;33"))
Return Nil

/*/{Protheus.doc} ShowHistory
@type function
/*/
Static Function ShowHistory(cEsc, aHistory, nWidth)
    Local nInner := nWidth - 2
    Local i, cPlain, cContent, cAgent, cSecs, cMsg

    ConOut("")
    ConOut(BoxTopD(cEsc, nInner, "1;33"))
    ConOut(BoxShadeD(cEsc, nInner, "1;33", "0;33", "░"))
    ConOut(BoxTitleD(cEsc, "[ HISTORY ]", nInner, "1;33", "1;36"))
    ConOut(BoxShadeD(cEsc, nInner, "1;33", "0;33", "░"))
    ConOut(BoxDivD(cEsc, nInner, "1;33"))

    If Len(aHistory) == 0
        ConOut(BoxLineAutoD(cEsc, cEsc + "[2m[EMPTY] No conversation history" + cEsc + "[0m", nInner, "1;33"))
    Else
        For i := 1 To Len(aHistory)
            cAgent   := aHistory[i][1]
            cSecs    := "(" + AllTrim(Str(aHistory[i][3], 5, 1)) + "s)"
            cMsg     := Left(aHistory[i][2], Max(0, nInner - 12 - Len(cAgent) - Len(cSecs)))
            cPlain   := "  [" + StrZero(i, 3) + "] " + cAgent + " " + cSecs + " " + cMsg
            cContent := "  " + cEsc + "[2m[" + StrZero(i, 3) + "]" + cEsc + "[0m " + cEsc + "[" + AgentColor(cAgent) + "m" + cAgent + cEsc + "[0m " + cEsc + "[2m" + cSecs + cEsc + "[0m " + cMsg
            ConOut(BoxLineD(cEsc, cContent, Utf8Len(cPlain), nInner, "1;33"))
        Next i
    EndIf

    ConOut(BoxBottomD(cEsc, nInner, "1;33"))
    ConOut("")
Return Nil

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
