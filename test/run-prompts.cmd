@echo off
setlocal enabledelayedexpansion

set ONLY_LIST_COUNT=0

:parse_args
if "%~1"=="" goto args_done
if "%~1"=="-h" goto show_help
if "%~1"=="--help" goto show_help
if "%~1"=="--only" (
    if "%~2"=="" (
        echo Error: --only requires a value >&2
        call :usage
        exit /b 1
    )
    REM Parse comma-separated list
    for %%a in (%~2) do (
        set part=%%a
        set part=!part:.txt=!
        set /a ONLY_LIST_COUNT+=1
        set ONLY_LIST[!ONLY_LIST_COUNT!]=!part!.txt
    )
    shift
    shift
    goto parse_args
)
echo Error: unknown argument: %~1 >&2
call :usage
exit /b 1

:show_help
call :usage
exit /b 0

:args_done

REM Get repository root
for /f "delims=" %%i in ('git rev-parse --show-toplevel 2^>nul') do set ROOT=%%i
if "%ROOT%"=="" (
    echo Error: must run inside a git repository >&2
    exit /b 1
)

REM Convert forward slashes to backslashes for Windows
set ROOT=%ROOT:/=\%

if "%MAIN_BRANCH%"=="" set MAIN_BRANCH=main
if "%MODEL%"=="" set MODEL=gpt-5.2

set LOG_ROOT=%ROOT%

REM Create timestamp for this run
for /f "tokens=1-6 delims=/:. " %%a in ("%date% %time%") do (
    set year=%%c
    set month=%%a
    set day=%%b
    set hour=%%d
    set minute=%%e
    set second=%%f
)
REM Pad with zeros
if "%month:~1%"=="" set month=0%month%
if "%day:~1%"=="" set day=0%day%
if "%hour:~1%"=="" set hour=0%hour%
if "%minute:~1%"=="" set minute=0%minute%
if "%second:~1%"=="" set second=0%second%
set TS=%year%%month%%day%T%hour%%minute%%second%Z

set RUN_LOG_DIR=%LOG_ROOT%\test\log\%TS%
if not exist "%RUN_LOG_DIR%" mkdir "%RUN_LOG_DIR%"

set PROMPTS_DIR=%ROOT%\prompts
if not exist "%PROMPTS_DIR%" (
    echo Error: prompts folder not found at: %PROMPTS_DIR% >&2
    exit /b 1
)

REM Find all prompt files
set PROMPT_COUNT=0
for /f "delims=" %%f in ('dir /b /a-d "%PROMPTS_DIR%\*.txt" 2^>nul ^| sort') do (
    set /a PROMPT_COUNT+=1
    set PROMPT_FILES[!PROMPT_COUNT!]=%%f
)

if %PROMPT_COUNT%==0 (
    echo Error: no prompt files found in %PROMPTS_DIR% >&2
    exit /b 1
)

REM Filter by ONLY_LIST if provided
if %ONLY_LIST_COUNT% gtr 0 (
    set FILTERED_COUNT=0
    for /l %%i in (1,1,%PROMPT_COUNT%) do (
        for /l %%j in (1,1,%ONLY_LIST_COUNT%) do (
            if "!PROMPT_FILES[%%i]!"=="!ONLY_LIST[%%j]!" (
                set /a FILTERED_COUNT+=1
                set FILTERED_PROMPTS[!FILTERED_COUNT!]=!PROMPT_FILES[%%i]!
            )
        )
    )
    if !FILTERED_COUNT!==0 (
        echo Error: --only filter matched no prompts >&2
        exit /b 1
    )
    set PROMPT_COUNT=!FILTERED_COUNT!
    for /l %%i in (1,1,!PROMPT_COUNT!) do (
        set PROMPT_FILES[%%i]=!FILTERED_PROMPTS[%%i]!
    )
)

echo Logging to: %RUN_LOG_DIR%

REM Create summary file
echo prompt	status	worktree > "%RUN_LOG_DIR%\summary.tsv"

