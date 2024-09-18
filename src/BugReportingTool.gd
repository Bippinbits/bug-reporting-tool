extends PanelContainer
class_name BugReportingTool
# Bug Reporting Tool - by Raffaele Picca: twitter.com/MV_Raffa

@export var config : BugReportingConfig

var report_hash:String = ""
var screenshot_data := Image.new()
var include_data:bool = true
var backend : BugReportingBackendFacade = null

@onready var data_button = $Content/Form/Checkbox/DataCheckboxButton
@onready var timer = $TimeoutTimer
@onready var http = HTTPClient.new()
@onready var long_text = $Content/Form/LongDescEdit
@onready var contact_text = $Content/Form/ContactEdit
@onready var send_button = $Content/Form/Custom/Send
@onready var feedback = $Content/Feedback/feedback_label
@onready var close_button = $Content/Feedback/close_button
@onready var close_form_button = $Content/HeaderLabel/CloseFormButton
@onready var type_box = $Content/Form/Type
@onready var main_window = get_parent().get_parent()

func _ready():
	backend = create_backend()
	if config.categories.size() > 0:
		for i in range(config.categories.size() ):
			type_box.add_item(config.categories[i], i)
		type_box.selected = 0
	else:
		type_box.hide()

func create_backend() -> BugReportingBackendFacade:
	match(config.backend):
		BugReportingConfig.BackendType.Trello:
			return BugReportingBackendTrello.new()
	
	return BugReportingBackendDummy.new()

func show_window():
	screenshot_data = get_viewport().get_texture().get_data()
	screenshot_data.flip_y()
	main_window.show()
	report_hash = str( round(hash(str(Time.get_datetime_string_from_system()) + OS.get_unique_id() )*0.00001) )
	data_button.text = "X"
	include_data = true
	$Content/Form.show()
	$Content/Feedback.hide()
	long_text.grab_focus()
	long_text.text = ""
	send_button.set_disabled(true)
	close_form_button.set_disabled(false)
	type_box.selected = 0

func _on_Send_pressed():
	close_form_button.set_disabled(true)
	show_feedback()
	dispatch()

func dispatch():
	var args = DispatchArgs.new()
	args.node = self
	args.config = config
	args.title = long_text.text.left(15)
	args.message = long_text.text
	args.report_hash = report_hash
	args.callback = change_feedback
	args.details = collect_info()
	args.attachments = collect_attachments()
	backend.dispatch(args)

func collect_attachments() -> Array[Attachment]:
	var r : Array[Attachment] = []
	r.append(BugReportingTool.Attachment.from_image(screenshot_data, report_hash+"_screenshot"))
	if include_data:
		var logs = get_latest_logs()
		if not logs.is_empty():
			r.append( BugReportingTool.Attachment.from_path(logs[0]) )
			if logs.size() > 1:
				r.append( BugReportingTool.Attachment.from_path(logs[1]) )
	
	#add game-specific attachments here
	#savefiles, meta-files etc
	
	return r
	
func collect_info() -> Array[String]:
	var r : Array[String] = []
	r.append("User Contact:" + contact_text.text)
	r.append("Graphics Adapter: " + RenderingServer.get_video_adapter_name() + " ( " + RenderingServer.get_video_adapter_vendor() + " )")
	r.append("Operating System: " + OS.get_name() )
	
	#add game-specific infos here
	#version, difficulty, mission,settings etc
	return r

func _input(event):
	if not main_window.visible:
		return
	if event.is_action_pressed("ui_end") or event.is_action_pressed("ui_cancel") and not close_form_button.disabled:
		main_window.hide()
		get_tree().set_input_as_handled()

func show_feedback():
	#disable all input fields and show a short message about the current status
	$Content/Form.hide()
	$Content/Feedback.show()
	change_feedback("Your feedback is being sent...", true)

func change_feedback(new_message: String, close_button_disabled: bool = false) -> void:
	feedback.text = new_message
	close_form_button.set_disabled(close_button_disabled)
	close_button.set_disabled(close_button_disabled)
	close_button.text = "Please wait" if close_button_disabled else "Close"
	close_button.grab_focus()

func _on_LongDescEdit_text_changed() -> void:
	update_send_button()

func update_send_button() -> void:
	# check if text is entered, if not, disable the send button
	send_button.set_disabled(long_text.text == "")

func _on_close_button_pressed():
	main_window.hide()

func get_latest_logs():
	var reports = dir_contents("user://logs/")
	if reports.is_empty():
		return null
	return reports

func dir_contents(path:String):
	var dir = DirAccess.open(path)
	var found_files := []
	
	if dir != null:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while (file_name != ""):
			if dir.current_is_dir() and !file_name.begins_with("."):
				dir_contents(path+file_name)
				
			elif !file_name.begins_with(".") and file_name.get_extension() == "log":
				found_files.append(path+"/"+file_name)
			
			file_name = dir.get_next()
	dir.list_dir_end()
	return found_files

func _on_CloseFormButton_pressed():
	main_window.hide()

func _on_DataCheckboxButton_pressed():
	include_data = !include_data
	data_button.text = "X" if include_data else ""

class DispatchArgs:
	var node:Node
	var callback:Callable
	var config:BugReportingConfig
	
	var report_hash:String
	var title:String
	var message:String
	var details: Array[String]
	var attachments:Array[Attachment]

class Attachment:
	# XXX: This is to prevent reference cycles (and thus memleaks), see:
	# https://github.com/godotengine/godot/issues/27491
	class Struct:
		var filename: String
		var mimetype: String
		var data: PackedByteArray

	static func from_path(path: String) -> Attachment.Struct:
		var obj = Attachment.Struct.new()
		obj.filename = path.get_file()

		match path.get_extension():
			'png':
				obj.mimetype = 'image/png'
			'jpg', 'jpeg':
				obj.mimetype = 'image/jpeg'
			'gif':
				obj.mimetype = 'image/gif'
			'txt', 'log':
				obj.mimetype = 'text/plain'
			_:
				obj.mimetype = 'application/octet-stream'

		var file = FileAccess.open(path, FileAccess.READ)
		if file == null:
			return null
		obj.data = file.get_buffer(file.get_length())
		file.close()
		return obj

	static func from_image(img: Image, name: String) -> Attachment.Struct:
		img.shrink_x2()
		var obj = Attachment.Struct.new()
		obj.filename = name + '.png'
		obj.mimetype = 'image/png'
		obj.data = img.save_png_to_buffer()
		return obj
	
	
	static func from_string(string: String, name: String) -> Attachment.Struct:
		var obj = Attachment.Struct.new()
		obj.filename = name + '.txt'
		obj.mimetype = 'text/plain'
		obj.data = string.to_utf8_buffer()
		return obj
