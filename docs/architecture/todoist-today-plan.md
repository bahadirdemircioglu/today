# Architecture Plan: todoist-today

**Status:** implemented (v1.0.0)
**Revision:** 4

> Revizyon 4: tartışma (`debates/todoist-today.md`) 3. turda tüm maddeler kapanarak bitti; açık sorular
> kapatıldı (bkz. Open Questions) ve uygulama sırasında yapılan düzeltmeler "Implementation Notes"
> bölümüne işlendi. Tartışma script'leri (DeepSeek eleştiri aracı) bu reponun parçası değildir.

## Overview & Goals

**Todoist Today**: KDE Plasma 6 (hedef sistem Plasma 6.7.5, CachyOS/Arch; minimum Plasma 6.0) için
saf QML + JavaScript plasmoid. Todoist'in "Today" görünümünü panelde ve masaüstünde gösterir:
önce gecikmiş (overdue), sonra bugünkü görevler; saatli görevler saate göre.

- **Kim / neden:** Kullanıcı görevlerini Android'de Todoist ile yönetiyor; masaüstünde görmek,
  tamamlamak ve hızlıca eklemek istiyor. Plasma 6 için bakımlı bir Todoist widget'ı yok →
  GitHub'da (sonra KDE Store'da) GPL-3.0-or-later ile açık kaynak yayınlanacak.
- **Ürün ilkesi:** "Apple ekosistemi gibi" = akıllı varsayılan, neredeyse sıfır ayar, platforma
  yerli görünüm (Plasma/Kirigami teması, açık/koyu ve vurgu rengini takip eder, bol boşluk,
  yuvarlak köşeler, az öğe). Apple kopyası değil; Breeze dilinde.
- **Boyuta duyarlı görünüm:**
  - Panel: ikon + sayı rozeti → tıklayınca liste popup'ı.
  - Masaüstü küçük: büyük sayı + sıradaki görev.
  - Masaüstü büyük / popup: tam liste, yuvarlak onay kutusu, tamamlama animasyonu, altta
    "+ New task" satırı; boş liste için sevimli "All done for today" durumu.
- **Özellikler (v1):** görev tamamlama, Todoist Quick Add doğal diliyle görev ekleme, artımlı sync,
  kalıcı çevrimdışı önbellek + işlem kuyruğu (UUID'li komutlar; widget/plasmashell yeniden
  başlasa da kaybolmaz).
- **Kurulum:** tek ekran. "Open Todoist settings" butonu token sayfasını açar
  (`https://app.todoist.com/app/settings/integrations/developer`), token yapıştırılınca anında
  `GET /api/v1/user` ile doğrulanır ve hesap adı gösterilir. OAuth yok.

**Başarı ölçütleri**
1. Telefonda eklenen/tamamlanan görev ≤ 5 dk içinde widget'ta; panel popup'ı açılınca veya masaüstü
   widget'ının üzerine gelinince (hover) son sync > 30 sn ise anında.
2. Widget'taki tamamlama/ekleme bir sonraki sync çağrısında (≤ ~2 sn, online iken) telefona yansır.
3. Kurulum = token yapıştırmak, < 1 dk.
4. KDE Store / GitHub release'ten tek tıkla (`.plasmoid`) kurulum; derleme yok.

## Non-Goals

