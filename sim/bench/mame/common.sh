# Sourced by run_states.sh / run_replay.sh / run_sr.sh (Git Bash on Windows).
#   MAME_EXE  MAME 0.289's mame.exe (default: mame on the PATH)
#   ROM_PATH  the folder holding ohmygod.zip and naname.zip, Windows path (default: roms)
#   OMG_WORK  scratch folder for dumps (default: <folder holding the repository>/work); never inside the repository
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)                   # the repository (mister/)
WORK=${OMG_WORK:-$(cd "$REPO/.." && pwd)/work}
mkdir -p "$WORK/mame/cfg" "$WORK/mame/nvram"
M=${MAME_EXE:-mame}
RP=${ROM_PATH:-roms}
LUA=$(cygpath -w "$REPO/tools/lua/dump_state.lua")
CFG=$(cygpath -w "$WORK/mame/cfg"); NVR=$(cygpath -w "$WORK/mame/nvram")
wpath() { cygpath -m "$1"; }                         # forward-slash Windows path (what the Lua script wants)
