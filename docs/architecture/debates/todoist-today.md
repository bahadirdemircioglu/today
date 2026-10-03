# Plan Tartışması: todoist-today

> Bu dosya `scripts/deepseek-critique.js` tarafından üretilir — elle düzenlemeyin.

**Durum:** running | **Tur:** 3/4 | **Model:** deepseek-v4-pro | **Plan revizyonu:** 3

**Maddeler:** 11 toplam — agreed 9, open 0, resolved 2, decided-by-claude 0

**Kullanım:** 71360 girdi / 36016 çıktı token (31630 akıl yürütme)

## Turlar

- **Tur 1** — 7 yeni itiraz. Planda iki yüksek öncelikli engel ve birkaç orta/düşük risk belirledim: Q2/Adım0 bağımlılığı, geçersiz sync_token'ın komutlarla birlikte sonsuz döngüye yol açması; ayrıca masaüstü görünürlük tetikleyicisi, config dialog entegrasyonu, quick_add rate yönetimi, SyncController test kapsamı ve resolveUncertain eşleştirme hassasiyeti eksik.
- **Tur 2** — 2 yeni itiraz. Mevcut itirazlar için düzeltmeler yeterli; iki yeni yüksek öncelikli sorun tespit edildi: user_item_orders kapsam filtresi ve GMT önekli saat dilimi parse.
- **Tur 3** — 2 yeni itiraz. D8 ve D9 düzeltmeleri yeterli bulunarak kapatıldı. İki yeni yüksek öncelikli itiraz eklendi: DST kaynaklı sabit saat dilimli görevlerin yanlış sınıflandırılması ve token değişiminde hesap doğrulaması yapılmadan kuyruk komutlarının gönderilme riski.

## Maddeler

