#!/bin/bash
# Opens every screen of the app on an iPhone and an iPad simulator (debug launch arguments), and fails if
# the app is not running afterwards or a crash report appeared. Screenshots of every screen go into one
# contact sheet per device for a look over before a release.
#
#   Tools/release/smoke.sh <Canopus.app built for the simulator> <output dir> [iphone-udid] [ipad-udid]
#
# The simulators should have a character signed in (the character pages are part of the run): without one
# those pages only show the sign-in prompt, so check the contact sheets.
set -u
APP=$1; OUT=$2
# The newest available simulator of a kind (names change with Xcode, ids with every machine).
find_sim() {
  xcrun simctl list devices available -j | python3 -c "
import json, re, sys
devices = json.load(sys.stdin)['devices']
for runtime in sorted(devices, reverse=True):
    for d in devices[runtime]:
        if re.fullmatch(sys.argv[1], d['name']): print(d['udid']); sys.exit()
" "$1"
}
IPHONE=${3:-$(find_sim 'iPhone \d+ Pro Max')}
IPAD=${4:-$(find_sim 'iPad Pro 13-inch.*')}
[ -n "$IPHONE" ] && [ -n "$IPAD" ] || { echo "SMOKE FAILED: no iPhone Pro Max / iPad Pro 13-inch simulator"; exit 1; }
echo "iPhone $IPHONE, iPad $IPAD"
BUNDLE=AlexPlumbing.Canopus
WAIT=${SMOKE_WAIT:-12}
mkdir -p "$OUT"; rm -f "$OUT"/*.png "$OUT"/failures.txt

# name|launch arguments
SCENARIOS=(
  "char-overview|-startPage character -charTab overview"
  "char-wealth|-startPage character -charTab wealth"
  "char-skills|-startPage character -charTab skills"
  "char-plan|-startPage character -charTab plan"
  "char-clones|-startPage character -charTab clones"
  "char-fits|-startPage character -charTab fits"
  "char-assets|-startPage character -charTab assets"
  "char-blueprints|-startPage character -charTab blueprints"
  "char-wallet|-startPage character -charTab wallet"
  "char-contracts|-startPage character -charTab contracts"
  "char-reputation|-startPage character -charTab reputation"
  "active-ship|-startPage character -charTab overview -openActiveShip YES"
  "mail|-startPage mail"
  "fit-modules|-startPage fitting -openFirstFit YES -fitTab modules"
  "fit-stats|-startPage fitting -openFirstFit YES -fitTab stats"
  "fit-trial|-startPage fitting -openFirstFit YES -fitTab stats -fitTrial 3319:1"
  "pvp|-startPage killboard"
  "market|-startPage market"
  "industry-calc|-startPage industry -industryTab calc -industryProduct 587"
  "industry-reprocess|-startPage industry -industryTab reprocess"
  "industry-jobs|-startPage industry -industryTab jobs"
  "industry-structures|-startPage industry -industryTab structures"
  "industry-moons|-startPage industry -industryTab moons"
  "pi-colonies|-startPage planets -piTab colonies"
  "pi-calc|-startPage planets -piTab calc -piProduct 2867"
  "mining|-startPage mining"
  "map|-startPage map"
  "jumps|-startPage jumps"
  "wormholes|-startPage wormholes"
  "thera|-startPage thera"
  "universe-incursions|-startPage universe -universeTab incursions"
  "universe-fw|-startPage universe -universeTab fw"
  "universe-sov|-startPage universe -universeTab sov"
  "universe-insurance|-startPage universe -universeTab insurance -insuranceShip 638"
  "database|-startPage database"
  "database-type|-startPage database -openType 24698"
  "mutaplasmids|-startPage database -dbTab mutaplasmids -mutaModule 3841"
  "people|-startPage people -peopleOpen alliance:99003214"
  "agents|-startPage agents"
  "settings|-startPage settings"
)

fail=0
run_device() {
  local dev=$1 tag=$2
  xcrun simctl boot "$dev" 2>/dev/null || true
  xcrun simctl bootstatus "$dev" -b >/dev/null 2>&1 || { echo "$tag: simulator did not boot" >> "$OUT/failures.txt"; fail=1; return; }
  xcrun simctl install "$dev" "$APP" || { echo "$tag: install failed" >> "$OUT/failures.txt"; fail=1; return; }
  xcrun simctl status_bar "$dev" override --time "9:41" --batteryState charged --batteryLevel 100 >/dev/null 2>&1
  for s in "${SCENARIOS[@]}"; do
    local name=${s%%|*} args=${s#*|}
    local marker; marker=$(mktemp)
    xcrun simctl terminate "$dev" $BUNDLE >/dev/null 2>&1
    # shellcheck disable=SC2086
    xcrun simctl launch "$dev" $BUNDLE $args >/dev/null 2>&1
    sleep "$WAIT"
    if ! xcrun simctl spawn "$dev" launchctl list 2>/dev/null | grep -q "$BUNDLE"; then
      echo "$tag $name: the app is not running (crashed?)" >> "$OUT/failures.txt"; fail=1
    fi
    if find ~/Library/Logs/DiagnosticReports -name 'Canopus*' -newer "$marker" 2>/dev/null | grep -q .; then
      echo "$tag $name: crash report written" >> "$OUT/failures.txt"; fail=1
    fi
    rm -f "$marker"
    xcrun simctl io "$dev" screenshot "$OUT/$tag-$name.png" >/dev/null 2>&1
    printf '.'
  done
  xcrun simctl terminate "$dev" $BUNDLE >/dev/null 2>&1
  echo " $tag done"
}

run_device "$IPHONE" iphone
run_device "$IPAD" ipad

# One contact sheet per device: every screen small, named, to look over.
python3 - "$OUT" <<'PY'
import glob, os, sys
from PIL import Image, ImageDraw
out = sys.argv[1]
for tag in ("iphone", "ipad"):
    files = sorted(glob.glob(os.path.join(out, f"{tag}-*.png")))
    if not files: continue
    w = 260; ims = []
    for f in files:
        im = Image.open(f).convert("RGB"); h = int(im.height * w / im.width)
        im = im.resize((w, h)); d = ImageDraw.Draw(im)
        d.rectangle((0, 0, w, 18), fill=(0, 0, 0)); d.text((4, 3), os.path.basename(f)[len(tag) + 1:-4], fill=(255, 255, 0))
        ims.append(im)
    cols = 8; rows = (len(ims) + cols - 1) // cols; h = max(i.height for i in ims)
    sheet = Image.new("RGB", (cols * w, rows * h), (40, 40, 40))
    for k, im in enumerate(ims): sheet.paste(im, ((k % cols) * w, (k // cols) * h))
    sheet.save(os.path.join(out, f"sheet-{tag}.jpg"), quality=80)
PY

if [ $fail -ne 0 ]; then echo "SMOKE FAILED:"; cat "$OUT/failures.txt"; exit 1; fi
echo "SMOKE OK: ${#SCENARIOS[@]} screens on iPhone and iPad, sheets in $OUT"