- OAuth, KWallet / Secret Service (token düz metin config'te — bilinçli tradeoff).
- Görev düzenleme, silme, erteleme; alt görev hiyerarşisi (bugün vadeli alt görevler **düz satır**
  olarak görünür, hiyerarşi gösterilmez); açıklama/yorum/etiket gösterimi; `deadline` alanı.
- Filtre/proje seçimi, Upcoming görünümü, çoklu hesap, bildirimler/hatırlatıcılar.
- Görev sıralamasını widget'tan değiştirme (sürükle-bırak).
- C++ eklenti, derleme adımı, harici runtime bağımlılığı.
- Geri alma (undo) — Open Questions'ta; v1 kapsamında değil.

## Directory Structure Changes

Proje kökü = bu repo (`github.com/bahadirdemircioglu/today`). Yapı:

```
today/
├── package/                              # .plasmoid zip'inin kökü (kpackagetool6 bunu kurar)
│   ├── metadata.json
│   └── contents/
│       ├── config/
│       │   ├── main.xml                  # KConfig şeması: apiToken, accountName
│       │   └── config.qml                # tek kategori: "Account" → ui/ConfigAccount.qml
│       ├── ui/
│       │   ├── main.qml                  # PlasmoidItem: temsil seçimi, contextualActions, SyncController örneği
│       │   ├── SyncController.qml        # QtObject/Item: Timer'lar, XHR orkestrasyonu, state, LocalStorage I/O
│       │   ├── CompactRepresentation.qml # panel: ikon + rozet
│       │   ├── FullRepresentation.qml    # durum + boyuta göre Setup / Loading / SmallView / TaskListView seçer
│       │   ├── SmallView.qml             # büyük sayı + sıradaki görev
│       │   ├── TaskListView.qml          # başlık, Overdue/Today bölümleri, boş durum, footer
│       │   ├── TaskRow.qml               # tek satır: RoundCheck + başlık + saat/proje
│       │   ├── RoundCheck.qml            # yuvarlak onay kutusu + tamamlama animasyonu
│       │   ├── NewTaskField.qml          # "+ New task" satırı → Quick Add
│       │   ├── StatusFooter.qml          # "Updated 2 min ago" / "Offline" / hata banner'ı
│       │   ├── SetupView.qml             # widget içi kurulum (PlasmaComponents3)
│       │   ├── ConfigAccount.qml         # ayarlar penceresi sayfası (KCM.SimpleKCM + QQC2)
│       │   └── logic/
│       │       ├── DateUtil.js           # .pragma library — saf: tz ofseti, gün anahtarı, due ayrıştırma
│       │       ├── TaskStore.js          # .pragma library — saf: sync merge, Today hesaplama/sıralama
│       │       ├── CommandQueue.js       # .pragma library — saf: kuyruk işlemleri, sync_status işleme
│       │       ├── SyncMachine.js        # .pragma library — saf: state reducer (state, event) → {state, effects}
│       │       ├── TodoistClient.js      # .pragma library — sadece HTTP (XMLHttpRequest), sınıflandırma
│       │       ├── ModelSync.js          # .pragma library — ListModel'i satır listesine minimal işlemle eşitler
│       │       └── Storage.js            # QML-only: QtQuick.LocalStorage sarmalayıcı (Node'da test edilmez)
│       └── locale/                       # ÜRETİLİR (scripts/i18n-build.sh), git'e girmez, release'te pakete girer
├── translations/
│   ├── template.pot
│   └── tr.po                             # kaynak dil en; tr çevirisi
├── scripts/
│   ├── i18n-extract.sh                   # xgettext → translations/template.pot, msgmerge → *.po
│   ├── i18n-build.sh                     # msgfmt → package/contents/locale/<lang>/LC_MESSAGES/plasma_applet_<Id>.mo
│   └── package.sh                        # i18n-build + zip → dist/todoist-today-<version>.plasmoid
├── tests/
│   ├── helpers/load-qml-js.mjs           # .pragma/.import satırlarını ayıklayıp vm context'inde yükler
│   ├── fixtures/                         # gerçek v1 yanıt şekillerinde JSON (full sync, incremental, sync_status hataları)
│   ├── dateutil.test.mjs
│   ├── taskstore.test.mjs
│   ├── commandqueue.test.mjs
│   ├── syncmachine.test.mjs
│   ├── modelsync.test.mjs
│   ├── loader.test.mjs
│   └── todoistclient.test.mjs            # sahte XMLHttpRequest ile
├── .github/workflows/
│   ├── ci.yml                            # push/PR: node --test + metadata/xml doğrulama + i18n build smoke
│   └── release.yml                       # v* etiketi: sürüm kontrolü, package.sh, GitHub Release'e .plasmoid ekle
├── docs/architecture/{INDEX.md, todoist-today-plan.md}
├── README.md  LICENSE (GPL-3.0 tam metin)  CHANGELOG.md  .gitignore  package.json (yalnızca "test" script'i, bağımlılık yok)
```

Not: Qt `ListView` ile çakışmaması için liste bileşeni `TaskListView.qml`. Plasma 6 dokümanına uygun
olarak representation dosyaları `CompactRepresentation.qml` / `FullRepresentation.qml` adlandırılır.

## Tech Decisions

### T1. Plasmoid iskeleti (Plasma 6 API — Context7 `/websites/develop_kde_plasma_widget` ile doğrulandı)

- `metadata.json`:
  ```json
  {
    "KPlugin": {
      "Id": "io.github.bahadirdemircioglu.todoisttoday",
      "Name": "Todoist Today", "Name[tr]": "Todoist Bugün",
      "Description": "Your Todoist Today view on the Plasma desktop and panel (unofficial)",
      "Description[tr]": "Todoist Bugün görünümü Plasma masaüstü ve panelinde (resmi değil)",
      "Icon": "view-calendar-tasks",
      "Category": "Online Services",
      "License": "GPL-3.0-or-later",
      "Version": "1.0.0",
      "Authors": [{ "Name": "Bahadir Demircioglu" }],
      "Website": "https://github.com/bahadirdemircioglu/today",
      "BugReportUrl": "https://github.com/bahadirdemircioglu/today/issues",
      "FormFactors": ["desktop", "panel"]
    },
    "KPackageStructure": "Plasma/Applet",
    "X-Plasma-API-Minimum-Version": "6.0"
  }
  ```
  `X-Plasma-MainScript` / `X-Plasma-API` yazılmaz (Plasma 6'da kaldırıldı). `KPlugin.Id` yayından
  sonra **asla değişmez** (kurulum klasörü + config grubu + i18n domain'i ona bağlı).
- `main.qml` kökü `PlasmoidItem`. `compactRepresentation: CompactRepresentation {}`,
  `fullRepresentation: FullRepresentation {}`.
  - `preferredRepresentation`: `Plasmoid.formFactor === PlasmaCore.Types.Planar` (masaüstü) ise
    `fullRepresentation`, aksi halde (panel) `compactRepresentation`.
  - `switchWidth: Kirigami.Units.gridUnit * 8`, `switchHeight: Kirigami.Units.gridUnit * 6`:
    masaüstünde bundan küçükse Plasma kendiliğinden compact'a düşer.
  - `toolTipMainText`: "Todoist Today"; `toolTipSubText`: "3 tasks today · Next: Dentist 15:00" /
    "All done for today" / durum mesajı.
  - `Plasmoid.contextualActions`: `PlasmaCore.Action` × 2 — "Refresh now" (`view-refresh`),
    "Open Todoist" (`internet-services`, `Qt.openUrlExternally("https://app.todoist.com/app/today")`).
    "Configure…" Plasma'nın kendi eylemidir.
  - Arka plan: varsayılan `backgroundHints` (temanın yuvarlak köşeli çerçevesi) — yerli görünüm.
- `FullRepresentation` seçim kuralı (masaüstünde):
  - state `SETUP` → `SetupView` (alan çok darsa yalnızca "Connect to Todoist…" butonu →
    `Plasmoid.internalAction("configure").trigger()`).
  - state `LOADING` ve önbellek yok → `PlasmaComponents3.BusyIndicator` + "Loading your tasks…".
  - `width < 14 gu || height < 12 gu` → `SmallView`; aksi → `TaskListView`.
  - Popup (panelden açılınca): her zaman `TaskListView`; `Layout.preferredWidth: 22 gu`,
    `Layout.preferredHeight: 26 gu`, `Layout.minimumWidth: 16 gu`.
  - Eşikler gridUnit cinsinden → yazı tipi ölçeğini otomatik takip eder.

### T2. Görsel dil

- Renkler yalnızca `Kirigami.Theme` / `PlasmaCore` tema renkleri (sabit hex yok) → açık/koyu ve
  vurgu rengi otomatik. Aralıklar `Kirigami.Units.smallSpacing/largeSpacing`, köşeler
  `Kirigami.Units.cornerRadius` (yoksa `smallSpacing`).
- `CompactRepresentation`: `Kirigami.Icon { source: Plasmoid.icon }` + sağ altta rozet (sayı =
  overdue + today; overdue > 0 ise `Kirigami.Theme.negativeTextColor` zemin, değilse
  `highlightColor`). Rozet bileşeni: kendi `Rectangle { radius: height/2 }` — `BadgeOverlay`
  (`org.kde.plasma.workspace.components`) üçüncü parti plasmoid için kararlı API olmadığından
  kullanılmadı (A8). Sayı 0 → rozet yok. SETUP/AUTH_INVALID → küçük uyarı amblemi.
- `TaskRow`: `RoundCheck` (çember rengi önceliğe göre: p1 `negativeTextColor`, p2 `neutralTextColor`,
  p3 `linkColor`, p4 `disabledTextColor`; API'de `priority` 4 = p1) + başlık (tek satır, elide) +
  ikinci satırda soluk metin: saat (varsa) · proje adı (Inbox dışındaysa). Saati geçmiş bugünkü
  görevin saati `negativeTextColor`. Başlığa tıklama → `https://app.todoist.com/app/task/<id>`.
- Tamamlama animasyonu: çember dolar + `checkmark` ikonu ölçeklenir (≈`Kirigami.Units.shortDuration`),
  başlık üstü çizilir ve soluklaşır, ~2×`longDuration` sonra satır listeden çıkar
  (`ListView` `remove` solma + küçülme, `displaced` geçişleri; model `ModelSync.sync()` ile minimal
  işlemle güncellendiğinden yalnız değişen satır animasyon alır). Süreler `Kirigami.Units`'ten → sistem "animasyon hızı / animasyonları kapat"
  ayarına uyar.
- Boş durum: `Kirigami.PlaceholderMessage { icon.name: "checkmark"; text: i18n("All done for today");
  explanation: i18n("Enjoy the rest of your day ✨") }` — emoji yerine tercihen ikon; metin kesinleşmesi
  uygulamada.
- Liste başlığı: büyük "Today" + yerel uzun tarih (`Qt.formatDate(now, "dddd, d MMMM")`).
  Overdue bölümü yalnızca öğe varsa, küçük bölüm başlığıyla. Bölüm başlıkları `ListView.section`
  ile değil, bölümün ilk satırının içinde çizilir (`flattenRows` → `header` rolü): `section`
  delegate'leri add/remove/displaced geçişleriyle üst üste biniyordu (duman testinde görüldü).
- Saat biçimi: sistem yerel ayarı (`Qt.locale().timeFormat(Locale.ShortFormat)`) — platforma yerli;
  Todoist'in `time_format` alanı kullanılmaz.
- İçerik her zaman `textFormat: Text.PlainText`; markdown/link sözdizimi `TaskStore.plainTitle()`
  ile sadeleştirilir (bkz. Security).

### T3. JS mantık katmanı: QML'de `.pragma library`, Node'da test — somut çözüm

Sorun: `.pragma library` ve `.import "X.js" as X` satırları geçerli JavaScript değildir; Node'da
`module.exports` guard'ı tek başına yetmez (dosya parse bile edilemez).

Çözüm (üretim koduna **hiçbir** Node özgü satır eklenmez):
1. Mantık dosyaları QML'de olduğu gibi yazılır:
   ```js
   .pragma library
   .import "DateUtil.js" as DateUtil
   var SCHEMA_VERSION = 1;
   function computeToday(store, queue, nowMs, sysOffsetAt) { … DateUtil.dayKeyAt(…) … }
   ```
2. `tests/helpers/load-qml-js.mjs` → `loadQmlJs(relPath, { deps: { DateUtil: "DateUtil.js" }, globals: { XMLHttpRequest: Fake } })`:
   - Dosyayı okur; `^\s*\.(pragma|import)\b` ile başlayan satırları **boş satırla** değiştirir
     (satır numaraları korunur → stack trace doğru).
   - `deps` içindeki her kütüphaneyi aynı yöntemle önce yükler, adıyla sandbox'a koyar
     (`.import "DateUtil.js" as DateUtil` karşılığı).
   - `vm.createContext(sandbox)` + `vm.runInContext(src, ctx, { filename })`. Üst düzey
     `function` bildirimleri ve `var`'lar context global'ine düşer → test `ctx.computeToday(...)` çağırır.
3. Kodlama kuralları (lib dosyaları için, review'da kontrol edilir):
   - Dışa açık API = üst düzey `function` bildirimleri ve `var` sabitleri (üst düzey `let/const/class`
     context global'ine düşmez → API için kullanılmaz; fonksiyon içinde serbest).
   - QV4 uyumluluğu: ES2020 alt kümesi; `Intl`, `structuredClone`, `setTimeout`, `fetch`, `crypto`,
     `require`, top-level `await` yok. Tarih biçimlendirme JS'te değil QML katmanında (`Qt.formatTime`).
   - Saat/rastgelelik enjekte edilir (`nowMs`, `uuidFn` parametreleri) → testler deterministik.
   - `TaskStore`, `CommandQueue`, `DateUtil`, `SyncMachine` ağdan ve QML'den habersiz.
     `TodoistClient` yalnızca global `XMLHttpRequest` kullanır (Node'da sahte nesne sandbox'a verilir).
4. Test koşucusu: Node ≥ 20 yerleşik `node:test` + `node:assert/strict`; `npm test` =
   `node --test tests/*.test.mjs` (Node 22'de dizin argümanı modül olarak çözülmeye çalışıldığından
   glob kullanılır). Sıfır npm bağımlılığı.

### T4. HTTP katmanı (`TodoistClient.js`)

- Base: `https://api.todoist.com/api/v1`. Başlık `Authorization: Bearer <token>`.
- Fonksiyonlar (her biri XHR nesnesini döndürür → çağıran `abort()` edebilir; QML JS'te
  `setTimeout` olmadığından 15 sn zaman aşımı `SyncController`'daki `Timer` ile `abort()` edilir):
  - `sync(token, params, cb)` — `POST /sync`, `Content-Type: application/x-www-form-urlencoded`,
    gövde: `sync_token=<tok>&resource_types=<JSON>&commands=<JSON>` (commands boşsa alan gönderilmez).
  - `getUser(token, cb)` — `GET /user`.
  - `quickAdd(token, text, cb)` — `POST /tasks/quick`, `Content-Type: application/json`,
    gövde `{"text": "<text>", "meta": false}`.
- `cb(result)`; `result = { kind, status, json, retryAfterSec }` ve
  `classify(status, json, retryAfterHeader)` saf fonksiyonu:

  | Koşul | `kind` |
  |-------|--------|
  | 200–299 ve JSON parse edilebilir | `ok` |
  | `status === 0` (bağlantı yok, DNS, abort/timeout) | `network` |
  | 401, 403 | `auth` |
  | 429 | `rate` (`retryAfterSec` = `Retry-After` başlığı ‖ `error_extra.retry_after` ‖ 60) |
  | 500–599 | `server` (`retryAfterSec` varsa onu taşır) |
  | diğer 4xx | `client` |
  | 2xx ama JSON bozuk | `server` |

### T5. Sync tasarımı (Todoist API v1 — developer.todoist.com/api/v1 ile doğrulandı)

**Doğrulanmış API gerçekleri (kesin adlar):**
- `POST https://api.todoist.com/api/v1/sync`, form-urlencoded, yanıt JSON.
- İlk istek `sync_token=*` → tam veri + `full_sync: true` + yeni `sync_token`. Sonraki istekler
  son `sync_token` ile → yalnız değişenler (`full_sync: false`). Büyük hesaplarda tam sync gecikmeli
  olabilir (`full_sync_date_utc`); doküman tavsiyesine uygun olarak tam sync'ten hemen sonra bir
  artımlı sync daha yapılır.
- `resource_types` (JSON dizi): bizim kullandığımız `["items","projects","user","user_item_orders"]`.
- Yazma: `commands` JSON dizisi; her komut `{type, uuid, args}` (+ yaratma komutlarında `temp_id`).
  Aynı `uuid` ikinci kez **çalıştırılmaz** → güvenli yeniden deneme. En fazla **100 komut/istek**,
  gövde ≤ 1 MiB, istek zaman aşımı 15 sn (sunucu).
- Yanıt `sync_status`: `{ "<uuid>": "ok" | { error_tag, error_code, error, http_code, error_extra: { retry_after?, … } } }`;
  `temp_id_mapping`: `{ "<temp_id>": "<real_id>" }`.
- Tamamlama komutu: **`item_close`**, `args: { id }` — resmi istemcilerin yaptığını yapar: normal
  görev arşive gider, **tekrarlayan görev bir sonraki tekrarına** planlanır. (`item_complete`
  tekrarlayanları doğru işlemez; `item_update_date_complete` gereksiz.) → v1 yalnız `item_close` kullanır.
- Görev (item) alanları: `id` (string), `content`, `project_id`, `parent_id`, `priority` (1–4, 4=p1),
  `due` (null | obje), `child_order`, `day_order` (Today/Next7 sırası, **deprecated**),
  `checked` (bool), `is_deleted` (bool), `added_at`, `completed_at`, `labels`, `section_id`, `duration`.
- `due` objesi: `{ date, timezone, string, lang, is_recurring }`. **v1'de ayrı `datetime` alanı yok**;
  üç biçim `date` içinde:
  1. Tam gün: `"YYYY-MM-DD"`, `timezone: null`.
  2. Kayan (floating) saatli: `"YYYY-MM-DDTHH:MM:SS"` (opsiyonel `.ffffff`), `Z` yok, `timezone: null`
     → kullanıcının o anki saat diliminde duvar saati.
  3. Sabit dilimli: `"YYYY-MM-DDTHH:MM:SS(.ffffff)Z"` (UTC), `timezone: "Europe/Madrid"`.
- Sıra: `user_item_orders` dizisi, öğe `{ item_id, scope: "day", scope_id: 0, order_key, is_deleted }`
  (doküman: şu an yalnız `day` servis ediliyor; ileride başka scope'lar gelebileceği için yalnız
  `scope==="day" && scope_id===0` kayıtları işlenir);
  `order_key` sözlüksel (lexicographic) karşılaştırılır; `is_deleted: true` → `order_key: null`.
  `day_orders`/`day_order` deprecated ama "senkron kalıyor" → yedek olarak kullanılır.
- Kullanıcı: `user.id`, `full_name`, `email`, `tz_info: { timezone, gmt_string: "+03:00", is_dst, (hours, minutes) }`,
  `time_format`, `lang`, `inbox_project_id`. `GET /api/v1/user` aynı objeyi döndürür (token doğrulama).
- Quick Add: `POST /api/v1/tasks/quick` `{ text, note?, reminder?, auto_reminder?, meta? }` →
  oluşturulan görev. Sözdizimi: tarih doğal dil, `#Proje` (boşluk için `#My\ Project`), `/Bölüm`,
  `@etiket`, `p1..p4`, `{deadline}`, `// açıklama`. **Sync komutu değildir → `uuid` idempotency'si yok.**
- Limitler (kullanıcı başına, 15 dk): **1000 artımlı (partial) sync**, **100 tam sync**; 100 komut
  tek istek sayılır.
- Hatalar: 401/403 (token), 429 (rate; `Retry-After` / `error_extra.retry_after`), gövde
  `{ error_tag, error_code, error, http_code, error_extra }`.

**Sync tetikleyicileri (SyncController):**
| Tetik | Davranış |
|-------|----------|
| Başlangıç (token var) | Önbelleği yükle → hemen sync |
| Periyodik `Timer` 5 dk | sync (state `AUTH_INVALID`/`SETUP` değilse) |
| Panel: popup açıldı (`expanded` → `true`) | son sync > 30 sn önceyse sync |
| Masaüstü: fare widget'a girdi (`HoverHandler.hovered` → `true`, FullRepresentation kökünde) | son sync > 30 sn önceyse sync. (Masaüstünde güvenilir "görünür oldu" sinyali yok — `Plasmoid.status` görünürlük değildir; hover, etkileşim niyetinin en ucuz yerli göstergesi) |
| Token değişti (`Plasmoid.configuration.apiTokenChanged`, T9) | `TOKEN_SET` / `TOKEN_CLEARED` |
| Kullanıcı işlemi (tamamla/ekle) | 1 sn debounce → flush + sync (art arda tıklamalar tek istekte) |
| Gün dönümü (bkz. T7) | yeniden hesapla + sync |
| Context menü "Refresh now" | anında sync (backoff'u sıfırlar) |
| Backoff timer | yeniden dene |

Eşzamanlılık: aynı anda **tek** uçuşta istek (`inFlight`); uçuştayken gelen tetik `pendingResync = true`
olarak birleştirilir, bitince bir kez daha çalışır. İki sync arası en az 5 sn (coalesce). En kötü
senaryo bile (≈ 12/saat periyodik + etkileşim) limitin çok altında.

**Bir sync döngüsü (sıra önemli):**
1. Kuyrukta `quick_add` girdisi varsa önce onları FIFO sırayla **tek tek** `POST /tasks/quick` ile gönder (T6);
   döngü başına **en fazla 10**, kalan sonraki döngüye (1 sn sonra yeniden planlanır). Bir quick add
   yanıtı `rate`/`network`/`auth`/`server` ise quick add aşaması **o döngüde durur** ve sonuç doğrudan
   `SyncMachine`'e olay olarak verilir (429'da `Retry-After`'a uyulur; sync isteği o döngüde atlanır).
2. `CommandQueue.nextSyncBatch(queue)` → ≤ 100 `item_close` komutu.
3. Tek `POST /sync`: `sync_token` + `resource_types` + `commands` (varsa). (Komut + okuma aynı
   istekte — Sync API tasarımı; uygulama adım 6'da gerçek token ile doğrulanır, olmazsa iki istek.)
4. `ok` → `CommandQueue.applySyncStatus(...)`, `TaskStore.applySyncResponse(...)`,
   `CommandQueue.resolveUncertain(queue, store)`, kalıcı kaydet, view'ı yeniden hesapla.
   `full_sync` idiyse hemen bir artımlı sync daha planla.
5. Hata → `SyncMachine` olayı (T8); kuyruk **değişmez** (uuid sayesinde tekrar güvenli).
6. **Tüm istek `client` (4xx, 401/403/429 hariç) dönerse** — sebep geçersiz `sync_token` da, bozuk bir
   komut da olabilir; v1 dokümanı geçersiz token için ayrı bir `error_tag` belgelemediğinden etikete
   güvenilmez, izolasyon prosedürü uygulanır (`SyncMachine` `recovery` alt durumu):
   a. **Komutsuz** ve `sync_token="*"` ile tek bir tam sync (okuma) yapılır.
   b. (a) başarılıysa yeni token ile batch bir kez daha gönderilir. Yine tüm istek `client` dönerse
      sorun batch'tedir: batch'teki komutlar düşürülür (`dropped`, footer bilgisi + warn log) — kuyruk
      sonsuza dek takılı kalmaz.
   c. (a) da `client` dönerse → `ERROR` (backoff ile yeniden dener; kuyruk korunur).
   Bu yol `SyncMachine` testlerinde ayrı vakalarla kapsanır (Adım 5).

### T6. Çevrimdışı kuyruk semantiği (`CommandQueue.js`)

**Girdi tipleri (kalıcı, sürümlü JSON):**
```js
{ kind: "close", uuid, itemId, createdAt, attempts }                 // → item_close
{ kind: "quick_add", localId, text, createdAt, attempts,
  state: "pending" | "uncertain", sentAt: null | ms }                // → POST /tasks/quick
```

**İlkeler**
- **Optimistic UI = türetilmiş görünüm.** UI asla sunucu verisini mutasyona uğratmaz; Today listesi
  her zaman `TaskStore.computeToday(store, queue, now)` ile hesaplanır: kuyrukta `close` girdisi olan
  item gizlenir, `quick_add` girdileri listenin altında soluk "Waiting to sync" satırı olarak görünür.
  Kuyruk kalıcı olduğundan yeniden başlatmadan sonra optimistic durum da aynen geri gelir.
  **Geri alma (revert) otomatik:** bir komut düşürülünce (drop) overlay kalkar; item hâlâ sunucuda
  açıksa listede yeniden belirir.
- `enqueueClose` aynı item için ikinci kez çağrılırsa no-op (çift tık).
- Bekleyen `quick_add` satırının onay kutusu devre dışı (gerçek id yok). Bu yüzden **v1'de `temp_id`
  ve `temp_id_mapping` kullanılmaz** (yaratma REST Quick Add ile yapılır). `applySyncResponse`
  `temp_id_mapping`'i yok sayar; ileride `item_add` eklenirse kuyrukta `temp_id → real id` yeniden
  yazımı bu modüle eklenecek (Open Questions değil, bilinçli erteleme — Decision Log D7).

**`sync_status` işleme (`applySyncStatus(queue, sentUuids, syncStatus)` → `{ queue, dropped }`):**
| Durum | Eylem |
|-------|-------|
| `"ok"` | girdiyi sil |
| hata, `http_code` 429 veya ≥ 500, ya da `error_extra.retry_after` var | tut, `attempts++`, controller backoff uygular |
| hata, diğer (ör. 404 item yok / telefonda silinmiş, 400 geçersiz argüman) | **düşür** (`dropped`'a ekle) → overlay kalkar; kullanıcıya `StatusFooter`'da kısa bilgi ("Couldn't complete "X" — it may have been deleted") |
| gönderildi ama `sync_status`'ta yok | tut (tekrar gönderilecek; uuid idempotent) |
| `attempts ≥ 20` (sadece geçici hatalarla) | düşür + bilgi (zehirli komut koruması) |

Tüm istek başarısızsa (`network/auth/rate/server`) kuyruk aynen kalır; `attempts` artmaz
(sayaç yalnızca komut bazlı geçici hatalar için).

**Quick Add (idempotent değil) — çift kayıt riskini yönetme:**
| Sonuç (`markQuickAddResult`) | Eylem |
|------------------------------|-------|
| `ok` (2xx) | sil; hemen sync (görev listeye gerçek haliyle gelir). Dönen görev bugünün değilse footer'da "Added to Inbox · Tomorrow" benzeri 4 sn bilgi (proje adı/due `string`'ten) |
| `client` (400 vb.) | düşür + bilgi |
| `auth` / `rate` / `server` (yanıt alındı, işlenmedi) | `pending` kalır, tekrar denenir |
| `network` **ve istek gönderilmiş** (`sentAt` set) | `uncertain` yap (sunucu işlemiş olabilir) |

`resolveUncertain(queue, store)`: her başarılı sync'ten sonra, `uncertain` girdi için store'da
`added_at ∈ [sentAt − 120 sn, sentAt + 600 sn]` olan ve `normWords(plainTitle(content))` kümesi boş
olmayan ve `normWords(text)` kümesinin alt kümesi olan bir item varsa (birden fazla aday varsa en
yakın `added_at`) girdi **tamamlanmış** sayılıp silinir. `normWords`: `toLowerCase()` (QV4'te Unicode
farkındalı; Türkçe `İ/I` için ek olarak `İ→i`, `I→ı` eşlemesi uygulanmaz, iki taraf da aynı fonksiyondan
geçtiği için tutarlıdır), noktalama silme, boşlukla bölme; Quick Add sözdizimi token'ları çıkarılır:
`#…`, `@…`, `/…`, `+…`, `p1`–`p4`, `!!1`–`!!4`, `!…` (hatırlatıcı), `{…}`, `//`'den sonrası. Tarih kelimeleri
çıkarılmaz (dil bağımsız ayrıştırma yok) — alt küme kuralı bunları zaten tolere eder; yoksa `pending`'e döner ve
yeniden gönderilir. Kalan risk (eşleşme kaçarsa ender çift görev) README'de belirtilir.
Yeniden deneme sırası: kuyruk sırası (FIFO).

**Kalıcılık:** her kuyruk mutasyonundan hemen sonra `Storage.saveQueue()` (senkron LocalStorage
transaction). `deserialize` bozuk/uyumsuz sürümde boş kuyruk döner ve uyarı loglar (çökme yok).

**Hesap değişimi:** token her değiştiğinde ilk istek komutsuz `GET /user`'dır (T8 `verifyAccount`); `user.id`
önbellektekinden farklıysa store + kuyruk **komut gönderilmeden** silinir; aynı kullanıcı (token yenileme)
ise kuyruk korunur ve flush edilir. Başlangıçta (`INIT`) config'teki token önbelleğin hesabına aittir
(önbellek o token'la oluşturuldu) → doğrulama gerekmez.

### T7. "Today" kuralları, saat dilimi ve gün dönümü (`DateUtil.js` + `TaskStore.computeToday`)

**Saat dilimi kararı:** Referans = **Todoist kullanıcı saat dilimi** (telefonla aynı Today'i
göstermek için). QV4'te `Intl`/IANA tz veritabanı olmadığından:
- `tz_info` → dakika ofseti (`tzInfoOffset`): sayısal `hours`/`minutes` varsa onlar (sync user objesi örneğinde var),
  yoksa `gmt_string` (`parseGmtOffset`; v1 örnekleri `"+01:00"`, `"-03:00"` biçiminde, savunma amaçlı
  `GMT`/`UTC` öneki ve `+0300`/`+3` biçimleri de kabul edilir). Gerçek değer Adım 6 curl doğrulamasında kontrol edilir.
- Sync anında Todoist ofseti == sistem ofseti (`-new Date().getTimezoneOffset()`) ise
  `tz.followSystem = true` → sonrasında ofset **her an için ayrı** sistemden alınır:
  `offsetAt(ms) = -new Date(ms).getTimezoneOffset()` (QV4 `Date` sistem tz kurallarını bilir, `Intl` gerekmez).
  Böylece hem "şimdi" (DST geçişleri) hem de **farklı DST dönemindeki sabit dilimli (`…Z`) görevler** doğru
  yerel güne/saate dönüşür.
- Farklıysa (ör. dizüstü başka dilimde) sabit Todoist ofseti kullanılır (`offsetAt(ms)` = sabit); `user` her
  sync'te istenir, Todoist DST ile `tz_info`'yu değiştirince artımlı yanıtta gelir. **Bilinen sınırlar
  (yalnız sistem dilimi ≠ Todoist dilimi iken):** (1) DST geçişinde ≤ 5 dk sapma; (2) şu anki DST
  döneminden farklı dönemdeki sabit dilimli görev 1 saat kayabilir → gece yarısına ±1 saat yakınsa yanlış
  güne düşebilir. Ender senaryo (farklı dilimde makine + sabit dilimli görev + gece yarısı yakını);
  gömülü DST tablosu bakım yükü nedeniyle eklenmez. README "Known limitations"da yazılır (A6).
- `user` hiç gelmemişse (ilk tam sync'ten önce) sistem ofseti.

**Due → (gün anahtarı, dakika) dönüşümü (`parseDue(due, offsetAt)` → `{ dateKey, minutes|null, isRecurring }`):**
- `"YYYY-MM-DD"` → `{dateKey, minutes: null}`.
- Kayan `"YYYY-MM-DDTHH:MM:SS[.ffffff]"` → duvar saati olduğu gibi.
- Sabit `"…Z"` → UTC ms + `offsetAt(utcMs)` → kullanıcı diliminde gün/saat (Todoist da kullanıcı diliminde gösterir).
- `due === null` veya ayrıştırılamaz → item Today'e girmez (ayrıştırılamaz ise uyarı log).

**Sınıflama** (`todayKey = dayKeyAt(nowMs, offsetAt)`):
- **Overdue:** `dateKey < todayKey` (sözlüksel = kronolojik).
- **Today:** `dateKey == todayKey`. Bugünün saati geçmiş saatli görev Today'de kalır, `isLate: true`
  (saat kırmızı) — Todoist davranışı; Overdue'ya taşınmaz.
- Gelecek → gizli (store'da tutulur, gün dönünce görünür).

**Sıralama** (her grup içinde, kararlı):
1. Overdue grubu önce `dateKey` artan (en eski üstte).
2. Aynı gün içinde: **saatli olanlar önce, `minutes` artan**; sonra saatsizler.
3. Saatsizler (ve eşit saatliler) için: `user_item_orders` `order_key` (sözlüksel artan, olmayan sona)
   → `day_order` artan (`-1`/yok sona) → `priority` azalan (4=p1 üstte) → `child_order` artan → `id`.
Kabul testinde telefondaki Today ile karşılaştırılır (Assumptions A5).

**Store budama:** `checked`, `is_deleted` veya `due === null` olan item'lar store'dan silinir (Today'e
giremezler; due eklenirse artımlı sync tam objeyi getirir). Böylece önbellek küçük kalır ama yarın
vadeli görevler gece yarısı ağsız da görünür.

**Gün dönümü:** `SyncController`'da 60 sn'lik `Timer` `todayKey`'i (ve "isLate" durumlarını) yeniden
hesaplar; anahtar değiştiyse view yeniden hesaplanır + sync tetiklenir. Uyku/uyanma sonrası Timer'ın
gecikmesi de böylece en geç 60 sn'de yakalanır (gece yarısına tam zamanlı tek Timer'a güvenilmez).

**Küçük görünüm "sıradaki görev":** bugünün saati gelmemiş ilk saatli görevi; yoksa birleşik listenin
ilk öğesi (overdue dahil). Sayı = overdue + today (bekleyen quick add'ler hariç).

### T8. Durum makinesi (`SyncMachine.js` — saf reducer)

Durumlar: `SETUP`, `LOADING`, `READY`, `OFFLINE`, `ERROR`, `AUTH_INVALID`. Ayrıca bayraklar:
`syncing` (uçuşta istek; footer'da ince gösterge), `hasCache`, `backoffStep`.

| Mevcut | Olay | Yeni | Effect |
|--------|------|------|--------|
| * | `TOKEN_CLEARED` | `SETUP` | timer'ları durdur, store+kuyruk sil |
| herhangi | `TOKEN_SET` (yeni/değişmiş token; SetupView veya ayarlar penceresi) | `hasCache ? READY : LOADING`, `accountVerified:false` | uçuştaki isteği iptal et, `verifyAccount` (komutsuz `GET /user`) — doğrulanana kadar **hiçbir kuyruk komutu gönderilmez** |
| (doğrulama bekleniyor) | `ACCOUNT_VERIFIED{userId}` | aynı `userId` → kuyruk korunur; farklı → `clearData` (store+kuyruk) | `accountVerified:true`, `syncNow` |
| (doğrulama bekleniyor) | `verifyAccount` sonucu `auth` / `network` | `AUTH_INVALID` / `OFFLINE` | `network`'te backoff ile yeniden **doğrulama** (sync değil) |
| (başlangıç) | `INIT{token, hasCache}` | token yok → `SETUP`; cache var → `READY`; yok → `LOADING` | token varsa `syncNow` |
| `LOADING`/`READY`/`OFFLINE`/`ERROR` | `SYNC_OK` | `READY` | backoff sıfırla, periyodik 5 dk |
| `LOADING`/`READY`/`OFFLINE`/`ERROR` | `NET_FAIL` | `OFFLINE` | `retryIn(backoff)` |
| `LOADING`/`READY`/`OFFLINE`/`ERROR` | `HTTP_SERVER` / `HTTP_CLIENT` | `ERROR` | `retryIn(retryAfter ‖ backoff)` |
| `LOADING`/`READY`/`OFFLINE`/`ERROR` | `HTTP_RATE{retryAfter}` | durum korunur (READY ise READY, footer "Rate limited") | `retryIn(max(retryAfter, 30 s))` |
| herhangi (token'lı) | `HTTP_AUTH` | `AUTH_INVALID` | tüm sync timer'larını durdur; kuyruk korunur |
| `AUTH_INVALID` | `SYNC_REQUESTED` | `AUTH_INVALID` | yok (token değişene kadar istek yok) |

Backoff: 30 s → 60 s → 120 s → 300 s (tavan), ±%20 jitter (`randomFn` enjekte). Popup açılması veya
"Refresh now" `OFFLINE/ERROR`'da backoff'u beklemeden bir deneme yapar.

**UI eşlemesi:**
| Durum | Panel rozeti | Liste / görünüm |
|-------|--------------|-----------------|
| `SETUP` | uyarı amblemi | `SetupView` |
| `LOADING` | yok | BusyIndicator |
| `READY` | sayı | liste; footer "Updated N min ago" (yalnız > 10 dk ise göster; az öğe ilkesi) |
| `OFFLINE` | sayı (önbellek) | liste + footer "Offline — showing saved tasks" + kuyruktaki işlem sayısı; önbellek yoksa PlaceholderMessage "Can't reach Todoist" + "Try again" |
| `ERROR` | sayı | liste + footer "Todoist is having trouble. Retrying…" |
| `AUTH_INVALID` | uyarı amblemi | liste (önbellek) + `Kirigami.InlineMessage` (warning) "Todoist didn't accept your token" + "Reconnect" → kurulum |

İşlemler (tamamla/ekle) `OFFLINE/ERROR/AUTH_INVALID`'de de kabul edilir ve kuyruğa girer.

### T9. Kurulum akışı (`SetupView.qml` / `ConfigAccount.qml`)

1. Başlık "Connect to Todoist" + tek cümle açıklama + buton "Open Todoist settings"
   (`Qt.openUrlExternally("https://app.todoist.com/app/settings/integrations/developer")`).
2. `TextField` "Paste your API token" (`echoMode: Password`, göster/gizle düğmesi). Metin değişince
   boşluklar kırpılır; uzunluk ≥ 32 ise 400 ms debounce ile veya Enter ile doğrulama başlar.
3. `TodoistClient.getUser`: `ok` → "Connected as **Full Name** (email)" + `checkmark`;
   `Plasmoid.configuration.apiToken`/`accountName` yazılır → `TOKEN_SET`. `auth` → "This token didn't
   work. Copy it again from Todoist settings." `network` → "Can't reach Todoist. Check your connection."
   Diğer → "Something went wrong (HTTP n)".
4. `ConfigAccount.qml` (`KCM.SimpleKCM` + `Kirigami.FormLayout` + QQC2 — doküman: config sayfasında
   PlasmaComponents kullanılmaz): `cfg_apiToken`, `cfg_accountName`; bağlıyken "Connected as …" +
   "Disconnect" (token'ı boşaltır). Aynı doğrulama mantığı `TodoistClient.getUser` üzerinden; UI
   tekrarı küçük ve kabul edilir (Plasma bileşen seti farkı).
5. **Tek doğruluk kaynağı = `Plasmoid.configuration.apiToken`.** Her iki yol da yalnızca bu değeri yazar;
   `main.qml`'de `Connections { target: Plasmoid.configuration; function onApiTokenChanged() {…} }`
   değişikliği yakalar → boşsa `TOKEN_CLEARED`, doluysa ve öncekinden farklıysa `TOKEN_SET`.
   SetupView doğrulamayı yazmadan önce yapar; ayarlar penceresinde kullanıcı doğrulanmamış token'ı
   Apply edebilir → `TOKEN_SET` sonrası ilk istek 401 dönerse `AUTH_INVALID` (banner). Böylece iki yol
   aynı olay akışına iner (M22).
6. README + ayar sayfasında tek satır: "Your token is stored unencrypted in your Plasma config file."

### T10. i18n

- Kaynak dil İngilizce; `i18n()`, `i18nc()`, `i18np()` (sayılar: "%1 task"/"%1 tasks").
- Plasma 6, `KPlugin.Id`'den domain'i otomatik türetir: `plasma_applet_<Id>`. `.mo` dosyaları paket içinde
  `contents/locale/<lang>/LC_MESSAGES/plasma_applet_<Id>.mo` (KDE Store kurulumunda da çalışır).
- `scripts/i18n-extract.sh`: Id'yi `metadata.json`'dan `node -e`/`jq` ile okur (KDE örnek script'lerindeki
  `kreadconfig5` + `metadata.desktop` Plasma 6'da geçersiz), `xgettext -C --from-code=UTF-8 -kde -ci18n
  -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3` ile `.qml`/`.js` → `translations/template.pot`,
  `msgmerge` ile `tr.po` günceller.
- `scripts/i18n-build.sh`: `msgfmt` → `package/contents/locale/...` (gitignore'da).
- `metadata.json` `Name[tr]`/`Description[tr]` ile mağaza/widget listesi Türkçe.
- Test: `LANGUAGE="tr" LANG="tr_TR.UTF-8" plasmoidviewer -a package`.

### T11. Paketleme ve yayın

- Geliştirme: `plasmoidviewer -a package` (masaüstü: `-l floating -f planar`; panel:
  `-l bottomedge -f horizontal`). Kurulum: `kpackagetool6 -t Plasma/Applet -i package` /
  güncelleme `-u package`; plasmashell önbelleği için gerekirse `systemctl --user restart plasma-plasmashell`.
- `.plasmoid` = `package/` **içeriğinin** zip'i (`metadata.json` zip kökünde). `scripts/package.sh`:
  i18n-build → `cd package && zip -r ../dist/todoist-today-<Version>.plasmoid . -x '*.swp'`.
  Kurulum: `kpackagetool6 -t Plasma/Applet -i todoist-today-1.0.0.plasmoid` veya Plasma "Get New
  Widgets → Install from local file".
- `ci.yml` (ubuntu-latest, push + PR): `actions/setup-node` (Node 22) → `npm test`;
  `node -e` ile `metadata.json` parse + zorunlu alanlar (`KPlugin.Id`, `Version`,
  `X-Plasma-API-Minimum-Version`); `xmllint --noout package/contents/config/main.xml`;
  `apt-get install gettext` + `scripts/i18n-build.sh` smoke. (`qmllint` CI'de Plasma import'larını
  çözemediğinden yok — QML doğrulaması manuel kabul listesinde.)
- `release.yml` (`v*` etiketi): etiket == `metadata.json` `KPlugin.Version` kontrolü (değilse fail) →
  test → `scripts/package.sh` → `softprops/action-gh-release` ile `.plasmoid` ekli GitHub Release;
  gövde = CHANGELOG'daki ilgili bölüm.
- KDE Store (store.kde.org, "Plasma 6 Widgets" kategorisi): ilk yükleme manuel (kullanıcı hesabıyla);
  sonraki sürümlerde release'teki `.plasmoid` yüklenir. Açıklamada "Unofficial; not affiliated with
  Doist" ifadesi; Todoist logosu kullanılmaz, ikon KDE `view-calendar-tasks`.
- Sürümleme: SemVer; CHANGELOG Keep a Changelog biçimi.

## Data Storage Decisions

Sunucu yok; PostgreSQL (§2 varsayılanı) uygulanamaz — tamamen istemci tarafı, derlemesiz plasmoid.

| Veri | Depo | Gerekçe |
|------|------|---------|
| `apiToken`, `accountName` | `Plasmoid.configuration` (KConfig, `main.xml`) → `~/.config/plasma-org.kde.plasma.desktop-appletsrc`, düz metin | Plasma'nın standart ayar mekanizması; ayar penceresiyle uyumlu; onaylı tradeoff |
| Görev önbelleği + sync_token + tz + kuyruk | `QtQuick.LocalStorage` (SQLite, `~/.local/share/plasmashell/QML/OfflineStorage/Databases/`) | Saf QML'de mevcut, transactional, yeniden başlatmaya dayanıklı; büyük JSON'u appletsrc'ye (her yazmada tüm dosyayı yeniden yazan INI) koymaktan kaçınır |

Anahtar `Plasmoid.id` (applet örneği) bazlı → panel ve masaüstündeki iki örnek birbirinin kuyruğunu
bozmaz. Widget kaldırılınca satırlar kalır (birkaç KB; Plasma'da kaldırma kancası yok) — kabul edilir.

## Database Schema

LocalStorage veritabanı `TodoistToday`, sürüm `"1"`:

```sql
CREATE TABLE IF NOT EXISTS kv (
  applet_id TEXT NOT NULL,      -- String(Plasmoid.id)
  key       TEXT NOT NULL,      -- 'store' | 'queue'
  value     TEXT NOT NULL,      -- JSON (TaskStore.serialize / CommandQueue.serialize)
  updated_at INTEGER NOT NULL,  -- ms
  PRIMARY KEY (applet_id, key)
);
```

`store` JSON (v1):
```js
{ v: 1, accountId, accountName, syncToken, lastSyncAt,
  tz: { gmtOffsetMin, followSystem, timezone },
  inboxProjectId,
  items:    { "<id>": { id, content, projectId, parentId, priority, due: {date, timezone, isRecurring, string} , dayOrder, childOrder, addedAt } },
  projects: { "<id>": { name, color } },
  orderKeys:{ "<itemId>": "<order_key>" } }
```
`queue` JSON: `{ v: 1, entries: [ …T6 girdileri… ] }`. Sürüm uyuşmazlığı → ilgili anahtar sıfırlanır
(store için tam sync, kuyruk için uyarı log).

## API Contract

Widget API sunmaz; **tükettiği** Todoist v1 uçları:

| Method | Path | İstek | Kullanılan yanıt alanları |
|--------|------|-------|---------------------------|
| POST | `/api/v1/sync` | form: `sync_token`, `resource_types=["items","projects","user","user_item_orders"]`, `commands=[{type:"item_close",uuid,args:{id}}…]` | `sync_token`, `full_sync`, `items[]`, `projects[]` (`id,name,color,is_deleted,is_archived`), `user`, `user_item_orders[]`, `sync_status` |
| GET | `/api/v1/user` | — | `id`, `full_name`, `email`, `tz_info`, `inbox_project_id` |
| POST | `/api/v1/tasks/quick` | JSON `{text, meta:false}` | `id`, `content`, `due`, `project_id` (bilgi mesajı için) |

## Docker Services & Ports

N/A — sunucu, konteyner veya port yok (ports.md §1 uygulanmaz).

## Security Considerations

- **Token:** düz metin appletsrc'de (onaylı tradeoff, README "Security" bölümü: kim okuyabilir,
  nasıl iptal edilir — Todoist ayarlarından token yenileme). Token **asla loglanmaz**, hata
  mesajlarına/tooltip'e girmez; ayar sayfasında maskelenir.
- **Taşıma:** yalnız `https://api.todoist.com`; URL'ler sabit, kullanıcı girdisiyle URL kurulmaz
  (görev linki yalnız sunucudan gelen `id` ile; `id` `^[A-Za-z0-9]+$` kontrolünden geçer).
- **Render güvenliği:** görev içeriği uzak/kullanıcı verisi → `Text.PlainText`; QML `Text`'in
  `StyledText` yorumlaması kapalı (HTML/`<img>` enjeksiyonu yok). Markdown linkleri `[a](url)` → `a`.
- **Girdi:** Quick Add metni kırpılır, boşsa gönderilmez, 1000 karakter üstü reddedilir (UI'da sayaç yok, hata mesajı).
- **Rate limit:** tek uçuş + coalesce + backoff + `Retry-After`'a uyum (T5, T8).
- **Bağımlılık yüzeyi:** sıfır npm runtime bağımlılığı; CI action'ları sürüm etiketiyle sabitlenir.
- OAuth/CORS/CSRF: N/A (masaüstü istemci, kişisel token).

## Monitoring & Logging

- `console.log/warn` → plasmashell journal (`journalctl --user -f -t plasmashell` / plasmoidviewer
  stdout). Önek `[todoist-today]`.
- Loglananlar: state geçişleri (`READY → OFFLINE`), istek sonucu `kind` + HTTP status + süre,
  düşürülen komutlar (`error_tag`, item id — içerik değil), kuyruk uzunluğu, `full_sync` olayı,
  ayrıştırılamayan due. **Loglanmayanlar:** token, görev içerikleri, e-posta.
- Kullanıcıya görünen tek "izleme": footer'daki son güncelleme zamanı / offline / bekleyen işlem sayısı.

## Migration Plan

Yeni proje; uygulama sırası küçük, test edilebilir adımlar. Executor rolleri delegation.md'ye göre
(`engineer` = Sonnet, `mechanic` = Haiku, `opus`). Her kod adımı = sözleşme-spec (dosya, sözleşme,
kabul vakaları, YAPMA). Mantık adımlarında önce kabul vakaları test olarak yazılır.

**Ön koşul (karşılandı):** Q1 ve Q2 kapatıldı — `KPlugin.Id` = `io.github.bahadirdemircioglu.todoisttoday`,
repo `github.com/bahadirdemircioglu/today`. Id yayından sonra değişemez; i18n domain'i
`plasma_applet_io.github.bahadirdemircioglu.todoisttoday`.

**Adım 0 — İskele (mechanic + manuel doğrulama)**
`LICENSE` (GPL-3.0 tam metin), `.gitignore` (`dist/`, `package/contents/locale/`, `node_modules/`),
`package.json` (`"test": "node --test tests/"`, `"engines": {"node": ">=20"}`), `metadata.json` (T1),
`config/main.xml` (`apiToken` String "", `accountName` String ""), minimal `main.qml`
(`PlasmoidItem` + "Hello"). Kabul: `plasmoidviewer -a package` hatasız açılır. (git init kullanıcı onayıyla.)

**Adım 1 — Test altyapısı (engineer)** — `tests/helpers/load-qml-js.mjs`
| # | Girdi | Beklenen |
|---|-------|----------|
| 1 | `.pragma library` + `function f(){return 1}` içeren fixture | `ctx.f() === 1` |
| 2 | `.import "Dep.js" as Dep` + `deps:{Dep:"Dep.js"}` | `Dep.g()` çağrısı çalışır |
| 3 | Fixture'da 5. satırda hata | stack trace satır 5'i gösterir |
| 4 | `globals:{XMLHttpRequest: Fake}` | lib içinden `new XMLHttpRequest()` Fake döner |

**Adım 2 — `DateUtil.js` (engineer)** — `parseGmtOffset(str)`, `tzInfoOffset(tzInfo)`, `makeOffsetFn(tz, sysOffsetAtFn)`,
`dayKeyAt(nowMs, offsetAt)`, `parseDue(due, offsetAt)` — `offsetAt: (ms) → dakika` fonksiyonu enjekte edilir
(`makeOffsetFn(tz, sysOffsetAtFn)`; testte sahte DST'li fonksiyon).
| # | Girdi | Beklenen |
|---|-------|----------|
| 1 | `parseGmtOffset("+03:00")` / `"-03:30"` / `"garbage"` | `180` / `-210` / `null` |
| 1b | `"GMT+03:00"` / `"UTC-03:30"` / `"+0300"` / `"+3"` | `180` / `-210` / `180` / `180` (önek ve iki nokta toleransı) |
| 1c | `tzInfoOffset({hours:-3, minutes:0, gmt_string:"x"})` | `-180` (sayısal `hours/minutes` varsa önce onlar; yoksa `gmt_string`) |
| 2 | `dayKeyAt(Date.UTC(2026,9,3,21,30), 180)` | `"2026-10-04"` |
| 3 | `parseDue({date:"2026-10-03"})` | `{dateKey:"2026-10-03", minutes:null}` |
| 4 | `parseDue({date:"2026-10-03T15:00:00"})` (floating) | `{dateKey:"2026-10-03", minutes:900}` |
| 5 | `parseDue({date:"2026-10-03T15:00:00.000000"})` | aynı (#4) |
| 6 | `parseDue({date:"2026-10-03T22:30:00.000000Z", timezone:"Europe/Madrid"}, sabit 180)` | `{dateKey:"2026-10-04", minutes:90}` |
| 6b | `followSystem:true`, sahte `sysOffsetAt` (Ekim'de 180, Ocak'ta 120); due `"2027-01-10T22:30:00Z"` | `{dateKey:"2027-01-11", minutes:30}` (görev tarihindeki ofset kullanılır) |
| 7 | `parseDue(null)` / `{date:"x"}` | `null` |
| 8 | `makeOffsetFn({gmtOffsetMin:180, followSystem:true}, ()=>120)(t)` / `followSystem:false` / `tz=null` | `120` / `180` / `120` |
| 9 | `is_recurring:true` | `isRecurring:true` taşınır |

**Adım 3 — `TaskStore.js` (engineer)** — `emptyStore()`, `applySyncResponse(store, resp)`,
`computeToday(store, queue, nowMs, sysOffsetAt)` → `{overdue, today, pending, counts, next, todayKey}`,
`plainTitle(content)`, `serialize/deserialize`. Fixture'lar `tests/fixtures/` (gerçek v1 şekli).
| # | Girdi | Beklenen |
|---|-------|----------|
| 1 | `full_sync:true` yanıt, 3 item (biri `due:null`) | store'da 2 item; `syncToken` güncel |
| 2 | Artımlı: mevcut item `checked:true` | store'dan silinir |
| 3 | Artımlı: `is_deleted:true` | silinir |
| 4 | Artımlı: yeni item due bugün | eklenir, Today'de görünür |
| 5 | Artımlı: due'su yarına taşınmış item | Today'den çıkar, store'da kalır |
| 6 | `full_sync:true` sonrası, eski store'da olup yanıtta olmayan item | silinir (tam değiştirme) |
| 7 | `user` alanı (`tz_info.gmt_string:"+03:00"`, sistem 180) | `tz.followSystem:true` |
| 8 | `user_item_orders` `is_deleted:true` | `orderKeys`'ten silinir |
| 8b | `user_item_orders` içinde `scope:"project"` (veya `scope_id ≠ 0`) kaydı | yok sayılır; yalnız `scope==="day" && scope_id===0` işlenir (ekleme ve silme) |
| 9 | Sıralama: dün(saatsiz), bugün 09:00, bugün saatsiz(order "a2"), bugün saatsiz(order "a1"), bugün 08:00 | overdue:[dün]; today:[08:00, 09:00, a1, a2] |
| 10 | Order key yok, `day_order` 2 vs 1, sonra priority 4 vs 1 | day_order artan; eşitse p4 önce |
| 11 | Bugün 10:00 görevi, now 11:00 | `today`'de, `isLate:true` |
| 12 | Kuyrukta `close` item X | X listede yok; counts X'i saymaz |
| 13 | Kuyrukta `quick_add` "Buy milk" | `pending:[{localId, text:"Buy milk"}]`, counts'a dahil değil |
| 14 | `next`: now 12:00; today [10:00 late, 15:00, saatsiz] | 15:00 görevi |
| 15 | `plainTitle("Call **Ann** [docs](https://x)")` | `"Call Ann docs"` |
| 16 | `deserialize("bozuk")` / farklı `v` | `emptyStore()` |
| 17 | Proje `is_archived`/`is_deleted` | projects'ten silinir; item'ın `projectName` boş |

**Adım 4 — `CommandQueue.js` (engineer)** — `emptyQueue()`, `enqueueClose(q, itemId, nowMs, uuidFn)`,
`enqueueQuickAdd(q, text, nowMs, uuidFn)` → `{queue, error}`, `nextSyncBatch(q, max=100)`,
`applySyncStatus(q, sentUuids, syncStatus)` → `{queue, dropped}`, `nextQuickAdd(q)`,
`markQuickAddSent(q, localId, nowMs)`, `markQuickAddResult(q, localId, kind)`,
`resolveUncertain(q, store)`, `serialize/deserialize`, `uuid4(randomFn)`.
| # | Girdi | Beklenen |
|---|-------|----------|
| 1 | `enqueueClose` aynı item iki kez | tek girdi |
| 2 | 150 close girdisi → `nextSyncBatch` | 100 komut, `{type:"item_close", uuid, args:{id}}` şeklinde |
| 3 | `sync_status` `{u1:"ok"}` | u1 silinir |
| 4 | `{u1:{http_code:404,error_tag:"ITEM_NOT_FOUND"}}` | silinir, `dropped` 1 |
| 5 | `{u1:{http_code:429, error_extra:{retry_after:30}}}` / `http_code:503` | kalır, `attempts:1` |
| 6 | u1 gönderildi, `sync_status`'ta yok | kalır, attempts değişmez |
| 7 | attempts 19 + geçici hata | düşer, `dropped` |
| 8 | `enqueueQuickAdd("   ")` / 1001 karakter | queue değişmez, `error:"empty"`/`"too_long"` |
| 9 | quick add `markQuickAddResult(..., "ok")` / `"client"` / `"server"` / `"network"`(sentAt var) | sil / sil+drop / pending / uncertain |
| 10 | `resolveUncertain`: store'da `content:"dişçi"`, `added_at` sentAt+3 s; girdi text "yarın 15:00 dişçi #Kişisel" | girdi silinir |
| 11 | `resolveUncertain`: eşleşme yok | girdi `pending`'e döner |
| 12 | `serialize`→`deserialize` | eşit; bozuk JSON → boş kuyruk |
| 13 | `uuid4(sabit random)` | RFC 4122 v4 biçimi (`xxxxxxxx-xxxx-4xxx-[89ab]xxx-…`) |

**Adım 5 — `SyncMachine.js` (opus yazar, engineer review)** — Eşzamanlılık **kararlarının tamamı**
burada, saf ve Node'da test edilir; `SyncController.qml` yalnızca effect yürüten ince sarmalayıcıdır.
State: `{ phase (T8 durumları), inFlight, pendingResync, lastSyncAt, backoffStep, recovery, debounceUntil }`.
`reduce(state, event)` → `{ state, effects }`; olaylar zaman damgalı (`event.now`):
`INIT`, `TOKEN_SET`, `TOKEN_CLEARED`, `SYNC_REQUESTED{reason: periodic|expanded|hover|action|dayChanged|manual|retry}`,
`DEBOUNCE_FIRED`, `REQUEST_DONE{kind, retryAfterSec, hadCommands}`, `QUICK_ADD_DONE{kind}`,
`ACCOUNT_VERIFIED{userId}`, `VERIFY_FAILED{kind}`;
effect'ler: `startRequest`, `startDebounce{ms}`, `retryIn{ms}`, `startPeriodic`, `stopTimers`, `clearData`,
`dropBatch`, `scheduleFollowUp{ms}`, `verifyAccount`. `backoffMs(step, randomFn)`.
| # | Durum / olay | Beklenen |
|---|--------------|----------|
| 1 | T8 tablosunun her satırı | tablodaki yeni durum + effect |
| 2 | `inFlight` iken `SYNC_REQUESTED` | `startRequest` yok, `pendingResync:true`; `REQUEST_DONE` sonrası tek `startRequest` |
| 3 | `action` 3 kez 300 ms arayla | tek `startDebounce`; `DEBOUNCE_FIRED` → tek `startRequest` |
| 4 | `expanded`/`hover`, `lastSyncAt` 10 sn önce | effect yok; 40 sn önce → `startRequest` |
| 5 | `manual` / `expanded` `OFFLINE`'da backoff beklerken | backoff'u beklemeden `startRequest` |
| 6 | İki istek arası < 5 sn | `scheduleFollowUp` ile 5 sn'ye ertelenir |
| 7 | `REQUEST_DONE{client, hadCommands:true}` | `recovery:"readOnlyFull"`, komutsuz tam sync isteği |
| 8 | recovery okuma ok → batch yine `client` | `dropBatch` + `READY` |
| 9 | recovery okuması da `client` | `ERROR` + `retryIn` |
| 10 | `full_sync` yanıtı sonrası | `scheduleFollowUp` (hemen artımlı) |
| 11 | `QUICK_ADD_DONE{rate, 30}` | quick add aşaması durur, `retryIn(30 s)`, sync isteği atlanır |
| 12 | `AUTH_INVALID`'de `SYNC_REQUESTED` | effect yok |
| 13 | Backoff dizisi | 30/60/120/300/300 s, ±%20 |
| 14 | `TOKEN_SET` (kuyrukta 2 close) | yalnız `verifyAccount`; `startRequest` (komutlu) yok |
| 15 | `ACCOUNT_VERIFIED` farklı `userId` | `clearData` → sonra `startRequest` (komutsuz tam sync) |
| 16 | `ACCOUNT_VERIFIED` aynı `userId` | kuyruk korunur, `startRequest` (komutlu) |

**Adım 6 — `TodoistClient.js` (engineer)** — T4 sözleşmesi. Testler sahte XHR ile:
| # | Durum | Beklenen |
|---|-------|----------|
| 1 | `sync` çağrısı | POST, doğru URL, `Authorization: Bearer t`, form gövdesi URL-encoded JSON alanları; commands boşsa alan yok |
| 2 | `quickAdd("a & b")` | JSON gövde `{"text":"a & b","meta":false}` |
| 3 | 200 + geçerli JSON | `kind:"ok"` |
| 4 | status 0 | `network` |
| 5 | 401 / 403 | `auth` |
| 6 | 429 + `Retry-After: 12` / başlıksız + `error_extra.retry_after:7` / hiçbiri | `rate`, 12 / 7 / 60 |
| 7 | 502 | `server` |
| 8 | 400 | `client` |
| 9 | 200 + bozuk JSON | `server` |
Ardından **manuel API doğrulaması** (kullanıcının gerçek token'ı, curl): sync'te commands + okuma aynı
istekte; `/tasks/quick` yanıt şekli; Türkçe tarih ayrıştırma (Assumptions A2, A3).

**Adım 7 — `Storage.js` + `SyncController.qml` (engineer)** — Controller yalnızca `SyncMachine`
effect'lerini Timer/XHR/LocalStorage çağrılarına eşler ve sonuçları olay olarak geri besler; kendi
karar mantığı yoktur (review'da kontrol: `if` dalları yalnız effect tipine göre). QML test runner
(`qmltestrunner`) Plasma import'larını CI'de çözemediği için kullanılmaz; kapsam = Adım 5 Node testleri +
manuel M3–M10, M22–M23.

**Adım 8 — UI (engineer)** — `CompactRepresentation`, `FullRepresentation`, `TaskListView`, `TaskRow`,
`RoundCheck`, `NewTaskField`, `SmallView`, `StatusFooter`, boş durum, contextualActions, tooltip.
Pattern referansı: Plasma 6 widget tutorial örnekleri (Context7). Kabul: M1, M2, M11–M16.

**Adım 9 — Kurulum (engineer)** — `SetupView`, `ConfigAccount`, `config/config.qml`. Kabul: M17–M19.

**Adım 10 — i18n (mechanic)** — script'ler + `tr.po` çevirisi (çeviri metni engineer/kullanıcı gözden
geçirir). Kabul: M20.

**Adım 11 — CI/Release (mechanic)** — `ci.yml`, `release.yml`, `scripts/package.sh`. Kabul: PR'da CI
yeşil; test etiketi (`v0.9.0-rc1`, prerelease) ile `.plasmoid` artefaktı üretilir ve M21 geçer.

**Adım 12 — Dokümantasyon + yayın (mechanic + kullanıcı)** — README (özellikler, ekran görüntüleri,
kurulum, token alma, Security notu, "Unofficial", Quick Add örnekleri, sorun giderme), CHANGELOG 1.0.0,
KDE Store sayfası (kullanıcı yükler).

**Manuel kabul listesi (plasmoidviewer + gerçek Plasma 6.7.5 oturumu)**
- M1 Masaüstünde büyük boyut: başlık, Overdue/Today bölümleri, doğru sıralama (telefondaki Today ile birebir).
- M2 Masaüstünde küçültünce SmallView (büyük sayı + sıradaki görev); çok küçükte ikon.
- M3 Telefonda görev ekle → widget popup'ını aç → ≤ 2 sn'de görünür; kapalıyken ≤ 5 dk.
- M4 Widget'ta tamamla → animasyon → telefonda ≤ birkaç sn'de tamamlanmış.
- M5 Tekrarlayan görev tamamla → bugün listesinden çıkar, telefonda sonraki tarihe ilerlemiş.
- M6 Ağı kes (`nmcli networking off`) → "Offline" footer; 2 görev tamamla + 1 ekle → plasmashell'i yeniden başlat → bekleyen durum korunmuş → ağı aç → hepsi Todoist'e gider, çift kayıt yok.
- M7 Telefonda sil, widget'ta offline tamamla → online olunca komut düşer, satır kaybolur, bilgi mesajı.
- M8 Token'ı Todoist'te yenile → widget `AUTH_INVALID` banner'ı → yeni token → kuyruk korunarak devam.
- M9 Gece yarısı (sistem saatini 23:59'a al veya bekle) → ≤ 60 sn'de dünkü saatsiz görev Overdue'ya geçer.
- M10 Uyku → uyanma → ≤ 60 sn'de doğru gün + sync.
- M11 Panelde rozet sayısı = overdue + today; overdue varken negatif renk; 0'da rozet yok.
- M12 Açık ve koyu temada, farklı vurgu renginde görünüm doğru (sabit renk yok).
- M13 Quick Add: "Dentist tomorrow 15:00 #Personal" → bilgi mesajı "Personal · Tomorrow 15:00"; listede yok (yarın).
- M14 Quick Add: "Call mom today p1" → listede, p1 çember rengi.
- M15 Boş liste → PlaceholderMessage.
- M16 Sistem "animasyonları kapat" → tamamlama animasyonsuz ama çalışır.
- M17 Yeni kurulum: token yapıştır → < 1 dk'da liste (başarı ölçütü 3).
- M18 Geçersiz token → anlaşılır hata, liste yok.
- M19 Ayarlar → Disconnect → `SETUP`, önbellek silinmiş.
- M20 `LANGUAGE=tr` ile tüm metinler Türkçe; çoğul biçimler doğru.
- M21 Release `.plasmoid` → "Install from local file" ile temiz kullanıcıda kurulur, çalışır.
- M22 Ayarlar penceresinden (ConfigAccount) token gir → Apply → widget `SETUP`'tan çıkıp listeyi yükler; geçersiz token Apply edilirse `AUTH_INVALID` banner'ı.
- M23 Masaüstünde 1 dk bekle, telefonda görev ekle, fareyi widget'a getir → ≤ 2 sn'de görünür.

## Assumptions

| # | Varsayım | Doğrulama |
|---|----------|-----------|
| A1 | Ad "Todoist Today"; resmi olmadığı belirtilir; Todoist logosu yok, KDE ikonu | README/Store metni (Adım 12) |
| A2 | `/sync` aynı istekte `commands` + `sync_token`/`resource_types` kabul eder | Adım 6 sonunda curl ile; olmazsa iki ardışık istek (yazma → okuma) |
| A3 | Quick Add Türkçe tarihleri ("yarın 15:00") ayrıştırır **— şüpheli:** v1 dokümanındaki `due.lang` listesi (en, da, pl, zh, ko, de, pt, ja, it, fr, sv, ru, es, nl, fi, nb, tw) Türkçe içermiyor. `#Proje`, `@etiket`, `p1` dilden bağımsız çalışır | Adım 6 sonunda gerçek hesapla; desteklenmiyorsa README'de "dates follow your Todoist language; English always works" notu (Open Q4) |
| A4 | Sync aralığı 5 dk + popup açılınca + işlemden 1 sn sonra | Kullanım sonrası ayarlanabilir sabit (ayar değil) |
| A5 | Today sıralaması (saatliler önce saate göre, sonra order_key/day_order) Todoist uygulamasının varsayılan Today sırasıyla örtüşür | M1'de telefonla karşılaştır; farklıysa yalnız sıralama fonksiyonu + testleri güncellenir |
| A6 | Referans saat dilimi = Todoist `tz_info` (eşitse her an için sistem ofseti; farklıysa T7'deki iki bilinen sınır kabul edilir ve README'de yazılır) | M9, ve farklı sistem dilimiyle bir test (`TZ=America/New_York plasmoidviewer …`) |
| A7 | `QtQuick.LocalStorage` plasmashell içinde (Arch `qt6-declarative`) kullanılabilir | Adım 7 başında küçük deneme |
| A8 | ~~`BadgeOverlay` üçüncü parti plasmoid'den import edilebilir~~ | Kapatıldı: kendi Rectangle rozeti kullanılıyor (T2) |
| A9 | Kişisel API token'ı `/api/v1` uçlarının hepsinde Bearer ile çalışır (v1 dokümanı örnekleri öyle) | Adım 6 curl |
| A10 | Proje kökü = bu repo; Node ≥ 20 geliştirme makinesinde mevcut | Adım 0 |
| A11 | Tek token tek widget örneğine aittir (panel + masaüstü = iki kez yapıştırma) | Open Q3 |

## Decision Log

| Decision | Alternatives | Rationale |
|----------|-------------|-----------|
| D1 Saf QML + JS, C++ yok | C++ plugin (QtKeychain, ağ izleme) | KDE Store'dan tek tık kurulum; onaylı kısıt |
| D2 Todoist `api/v1/sync` (+ `/user`, `/tasks/quick`) | REST v2 / Sync v9 | v2/v9 eski (onaylı kısıt); v1 artımlı sync + uuid idempotency sağlar |
| D3 Kişisel API token, düz metin config | OAuth; KWallet | Açık kaynakta `client_secret` saklanamaz; KWallet C++/DBus gerektirir; onaylı tradeoff, README'de açık |
| D4 Tamamlama = `item_close` | `item_complete`, `item_update_date_complete`, REST `POST /tasks/{id}/close` | Resmi istemci semantiği (tekrarlayanlar doğru ilerler), sync komutu → uuid idempotency + 100'lük batch |
| D5 Görev ekleme = REST `POST /tasks/quick` | sync `item_add` + `due:{string}` | Onaylı özellik "Todoist doğal dili" (#proje, @etiket, p1); `item_add` yalnız tarih ayrıştırır. Bedeli: idempotency yok → `uncertain` + `resolveUncertain` sezgisi (T6) |
| D6 Optimistic UI = kuyruk overlay'inden türetilmiş görünüm | Store'u yerinde mutasyon + revert | Yeniden başlatmada tutarlı, revert otomatik, saf fonksiyon → Node'da test edilir |
| D7 v1'de `temp_id` kullanılmaz | Pending görevi tamamlamaya izin verip `temp_id` ile `item_add`+`item_close` zinciri | Yaratma REST ile; bekleyen görevin onay kutusu kapalı → karmaşıklık yok. `item_add`'e geçilirse eklenir |
| D8 Önbellek/kuyruk `QtQuick.LocalStorage`, ayar `Plasmoid.configuration` | Hepsi KConfig'te JSON string | appletsrc'yi büyük JSON ile şişirmez; transactional |
| D9 Referans saat dilimi Todoist `tz_info` (eşitse sistem) | Daima sistem saati | Telefonla aynı "Today"; QV4'te Intl yok → ofset tabanlı çözüm |
| D10 Gün dönümü 60 sn tick ile | Gece yarısına tek Timer | Uyku/uyanma ve saat değişikliklerine dayanıklı, maliyet ihmal edilebilir |
| D11 Node testleri vm loader ile, üretim koduna guard yok | `if (typeof module !== "undefined") module.exports=…` | `.pragma`/`.import` satırları Node'da parse hatası; guard bunu çözmez. Loader satırları ayıklar, deps'i enjekte eder |
| D12 `node:test`, sıfır bağımlılık | Jest/Vitest | Basit, hızlı CI, tedarik zinciri yüzeyi yok |
| D13 Saat biçimi sistem yerel ayarından | Todoist `time_format` | Platforma yerli ilke |
| D14 Store'da yalnız açık + vadeli item'lar | Tüm item'lar | Küçük önbellek; Today'e girebilecek her şey yine de yerelde (gece yarısı ağsız çalışır) |
| D15 Sıralama: `user_item_orders.order_key` → `day_order` yedek | Yalnız `day_order` | `day_order` v1'de deprecated ("ileride kaldırılacak"); ikisi şimdilik senkron |
| D16 Repo kökünde `translations/` + script'ler, `.mo` paketin içinde üretilir | KDE örneğindeki `package/translate/` | Kaynak dosyalar pakete girmez; `.mo` release'te paketlenir; onaylı yapıya uygun |

## Open Questions

Tümü kapatıldı (Revizyon 4):

- [x] **Q1** Repo görünürlüğü: repo `bahadirdemircioglu/today` olarak oluşturuldu; görünürlük GitHub
  ayarından yönetilir, CI her iki durumda çalışır. KDE Store yüklemesi 1.0 README'si ile.
- [x] **Q2** `KPlugin.Id` = `io.github.bahadirdemircioglu.todoisttoday`; Website/BugReportUrl
  `github.com/bahadirdemircioglu/today`.
- [x] **Q3** v1: her örnek için token ayrı yapıştırılır (basit; token tek yerde). Devralma v2'ye ertelendi.
- [x] **Q4** İkisi birden: README notu ("dates follow your Todoist language; English always works") +
  "New task" alanında İngilizce örnek placeholder.
- [x] **Q5** Undo v1'e alınmadı (Non-Goals'ta kalıyor).
- [x] **Q6** Bilgi notu; v1 kapsamı değişmez (OAuth yok).

## Implementation Notes (Revizyon 4)

Uygulama sırasında plandan sapmalar / plana eklenen düzeltmeler:

1. **Tarihsiz Quick Add çift kayıt riski (hata düzeltmesi):** Store budama kuralı `due === null`
   item'ları sildiğinden, tarihsiz bir Quick Add ("Buy milk") `uncertain` kaldığında
   `resolveUncertain` onu store'da asla bulamaz ve yeniden gönderirdi → kesin çift görev. Çözüm:
   store'a `recent` haritası eklendi: son 30 dk'da eklenen her item (vadesi olmasa da) `{content, addedAt}`
   olarak tutulur; `resolveUncertain` hem `items` hem `recent` üzerinde arar. Şema sürümü değişmedi
   (`deserialize` eksik `recent`'i boş harita yapar).
2. **SyncMachine olayları:** `ACCOUNT_VERIFIED{sameAccount}` (karşılaştırmayı controller yapar, makine
   önbellek hesabını bilmez); `RETRY_FIRED` olayı (doğrulanmamış hesapta yeniden doğrulama, aksi halde
   sync); `cancelRetry` ve `abortRequest` effect'leri. `action` nedenli ve takip (follow-up/retry)
   istekleri 5 sn aralık kuralından muaf (debounce zaten birleştiriyor; başarı ölçütü 2).
3. **Komutsuz istek de `client` dönerse** (geçersiz `sync_token` olasılığı) aynı izolasyon yolu
   (`readOnlyFull`) kullanılır.
4. **Quick Add sonuçları:** `ok` → bugünün değilse "Added to <Proje> · <due.string>" bilgisi;
   `server`/`auth`/`rate` 20 denemeden sonra da düşürülür (zehirli girdi koruması).
5. **i18n:** `logic/*.js` metin içermez (kod döner, QML çevirir); `i18n-extract.sh` yalnız `.qml`
   tarar. `template.pot`'ta zaman damgası satırı silinir → CI "çeviriler güncel mi" kontrolü yapar.
6. **CI:** metadata/`package.json` sürüm eşitliği, `main.xml` doğrulaması, çeviri güncelliği,
   `.plasmoid` paketleme smoke testi. `release.yml` `v1.0.0-rc1` gibi ön sürüm etiketlerini
   prerelease olarak yayınlar.
7. **Doğrulama durumu:** mantık katmanı Node'da test edildi (Adım 1–6 tabloları + ek vakalar).
   QML; Qt 6 `qmllint`/`qmlformat` ile sözdizimi açısından ve KDE modüllerinin stub'larıyla offscreen
   duman testinde (liste, küçük görünüm, rozet, kurulum ekranı, tamamlama, çevrimdışı kuyruk) çalıştırıldı.
   Gerçek Plasma 6 oturumunda manuel kabul listesi (M1–M23) ve Adım 6 sonundaki gerçek token ile API
   doğrulaması (A2, A3, A9) henüz yapılmadı.
8. **Yeniden başlatmada uçuştaki Quick Add (hata düzeltmesi):** `markQuickAddSent` gönderimden önce
   kalıcı yazıldığından, istek yoldayken plasmashell kapanırsa girdi `pending` + `sentAt` ile kalıyordu
   ve körlemesine yeniden gönderilirdi. `CommandQueue.recoverAfterRestart()` yüklemede bu girdileri
   `uncertain` yapar; ilk başarılı sync'te `resolveUncertain` karar verir.
