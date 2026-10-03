# Architecture Plan: todoist-plasma v2.1 (kullanım kolaylıkları)

**Status:** in progress
**Revision:** 1
**Temel:** [v1 planı](todoist-today-plan.md) (sync, kuyruk, durum makinesi) ve [v2 planı](todoist-plasma-v2-plan.md)
(listeler). Bu plan yalnız eklemeleri anlatır; önceki kararlar geçerlidir.

Kaynak: benzer projelerden derlenen 11 öneri (GNOME todoist-indicator, KDE Store "To Do" widget'ları,
Todoist macOS global Quick Add, Raycast Todoist eklentisi, Todoist Android widget'ları). Kullanıcı hepsini istedi.

## Özellikler ve tasarım kararları

| # | Özellik | Uygulama | Not |
|---|---|---|---|
| F1 | Global kısayolla görev ekleme | Plasma'nın widget kısayolu (Ayarlar → Keyboard Shortcuts) `Plasmoid.activated` sinyalini verir → popup açılır, "New task" alanı odaklanır | Üçüncü parti widget varsayılan kısayol atayamaz; README'de anlatılır |
| F2 | Arka plan / saydamlık | `Plasmoid.backgroundHints = DefaultBackground \| ConfigurableBackground` → düzenleme modunda Plasma'nın kendi "arka planı göster" seçeneği | Ek ayar yok (yerli kontrol) |
| F3 | Hesap paylaşımı | Bağlanan widget hesabı (token, ad, kullanıcı id) LocalStorage'da `_shared` satırına yazar; başka bir örneğin kurulum ekranı "Use the connected account (Ad)" sunar | **Önbellek/kuyruk paylaşılmaz:** saf QML'de örnekler arası kilit/IPC yok; ortak kuyruk eşzamanlı yazımda kayıt kaybeder. Token ikinci bir yerde (aynı kullanıcı dizini, düz metin) saklanır — v1'deki tradeoff ile aynı seviye, README'de yazılır |
| F4 | Deadline | item `deadline.date` → satırda bayrak + göreli tarih (bugün/geçmişse kırmızı) | Düzenleme yok |
| F5 | Bildirimler | Saatli görevlerden `notifyLeadMinutes` (vars. 10; 0 = kapalı) önce Plasma bildirimi; eylemler *Complete* ve *Remind me in 10 min* (yerel erteleme). Planlama saf `Reminders.js`; bildirim `org.kde.notification` QML ile, **Loader** içinde (modül yoksa widget yine çalışır). Tekrar önleme: gönderilen anahtarlar (`id|tarih|dakika`) LocalStorage `_shared/notified`'da → panel + masaüstü aynı bildirimi iki kez göstermez | Todoist'in kendi hatırlatıcıları (Pro) ayrı; widget yalnız görevin saatine bakar |
| F6 | Tamamlamayı geri alma | `close` girdisi 4 sn `sendAfter` ile tutulur (silmedeki gibi); footer "Completed “X” · Undo" | Telefona yansıma ~4 sn gecikir (başarı ölçütü 2 güncellenir: ≤ 6 sn) |
| F7 | Klavye | Liste odaktayken: ↑/↓ gezin, Space tamamla, E/F2 düzenle, T tarih menüsü, 1–4 öncelik, Delete sil, Enter Todoist'te aç, Q veya / yeni görev alanı | Todoist web kısayollarına yakın |
| F8 | Kaydedilmemiş filtre sorgusu | Ayarlarda "Custom filter" (ad + sorgu) → listede "query" görünümü; filtrelerle aynı sunucu yolu (`/tasks/filter`) | Raycast menü çubuğu filtresi gibi |
| F9 | Alt görev aç/kapa + ayrıntı | Proje/Inbox listesinde ebeveynde ok; kapalı ebeveynler LocalStorage'da (örnek başına). Açıklama 2000 karaktere kadar saklanır; açıklama satırına tıklayınca tamamı açılır | |
| F10 | Günlük hedef halkası | `GET /api/v1/tasks/completed/stats` (15 dk'da bir, sync döngüsü içinde) → bugünkü tamamlanan / `goals.daily_goal`; küçük görünümde ve Today başlığında halka | Uç nokta şekli doğrulanmadı → savunmacı ayrıştırma; başarısızsa halka gizlenir |
| F11 | KRunner | `krunner/`: Python D-Bus runner (`org.kde.krunner1`), `todo <metin>` → Quick Add; `todo ?<arama>` → açık görevlerde arama (sunucu `search:` filtresi), Enter tamamlar / Todoist'te açar. Token: widget'ın appletsrc kaydından okunur | **İsteğe bağlı ayrı bileşen** (python3-dbus, python3-gobject); `.plasmoid`'e girmez, `krunner/install.sh` ile kurulur |

## Değişen başarı ölçütü

- v1 ölçüt 2: "widget'taki tamamlama ≤ ~2 sn'de telefona" → tamamlama geri alınabilir olduğu için **≤ 6 sn**.
  Ekleme/düzenleme değişmez.

## Doğrulama

Saf mantık (Reminders, deadline, collapse, query görünümü, undo hold, stats ayrıştırma, runner yardımcıları)
Node/Python birim testleriyle; QML offscreen duman testiyle. Gerçek Plasma + token ile: F1 kısayol, F2 arka
plan, F5 bildirim eylemleri, F10 uç nokta, F11 KRunner — manuel kabul listesi M-v21-1…8 (aşağıda).

## Manuel kabul (v2.1)

- M-v21-1 Widget'a Meta+T ata → başka uygulamadayken bas → popup açık, imleç "New task"te.
- M-v21-2 Düzenleme modunda arka planı kapat/aç; masaüstünde okunurluk.
- M-v21-3 Panel widget'ı bağlıyken masaüstüne ikinci widget ekle → kurulumda "Use the connected account".
- M-v21-4 Saati 2 dk sonraya olan görev, öncü süre 1 dk → bildirim; *Complete* tamamlar; panel+masaüstü varken tek bildirim.
- M-v21-5 Tamamla → 4 sn içinde Undo → görev geri gelir, telefonda hiç tamamlanmamış.
- M-v21-6 Klavye: ↓↓ Space, E, T, 2, Delete, Q.
- M-v21-7 Ayarlara `today & p1` yaz → "Custom filter" listesi web ile aynı.
- M-v21-8 KRunner: `todo Süt al yarın` → görev eklenir; `todo ?süt` → bulunur, Enter tamamlar.