| ID | Dosya / Bölüm | Önem | Durum | İtiraz |
|----|---------------|------|-------|--------|
| D1 | plan.md / Migration Plan Adım 0 / Open Questions Q2 | high | agreed | Adım 0, metadata.json'u T1 şablonuyla oluşturmayı içeriyor; ancak Q2'de KPlugin.Id ve GitHub kullanıcı adı 'adım 0'dan önce kesinleşmeli' deniyor. Bu karar verilmeden metadata.json'daki KPlugin.Id, Website, BugReportUrl alanları gerçek değerlerle doldurulamaz. KPlugin.Id sonradan değiştirilemeyeceği için geçici veya yanlış bir değerle başlamak risklidir. Ayrıca i18n script'leri Id'yi okuduğu için Q2 çözülmeden bu script'ler de test edilemez. |
| D2 | plan.md / T5 Sync tasarımı / Sync döngüsü adım 6 | high | agreed | Geçersiz sync_token işleme kuralı yalnızca 'komut yokken' tam sync reset öngörüyor. Komutlar (item_close) ile gönderilen istek 400 dönerse sync_token geçersiz olabilir; ancak koşul sağlanmadığı için reset yapılmaz ve kuyruk korunur. Sonraki denemeler aynı geçersiz token ve aynı komutlarla tekrarlanır; kullanıcı işlemleri sonsuza kadar bekler. |
| D3 | plan.md / T5 Sync tetikleyicileri | medium | agreed | Tetik tablosunda 'Popup açıldı (expanded → true) / masaüstünde widget görünür oldu' deniyor; ancak masaüstünde widget'ın görünür olduğunu algılayacak mekanizma belirtilmemiş. PlasmoidItem masaüstünde sürekli yüklü olabilir; yalnızca `expanded` sinyali panel popup içindir. Bu tetik uygulanamazsa masaüstü widget'ında 'açılınca anında senkron' başarı ölçütü karşılanamayabilir. |
| D4 | plan.md / T9 Kurulum akışı / T8 Durum makinesi | medium | agreed | Token iki yoldan değiştirilebilir: SetupView (widget içi) ve ConfigAccount (ayarlar penceresi). T8 yalnızca `TOKEN_SET` olayını tanımlıyor; ancak ConfigAccount'ta token değiştiğinde SyncController'ın bu değişikliği nasıl algılayıp `TOKEN_SET`/`TOKEN_CLEARED` üreteceği belirtilmemiş. Sadece SetupView butonuna bağlı kalınırsa, kullanıcı ayarlar penceresinden token girdiğinde senkron tetiklenmez. |
| D5 | plan.md / T5 Sync döngüsü / T6 Çevrimdışı kuyruk | medium | agreed | Çevrimdışıyken birikmiş quick_add girdileri 'tek tek' POST /tasks/quick ile gönderiliyor; ancak bu isteklerin sayısına bir üst sınır veya rate limit (429) yönetimi belirtilmemiş. Uzun süre çevrimdışı kalıp onlarca/yüzlerce görev eklenirse, tek bir sync döngüsünde onlarca REST çağrısı yapılır; bu süreyi uzatır, 429 tetikleyebilir ve `inFlight` kilidi altında uzun süre kalınmasına yol açar. |
| D6 | plan.md / Migration Plan Adım 7 | medium | agreed | SyncController (Adım 7) eşzamanlılık ve zamanlayıcı mantığı içerdiği hâlde yalnızca manuel M3–M10 ile doğrulanıyor; otomatik test yok. Tek uçuş, coalesce, debounce, gün dönümü tick'i ve backoff gibi davranışlar manuel testlerde deterministik değildir; yarış koşulları gözden kaçabilir. |
| D7 | plan.md / T6 resolveUncertain | low | agreed | `resolveUncertain` eşleştirme kuralı `plainTitle(content)` kelimelerinin girdi metninin kelimelerinin alt kümesi olmasına dayanıyor. Büyük/küçük harf ve Türkçe karakter normalizasyonu belirtilmemiş. Örneğin 'Dişçi' ile 'dişçi' eşleşmeyebilir; ayrıca metin 'yarın 15:00 dişçi' gibi tarih/proje içerirken içerik yalnızca 'dişçi' olabilir, alt küme koşulu sağlanır ancak eşleşme hassasiyeti düşüktür. Bu, çift kayıt riskini artırabilir. |
| D8 | plan.md / T5 Sync tasarımı / TaskStore.applySyncResponse | high | agreed | `user_item_orders` yanıtı tüm kapsamları (scope) içerir; plan yalnızca `scope: 'day', scope_id: 0` kayıtlarını kullanması gerektiğini açıkça belirtmiyor. `orderKeys` map'ine tüm scope'lardan gelen `order_key` değerleri yazılırsa, proje sırası Today sıralamasını bozar; M1 kabul testi başarısız olabilir. |
| D9 | plan.md / T7 / DateUtil.parseGmtOffset | high | agreed | Todoist v1 `tz_info.gmt_string` alanı genellikle `GMT+03:00` biçimindedir; plan yalnızca `+03:00` biçimini parse ediyor. `parseGmtOffset('GMT+03:00')` null dönerse kullanıcı saat dilimi ofseti yanlış hesaplanır, Today sınıflandırması kayar (özellikle sistem saat dilimi farklıyken). |
| D10 | plan.md / T7 (Saat dilimi ve due ayrıştırma) | high | resolved | Sabit saat dilimli (`...Z`) görevlerde `parseDue` dönüşümü, `offsetMin` olarak senkron anındaki ofseti kullanır. DST uygulayan bölgelerde, görev tarihi farklı bir DST dönemindeyse (ör. yazın kış tarihli görev) gerçek yerel saatten 1 saat sapma oluşur; gece yarısına yakın görevler yanlış güne atanabilir. Plan yalnızca sistem saati farklıyken '≤ 5 dk sapma' kabul ediyor; bu ise kalıcı ve senkron aralığından bağımsız bir sınıflandırma hatasıdır. |
| D11 | plan.md / T5 Sync tetikleyicileri / T6 Hesap değişimi / T8 TOKEN_SET | high | resolved | Token değiştiğinde `TOKEN_SET` olayı `syncNow` tetikler; ancak senkron döngüsü önce kuyruktaki komutları (quick_add ve item_close) gönderir. Yeni token farklı bir Todoist hesabına aitse, eski hesabın kuyruğundaki komutlar yeni hesaba uygulanabilir (yanlış görev kapatma veya ekleme). Plan hesap farklılığını yalnızca senkron yanıtındaki `user.id`'yi gördükten sonra tespit edip kuyruğu temizlemektedir; bu durumda komutlar çoktan gönderilmiş olur. |

## Madde Geçmişi

### D1 — agreed

**Öneri:** Adım 0'ı Q1 ve Q2 kapanana kadar başlatmayın; migration planına açık bir ön koşul maddesi ekleyin ('Q1/Q2 çözülmeden Adım 0 başlamaz'). Alternatif olarak Adım 0'ı metadata.json hariç diğer iskelet dosyalar olarak daraltın.

