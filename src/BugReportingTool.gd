extends PanelContainer
class_name BugReportingTool
# Bug Reporting Tool - by Raffaele Picca: twitter.com/MV_Raffa

@export var config : BugReportingConfig

var report_hash:String = ""
var screenshot_data := Image.new()
var include_data:bool = true
var backend : BugReportingBackendFacade = null
var additional_attachments = {}

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
	%AttachmentsFileDialog.file_selected.connect(on_attachment_selected)
	
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
		BugReportingConfig.BackendType.Jira:
			return BugReportingBackendJira.new()
	
	printerr("BugReportingTool: Unimplemented Backend")
	return BugReportingBackendFacade.new()

func show_window():
	screenshot_data = get_viewport().get_texture().get_image()
	main_window.show()
	report_hash = str((hash(str(Time.get_datetime_string_from_system()) + OS.get_unique_id() )))
	include_data = true
	$Content/Form.show()
	$Content/Feedback.hide()
	long_text.grab_focus()
	long_text.text = long_text.placeholder_text
	send_button.set_disabled(true)
	close_form_button.set_disabled(false)
	type_box.selected = 0
	
	for x in additional_attachments:
		remove_attachment(x)
		
	main_window.scale = Vector2.ZERO
	var tw = create_tween()
	tw.tween_property(main_window,"scale", Vector2.ONE, 0.1)

func _on_Send_pressed():
	close_form_button.set_disabled(true)
	show_feedback()
	dispatch()

func dispatch():
	var args = DispatchArgs.new()
	args.node = self
	args.config = config
	args.title = (long_text.text as String).substr(10).left(15) #skip [Problem]
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
	
	BugReportingToolExtension.collect_additional_attachments(r)
	
	for x in additional_attachments:
		r.append(BugReportingTool.Attachment.from_path(x))
	return r
	
func collect_info() -> Array[String]:
	var r : Array[String] = []
	r.append("User Contact:" + contact_text.text)
	r.append("Graphics Adapter: " + RenderingServer.get_video_adapter_name() + " ( " + RenderingServer.get_video_adapter_vendor() + " )")
	r.append("Operating System: " + OS.get_name() )
	
	BugReportingToolExtension.collect_additional_infos(r)
	return r

func _input(event):
	if not main_window.visible:
		if event.is_action_pressed("send_feedback"):
			show_window()
			get_viewport().set_input_as_handled()
	else:
		if event.is_action_pressed("send_feedback") or event.is_action_pressed("ui_end") \
		or event.is_action_pressed("ui_cancel") and not close_form_button.disabled:
			main_window.hide()
			get_viewport().set_input_as_handled()

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

func _on_add_attachment_button_pressed() -> void:
	%AttachmentsFileDialog.show()

func _on_close_form_button_pressed() -> void:
	main_window.hide()

func on_attachment_selected(path:String):
	var size = get_file_size(path)
	var oversized = size > 2_000_000 #2MB
	if oversized:
		$ErrorDialog.popup_centered()
		return
	
	var box = HBoxContainer.new()
	var l = Label.new()
	l.text = path
	box.add_child(l)
	var b = Button.new()
	b.text = "Remove -"
	b.pressed.connect(func():remove_attachment(path))
	box.add_child(b)
	additional_attachments[path] =  box
	%AttachmentsVBox.add_child(box)

func remove_attachment(i):
	additional_attachments[i].queue_free()
	additional_attachments.erase(i)

func get_file_size(path: String) -> int:
	var file = FileAccess.open(path, FileAccess.ModeFlags.READ)
	
	if file:
		var size = file.get_length()
		file.close()
		return size
	else:
		return -1  # Return -1 if the file can't be opened

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
	var filename: String
	var mimetype: String
	var data: PackedByteArray

	static func from_path(path: String) -> Attachment:
		var obj = Attachment.new()
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

	static func from_image(img: Image, name: String) -> Attachment:
		img.shrink_x2()
		var obj = Attachment.new()
		obj.filename = name + '.png'
		obj.mimetype = 'image/png'
		obj.data = img.save_png_to_buffer()
		return obj
	
	static func from_string(string: String, name: String) -> Attachment:
		var obj = Attachment.new()
		obj.filename = name + '.txt'
		obj.mimetype = 'text/plain'
		obj.data = string.to_utf8_buffer()
		return obj
