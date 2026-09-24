@echo off
setlocal
cd /d "%~dp0"

echo.
echo   Visor de documentacion  -  ProLisSaas
echo   ------------------------------------
echo   Sirviendo: %CD%
echo.
echo   (Si esto falla, abre documentacion.html con doble clic:
echo    lleva los documentos dentro y no necesita servidor.)
echo.

rem Si quedo un visor abierto de antes -- por ejemplo el de la carpeta vieja
rem del escritorio, antes de que la documentacion se mudara aqui -- ese proceso
rem sigue ocupando el puerto y el navegador termina viendo la carpeta que no es.
set PUERTO=8099
netstat -an | findstr /c:":8099 " | findstr /i "LISTENING" >nul 2>nul
if not errorlevel 1 (
  echo   AVISO: el puerto 8099 ya esta ocupado.
  echo   Suele ser un visor que quedo abierto desde antes de mover la carpeta,
  echo   y sirve archivos que ya no estan ahi. Uso el 8100 en su lugar.
  echo   Si te sobra, cierra la otra ventana de consola y vuelve a abrir esto.
  echo.
  set PUERTO=8100
)

where py >nul 2>nul
if %errorlevel%==0 goto :usar_py

where python >nul 2>nul
if %errorlevel%==0 goto :usar_python

where node >nul 2>nul
if %errorlevel%==0 goto :usar_node

echo   No encontre Python ni Node en esta computadora.
echo.
echo   Opciones:
echo     - Instala Python desde python.org, o
echo     - abre esta carpeta en Visual Studio Code y usa la extension
echo       "Live Server" sobre documentacion.html
echo.
pause
exit /b 1

:usar_py
echo   Sirviendo en http://localhost:%PUERTO%/documentacion.html
echo   Deja esta ventana abierta. Ctrl+C para detener.
echo.
start "" http://localhost:%PUERTO%/documentacion.html
py -m http.server %PUERTO%
exit /b

:usar_python
echo   Sirviendo en http://localhost:%PUERTO%/documentacion.html
echo   Deja esta ventana abierta. Ctrl+C para detener.
echo.
start "" http://localhost:%PUERTO%/documentacion.html
python -m http.server %PUERTO%
exit /b

:usar_node
echo   Sirviendo en http://localhost:%PUERTO%/documentacion.html
echo   Deja esta ventana abierta. Ctrl+C para detener.
echo.
start "" http://localhost:%PUERTO%/documentacion.html
npx --yes http-server -p %PUERTO% -c-1
exit /b