- Tur 1 · deepseek · raise: Adım 0, metadata.json'u T1 şablonuyla oluşturmayı içeriyor; ancak Q2'de KPlugin.Id ve GitHub kullanıcı adı 'adım 0'dan önce kesinleşmeli' deniyor. Bu karar verilmeden metadata.json'daki KPlugin.Id, Website, BugReportUrl alanları gerçek değerlerle doldurulamaz. KPlugin.Id sonradan değiştirilemeyeceği için geçici veya yanlış bir değerle başlamak risklidir. Ayrıca i18n script'leri Id'yi okuduğu için Q2 çözülmeden bu script'ler de test edilemez.
- Tur 1 · claude · accept: Migration Plan'a Adım 0'dan önce açık 'Ön koşul' eklendi: Q1 ve Q2 kapanmadan Adım 0 başlamaz (Id değişmez; i18n domain, Website/BugReportUrl ona bağlı).
- Tur 2 · deepseek · withdraw: Ön koşul metni eklendi; Q1/Q2 kapanmadan Adım 0 başlamaz, metadata.json Id bağımlılığı çözüldü.

### D2 — agreed

**Öneri:** sync_token geçersizliğini komut varlığından bağımsız ele alın: `client` hatası ve yanıt gövdesinde `INVALID_SYNC_TOKEN` veya benzeri bir işaret varsa sync_token='*' ile tek seferlik tam sync planlayın. Bu istekte komut gönderilemiyorsa önce tam sync ile token tazeleyip ardından kuyruğu flush edin. Bu durum için bir test vakası ekleyin.

- Tur 1 · deepseek · raise: Geçersiz sync_token işleme kuralı yalnızca 'komut yokken' tam sync reset öngörüyor. Komutlar (item_close) ile gönderilen istek 400 dönerse sync_token geçersiz olabilir; ancak koşul sağlanmadığı için reset yapılmaz ve kuyruk korunur. Sonraki denemeler aynı geçersiz token ve aynı komutlarla tekrarlanır; kullanıcı işlemleri sonsuza kadar bekler.
- Tur 1 · claude · accept: T5 adım 6 yeniden yazıldı: tüm istek client(4xx, 401/403/429 hariç) dönerse komut varlığından bağımsız izolasyon prosedürü — (a) komutsuz sync_token='*' tam sync, (b) başarılıysa batch bir kez yeniden; yine client ise batch düşürülür (dropBatch), (c) okuma da client ise ERROR+backoff. v1 dokümanı geçersiz token için ayrı error_tag belgelemediğinden etikete güvenilmiyor. Adım 5'e vaka 7-9 eklendi.
- Tur 2 · deepseek · withdraw: T5 adım 6 izolasyon prosedürü komut varlığından bağımsız hale getirildi; test vakaları eklendi.

### D3 — agreed

**Öneri:** Masaüstü görünürlüğü için somut bir sinyal/özellik belirtin (ör. `Plasmoid.status === PlasmaCore.Types.Active` veya görünürlük değişimi) ve bu tetiği Adım 7'nin manuel test listesine ekleyin. Eğer böyle bir sinyal yoksa bu satırı çıkarıp yalnızca periyodik tetikleyiciye dayanın.

- Tur 1 · deepseek · raise: Tetik tablosunda 'Popup açıldı (expanded → true) / masaüstünde widget görünür oldu' deniyor; ancak masaüstünde widget'ın görünür olduğunu algılayacak mekanizma belirtilmemiş. PlasmoidItem masaüstünde sürekli yüklü olabilir; yalnızca `expanded` sinyali panel popup içindir. Bu tetik uygulanamazsa masaüstü widget'ında 'açılınca anında senkron' başarı ölçütü karşılanamayabilir.
- Tur 1 · claude · accept: Masaüstünde güvenilir görünürlük sinyali yok; tetik tablosu ayrıldı: panelde expanded→true, masaüstünde FullRepresentation kökündeki HoverHandler.hovered→true (son sync >30 sn ise). Başarı ölçütü 1 buna göre güncellendi, M23 manuel testi eklendi.
- Tur 2 · deepseek · withdraw: Masaüstü tetikleyici HoverHandler olarak somutlaştırıldı, başarı ölçütü ve M23 güncellendi.

