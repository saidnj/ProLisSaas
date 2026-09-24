@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
title ProLisSaas - cargar la base

rem =====================================================================
rem  Crea la base prolissaas desde cero y le carga el esquema entero.
rem
rem  Doble clic y listo. Si psql no esta en el PATH, lo busca donde el
rem  instalador de Windows lo deja.
rem
rem  OJO: borra la base prolissaas si ya existe. Pide confirmacion.
rem =====================================================================

set "BASE=prolissaas"
set "USUARIO=postgres"

rem ---- LA LINEA QUE IMPORTA ------------------------------------------
rem  Los .sql estan en UTF-8. psql en Windows, si nadie le dice nada,
rem  supone que el archivo viene en la pagina de codigos del sistema
rem  (WIN1252 en espanol) y lee mal cada caracter acentuado.
rem
rem  Casi siempre eso no falla, solo corrompe: 'ó' pasa a 'Ã³' y el
rem  comentario queda con basura adentro. Falla ruidosamente cuando
rem  aparece un byte que WIN1252 no tiene -- la 'Á' de la tabla de
rem  acentos de unaccent_simple() son los bytes C3 81, y 0x81 no existe
rem  en WIN1252:
rem
rem    ERROR: caracter con secuencia de bytes 0x81 en codificacion
rem           «WIN1252» no tiene equivalente en la codificacion «UTF8»
rem
rem  Con esto psql deja de adivinar.
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
  echo   No encontre psql.
  echo.
  echo   Instala PostgreSQL desde postgresql.org/download/windows
  echo   o agrega su carpeta bin al PATH.
  echo.
  pause
  exit /b 1
)

cd /d "%~dp0"

echo.
echo   psql:  %PSQL%
"%PSQL%" --version
echo   base:  %BASE%
echo   desde: %CD%
echo.
echo   Esto BORRA la base %BASE% si ya existe y la vuelve a crear.
echo.
set /p "OK=  Escribe SI para continuar: "
if /i not "%OK%"=="SI" (
  echo.
  echo   Cancelado. No se toco nada.
  pause
  exit /b 0
)

echo.
echo   Te va a pedir la contrasena de %USUARIO% varias veces.
echo   Para que no la pida, crea el archivo %APPDATA%\postgresql\pgpass.conf
echo   con una linea:  localhost:5432:*:postgres:TU_CLAVE
echo.

"%DROPDB%"   -U %USUARIO% --if-exists %BASE%
"%CREATEDB%" -U %USUARIO% %BASE%
if errorlevel 1 (
  echo.
  echo   No se pudo crear la base. Revisa que el servicio de PostgreSQL este
  echo   corriendo:  Get-Service postgresql*
  echo.
  pause
  exit /b 1
)

echo.
for %%f in (01_tipos.sql 02_tablas.sql 03_indices.sql 04_funciones.sql 05_privilegios.sql 06_semillas.sql) do (
  echo   ^> %%f
  "%PSQL%" -U %USUARIO% -d %BASE% -v ON_ERROR_STOP=1 -q -f "%%f"
  if errorlevel 1 (
    echo.
    echo   FALLO en %%f. La base quedo a medias.
    echo.
    pause
    exit /b 1
  )
)

echo.
echo   ============================================================
echo    Listo. La base %BASE% esta cargada.
echo.
echo    Para verla:  abre pgAdmin, conectate al servidor local,
echo    despliega Databases ^> %BASE% ^> Schemas.
echo.
echo    Para el diagrama: clic derecho sobre el esquema "core"
echo    y elige ERD For Schema.
echo   ============================================================
echo.
echo   Si quieres correr las pruebas, cada una necesita una base
echo   recien cargada. Vuelve a correr este .bat antes de cada una:
echo.
echo     %PSQL% -U %USUARIO% -d %BASE% -f 94_pruebas_modulos.sql
echo.
pause
