@echo off
setlocal enabledelayedexpansion

set RALPH_VERSION=1.1.0

set SCRIPT_DIR=%~dp0
set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%

set prompt_file=
set prd_file=
set skills_csv=
set allow_profile=
set allow_tools_count=0
set deny_tools_count=0

:parse_args
if "%~1"=="" goto args_done
if "%~1"=="--prompt" (
    if "%~2"=="" (
        echo Error: --prompt requires a file path >&2
        call :usage
        exit /b 1
    )
    set prompt_file=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="--prd" (
    if "%~2"=="" (
        echo Error: --prd requires a file path >&2
        call :usage
        exit /b 1
    )
    set prd_file=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="--skill" (
    if "%~2"=="" (
        echo Error: --skill requires a value >&2
        call :usage
        exit /b 1
    )
    if "!skills_csv!"=="" (
        set skills_csv=%~2
    ) else (
        set skills_csv=!skills_csv!,%~2
    )
    shift
    shift
    goto parse_args
)
if "%~1"=="--allow-profile" (
    if "%~2"=="" (
        echo Error: --allow-profile requires a value >&2
        call :usage
        exit /b 1
    )
    set allow_profile=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="--allow-tools" (
    if "%~2"=="" (
        echo Error: --allow-tools requires a tool spec >&2
        call :usage
        exit /b 1
    )
    set /a allow_tools_count+=1
    set allow_tools[!allow_tools_count!]=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="--deny-tools" (
    if "%~2"=="" (
        echo Error: --deny-tools requires a tool spec >&2
        call :usage
        exit /b 1
    )
    set /a deny_tools_count+=1
    set deny_tools[!deny_tools_count!]=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="-h" goto show_help
if "%~1"=="--help" goto show_help
if "%~1"=="--" (
    shift
    goto args_done
)
if "%~1:~0,1%"=="-" (
    echo Error: unknown option: %~1 >&2
    call :usage
    exit /b 1
)
goto args_done

:show_help
call :usage
exit /b 0

:args_done

REM Default model if not provided
if "%MODEL%"=="" set MODEL=gpt-5.2

if "%prompt_file%"=="" (
    echo Error: --prompt is required >&2
    call :usage
    exit /b 1
)

if not exist "%prompt_file%" (
    echo Error: prompt file not readable: %prompt_file% >&2
    exit /b 1
)

if not "%prd_file%"=="" (
    if not exist "%prd_file%" (
        echo Error: PRD file not readable: %prd_file% >&2
        exit /b 1
    )
)

set progress_file=progress.txt
if not exist "%progress_file%" (
    echo Error: progress file not readable: %progress_file% >&2
    exit /b 1
)

if "%allow_profile%"=="" (
    if %allow_tools_count%==0 (
        echo Error: you must specify --allow-profile or at least one --allow-tools >&2
        call :usage
        exit /b 1
    )
)

REM Build copilot tool arguments
set copilot_tool_args=--deny-tool "shell(rm)" --deny-tool "shell(git push)"

if %allow_tools_count%==0 (
    if not "%allow_profile%"=="" (
        if "%allow_profile%"=="dev" (
            set copilot_tool_args=!copilot_tool_args! --allow-all-tools --allow-tool "write" --allow-tool "shell(pnpm:*)" --allow-tool "shell(git:*)"
        ) else if "%allow_profile%"=="safe" (
            set copilot_tool_args=!copilot_tool_args! --allow-tool "write" --allow-tool "shell(pnpm:*)" --allow-tool "shell(git:*)"
        ) else if "%allow_profile%"=="locked" (
            set copilot_tool_args=!copilot_tool_args! --allow-tool "write"
        ) else (
            echo Error: unknown --allow-profile: %allow_profile% >&2
            call :usage
            exit /b 1
        )
    )
)

for /l %%i in (1,1,%allow_tools_count%) do (
    set copilot_tool_args=!copilot_tool_args! --allow-tool "!allow_tools[%%i]!"
)

for /l %%i in (1,1,%deny_tools_count%) do (
    set copilot_tool_args=!copilot_tool_args! --deny-tool "!deny_tools[%%i]!"
)

REM Create context file
set context_file=.ralph-context.%RANDOM%.tmp
(
    echo # Context
    echo.
    if not "%skills_csv%"=="" (
        echo ## Skills
        for %%s in (%skills_csv:,= %) do (
            set skill_name=%%s
            set skill_file=skills\!skill_name!\SKILL.md
            if not exist "!skill_file!" (
                echo Error: skill not found/readable: !skill_file! >&2
                exit /b 1
            )
            echo.
            echo ### !skill_name!
            echo.
            type "!skill_file!"
        )
        echo.
    )
    if not "%prd_file%"=="" (
        echo ## PRD ^(%prd_file%^)
        type "%prd_file%"
        echo.
    )
    echo ## progress.txt
    type "%progress_file%"
    echo.
) > "%context_file%"

set combined_prompt_file=.ralph-prompt.%RANDOM%.tmp
(
    type "%context_file%"
    echo.
    echo # Prompt
    echo.
    type "%prompt_file%"
    echo.
) > "%combined_prompt_file%"

REM Run copilot
copilot --add-dir "%CD%" --model "%MODEL%" --no-color --stream off --silent -p "@%combined_prompt_file% Follow the attached prompt." %copilot_tool_args%
set exit_code=%errorlevel%

REM Cleanup
if exist "%context_file%" del /q "%context_file%" >nul 2>&1
if exist "%combined_prompt_file%" del /q "%combined_prompt_file%" >nul 2>&1

exit /b %exit_code%

:usage
echo Usage:
echo    %~nx0 --prompt ^<file^> [--prd ^<file^>] [--skill ^<a[,b,...]^>] [--allow-profile ^<safe^|dev^|locked^>] [--allow-tools ^<toolSpec^> ...] [--deny-tools ^<toolSpec^> ...]
echo.
echo Options:
echo    --prompt ^<file^>           Load prompt text from file (required).
echo    --prd ^<file^>              Optionally attach a PRD JSON file.
echo    --skill ^<a[,b,...]^>       Prepend one or more skills from skills/^<name^>/SKILL.md (comma-separated).
echo    --allow-profile ^<name^>    Tool permission profile: safe ^| dev ^| locked.
echo    --allow-tools ^<toolSpec^>  Allow a specific tool (repeatable). Example: --allow-tools write
echo                                           Use quotes if the spec includes spaces: --allow-tools "shell(git push)"
echo    --deny-tools ^<toolSpec^>   Deny a specific tool (repeatable). Example: --deny-tools "shell(rm)"
echo    -h, --help                Show this help.
echo.
echo Notes:
echo    - You must pass --allow-profile or at least one --allow-tools.
exit /b 0
