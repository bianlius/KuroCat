Unicode true

!include "MUI2.nsh"
!include "WinMessages.nsh"
!include "x64.nsh"

!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\KuroCat"
!define AUTOSTART_KEY "Software\Microsoft\Windows\CurrentVersion\Run"

Name "KuroCat ${VERSION}"
OutFile "${SETUP_EXE}"
InstallDir "$LOCALAPPDATA\Programs\KuroCat"
RequestExecutionLevel user
SetCompressor /SOLID lzma

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "KuroCat"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "KuroCat x64 Setup"
VIAddVersionKey "LegalCopyright" "KuroCat contributors"

!define MUI_FINISHPAGE_RUN "$INSTDIR\KuroCat.exe"
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"

LangString Requires64Bit ${LANG_ENGLISH} "KuroCat requires 64-bit Windows."
LangString Requires64Bit ${LANG_SIMPCHINESE} "KuroCat 需要 64 位 Windows。"
LangString CloseAndRetry ${LANG_ENGLISH} "Close KuroCat and run the uninstaller again."
LangString CloseAndRetry ${LANG_SIMPCHINESE} "请退出 KuroCat 后重新运行卸载程序。"

Function .onInit
    ${IfNot} ${RunningX64}
        MessageBox MB_OK|MB_ICONSTOP "$(Requires64Bit)"
        Abort
    ${EndIf}
FunctionEnd

!macro CloseKuroCat
    FindWindow $0 "KuroCatOverlayWindowClass"
    ${If} $0 != 0
        SendMessage $0 ${WM_CLOSE} 0 0 /TIMEOUT=3000
    ${EndIf}
!macroend

Section "KuroCat"
    SetShellVarContext current
    ${If} ${FileExists} "$INSTDIR\KuroCat.exe"
        !insertmacro CloseKuroCat
    ${EndIf}

    SetOutPath "$INSTDIR"
    File /oname=KuroCat.exe "${APP_EXE}"
    File /oname=LICENSE.txt "..\LICENSE"
    WriteUninstaller "$INSTDIR\Uninstall.exe"

    CreateShortcut "$SMPROGRAMS\KuroCat.lnk" "$INSTDIR\KuroCat.exe"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "KuroCat"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\KuroCat.exe"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
    SetShellVarContext current
    !insertmacro CloseKuroCat
    ClearErrors
    Delete "$INSTDIR\KuroCat.exe"
    ${If} ${Errors}
        MessageBox MB_OK|MB_ICONSTOP "$(CloseAndRetry)"
        Abort
    ${EndIf}

    ReadRegStr $0 HKCU "${AUTOSTART_KEY}" "KuroCat"
    ${If} $0 == '$\"$INSTDIR\KuroCat.exe$\"'
        DeleteRegValue HKCU "${AUTOSTART_KEY}" "KuroCat"
    ${EndIf}
    DeleteRegKey HKCU "${UNINSTALL_KEY}"
    Delete "$SMPROGRAMS\KuroCat.lnk"
    Delete "$INSTDIR\LICENSE.txt"
    Delete "$INSTDIR\Uninstall.exe"
    RMDir "$INSTDIR"
SectionEnd
