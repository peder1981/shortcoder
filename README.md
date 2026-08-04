# shortcoder — Interface Retrô

Versao do shortcoder com estetica (Bulletin Board System) classica dos anos 90.

## Instalacao rapida

Linux (x86_64) e macOS (Apple Silicon):

```bash
curl -fsSL https://raw.githubusercontent.com/peder1981/shortcoder/master/install.sh | bash
```

Instala em `~/.local/bin/shortcoder`.

Windows: baixe e execute `shortcoder-windows-amd64-setup.exe` na
[página de releases](https://github.com/peder1981/shortcoder/releases/latest) — instalador
NSIS que copia o binário para `%LOCALAPPDATA%\Programs\shortcoder`, cria atalho no Menu
Iniciar e adiciona ao PATH do usuário (abra um terminal novo depois de instalar). O
instalador não é assinado digitalmente, então o SmartScreen do Windows vai avisar na
primeira execução — clique em "Mais informações" → "Executar assim mesmo".

| Plataforma | Arquitetura | Asset |
|------------|-------------|-------|
| Linux | amd64 | `shortcoder-linux-amd64.tar.gz` |
| macOS | arm64 (Apple Silicon) | `shortcoder-macos-arm64.tar.gz` |
| Windows | amd64 | `shortcoder-windows-amd64-setup.exe` (instalador) ou `shortcoder-windows-amd64.zip` (binário avulso) |

Cada release traz um `checksums.txt` (SHA-256) para conferir a integridade do download.

## Visual

- **ASCII Art** no header com o nome "SHORTCODER"
- **Cores vintage**: amarelo (#FFFF00), ciano, verde, magenta
- **Caixas delimitadas** com `+──+|` estilo
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

## Como Compilar (a partir do fonte)

Requer um checkout do [AdvPP](https://github.com/peder1981/AdvPP) (`ADVPP_SRC` ou rodar de
dentro do próprio repositório do compilador) e toolchain Go + C (CGO obrigatório).

```bash
cd ~/Projetos/shortcoder
advplc build shortcoder.prw -o shortcoder
./shortcoder
```

Cross-compile para Windows a partir do Linux (via `mingw-w64`):

```bash
sudo apt install gcc-mingw-w64-x86-64
GOOS=windows GOARCH=amd64 CC=x86_64-w64-mingw32-gcc CGO_ENABLED=1 \
  ADVPP_SRC=/caminho/para/AdvPP advplc build shortcoder.prw -o shortcoder.exe
```

macOS precisa compilar nativamente numa Mac (CGO + frameworks Cocoa/OpenGL não cruzam a
partir do Linux) — é o que o workflow `.github/workflows/release.yml` faz num runner
`macos-latest` a cada tag `vX.Y.Z` publicada.

## Testes

```bash
# Testar ajuda
printf '/help\n/exit\n' | ./shortcoder

# Testar resposta LLM
printf '2+2\n/exit\n' | ./shortcoder

# Testar memoria
printf '/mem0 add "teste"\n/mem0 list\n/exit\n' | ./shortcoder

# Testar historico
printf 'ola\n/history\n/exit\n' | ./shortcoder
```

## Comparacao com Versoes Anteriores

| Versao | Estilo | Funcionalidades |
|--------|--------|-----------------|
| shortcoder | Minimalista | LLM via ProcRun |
| shortcoder-rag | Cards modernos | LLM + Mem0 HTTP |
| **shortcoder** | **retrô** | **LLM + Mem0 + visual** |
