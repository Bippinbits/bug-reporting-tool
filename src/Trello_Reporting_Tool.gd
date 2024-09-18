extends PanelContainer

# Trello Reporting Tool - by Raffaele Picca: twitter.com/MV_Raffa

# The URL pointing to the webserver location where "proxy.php" from this
# repository is served.
const PROXY_URL = "https://proxy.example/proxy.php"

# Internal constants, only change if you must ;-)
const POST_BOUNDARY: String = "GodotFileUploadBoundaryZ29kb3RmaWxl"
const URL_REGEX: String = \
	'^(?:(?<scheme>https?)://)?' + \
	'(?<host>\\[[a-fA-F0-9:.]+\\]|[^:/]+)' + \
	'(?::(?<port>[0-9]+))?(?<path>$|/.*)'

# If you don't want to use labels, just leave this dictionary empty, you can
# add as many labels as you need by just expanding the library.
#
# To find out the label ids, use the same way as with the list ids. look for
# the label ids in the Trello json.
var trello_labels = {
	0 : {
		"label_trello_id"	: "LABEL ID FROM TRELLO",
		"label_description"	: "Label name for Option Button"
	},
	1 : {
		"label_trello_id"	: "LABEL ID FROM TRELLO",
		"label_description"	: "Label name for Option Button"
	}
}

var report_hash:String = ""
var screenshot_data := Image.new()
var include_data:bool = true

onready var data_button = $Content/Form/Checkbox/DataCheckboxButton
onready var timer = $TimeoutTimer
onready var http = HTTPClient.new()
onready var long_text = $Content/Form/LongDescEdit
onready var contact_text = $Content/Form/ContactEdit
onready var send_button = $Content/Form/Custom/Send
onready var feedback = $Content/Feedback/feedback_label
onready var close_button = $Content/Feedback/close_button
onready var close_form_button = $Content/HeaderLabel/CloseFormButton
onready var type_box = $Content/Form/Type
onready var main_window = get_parent().get_parent()


func _enter_tree():
	_g.feedback_tool = self


func _ready():
	timer.set_wait_time(0.1)
	if !trello_labels.empty():
		for i in range(trello_labels.size()):
			type_box.add_item(trello_labels[i].label_description, i)
		type_box.selected = 0
	else:
		type_box.hide()


func show_window():
	#screenshot_data = get_viewport().get_texture().get_data()
	screenshot_data = _g.main_game.game_viewport.get_texture().get_data()
	screenshot_data.flip_y()
	main_window.show()
	report_hash = str( round(hash(str(OS.get_datetime()) + OS.get_unique_id() )*0.00001) )
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
	create_card()

class Attachment:
	# XXX: This is to prevent reference cycles (and thus memleaks), see:
	# https://github.com/godotengine/godot/issues/27491
	class Struct:
		var filename: String
		var mimetype: String
		var data: PoolByteArray

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

		var file = File.new()
		if file.open(path, File.READ) != OK:
			return null
		obj.data = file.get_buffer(file.get_len())
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
		obj.data = string.to_utf8()
		return obj


func create_post_data(key: String, value) -> PoolByteArray:
	var body: PoolByteArray = []
	var extra: String = ''
	var bytes: PoolByteArray = []

	if value is Array:
		for idx in range(0, value.size()):
			var newkey = "%s[%d]" % [key, idx]
			body += create_post_data(newkey, value[idx])
		return body
	elif value is Attachment.Struct:
		extra = '; filename="' + value.filename + '"'
		if value.mimetype != 'application/octet-stream':
			extra += '\r\nContent-Type: ' + value.mimetype
		bytes = value.data
	elif value != null:
		bytes = value.to_utf8()

	var buf = 'Content-Disposition: form-data; name="' + key + '"' + extra
	body += ('--' + POST_BOUNDARY + '\r\n' + buf + '\r\n\r\n').to_ascii()
	body += bytes + '\r\n'.to_ascii()
	return body

func send_post(_http: HTTPClient, path: String, data: Dictionary) -> int:
	var headers = [
		'Content-Type: multipart/form-data; boundary=' + POST_BOUNDARY,
	]

	var body: PoolByteArray = []
	for key in data:
		body += create_post_data(key, data[key])
	body += ('--' + POST_BOUNDARY + '--\r\n').to_ascii()

	return _http.request_raw(HTTPClient.METHOD_POST, path, headers, body)

