; Instalador Windows do shortcoder (NSIS). Gerado no CI via `makensis`, a
; partir do shortcoder.exe cross-compilado no job linux-windows.
; Uso: makensis -DEXE_PATH=<caminho para shortcoder.exe> installer/windows.nsi

!ifndef EXE_PATH
  !define EXE_PATH "shortcoder.exe"
!endif
!ifndef OUT_PATH
  !define OUT_PATH "shortcoder-windows-amd64-setup.exe"
!endif

!include "MUI2.nsh"
!include "WinMessages.nsh"

Name "shortcoder"
OutFile "${OUT_PATH}"
InstallDir "$LOCALAPPDATA\Programs\shortcoder"
RequestExecutionLevel user
Unicode true

!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "PortugueseBR"

Section "Instalar"
  SetOutPath "$INSTDIR"
  File "${EXE_PATH}"

  CreateDirectory "$SMPROGRAMS\shortcoder"
  CreateShortcut "$SMPROGRAMS\shortcoder\shortcoder.lnk" "$INSTDIR\shortcoder.exe"
  CreateShortcut "$SMPROGRAMS\shortcoder\Desinstalar.lnk" "$INSTDIR\uninstall.exe"

  ; ponytail: acrescenta ao PATH do usuário sem checar duplicata — reinstalar
  ; empilha a mesma entrada de novo. Upgrade path se incomodar: plugin EnVar
  ; (checa/dedupe) em vez de WriteRegExpandStr direto.
  ReadRegStr $0 HKCU "Environment" "Path"
  WriteRegExpandStr HKCU "Environment" "Path" "$0;$INSTDIR"
  SendMessage ${HWND_BROADCAST} ${WM_SETTINGCHANGE} 0 "STR:Environment" /TIMEOUT=5000

  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\shortcoder.exe"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\shortcoder\shortcoder.lnk"
  Delete "$SMPROGRAMS\shortcoder\Desinstalar.lnk"
  RMDir "$SMPROGRAMS\shortcoder"
SectionEnd
