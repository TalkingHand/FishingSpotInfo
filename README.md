# Fishing Spot Info

Project Zomboid Build 42 mod. Right-click any water tile and choose **Fishing spot info** to see:

- **Fish here**: the fish number the game uses for the bite chance at that tile, and its bite
  multiplier (x0.1 with no fish, x0.5 below 10, x1.0 up to 25, x1.5 above)
- **Caught in this area**: fish caught in the 40x40 area around the spot, and the area's corners
- **Restocks in**: time until the area resets (5 in-game days after the last catch there)

While the window is open, the tile is highlighted and the area's border is drawn on the ground:
green when the area is fully stocked, orange when it has been fished.

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

- Steam Workshop: link follows after the first upload.
- Manual: copy `Contents/mods/FishingSpotInfo` into `%USERPROFILE%\Zomboid\mods\`.

## Tests

In-game tests use PZTestHarness (`pzt.conf`, `tests/`; the save is a local copy, not in this repository):

- `pzt run`: query values against vanilla, a catch, the 5-day reset, the menu hook on water and
  land, the window, the ground border.
- `bash tests/tools/uitest.sh`: the same plus real mouse clicks (right-click land and water,
  left-click the option). The mouse cursor moves for a moment.

`vanilla-deps.txt` lists what the mod uses from vanilla.

## 한국어

물 타일을 우클릭하고 **낚시터 정보**를 고르면 그 칸의 물고기 수와 입질 배율, 그 구역(40x40)에서
잡은 수, 회복까지 남은 시간(마지막으로 잡은 뒤 게임 시간 5일)이 창에 나옵니다. 창이 열려 있는
동안 바닥에 칸과 구역 테두리가 표시됩니다(초록 = 가득 참, 주황 = 줄어듦). 조회만 하고 낚시 값은
바꾸지 않습니다.

## License

All rights reserved. No license is granted for redistribution or modified versions.

## Support

If this mod helps you, you can support it via [PayPal](https://www.paypal.com/paypalme/TalkingHands619/3). It's optional; every feature stays free.