func parse_url(url: String) -> Dictionary:
	var regex = RegEx.new()

	if regex.compile(URL_REGEX) != OK:
		return {}

	var re_match = regex.search(url)
	if re_match == null:
		return {}

	var scheme = re_match.get_string('scheme')
	if not scheme:
		scheme = 'http'

	var port: int = 80 if scheme == 'http' else 443
	if re_match.get_string('port'):
		port = int(re_match.get_string('port'))

	return {
		'scheme': scheme,
		'host': re_match.get_string('host'),
		'port': port,
		'path': re_match.get_string('path'),
	}

func create_card():
	var title_text = long_text.text.left(15)
	var descr_text = "**Gameversion:** " + _g.version_number + "\n"
	descr_text += "**Wave:** " + str(_g.spawner.wave_counter) + "\n"
	descr_text += "**Difficulty:** " + _g.get_difficulty_as_text() + "\n"
	descr_text += "**Graphics Adapter:** " + VisualServer.get_video_adapter_name() + " ( " + VisualServer.get_video_adapter_vendor() + " )\n"
	descr_text += ("**Window Resolution:** " + str(Settings.resolution_setting) + "\n" +
	"**Screen Resolution:** " + str( OS.get_screen_size() ) + " ( " + str(Settings.screen_ratio) + " )\n" )
	descr_text += "**Operating System:** " + OS.get_name() + "\n"
#	if contact_text.text != "":
#		descr_text += "**User Contact:** " + contact_text.text + "\n"
	
	var data = {
		'name': title_text + " #" + report_hash,
		'desc': ("\n\n**--------- MESSAGE --------**\n\n" + long_text.text + "\n\n\n\n**---------- REPORT ---------**\n\n" + descr_text ),
	}

	if !trello_labels.empty():
		var type = type_box.selected
		data['label_id'] = trello_labels[type].label_trello_id

	var savegame_as_string = Save.create_save_game()
	
	# The cover attachment must be an image. If you don't want so sent further
	# attachments, just leave attachments empty.
	#
	# Use the function Attachment.from_path() to attach files from the
	# filesystem or Attachment.from_image() to convert an Image instance to a
	# file.
	data['cover'] = Attachment.from_image(screenshot_data, report_hash+"_screenshot")
	data['attachments'] = [
		Attachment.from_string(str(savegame_as_string), report_hash+"_savegame")
	]
	
	if include_data:
		var logs = get_latest_logs()
		if not logs.empty():
			data['attachments'].append( Attachment.from_path(logs[0]) )
			if logs.size() > 1:
				data['attachments'].append( Attachment.from_path(logs[1]) )

	var parsed_url = parse_url(PROXY_URL)
	if parsed_url.empty():
		change_feedback("Wrong proxy URL provided, can't send data :-(")
		return

	http.connect_to_host(
		parsed_url['host'],
		parsed_url['port'],
		parsed_url['scheme'] == 'https'
	)

	var timeout = 30.0
	timer.start()
	while http.get_status() in [
		HTTPClient.STATUS_CONNECTING,
		HTTPClient.STATUS_RESOLVING
	]:
		http.poll()
		yield(timer, 'timeout')
		timeout -= timer.get_wait_time()
		if timeout < 0.0:
			change_feedback("Timeout while waiting to connect to server :-(")
			timer.stop()
			return
	timer.stop()

	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		change_feedback("Unable to connect to server :-(")
		return

	if send_post(http, parsed_url['path'], data) != OK:
		change_feedback("Unable to send feedback to server :-(")
		return

	timeout = 30.0
	timer.start()
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		yield(timer, 'timeout')
		timeout -= timer.get_wait_time()
		if timeout < 0.0:
			change_feedback("Timeout waiting for server acknowledgement :-(")
			timer.stop()
			return
	timer.stop()

	if not http.get_status() in [
		HTTPClient.STATUS_BODY,
		HTTPClient.STATUS_CONNECTED
	]:
		change_feedback("Unable to connect to server :-(")
		return

	if http.has_response() && http.get_response_code() != 200:
		timeout = 30.0
		timer.start()
		var response: PoolByteArray = []
		while http.get_status() == HTTPClient.STATUS_BODY:
			http.poll()
			var chunk = http.read_response_body_chunk()
			if chunk.size() == 0:
				yield(timer, 'timeout')
				timeout -= timer.get_wait_time()
				if timeout < 0.0:
					change_feedback("Timeout waiting for server response :-(")
					timer.stop()
					return
			else:
				response += chunk
		timer.stop()
		feedback.text = 'Error from server: ' + response.get_string_from_utf8()
		return

	change_feedback("Feedback sent successfully, thank you!")

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
	if reports.empty():
		return null
	return reports

func dir_contents(path:String):
	var dir = Directory.new()
	var found_files := []
	
	if dir.open(path) == OK:
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
