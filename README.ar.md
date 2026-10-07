# ثيم نجم لـ GRUB

ثيم GRUB بخط بكسلي وآيات عربية في الزوايا. داكن وهادئ وواضح على كل الدقات من 1024×768 حتى 4K والشاشات العريضة.

[English](README.md)

![ثيم نجم على دقة 1920×1080](docs/preview/hero.png)

كل الصور في المستودع من **GRUB حقيقي** (2.12) يعمل داخل QEMU، وليست تصاميم مرسومة.

## المميزات

- **15 دقة جاهزة**، وأي دقة أخرى `WxH` تُبنى عند الطلب. التخطيط والزخارف والخط كلها تتكبّر وتتصغّر معاً.
- **تخصيص أثناء التثبيت**: لون التمييز، الآيات (خمس أبيات كلاسيكية أو نصّك أنت)، شريط الاختصارات، شريط العدّ التنازلي، ومدة انتظار القائمة.
- **مثبّت واحد لكل التوزيعات**: يميّز `/boot/grub` من `/boot/grub2` و`grub-mkconfig` من `grub2-mkconfig`، ويكتشف دقة شاشتك الأصلية.
- **آمن**: ينسخ `/etc/default/grub` احتياطياً، ويعدّل كتلة محددة بعلامات فقط، ويتراجع إن فشل `grub-mkconfig`، و`--uninstall` يعيد ملفك كما كان.
- **بلا اعتماديات للشكل الافتراضي.** Python وPillow مطلوبان للتخصيص فقط، والمثبّت يقدر يجلبهما في بيئة افتراضية مؤقتة.

## التثبيت

```sh
git clone https://github.com/najm-labs/grub-theme.git
cd grub-theme
sudo ./install.sh
```

داخل الطرفية يبدأ معالج قصير (الدقة، اللون، الآيات، الإضافات، المهلة). أعد التشغيل بعد الانتهاء.

بدون أسئلة:

```sh
sudo ./install.sh -y                                   # اكتشاف الدقة تلقائياً، الشكل الافتراضي
sudo ./install.sh -y -r 2560x1440 --accent cyan --verse stars --timeout 5
sudo ./install.sh -y --no-verses --no-hints            # بسيط: القائمة والعدّ فقط
sudo ./install.sh --dry-run                            # يعرض ما سيحدث دون تغيير
sudo ./install.sh --uninstall                          # إزالة الثيم
```

يحتاج `bash` وأن يكون GRUB 2 هو محمّل الإقلاع (على Alpine: `apk add bash`).

الخيارات الكاملة: `./install.sh --help`. أهمها: `--accent` للون (`najm` `gold` `green` `cyan` `blue` `violet` `rose` `white` أو أي `#RRGGBB`)، و`--verse` للبيت، و`--vertical` مع `--horizontal` لنص عربي من عندك، و`--show-menu` لإظهار القائمة دائماً (Ubuntu تخفيها افتراضياً)، و`--export DIR` لكتابة الثيم فقط (NixOS والتغليف).

## معاينات

![الألوان](docs/preview/accents.png)

![التخطيطات والآيات](docs/preview/layouts.png)

![الدقات](docs/preview/resolutions.png)

## هل يعمل على توزيعتي؟

مكان GRUB يختلف بين التوزيعات والمثبّت يتعامل مع ذلك:

| العائلة | ملفات GRUB | إعادة التوليد |
| --- | --- | --- |
| Debian وUbuntu وMint وArch وManjaro وGentoo وVoid وAlpine | `/boot/grub` | `grub-mkconfig` |
| Fedora وRHEL وAlma وRocky وopenSUSE | `/boot/grub2` | `grub2-mkconfig` |
| NixOS | تصريحي (declarative) | يرفض ويشرح الطريقة، استخدم `--export` |
| systemd-boot وrEFInd | ليس GRUB | غير مدعوم |

ما جُرّب فعلاً: العرض في GRUB حقيقي داخل QEMU (BIOS وUEFI)، وتشغيل `grub-mkconfig` حقيقي على بيئة Ubuntu 24.04، ومنطق المثبّت على هياكل مجلدات Debian/Ubuntu وFedora وRHEL (`tests/test_install.sh`). بقية التوزيعات تتبع نفس الأعراف لكنها لم تُجرَّب على أجهزة حقيقية. إن واجهت مشكلة افتح issue مع ناتج `./install.sh --detect`.

## استكشاف الأخطاء

- **لا أرى الثيم عند الإقلاع.** كثير من التوزيعات تخفي القائمة. اضغط <kbd>Shift</kbd> (BIOS) أو <kbd>Esc</kbd> (UEFI) أثناء الإقلاع، أو أعد التثبيت مع `--show-menu`.
- **`bitmap file ... is of unsupported format`.** ملف في الثيم يشير إلى مسار صورة فارغ (مثل `desktop-image: ""`). المثبّت يفحص الثيم لمنع هذا؛ إن عدّلت `theme.txt` يدوياً فاحذف السطر الفارغ.
- **الخط صغير أو مختلف.** لم يُحمَّل ملف `.pf2`؛ أعد التوليد بـ `grub-mkconfig` ولا تكتفِ بنسخ الملفات.

## الاعتمادات والرخصة

الأبيات للمتنبي (`najm` و`ships` و`stars`) وأحمد شوقي (`dunya`) وأبي القاسم الشابي (`qadar`). النص العربي مرسوم بخط [Amiri](https://github.com/aliftype/amiri) (SIL OFL 1.1). تفاصيل الخطوط في [assets/fonts/NOTICE.md](assets/fonts/NOTICE.md).

الرخصة: [MIT](LICENSE)، عدا الخطوط الخارجية فلها رخصها.
