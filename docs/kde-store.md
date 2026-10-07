# Publishing on the KDE Store

The KDE Store (store.kde.org, run on Pling) is where Plasma's **Get New Widgets…** dialog finds
widgets. Uploading needs a KDE Store account; nothing here can be automated from CI.

## What to upload

The `.plasmoid` file from the GitHub release (`todoist-plasma-<version>.plasmoid`), or build it
with `scripts/package.sh` (it lands in `dist/`). It is a zip with `metadata.json` at the root, so
Get New Widgets can install and update it.

## First upload

1. Sign in at https://store.kde.org (create an account if needed).
2. Your profile menu → **Add Product**.
3. Category: the **Plasma 6** widgets category ("Plasma 6 Applets"). Not the Plasma 5 one:
   the widget needs Plasma 6.
4. Fill in the fields below, add screenshots, then upload the `.plasmoid` under **Files**.
5. Publish. It shows up in Get New Widgets once the store has indexed it.

| Field | Value |
|---|---|
| Title | Todoist for Plasma |
| License | GPL-3.0-or-later (GPLv3) |
| Source / homepage | https://github.com/bahadirdemircioglu/today |
| Tags | todoist, tasks, todo, productivity, plasma6 |
| Version | the `Version` in `package/metadata.json` |

### Description (English)

> **Unofficial** Todoist widget for KDE Plasma 6, for the panel and the desktop.
>
> - Every Todoist list: Today, Upcoming, Inbox, projects (with sections and sub-tasks), labels and filters.
> - Quick Add with a live preview: dates and times (`tomorrow 3pm`, `12/10-15:00`), `#project` and `@label` suggestions, `p1`–`p4`. English and Turkish dates are understood whatever language your Todoist account uses.
> - Complete with one click (with undo); edit, reschedule with a calendar, change priority, move, delete. Reschedule all overdue tasks at once.
> - Works offline: changes are queued and sent when you are back online.
> - Reminders as Plasma notifications, daily goal ring, keyboard navigation, project colours.
> - Appearance settings: Todoist or Plasma priority colours, compact rows, translucent or no background on the desktop. English and Turkish UI.
>
> Needs a Todoist API token (Todoist → Settings → Integrations → Developer). The token is stored in your Plasma config file, unencrypted.
>
> Not affiliated with or endorsed by Doist. Todoist is a trademark of Doist.

### Açıklama (Türkçe)

> KDE Plasma 6 için **resmi olmayan** Todoist widget'ı; panelde ve masaüstünde çalışır.
>
> - Tüm Todoist listeleri: Bugün, Yaklaşan, Gelen Kutusu, projeler (bölümler ve alt görevlerle), etiketler ve filtreler.
> - Canlı önizlemeli hızlı ekleme: tarih ve saat (`yarın 15:00`, `12/10-15:00`), `#proje` ve `@etiket` önerileri, `p1`–`p4`. Türkçe tarihler Todoist hesabınızın dili ne olursa olsun anlaşılır.
> - Tek tıkla tamamlama (geri alınabilir); düzenleme, takvimle yeniden planlama, öncelik, taşıma, silme. Gecikmiş görevlerin hepsini tek seferde taşıma.
> - Çevrimdışı çalışır: değişiklikler sıraya alınır, bağlantı gelince gönderilir.
> - Plasma bildirimi olarak hatırlatmalar, günlük hedef halkası, klavyeyle gezinme, proje renkleri.
> - Görünüm ayarları: Todoist ya da Plasma öncelik renkleri, sıkı satırlar, masaüstünde yarı saydam ya da arka plansız görünüm. Türkçe ve İngilizce arayüz.
>
> Todoist API anahtarı gerekir (Todoist → Ayarlar → Entegrasyonlar → Geliştirici). Anahtar Plasma ayar dosyasında şifrelenmeden saklanır.
>
> Doist ile bağlantılı değildir. Todoist, Doist'in tescilli markasıdır.

## Screenshots

Use **real** screenshots of the widget (Spectacle, `Meta+Shift+Print` for a region), not the
design mock-ups in `docs/screenshots/`. A good set:

1. The panel popup on Today, light theme.
2. The same in a dark theme.
3. Quick Add with the preview (a date, a `#project` suggestion).
4. A project with sections and sub-tasks.
5. The desktop widget, ideally with the translucent background.
6. Settings → Appearance.

Hide anything private in the task list first (or use a test Todoist account).

## Updating

For every new version: bump `Version` in `package/metadata.json` (and `package.json`), release
as usual, then on the store product page → **Edit** → **Files**: upload the new `.plasmoid` and
set the version. Plasma offers the update in Get New Widgets → Updates.

The widget's `Id` (`io.github.bahadirdemircioglu.todoistplasma`) must never change, or Plasma
treats it as a different widget.
