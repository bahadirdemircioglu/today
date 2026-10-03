# Architecture Plan: todoist-plasma (v2 — esnek görünümler)

**Status:** implemented (v2.0.0)
**Revision:** 3
**Önceki plan:** [todoist-today-plan.md](todoist-today-plan.md) (v1, uygulandı). Bu plan onun üzerine
kurulur; v1'deki sync, kuyruk, durum makinesi, güvenlik ve i18n kararları aynen geçerlidir. Yalnızca
değişenler burada.

## Overview & Goals

Kullanıcı geri bildirimi: "Uygulama sadece Today değil, web'deki gibi esnek olmalı." Widget, Todoist web
uygulamasının sol menüsündeki ana görünümleri Plasma'da sunar:

| Görünüm | İçerik | Gruplama | "+ Yeni görev" varsayılanı |
|---|---|---|---|
| **Inbox** | Inbox projesindeki açık görevler | bölümler (section), alt görevler girintili | Inbox, tarihsiz |
| **Today** | v1 ile aynı (gecikmiş + bugün) | Overdue / Today | bugün |
| **Upcoming** | önümüzdeki 7 gün (+ gecikmiş) | gün gün ("Pazartesi 5 Ekim") | o günün tarihi (grup başlığındaki "+") |
| **Proje** | seçilen projenin açık görevleri | bölümler, alt görevler girintili | o proje |
| **Etiket** | etiketi taşıyan açık görevler | tarih / öncelik | o etiket (`@etiket`) |
| **Filtre** | Todoist'te kayıtlı filtrenin sonucu | sunucunun sırası | — (filtre sorgusu yorumlanmaz) |

- **Gezinme:** popup başlığındaki görünüm adı bir açılır seçicidir ("Today ▾"): Inbox, Today,
  Upcoming, ardından Projeler / Etiketler / Filtreler alt listeleri (sayılarıyla). Dar alanda yan menü
  yok; tek tıkla geçiş, son seçilen görünüm hatırlanır.
- **Masaüstü widget'ı bir görünüme sabitlenebilir** (ayarlar: "Bu widget şunu göstersin: …"). Böylece
  masaüstüne bir "İş" projesi widget'ı, bir "Today" widget'ı ayrı ayrı konabilir. Seçici yine açık kalır
  (geçici gezinme), "sabitle" ayarı başlangıç görünümüdür.
- **Panel rozeti:** varsayılan Today sayısı (gecikmiş + bugün); ayarlardan "rozet = seçili görünümün
  sayısı / kapalı" seçilebilir.