### D4 — agreed

**Öneri:** `Plasmoid.configuration.apiToken` değişikliklerini izleyen (örn. `onApiTokenChanged` veya KConfig nesnesi bağlantısı) ve doğrulayıp aynı durum makinesi olayını yayan açık bir mekanizma ekleyin. ConfigAccount akışı için de M18'e benzer bir manuel test tanımlayın.

- Tur 1 · deepseek · raise: Token iki yoldan değiştirilebilir: SetupView (widget içi) ve ConfigAccount (ayarlar penceresi). T8 yalnızca `TOKEN_SET` olayını tanımlıyor; ancak ConfigAccount'ta token değiştiğinde SyncController'ın bu değişikliği nasıl algılayıp `TOKEN_SET`/`TOKEN_CLEARED` üreteceği belirtilmemiş. Sadece SetupView butonuna bağlı kalınırsa, kullanıcı ayarlar penceresinden token girdiğinde senkron tetiklenmez.
- Tur 1 · claude · accept: T9'a madde 5 eklendi: tek doğruluk kaynağı Plasmoid.configuration.apiToken; main.qml'de Connections/onApiTokenChanged → TOKEN_CLEARED/TOKEN_SET. Doğrulanmamış token ayarlardan Apply edilirse ilk 401 → AUTH_INVALID. T8'de TOKEN_SET artık 'herhangi' durumdan (uçuştaki isteği iptal eder). M22 eklendi.
- Tur 2 · deepseek · withdraw: Token değişikliği single source of truth ile izleniyor; Connections onApiTokenChanged ve M22 eklendi.

### D5 — agreed

**Öneri:** Bir döngüde gönderilecek quick_add sayısına bir sınır koyun (ör. 20) ve kalanı sonraki döngüye bırakın. Her quick_add yanıtı `rate` ise `Retry-After`'a uyup döngüyü sonlandırın. Bu akış için bir test senaryosu ekleyin.

- Tur 1 · deepseek · raise: Çevrimdışıyken birikmiş quick_add girdileri 'tek tek' POST /tasks/quick ile gönderiliyor; ancak bu isteklerin sayısına bir üst sınır veya rate limit (429) yönetimi belirtilmemiş. Uzun süre çevrimdışı kalıp onlarca/yüzlerce görev eklenirse, tek bir sync döngüsünde onlarca REST çağrısı yapılır; bu süreyi uzatır, 429 tetikleyebilir ve `inFlight` kilidi altında uzun süre kalınmasına yol açar.
- Tur 1 · claude · accept: T5 adım 1: döngü başına en fazla 10 quick add (FIFO), kalan 1 sn sonra sonraki döngüye; rate/network/auth/server yanıtında quick add aşaması o döngüde durur, sonuç SyncMachine'e QUICK_ADD_DONE olarak verilir, 429'da Retry-After'a uyulur ve sync isteği atlanır. Adım 5 vaka 11.
- Tur 2 · deepseek · withdraw: Quick add döngü limiti 10 ile sınırlandı, rate handling ve test vakası eklendi.

### D6 — agreed

**Öneri:** SyncController'ı ince bir QML sarmalayıcı olarak tutup karar mantığını büyük ölçüde saf `SyncMachine`'e bırakın. Timer/XHR'ı sahte nesnelerle değiştirilebilir hale getirip en azından controller'ın effect sırasını test eden bir test katmanı ekleyin veya QML test runner kullanın.

- Tur 1 · deepseek · raise: SyncController (Adım 7) eşzamanlılık ve zamanlayıcı mantığı içerdiği hâlde yalnızca manuel M3–M10 ile doğrulanıyor; otomatik test yok. Tek uçuş, coalesce, debounce, gün dönümü tick'i ve backoff gibi davranışlar manuel testlerde deterministik değildir; yarış koşulları gözden kaçabilir.
- Tur 1 · claude · accept: Kısmen öneri doğrultusunda: tek uçuş, coalesce, debounce, min aralık, recovery, follow-up kararlarının tamamı saf SyncMachine'e taşındı (zaman damgalı olaylar, effect listesi) ve Adım 5'te 13 vakalı Node testleriyle kapsandı; Adım 5 artık opus yazar. SyncController yalnızca effect→Timer/XHR/LocalStorage eşleyicisi (karar mantığı yok, review kontrolü). QML test runner eklenmedi: Plasma import'ları CI'de çözülemiyor — Adım 7'de gerekçesi yazıldı.
- Tur 2 · deepseek · withdraw: Eşzamanlılık kararları saf SyncMachine'e taşındı ve 13 Node testiyle kapsandı; controller thin eşleyici.

