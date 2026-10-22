# Магазинчик

Кошелёк скидочных карт для iPhone: SwiftUI, SwiftData, iOS 26 и Liquid Glass. Открыли приложение у магазина — его карта уже первая, со штрихкодом.

## Запуск

Нужен **Xcode 26** (SDK iOS 26).

```bash
git clone <url этого репозитория>
cd magazinchik
open Magazinchik.xcodeproj
```

1. Схема **Magazinchik**, симулятор на iOS 26 → **⌘R**. Тесты логики — **⌘U**.
2. Для своего iPhone: Signing & Capabilities → Team → ваша команда; при конфликте поменяйте Bundle ID `ru.magazinchik.app`.
3. Геолокация в симуляторе: Features → Location → Custom Location рядом с магазином. Сканер и камера работают только на устройстве, «Из фото» — и в симуляторе.

> Проект пока не собирался в Xcode: код писался на Linux. Логика из `Core/` и тесты к ней проверены на Swift 6.1.2. При первой сборке возможны мелкие правки API.

## Синхронизация

Карты и «Мои места» можно переносить между телефонами через Firebase Auth и Cloud Firestore на бесплатном плане Spark. Фото, картинки штрихкодов и каталог магазинов OpenStreetMap не уходят с телефона: в новом городе точки сети скачиваются снова.

Без `GoogleService-Info.plist` приложение запускается и работает как раньше, только на этом телефоне.

1. Создайте проект в [Firebase console](https://console.firebase.google.com/) на плане Spark.
2. Добавьте iOS-приложение с bundle id `ru.magazinchik.app`.
3. Authentication → Sign-in method → включите Email/Password и Google.
4. Создайте базу Cloud Firestore.
5. Опубликуйте `firestore.rules` из корня репозитория (правила Firestore в консоли или `firebase deploy --only firestore:rules`).
6. Скачайте `GoogleService-Info.plist` и положите его в папку `Magazinchik/`, рядом с `GoogleService-Info.plist.example`. Сам plist в git не входит.
7. Соберите приложение ещё раз. В настройках откройте «Войти», создайте аккаунт, затем на втором телефоне войдите с той же почтой.

Cloud Storage, Cloud Functions и план Blaze не нужны. Вход по почте и паролю. «Продолжить с Google» читает `CLIENT_ID` из plist и скрывается, если его нет. Сборка прописывает `REVERSED_CLIENT_ID` как URL scheme, чтобы Google мог вернуть в приложение.

## Что умеет

- **Карта по геолокации.** Точки магазинов карта получает двумя способами: свои — кнопкой «Я сейчас здесь» или поиском адреса, магазины сети — поиском MapKit по названию в радиусе 5 км. Если вы ближе 200 м к одной из точек, карта встаёт первой во вкладке «Рядом» и подсвечивается во «Все».
- **Добавление.** Вручную; сканером (VisionKit); со снимка или фото из галереи (Vision: штрихкод или QR, а без кода — номер распознаётся по тексту).
- **Карта крупно.** QR, Code 128, PDF417, Aztec, EAN-13 и EAN-8 на белой плашке, яркость экрана на максимум.
- **Свой порядок.** Удерживайте карту и перетащите. Порядок сохраняется.
- **Сетка.** От 1 до 4 колонок, выбор запоминается.

## Структура

```
Magazinchik.xcodeproj
Magazinchik/
  App/        вход, вкладки, демо-данные для превью
  Core/       чистая логика: EAN-кодер, ранжирование по расстоянию, номер из OCR, порядок
  Models/     SwiftData: LoyaltyCard, StoreLocation
  Sync/       Firestore: карты и свои места
  Location/   геолокация и поиск магазинов сети (MapKit)
  Design/     тема, штрихкоды, яркость, стеклянные кнопки
  Features/   Рядом, Все, карта крупно, редактор
MagazinchikTests/   тесты Core (Swift Testing)
.agents/skills/     дизайн-скиллы для агентов (taste, apple-design, web-design-guidelines)
```
