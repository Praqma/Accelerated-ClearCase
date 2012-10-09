color e0
:loop
cls
for /f %%a in ('dir /s /b m:\1349446165.txt') do @(
@cleartool checkout -nc %%a
@echo %time% > %%a
@cleartool checkin -nc %%a
)
@ratlperl -e "$|=1; $i=900; while ($i > 0) {sleep 1; print \"$i seconds left, CTRL+C to exit\r\"; $i--;} ";
goto loop
:ende
color 