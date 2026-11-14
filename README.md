# Fishing Spot Info

Project Zomboid Build 42 mod. Hold a fishing rod and aim (the Aim key, Ctrl by default). The tile
where the bobber will land is coloured by how well fish bite there, and a box right of the mouse
cursor shows:

- **Spot score**: bites per minute at this tile compared with the best spot under the same
  weather and time (100% = best). Tile colour: green 90% and up, yellow-green 50% and up, orange
  15% and up, red below.
- **Fish here**: the fish number the game uses at that tile, and its bite multiplier (x0.1 with
  no fish, x0.5 below 10, x1.0 up to 25, x1.5 above)
- **Bite chance per try**: `0.8 x fish x time x weather x temperature x hook`, as in
  `Bobber:attractFish`, with each factor. No hook on the rod means no bites.
- **Slower tries**: the wait between tries is doubled near the shore and tripled closer than 3
  tiles to you (`Bobber:update`)
- **Area**: fish caught in the 40x40 area around the spot and when it restocks (5 in-game days
  after the last catch there). A fished area's border is drawn in orange.
- **Dawn/dusk bonus**: bites x1.2 from 04:00 to 07:00 and 18:00 to 21:00; when it starts or ends
- "Too far" when the tile is 16 tiles or more away (no cast)

With more Fishing skill, more water tiles around the aimed one are coloured too, lighter, each by
its own score: levels 0-2 the aimed tile only, 3-5 also the 4 next to it (cross), 6-8 the 8
around it (3x3), 9-10 the 12 within 2 tiles (diamond).

The bobber lands near the aimed point with a small random offset (less with more Fishing skill);
the fish number sums fish schools within 6 tiles, so neighbouring tiles read about the same.

## How vanilla fishing depletes (42.21)

From `zombie.iso.FishSchoolManager`:

- The first catch registers a 40x40 metagrid zone of type `Fishing` centred on the bobber. Its
  name is the catch count; each catch inside adds 1 and stamps the time.
- Each fish school counts `rand * 40 * FishAbundance / 5` minus that count.
- With no catch for 7200 game minutes (5 days) the count goes back to 0. The game applies this to
  areas it has cached, so a recovered area may show the old count until fish are counted there
  again.
- Fish schools move every day; the catch count stays with the area.

Read only: the mod never changes fishing. No vanilla files replaced. Safe to add to or remove
from existing saves. Client-side; not tested on a multiplayer server.

## Install

- Subscribe on the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3829682476) (ID `3829682476`) and enable it in the mod list.
- Manual: copy `Contents/mods/FishingSpotInfo` into `%USERPROFILE%\Zomboid\mods\`.

## Tests

In-game tests use PZTestHarness (`pzt.conf`, `tests/`; the save is a local copy, not in this repository):

- `pzt live`: values against vanilla (fish number, time bonus at every hour, bite chance, wait
  between tries), a catch, the 5-day reset, the spot score and colours, the box for an aimed tile.
- `bash tests/tools/uitest.sh`: the same plus a real aim: holds left Ctrl with the mouse on water,
  then on land, then lets go. The mouse cursor moves for a moment. `pzt stop` afterwards.

`vanilla-deps.txt` lists what the mod uses from vanilla.

## 한국어

낚싯대를 들고 조준(Ctrl)하면 찌가 떨어질 칸이 입질이 잘 되는 정도에 따라 색칠되고(초록 = 최고, 연두,
주황, 빨강 = 거의 없음), 마우스 커서 오른쪽에 정보가 나옵니다: 지점 점수(지금 날씨·시각에서 최고 지점
대비 분당 입질), 물고기 수와 배율, 한 번 시도할 때 입질 확률과 그 요소(물고기·시각·날씨·기온·바늘),
물가 근처(2배)·3칸 이내(3배) 느려짐, 구역(40x40)에서 잡은 수와 회복까지 남은 시간, 새벽/저녁 보너스.
낚시 레벨이 오르면 주변 물 칸도 각자 점수 색으로 옅게 칠해집니다: 0-2는 조준한 칸만, 3-5는 상하좌우 4칸,
6-8은 둘레 8칸(3x3), 9-10은 2칸 거리 안 12칸(마름모). 조회만 하고 낚시 값은 바꾸지 않습니다.

## License

All rights reserved. No license is granted for redistribution or modified versions.

## Support

If this mod helps you, you can support it via [Ko-fi](https://ko-fi.com/talkinghands2285) or [PayPal](https://www.paypal.com/paypalme/TalkingHands619/3). It's optional; every feature stays free.

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/talkinghands2285)