### D7 — agreed

**Öneri:** Eşleştirmede Unicode-aware case folding ve basit normalizasyon uygulayın (QV4'te sınırlıysa en azından İngilizce lower case). Tarih/proje/etiket parçalarını çıkarıp yalnızca anlamlı kelimelere göre karşılaştırın.

- Tur 1 · deepseek · raise: `resolveUncertain` eşleştirme kuralı `plainTitle(content)` kelimelerinin girdi metninin kelimelerinin alt kümesi olmasına dayanıyor. Büyük/küçük harf ve Türkçe karakter normalizasyonu belirtilmemiş. Örneğin 'Dişçi' ile 'dişçi' eşleşmeyebilir; ayrıca metin 'yarın 15:00 dişçi' gibi tarih/proje içerirken içerik yalnızca 'dişçi' olabilir, alt küme koşulu sağlanır ancak eşleşme hassasiyeti düşüktür. Bu, çift kayıt riskini artırabilir.
- Tur 1 · claude · accept: resolveUncertain netleştirildi: added_at penceresi [sentAt−120 sn, sentAt+600 sn], normWords = toLowerCase (QV4 Unicode farkındalı; iki taraf aynı fonksiyondan geçer), noktalama silme, Quick Add token'larının (#, @, /, +, p1-p4, !!n, !…, {…}, // sonrası) çıkarılması; içerik kelime kümesi boş olmamalı; birden çok adayda en yakın added_at. Tarih kelimeleri dil bağımsız çıkarılamadığından alt küme kuralıyla tolere ediliyor.
- Tur 2 · deepseek · withdraw: normWords detaylandı, token ve noktalama temizliği netleştirildi; düşük risk kabul edilebilir.

### D8 — agreed

**Öneri:** `TaskStore.applySyncResponse` içinde `user_item_orders` dizisini `scope === 'day' && scope_id === 0` koşuluyla filtreleyip yalnızca bu kayıtları `orderKeys`'e ekleyin. `is_deleted` olanları silerken de bu filtre uygulanmalı. Adım 3 test listesine farklı scope'lara sahip örnek fixture ekleyin.

- Tur 2 · deepseek · raise: `user_item_orders` yanıtı tüm kapsamları (scope) içerir; plan yalnızca `scope: 'day', scope_id: 0` kayıtlarını kullanması gerektiğini açıkça belirtmiyor. `orderKeys` map'ine tüm scope'lardan gelen `order_key` değerleri yazılırsa, proje sırası Today sıralamasını bozar; M1 kabul testi başarısız olabilir.
- Tur 2 · claude · accept: T5'te user_item_orders açıklamasına scope filtresi eklendi (yalnız scope==='day' && scope_id===0 işlenir, ekleme ve silmede). Adım 3'e vaka 8b (farklı scope kaydı yok sayılır) eklendi.
- Tur 3 · deepseek · withdraw: Düzeltme yeterli: T5'e kapsam filtresi (scope === 'day' && scope_id === 0) eklenmiş, Adım 3'e 8b test vakası işlenmiş.

### D9 — agreed

**Öneri:** `parseGmtOffset` fonksiyonunu baştaki 'GMT' önekini yok sayacak şekilde güncelleyin veya normalizasyon adımı ekleyin. Adım 2 testlerine 'GMT+03:00' ve 'GMT-03:30' girdilerini ekleyin; ayrıca manuel doğrulamada gerçek `tz_info.gmt_string` değerini kontrol edin.

- Tur 2 · deepseek · raise: Todoist v1 `tz_info.gmt_string` alanı genellikle `GMT+03:00` biçimindedir; plan yalnızca `+03:00` biçimini parse ediyor. `parseGmtOffset('GMT+03:00')` null dönerse kullanıcı saat dilimi ofseti yanlış hesaplanır, Today sınıflandırması kayar (özellikle sistem saat dilimi farklıyken).
- Tur 2 · claude · accept: v1 dokümanındaki örnekler '+01:00' / '-03:00' biçiminde (GMT öneki yok), yine de savunma amaçlı kabul edildi: yeni tzInfoOffset(tzInfo) önce sayısal hours/minutes'ı (sync user örneğinde mevcut), yoksa gmt_string'i kullanır; parseGmtOffset GMT/UTC önekini, +0300 ve +3 biçimlerini tolere eder. Adım 2'ye vaka 1b/1c eklendi; gerçek değer Adım 6 curl doğrulamasında kontrol edilir.
- Tur 3 · deepseek · withdraw: Düzeltme yeterli: parseGmtOffset GMT/UTC öneklerini ve +0300/+3 biçimlerini tolere eder hale getirilmiş, Adım 2'ye 1b/1c testleri eklenmiş.

### D10 — resolved

**Öneri:** Bu sınırlamayı Assumptions'a ve README'ye açıkça ekleyin (DST gözlemleyen dilimlerde gün sınırında sapma olabilir). Alternatif olarak, `timezone` alanını kullanarak basit DST kuralı uygulayın (ör. EU/US geçiş tarihleri) veya bu tür görevler için yalnızca UTC tarihini kullanıp saat bilgisini yok sayın. En azından, `timezone` DST uyguluyorsa, görev tarihindeki ofseti tahmin etmek için sabit bir tablo kullanılabilir.

- Tur 3 · deepseek · raise: Sabit saat dilimli (`...Z`) görevlerde `parseDue` dönüşümü, `offsetMin` olarak senkron anındaki ofseti kullanır. DST uygulayan bölgelerde, görev tarihi farklı bir DST dönemindeyse (ör. yazın kış tarihli görev) gerçek yerel saatten 1 saat sapma oluşur; gece yarısına yakın görevler yanlış güne atanabilir. Plan yalnızca sistem saati farklıyken '≤ 5 dk sapma' kabul ediyor; bu ise kalıcı ve senkron aralığından bağımsız bir sınıflandırma hatasıdır.
- Tur 3 · claude · accept: Geçerli. QV4 Date sistem tz kurallarını bildiğinden followSystem=true iken ofset her an için ayrı alınıyor: offsetAt(ms) = -new Date(ms).getTimezoneOffset(); parseDue/dayKeyAt artık offsetAt fonksiyonu alıyor (makeOffsetFn). Böylece farklı DST dönemindeki sabit dilimli görevler doğru güne düşer (Adım 2 vaka 6b). Sistem dilimi ≠ Todoist dilimi durumunda kalan iki sınır (DST geçişinde ≤5 dk, farklı DST dönemindeki sabit dilimli görevde ±1 saat) T7'de ve A6'da açıkça yazıldı, README 'Known limitations'a girecek; gömülü DST tablosu bakım yükü nedeniyle reddedildi.

### D11 — resolved

**Öneri:** Token değişikliğinde senkron başlatmadan önce, komutsuz bir istekle (`GET /user` veya `sync` with empty commands) yeni token'ın `user.id`'sini doğrulayın. Hesap farklıysa kuyruğu ve önbelleği temizleyip yeni hesap için tam senkron yapın; aynı hesapsa mevcut kuyruğu koruyup flush edin. Bu doğrulama adımı `TOKEN_SET` effect'ine eklenmeli ve Adım 5 testlerine vaka eklenmelidir.

- Tur 3 · deepseek · raise: Token değiştiğinde `TOKEN_SET` olayı `syncNow` tetikler; ancak senkron döngüsü önce kuyruktaki komutları (quick_add ve item_close) gönderir. Yeni token farklı bir Todoist hesabına aitse, eski hesabın kuyruğundaki komutlar yeni hesaba uygulanabilir (yanlış görev kapatma veya ekleme). Plan hesap farklılığını yalnızca senkron yanıtındaki `user.id`'yi gördükten sonra tespit edip kuyruğu temizlemektedir; bu durumda komutlar çoktan gönderilmiş olur.
- Tur 3 · claude · accept: T8'e verifyAccount akışı eklendi: TOKEN_SET → uçuştaki istek iptal, komutsuz GET /user; doğrulanana kadar hiçbir kuyruk komutu gönderilmez. ACCOUNT_VERIFIED aynı userId → kuyruk korunur ve flush; farklı → clearData sonra komutsuz tam sync; auth/network → AUTH_INVALID/OFFLINE (network'te doğrulama yeniden denenir). INIT'te doğrulama gerekmez (önbellek o token'la oluştu). T6 hesap değişimi paragrafı güncellendi, Adım 5'e vaka 14-16 eklendi.
