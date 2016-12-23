# PYMOD = $(nimble path pymod | tail -n 1)
all:
	nim c nimtga.nim

# pymod:
# 	echo $()PYMOD
