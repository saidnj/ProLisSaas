@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
title ProLisSaas - solo las tablas

rem =====================================================================
rem  SOLO LAS TABLAS, con sus llaves foraneas.
rem
rem  Carga 01_tipos.sql y 02_tablas.sql y para ahi. Es lo minimo para ver
rem  el diagrama entidad-relacion en pgAdmin:
rem
rem     44 tablas · 111 llaves foraneas · 106 primarias · 91 unicas
rem
rem  Los tipos enumerados hacen falta igual: son el tipo de varias
rem  columnas, sin ellos las tablas no se crean.
rem
rem  Lo que NO carga: indices, funciones, privilegios, Row Level Security
rem  y semillas. Para eso esta cargar-db.bat.
rem =====================================================================

set "BASE=prolissaas"
set "USUARIO=postgres"

rem  Los .sql estan en UTF-8 y psql en Windows supone WIN1252. Sin esto,
rem  los comentarios entran con basura y la tabla de acentos de
rem  unaccent_simple() revienta con "byte 0x81".
set "PGCLIENTENCODING=UTF8"

rem ---- encontrar psql -------------------------------------------------
where psql >nul 2>&1
if %errorlevel%==0 (
  set "PSQL=psql"
  set "CREATEDB=createdb"
  set "DROPDB=dropdb"
) else (
  set "PSQL="
  for %%v in (18 17 16) do (
    if exist "C:\Program Files\PostgreSQL\%%v\bin\psql.exe" (
      if "!PSQL!"=="" (
        set "PSQL=C:\Program Files\PostgreSQL\%%v\bin\psql.exe"
        set "CREATEDB=C:\Program Files\PostgreSQL\%%v\bin\createdb.exe"
        set "DROPDB=C:\Program Files\PostgreSQL\%%v\bin\dropdb.exe"
      )
    )
  )
)

if "%PSQL%"=="" (
  echo.
  echo   No encontre psql. Instala PostgreSQL o agrega su bin al PATH.
  echo.
  pause
  exit /b 1
)

cd /d "%~dp0"

echo.
echo   SOLO LAS TABLAS Y SUS LLAVES FORANEAS
echo.
echo   psql:  %PSQL%
echo   base:  %BASE%
echo.
echo   Esto BORRA la base %BASE% si ya existe.
echo.
set /p "OK=  Escribe SI para continuar: "
if /i not "%OK%"=="SI" (
  echo.
  echo   Cancelado. No se toco nada.
  pause
  exit /b 0
)

echo.
"%DROPDB%"   -U %USUARIO% --if-exists %BASE%
"%CREATEDB%" -U %USUARIO% %BASE%
if errorlevel 1 (
  echo.
  echo   No se pudo crear la base. Revisa que el servicio este corriendo:
  echo     Get-Service postgresql*
  echo.
  pause
  exit /b 1
)

echo.
for %%f in (01_tipos.sql 02_tablas.sql) do (
  echo   ^> %%f
  "%PSQL%" -U %USUARIO% -d %BASE% -v ON_ERROR_STOP=1 -q -f "%%f"
  if errorlevel 1 (
    echo.
    echo   FALLO en %%f.
    echo.
    pause
    exit /b 1
  )
)

echo.
echo   Cuantas cosas quedaron:
"%PSQL%" -U %USUARIO% -d %BASE% -q -c "SELECT (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' AND n.nspname IN ('plataforma','core','lab','integra','audit','comercial')) AS tablas, (SELECT count(*) FROM pg_constraint WHERE contype='f') AS foraneas, (SELECT count(*) FROM pg_constraint WHERE contype='p') AS primarias, (SELECT count(*) FROM pg_constraint WHERE contype='u') AS unicas;"

echo.
echo   ============================================================
echo    Listo.
echo.
echo    En pgAdmin: clic derecho sobre el esquema "core"
echo    y elige ERD For Schema.
echo.
echo    Por esquema y no por base: con 44 tablas, un diagrama de
echo    todo junto no se lee.
echo   ============================================================
echo.
pause
