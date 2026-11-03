# Уведомления для AFK-сундука

Используется Android-версия Notification Scheduler 6.0 (MIT):
https://github.com/godot-mobile-plugins/godot-notification-scheduler/releases/tag/v6.0
Лицензия — файл LICENSE рядом. AAR-файлы и исходный интерфейс GDScript взяты из
официального архива NotificationSchedulerPlugin-Android-v6.0.zip. Из манифестов AAR удалены неиспользуемые разрешения SCHEDULE_EXACT_ALARM и REQUEST_IGNORE_BATTERY_OPTIMIZATIONS; внутренние получатели уведомлений закрыты для других приложений.

Модуль подключается через Android Gradle build. Игра не запрашивает разрешения на
точные будильники и отключение оптимизации батареи. Android может отложить показ
уведомления. После входа, получения сундука и открытия кампании уведомление
перепланируется по серверному времени заполнения. Разрешение на уведомления
запрашивается кнопкой в кампании.