REM Process each prompt
for /l %%i in (1,1,%PROMPT_COUNT%) do (
    set prompt_file=!PROMPT_FILES[%%i]!
    set prompt_name=!prompt_file:.txt=!
    set prd_file=plans\prd-!prompt_name!.json
    set prd_src=%ROOT%\!prd_file!
    set needs_prd=1
    
    set wt_dir=%ROOT%\test\worktrees\%TS%-!prompt_name!
    set branch=ralph-test/%TS%-!prompt_name!
    set log_file=%RUN_LOG_DIR%\!prompt_name!.log
    
    REM Check if PRD is needed for this prompt
    if "!prompt_file!"=="pest-coverage.txt" (
        set needs_prd=0
        set prd_file=
        set prd_src=
    )
    
    if !needs_prd!==1 (
        if not exist "!prd_src!" (
            set prd_file=plans\prd.json
            set prd_src=%ROOT%\!prd_file!
            if not exist "!prd_src!" (
                echo Error: default PRD file not readable: !prd_file! >> "!log_file!"
                echo Hint: create it at: !prd_src! >> "!log_file!"
                echo !prompt_file!	SKIP^(missing-prd^)	- >> "%RUN_LOG_DIR%\summary.tsv"
                goto :next_prompt
            )
        )
    )
    
    echo ==^> [!prompt_name!] creating worktree: !wt_dir! >> "!log_file!"
    
    REM Create worktree
    if not exist "!wt_dir!" mkdir "!wt_dir!"
    git -C "%ROOT%" worktree add -b "!branch!" "!wt_dir!" "%MAIN_BRANCH%" >> "!log_file!" 2>&1
    if errorlevel 1 (
        echo !prompt_file!	FAIL^(worktree-create^)	!wt_dir! >> "%RUN_LOG_DIR%\summary.tsv"
        goto :cleanup_worktree
    )
    
    pushd "!wt_dir!" >nul
    
    REM Copy prompt file
    if not exist prompts mkdir prompts
    copy "%ROOT%\prompts\!prompt_file!" "prompts\!prompt_file!" >nul 2>&1
    
    REM Handle WordPress-specific setup
    if "!prompt_file!"=="wordpress-plugin-agent.txt" (
        if not exist skills mkdir skills
        if exist skills\wp-plugin-development rmdir /s /q skills\wp-plugin-development 2>nul
        if exist skills\wp-project-triage rmdir /s /q skills\wp-project-triage 2>nul
        if exist "%ROOT%\test\skills\wp-plugin-development" (
            xcopy /E /I /Q "%ROOT%\test\skills\wp-plugin-development" "skills\wp-plugin-development" >nul 2>&1
        )
        if exist "%ROOT%\test\skills\wp-project-triage" (
            xcopy /E /I /Q "%ROOT%\test\skills\wp-project-triage" "skills\wp-project-triage" >nul 2>&1
        )
    )
    
    REM Build copilot arguments
    set copilot_tool_args=--deny-tool "shell(rm)" --deny-tool "shell(git push)"
    
    if "!prompt_file!"=="wordpress-plugin-agent.txt" (
        set copilot_tool_args=!copilot_tool_args! --allow-tool "write" --allow-tool "shell(git:*)" --allow-tool "shell(npx:*)" --allow-tool "shell(composer:*)" --allow-tool "shell(npm:*)"
    ) else if "!prompt_file!"=="safe-write-only.txt" (
        set copilot_tool_args=!copilot_tool_args! --allow-tool "write"
    ) else (
        set copilot_tool_args=!copilot_tool_args! --allow-tool "write" --allow-tool "shell(pnpm:*)" --allow-tool "shell(git:*)"
    )
    
    if !needs_prd!==1 (
        if not exist "!prd_file!" (
            for %%p in ("!prd_file!") do (
                if not exist "%%~dpp" mkdir "%%~dpp"
            )
        )
        copy "!prd_src!" "!prd_file!" >nul 2>&1
    )
    
    echo ==^> [!prompt_name!] running copilot >> "!log_file!"
    echo ==^> [!prompt_name!] prompt: !prompt_file! >> "!log_file!"
    echo ==^> [!prompt_name!] tools: !copilot_tool_args! >> "!log_file!"
    echo --- COPILOT OUTPUT START --- >> "!log_file!"
    
    REM Create context file
    set context_file=.ralph-context.%RANDOM%.tmp
    set preflight_failed=0
    (
        echo # Context
        echo.
        if "!prompt_file!"=="wordpress-plugin-agent.txt" (
            set skill_file=skills\wp-plugin-development\SKILL.md
            if exist "!skill_file!" (
                echo ## Skill ^(wp-plugin-development^)
                type "!skill_file!"
                echo.
            ) else (
                echo [HARNESS] Error: WordPress skill not readable: !skill_file! >&2
                set preflight_failed=1
            )
        )
        if !needs_prd!==1 (
            echo ## PRD ^(!prd_file!^)
            type "!prd_file!"
            echo.
        )
        echo ## progress.txt
        type "progress.txt"
        echo.
    ) > "!context_file!"
    
    if !preflight_failed!==1 (
        echo [ASSERT] Missing required WordPress skill files >> "!log_file!"
        del /q "!context_file!" >nul 2>&1
        popd >nul
        echo !prompt_file!	FAIL^(missing-skill^)	!wt_dir! >> "%RUN_LOG_DIR%\summary.tsv"
        goto :cleanup_worktree
    )
    
    REM Run copilot
    set result_file=.ralph-output.%RANDOM%.tmp
    copilot --add-dir "%CD%" --model "%MODEL%" -p "@!context_file! " !copilot_tool_args! < "prompts\!prompt_file!" > "!result_file!" 2>&1
    set copilot_status=!errorlevel!
    
    type "!result_file!" >> "!log_file!" 2>&1
    del /q "!result_file!" >nul 2>&1
    del /q "!context_file!" >nul 2>&1
    
    echo --- COPILOT OUTPUT END --- >> "!log_file!"
    
    REM Check for output
    findstr /r /v "^$" "!log_file!" | findstr "--- COPILOT OUTPUT" >nul 2>&1
    if errorlevel 1 (
        echo [ASSERT] No Copilot output captured >> "!log_file!"
        set copilot_status=3
    )
    
    REM WordPress-specific checks
    if "!prompt_file!"=="wordpress-plugin-agent.txt" (
        findstr /i /c:"wp-env start" /c:"composer lint" /c:"composer test" "!log_file!" >nul 2>&1
        if errorlevel 1 (
            echo [ASSERT] Missing expected WordPress checks in output >> "!log_file!"
            set copilot_status=2
        )
        findstr /r "\bpnpm\b" "!log_file!" >nul 2>&1
        if not errorlevel 1 (
            echo [ASSERT] Unexpected pnpm mention in output >> "!log_file!"
            set copilot_status=2
        )
    )
    
    popd >nul
    
    if !copilot_status!==0 (
        echo !prompt_file!	PASS	!wt_dir! >> "%RUN_LOG_DIR%\summary.tsv"
    ) else (
        echo !prompt_file!	FAIL^(!copilot_status!^)	!wt_dir! >> "%RUN_LOG_DIR%\summary.tsv"
    )
    
    :cleanup_worktree
    REM Cleanup worktree
    git -C "%ROOT%" worktree remove --force "!wt_dir!" >nul 2>&1
    git -C "%ROOT%" branch -D "!branch!" >nul 2>&1
    git -C "%ROOT%" worktree prune >nul 2>&1
    
    :next_prompt
)

echo Done. Summary: %RUN_LOG_DIR%\summary.tsv
exit /b 0

:usage
echo Usage:
echo    %~nx0 [--only ^<prompt1[,prompt2...]^>]
echo.
echo What it does:
echo    - Finds all *.txt prompts in .\prompts
echo    - Creates a git worktree per prompt
echo    - Runs .\ralph-once.cmd with that prompt inside the worktree
echo    - Logs stdout/stderr to .\test\log\^<timestamp^>/
echo    - Removes the worktree and its temp branch
echo.
echo Options:
echo    --only ^<prompt1[,prompt2...]^>  Only run the selected prompt(s). Values can be
echo                                  basenames like default.txt, or names like default.
echo                                  Repeatable.
echo.
echo Environment variables:
echo    MAIN_BRANCH   Base branch for worktrees (default: main)
echo    MODEL         Copilot model (default: gpt-5.2)
exit /b 0