- **Görev menüsü** (v1.1'de eklendi: düzenle, tarih, öncelik, taşı, bağlantı, sil) tüm görünümlerde.
  Ek olarak: "Alt görev ekle", "Etiketler…" (çoklu seçim).
- **Ürün ilkesi değişmez:** az ayar, Breeze dili, çevrimdışı çalışma.

**Başarı ölçütleri** (v1'e ek)
1. Web'deki Inbox/Today/Upcoming/proje görünümüyle aynı görev kümesi ve sıra (M-v2-1…3).
2. Görünüm geçişi ağ beklemeden < 100 ms (yerel önbellekten; filtreler hariç).
3. Bir projeye eklenen görev o projede görünür; Upcoming'de bir güne eklenen görev o güne düşer.

## Non-Goals (v2)

- Filtre sorgu dilini istemcide yorumlamak (Todoist sorgu dili geniş: `(today | overdue) & #İş & !@bekle`).
  Filtreler **sunucuda** değerlendirilir (aşağıda T4); çevrimdışıyken son sonuç gösterilir.
- Proje/bölüm/etiket/filtre **oluşturma, düzenleme, silme**; sürükle-bırak sıralama; tamamlanmış
  görevler arşivi; yorumlar, ekler, hatırlatıcılar, deadline düzenleme; ekip/paylaşım özellikleri;
  Reporting; takvim (board/calendar) düzenleri.
- Tekrarlayan görevi widget'tan yeniden planlamak (v1.1'deki gibi kapalı kalır).

## Architecture Changes

### A1. Önbellek kapsamı (TaskStore)

v1 budama kuralı ("vadesiz item'ı sil") kaldırılır: **tüm açık görevler** saklanır (yalnız
`checked`/`is_deleted` silinir). `recent` haritası gereksizleşir (tarihsiz görevler artık `items`'ta) ama
`resolveUncertain` uyumluluğu için korunur.

`resource_types` genişler: `["items","projects","sections","labels","filters","user","user_item_orders","day_orders"]`.
Yeni store alanları (şema `v: 2`, `v: 1` önbellek → tam sync ile yeniden kurulur):

```js
sections: { "<id>": { name, projectId, order } },
labels:   { "<id>": { name, color, order } },        // kişisel etiketler
filters:  { "<id>": { name, query, color, order } },
projects: { "<id>": { name, color, order, parentId, isInbox } },  // order/parentId eklendi
items[id]: + sectionId, labels[], description (ilk satır), childOrder, parentId (mevcut)
```

Büyüklük: birkaç bin görevde JSON ~1–2 MB; LocalStorage tek satır yazımı kabul edilebilir. Gerekirse
(A1-risk) `items` ayrı anahtara bölünür.

### A2. Görünüm hesaplama: `ViewModel.js` (yeni, saf)

`computeToday` genelleşir: `computeView(store, queue, viewSpec, nowMs, sysOffsetAt)` →
`{ title, groups: [{ key, label, dateKey?, sectionId?, rows: [...] }], counts, next }`.

`viewSpec`: `{ kind: "inbox" | "today" | "upcoming" | "project" | "label" | "filter", id? }`.

- **Overlay** (v1.1 kuyruk: close/delete gizler; update/move yamalar) tüm görünümlerde aynı.
- **Proje/Inbox:** bölümsüz görevler önce, sonra `section.order` sırasıyla bölümler; içinde
  `child_order`; alt görevler ebeveynin altında girintili (`depth` rolü, en fazla 4 seviye gösterilir).
- **Upcoming:** gecikmişler en üstte tek grup, sonra bugün + 6 gün, her gün ayrı grup (boş günler de
  başlıkla görünür, web gibi); gün içi sıralama Today kuralıyla aynı.
- **Etiket:** `labels` içinde etiket adı geçen görevler; sıralama: tarihliler tarih, sonra öncelik.
- **Filtre:** A3.
- `flattenRows` gruplara göre `header` rolünü üretir (v1 düzeni korunur), yeni roller: `depth`,
  `labels` (metin), `groupDateKey` (Upcoming "+").

`computeToday` → `computeView({kind:"today"})` ile birebir aynı sonucu verir (mevcut testler korunur).

### A3. Filtreler

Todoist v1 `GET /api/v1/tasks/filter?query=<sorgu>&lang=<dil>` sunucu tarafında değerlendirir
(**Adım 0'da curl ile doğrulanacak**, A-v2-1). Akış:
- Filtre görünümü açılınca / periyodik sync'te o filtre için istek → sonuç id listesi
  `filterResults[filterId] = { ids, fetchedAt }` olarak saklanır; görev verisi store'dan okunur
  (store'da olmayan id → tam sync tetikler).
- Çevrimdışı: son sonuç + footer "Showing results from 14:05".
- Kuyruk overlay'i uygulanır (tamamlanan görev filtreden de düşer).
- Endpoint yoksa/yetersizse yedek: yalnız basit sorgular (`today`, `overdue`, `#Proje`, `@etiket`, `p1`
  ve `&`/`|`) için istemci yorumlayıcı; diğerleri "Open in Todoist" bağlantısı gösterir.

### A4. Gezinme ve durum

- `SyncController` → `viewSpec` (geçerli görünüm) + `pinnedView` (config) tutar; `rows` geçerli
  görünümden hesaplanır. Görünüm listesi (`navModel`): sabit üçlü + `projectList` + labels + filters,
  her biri sayısıyla (sayılar tek geçişte hesaplanır).
- Config (`main.xml`): `pinnedView` (String, `"today"` / `"project:<id>"` / …), `badgeSource`
  (`today` | `view` | `none`). Ayarlar sayfasına "Görünüm" kategorisi.
- Seçili görünüm silinmiş/arşivlenmiş proje ise → Today'e düşer, bilgi satırı.

### A5. Görev ekleme bağlamı

Quick Add metni yorumlanmadan gönderilir; bağlam, yanıttan sonra uuid'li sync komutlarıyla uygulanır
(v1.1'deki `due_today` yaklaşımının genellemesi):

| Görünüm | Quick Add yanıtında… | Ek komut |
|---|---|---|
| Today | `due` yok | `item_update {due: today}` (mevcut) |
| Upcoming (gün grubu "+") | `due` yok | `item_update {due: o gün}` |
| Proje / bölüm | proje Inbox ise (kullanıcı `#` yazmamış) | `item_move {project_id[, section_id]}` |
| Etiket | etiket yoksa | `item_update {labels: [...mevcut, etiket]}` |
| Alt görev (menü) | — | `item_move {parent_id}` |

Kullanıcının yazdığı `#proje` / tarih her zaman kazanır.

### A6. UI

- **Başlık:** görünüm seçici (PlasmaComponents3 `ToolButton` + `Menu`, alt menüler: Projects / Labels /
  Filters), sağda senkron göstergesi.
- **Gruplar:** bölüm başlıkları (proje/Inbox), gün başlıkları (Upcoming, yanında "+"), v1 header
  satırı bileşeni yeniden kullanılır.
- **Satır:** `depth` kadar girinti (her seviye `gridUnit`), etiketler küçük metin olarak proje adının
  yanında; açıklamanın ilk satırı (varsa) ikinci satırda soluk.
- **Küçük masaüstü görünümü:** seçili görünümün sayısı + sıradaki görev (Upcoming/Today), proje
  görünümünde ilk görev.
- Tasarım: Claude Design kanvasına v2 ekranları eklenir (görünüm seçici, Upcoming, proje + bölümler,
  filtre çevrimdışı) ve uygulamadan önce onaylanır.

### A7. Ad ve kimlik

Kapsam artık "Today" değil. Widget henüz yayımlanmadığı için `KPlugin.Id` **şimdi** değiştirilebilir
(yayından sonra imkânsız). Öneri: ad **"Todoist for Plasma"** (resmi değil ibaresiyle), Id
`io.github.bahadirdemircioglu.todoistplasma`, paket adı `todoist-plasma-<v>.plasmoid`. Repo adı
(`today`) ayrı bir karardır (GitHub yeniden adlandırmada yönlendirme yapar). → Open Question Q1.

## Migration Plan

Her adım v1'deki gibi: önce kabul vakaları test olarak, sonra kod; her adım ayrı commit, CI yeşil.

0. **API doğrulama (curl, gerçek token):** `/tasks/filter` varlığı ve yanıt şekli; `sections`,
   `labels`, `filters` resource şekilleri; `item_move` ile `section_id`/`parent_id`; Quick Add yanıtında
   `project_id` Inbox iken davranış. Sonuçlar bu plana işlenir.
1. **Store v2** (A1): tüm açık görevler, yeni kaynaklar, şema yükseltme. Testler: budama değişikliği,
   sections/labels/filters merge, v1→v2 sıfırlama.
2. **ViewModel.js** (A2): inbox/project/upcoming/label + Today eşdeğerliği. Testler: bölüm sırası,
   alt görev derinliği, Upcoming 7 gün + boş günler, etiket eşleşmesi, overlay her görünümde.
3. **Filtreler** (A3): istemci + sonuç önbelleği + çevrimdışı; SyncMachine'e `filter` istek türü
   (aynı tek-uçuş/backoff kuralları). Testler: sonuç birleştirme, overlay, eksik id → tam sync.
4. **Ekleme bağlamı** (A5): `ContextRules.js` saf fonksiyonu (görünüm + Quick Add yanıtı → komutlar).
5. **Gezinme + config** (A4): `navModel`, `pinnedView`, `badgeSource`, ayarlar sayfası.
6. **UI** (A6): seçici, gruplar, girinti, etiketler; Claude Design onayından sonra.
7. **Ad/Id değişikliği** (A7, Q1 kararına göre), i18n güncelleme, README/CHANGELOG, `2.0.0`.

## Manuel kabul (v2 ek)

- M-v2-1 Inbox ve iki proje: görev kümesi + bölüm sırası + alt görev girintisi web ile aynı.
- M-v2-2 Upcoming: 7 gün, boş günler, gün başlığı "+" ile ekleme o güne düşer.
- M-v2-3 Bir filtre (`today & p1`): sonuç web ile aynı; ağ kesikken son sonuç + zaman bilgisi.
- M-v2-4 Masaüstüne iki widget: biri "İş" projesine, biri Today'e sabit; yeniden başlatmada korunur.
- M-v2-5 Proje görünümünde "Buy milk" ekle → o projede; "Buy milk #Kişisel" → Kişisel'de.
- M-v2-6 Seçili proje web'de arşivlenince widget Today'e düşer, bilgi gösterir.

## Assumptions

| # | Varsayım | Doğrulama |
|---|---|---|
| A-v2-1 | `GET /api/v1/tasks/filter?query=` mevcut ve kişisel token ile çalışır | Adım 0 curl |
| A-v2-2 | Sync `sections`/`labels`/`filters` resource'ları v1'de bu adlarla gelir | Adım 0 |
| A-v2-3 | Tüm açık görevlerin LocalStorage'da tutulması (birkaç bin) performans sorunu yaratmaz | Adım 1'de 5000 görevlik fixture ile ölçüm |
| A-v2-4 | Filtreler ücretsiz planda da (sınırlı sayıda) API'den okunabilir | Adım 0 |

## Open Questions

Kapatıldı (kullanıcı kararları, Rev. 2):

- [x] **Q1** Ad "Todoist for Plasma", Id `io.github.bahadirdemircioglu.todoistplasma`, paket
  `todoist-plasma-<v>.plasmoid`, LocalStorage veritabanı `TodoistPlasma`. Repo adı `today` kalır.
- [x] **Q2** Filtreler v2'de (sunucu tarafı).
- [x] **Q3** Sabitlenmiş widget'ta seçici açık kalır; sabit görünüm başlangıç noktasıdır.
- [x] **Q4** Upcoming 7 gün (öneri kabul edildi; sabit, ayar yok).
- [x] **Q5** Panel rozeti varsayılanı Today sayısı (ayarlardan değiştirilebilir).

## Decision Log

| Decision | Alternatives | Rationale |
|---|---|---|
| V1 Tüm açık görevleri önbellekle | Görünüm başına istek | Çevrimdışı + anında görünüm geçişi; tek artımlı sync |
| V2 Filtreleri sunucuda değerlendir | İstemci sorgu yorumlayıcı | Todoist sorgu dili geniş ve dile bağlı; yanlış sonuç riski |
| V3 Ekleme bağlamı sonradan uuid'li komutla | Quick Add metnine `#proje`/tarih eklemek | Metne ekleme kullanıcının yazdığıyla çakışır ve dile bağlıdır; komutlar idempotent |
| V4 Görünüm seçici başlıkta açılır menü | Yan menü (web gibi) | Popup 22 gu genişlikte; yan menü listeye yer bırakmaz |
| V5 `computeToday` → `computeView` genellemesi | Görünüm başına ayrı modül | Overlay/sıralama kuralları tek yerde; v1 testleri eşdeğerliği korur |

## Implementation Notes (Rev. 3)

1. **Adım 0 (API doğrulama) yapılamadı:** geliştirme ortamında Todoist token'ı yok. Belirsiz noktalar
   savunmacı uygulandı: `/tasks/filter` yanıtı hem `{results, next_cursor}` hem düz dizi olarak kabul edilir
   (en fazla 5 sayfa); filtre isteği başarısız olursa sync döngüsü bozulmaz, liste "Todoist couldn't run this
   filter" / son sonuç gösterir. A-v2-1…4 gerçek hesapla doğrulanmalı.
2. **Filtre isteği sync döngüsünün içinde:** tek uçuş kuralı korunsun diye geçerli görünüm filtreyse
   `/sync` başarısından sonra aynı döngüde istenir; görünüm değişince `SYNC_REQUESTED{view}` (5 sn kuralından muaf).
3. **Bağlam kuyruktaki girdide:** `quick_add.context` kaydedilir; görev çevrimdışı eklenip sonra
   gönderilse veya kullanıcı başka listeye geçse de doğru yere düşer. `due_today` girdisi `update`'e genellendi.
4. **Görünüm geçişi animasyonsuz:** liste değişince model sıfırlanır (silme animasyonları boşluk bırakıyordu);
   yalnız aynı liste içindeki değişiklikler animasyonlu.
5. **Sabitleme widget'tan:** ayarlar sayfası applet verisine erişemediği için görünüm, başlık menüsündeki
   "Start here in this widget" ile `pinnedView`'e yazılır; ayarlarda yalnız "Unpin" ve rozet kaynağı var.
6. **Upcoming'de tekrarlayan görevler** yalnız bir sonraki tarihlerinde görünür (web her tekrarı gösterir) —
   README "Known limitations".
7. **Doğrulama:** 113 Node testi (ViewModel, ContextRules, store v2 dahil); QML offscreen duman testinde altı
   görünümün hepsi (Inbox, Today, Upcoming, proje + bölüm + alt görev, etiket, filtre) uyarısız çizildi. Gerçek
   Plasma oturumunda M-v2-1…6 henüz yapılmadı.
