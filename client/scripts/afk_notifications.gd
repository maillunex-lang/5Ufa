extends Node
## Android-уведомление о заполнении AFK-сундука; время берём из ответа сервера.

const NOTIFICATION_ID := 4101
const CHANNEL := "afk_chest"
var _scheduler: NotificationScheduler
var _ready_android := false
var _status: Dictionary = {}

func _ready() -> void:
	if OS.get_name() != "Android":
		return
	_scheduler = NotificationScheduler.new()
	add_child(_scheduler)
	_scheduler.initialization_completed.connect(_initialized)
	_scheduler.post_notifications_permission_granted.connect(func(_permission): _schedule())
	_scheduler.initialize()

func _initialized() -> void:
	_ready_android = true
	_schedule()

func permission_enabled() -> bool:
	return _ready_android and _scheduler.has_post_notifications_permission()

func request_permission() -> void:
	if _ready_android:
		_scheduler.request_post_notifications_permission()

func update_status(status: Dictionary) -> void:
	_status = status.duplicate()
	_schedule()

func refresh() -> void:
	if OS.get_name() != "Android":
		return
	var response: Dictionary = await Api.request_json(HTTPClient.METHOD_GET, "/api/v1/campaign")
	if response.ok:
		update_status(response.data)

func _schedule() -> void:
	if not _ready_android or not _scheduler.has_post_notifications_permission() or _status.is_empty():
		return
	_scheduler.cancel(NOTIFICATION_ID)
	var remaining: int = int(_status.get("cap_seconds", 0)) - int(_status.get("elapsed_seconds", 0))
	if remaining <= 0:
		return
	var channel := NotificationChannel.new().set_id(CHANNEL).set_name("AFK-награды").set_description("Сундук с наградами заполнен").set_importance(NotificationChannel.Importance.DEFAULT)
	_scheduler.create_notification_channel(channel)
	var notification := NotificationData.new().set_id(NOTIFICATION_ID).set_channel_id(CHANNEL).set_title("Сундук заполнен").set_content("AFK-награды ждут вас в игре.").set_delay(remaining)
	_scheduler.schedule(notification)
